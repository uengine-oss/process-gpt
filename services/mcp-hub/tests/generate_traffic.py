"""데모/검증용 MCP 호출 트래픽 생성기.

실제 MCP 서버에 실제 툴 호출을 날려, 계측이 만든 진짜 스팬을 쌓는다.
(관측 화면에 넣을 데이터를 손으로 INSERT 하지 않기 위한 것)
"""
import asyncio
import json
import os
import random
import sys
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "deepagents" / "core"))
from observability import (  # noqa: E402
    MCPContext, correlation_headers, flush, observe_tools, set_context,
)
import observability.mcp_trace as mt  # noqa: E402

DEMO = os.getenv("DEMO_MCP_URL", "http://127.0.0.1:8790/mcp")
HUB = os.getenv("MCP_HUB_URL", "http://127.0.0.1:8500").rstrip("/")
TENANT = os.getenv("TEST_TENANT", "localhost")
ROUNDS = int(os.getenv("ROUNDS", "40"))

# 실제 todolist 워크아이템에 붙여 프로세스 관점 드릴다운이 되게 한다.
# proc_inst_id 도 그 워크아이템의 실제 값이어야 DW 조인이 성립한다.
TODOS = [t for t in (os.getenv("TODO_IDS", "").split(",")) if t]
DB = os.getenv(
    "PROCESSGPT_DB_URL",
    "postgresql://postgres:your-super-secret-and-long-postgres-password@127.0.0.1:54322/postgres",
)


def _resolve_instances(todo_ids: list) -> dict:
    """워크아이템 -> 그 워크아이템이 속한 프로세스 인스턴스."""
    if not todo_ids:
        return {}
    try:
        import psycopg
        from psycopg.rows import dict_row
        with psycopg.connect(DB) as c, c.cursor(row_factory=dict_row) as cur:
            cur.execute(
                "select id::text as todo, proc_inst_id from public.todolist "
                "where id::text = any(%s)", [todo_ids])
            return {r["todo"]: r["proc_inst_id"] for r in cur.fetchall()
                    if r["proc_inst_id"]}
    except Exception as exc:  # noqa: BLE001
        print("인스턴스 해석 실패:", exc)
        return {}


async def _post_llm_span(corr: dict, started, duration_ms: int) -> None:
    """LLM 스팬 하나를 허브에 기록한다 (프록시 콜백이 하는 일과 같은 모양)."""
    import httpx

    finished = started + timedelta(milliseconds=duration_ms)
    prompt_t = random.randint(400, 3000)
    comp_t = random.randint(20, 400)
    rec = {
        **{k: corr.get(k) for k in
           ("tenant_id", "trace_id", "span_id", "parent_span_id",
            "proc_inst_id", "todo_id", "job_id", "agent_id", "engine")},
        "call_type": "completion",
        "model": random.choice(["gpt-4o", "claude-sonnet-4-6"]),
        "provider": "openai",
        "started_at": started.isoformat(),
        "finished_at": finished.isoformat(),
        "duration_ms": duration_ms,
        "status": "success",
        "prompt_tokens": prompt_t,
        "completion_tokens": comp_t,
        "total_tokens": prompt_t + comp_t,
        "cost_usd": round((prompt_t * 2.5 + comp_t * 10) / 1_000_000, 6),
        "finish_reason": "tool_calls",
        "tool_calls_count": 1,
    }
    payload = {
        "span_kind": "llm",
        "span_id": corr["span_id"],
        "tenant_id": corr.get("tenant_id"),
        "trace_id": corr.get("trace_id"),
        "proc_inst_id": corr.get("proc_inst_id"),
        "todo_id": corr.get("todo_id"),
        "job_id": corr.get("job_id"),
        "messages": [
            {"role": "system", "content": "너는 창고 재고를 관리하는 도우미다."},
            {"role": "user", "content": "재고가 부족한 품목을 확인하고 필요하면 조정해줘."},
        ],
        "completion": {
            "content": "재고를 확인하겠습니다.",
            "tool_calls": [{"name": "check_stock",
                            "arguments": '{"sku": "SKU-1001"}'}],
            "finish_reason": "tool_calls",
        },
        "model_params": {"temperature": 0.2, "max_tokens": 1000,
                         "tools": ["check_stock", "list_low_stock",
                                   "create_stock_adjustment"]},
        "orig_bytes": 420,
    }
    try:
        async with httpx.AsyncClient(timeout=10) as c:
            await c.post(f"{HUB}/ingest/llm-calls", json={"records": [rec]})
            await c.post(f"{HUB}/ingest/llm-payloads", json={"records": [payload]})
    except Exception as exc:  # noqa: BLE001
        print("LLM 스팬 기록 실패:", exc)


async def main():
    from langchain_mcp_adapters.client import MultiServerMCPClient

    client = MultiServerMCPClient(
        {"demo-inventory": {"transport": "streamable_http", "url": DEMO}}
    )
    raw = await client.get_tools(server_name="demo-inventory")
    inst_by_todo = _resolve_instances(TODOS)
    print(f"인스턴스 해석: {len(inst_by_todo)}/{len(TODOS)} 워크아이템")

    engines = ["deepagents", "completion"]
    skus = ["SKU-1001", "SKU-1002", "SKU-1003", "SKU-9999"]  # 9999 는 실패를 유발
    ok = err = 0

    for i in range(ROUNDS):
        todo = random.choice(TODOS) if TODOS else f"demo-todo-{i % 6}"
        ctx = MCPContext(
            tenant_id=TENANT,
            engine=random.choice(engines),
            trace_id=uuid.uuid4().hex,
            proc_inst_id=inst_by_todo.get(todo) or f"demo-proc-{i % 4}",
            todo_id=todo,
            job_id=f"job-{todo[:8]}-{i // 8}",
            agent_id=f"agent-{i % 3}",
        )
        set_context(ctx)

        # 실제 실행에서는 LLM 요청 훅이 correlation_headers() 를 불러 스팬을
        # 발급하고, 프록시 콜백이 그 스팬을 llm_call_log 에 남긴다. 여기서는
        # 같은 경로를 그대로 타되 콜백 대신 허브에 직접 넣는다.
        headers = correlation_headers()
        corr = json.loads(headers["x-processgpt-trace"])
        llm_span = corr["span_id"]
        started = datetime.now(timezone.utc)
        await _post_llm_span(corr, started, random.randint(400, 2500))

        tools = {t.name: t for t in observe_tools(raw, "demo-inventory", ctx)}

        choice = random.random()
        try:
            if choice < 0.5:
                await tools["check_stock"].ainvoke({"sku": random.choice(skus)})
            elif choice < 0.85:
                await tools["list_low_stock"].ainvoke({"threshold": random.choice([5, 10, 50])})
            else:
                await tools["create_stock_adjustment"].ainvoke(
                    {"sku": "SKU-1001", "delta": -1, "reason": "데모 조정"}
                )
            ok += 1
        except Exception:
            err += 1
        await asyncio.sleep(0.03)

    await flush()
    await asyncio.sleep(1.5)
    print(f"생성 완료 — 성공 {ok}건, 실패 {err}건 (총 {ROUNDS})")


if __name__ == "__main__":
    asyncio.run(main())
