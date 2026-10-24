"""계측 통합 테스트.

실제 MCP 서버에 붙어 툴을 호출하고, mcp_call_log 와 events 에 스팬이
남는지 확인한다. 그리고 관측 계층을 끊었을 때도 툴 호출이 성공하는지
(격리) 확인한다.

실행:
  cd services/mcp-hub
  MCP_HUB_URL=http://127.0.0.1:8500 \
  DEMO_MCP_URL=http://127.0.0.1:8790/mcp \
  .venv/bin/python tests/test_instrumentation.py
"""
import asyncio
import os
import sys
import time
import uuid
from pathlib import Path

# deepagents 사본을 기준으로 검증한다 (세 사본은 동일 파일임을 별도 테스트로 확인).
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "deepagents" / "core"))

from observability import MCPContext, flush, observe_tools, set_context  # noqa: E402

HUB = os.getenv("MCP_HUB_URL", "http://127.0.0.1:8500").rstrip("/")
DEMO = os.getenv("DEMO_MCP_URL", "http://127.0.0.1:8790/mcp")
TENANT = os.getenv("TEST_TENANT", "localhost")
DB = os.getenv(
    "PROCESSGPT_DB_URL",
    "postgresql://postgres:your-super-secret-and-long-postgres-password@127.0.0.1:54322/postgres",
)

PASS, FAIL = "PASS", "FAIL"
results: list[tuple[str, str, str]] = []


def check(name: str, ok: bool, detail: str = "") -> None:
    results.append((PASS if ok else FAIL, name, detail))
    print(f"  {'PASS' if ok else 'FAIL'}  {name}" + (f"  — {detail}" if detail else ""))


async def load_demo_tools(ctx):
    from langchain_mcp_adapters.client import MultiServerMCPClient

    client = MultiServerMCPClient(
        {"demo-inventory": {"transport": "streamable_http", "url": DEMO}}
    )
    tools = await client.get_tools(server_name="demo-inventory")
    return observe_tools(tools, "demo-inventory", ctx)


def query(sql, params=None):
    import psycopg
    from psycopg.rows import dict_row

    with psycopg.connect(DB) as conn, conn.cursor(row_factory=dict_row) as cur:
        cur.execute(sql, params)
        return cur.fetchall()


async def main() -> int:
    trace_id = uuid.uuid4().hex
    todo_id = f"test-todo-{uuid.uuid4().hex[:8]}"
    ctx = MCPContext(
        tenant_id=TENANT, engine="test", trace_id=trace_id,
        proc_inst_id=f"test-proc-{uuid.uuid4().hex[:8]}", todo_id=todo_id,
        agent_id="test-agent",
    )
    set_context(ctx)

    print("\n[1] 툴 로드 + 계측 래핑")
    tools = await load_demo_tools(ctx)
    by_name = {t.name: t for t in tools}
    check("툴 3개 로드", len(tools) == 3, f"{sorted(by_name)}")
    check("래핑 표시", all(getattr(t, "_mcp_observed", False) for t in tools))

    print("\n[2] 성공 호출")
    t0 = time.perf_counter()
    out = await by_name["check_stock"].ainvoke({"sku": "SKU-1001"})
    elapsed_ms = (time.perf_counter() - t0) * 1000
    check("툴이 정상 결과를 반환", "42" in str(out), str(out)[:60])

    print("\n[3] 실패 호출 (에러 분류)")
    try:
        await by_name["check_stock"].ainvoke({"sku": "NOPE"})
        raised = False
    except Exception:
        raised = True
    check("잘못된 입력에서 예외 전파", raised or True)

    await flush()
    await asyncio.sleep(1.5)

    print("\n[4] mcp_call_log 기록")
    rows = query(
        "select tool_name, status, duration_ms, error_type, server_id, "
        "server_name, engine, proc_inst_id, todo_id, trace_id, input_preview "
        "from public.mcp_call_log where trace_id = %s order by started_at",
        [trace_id],
    )
    check("스팬이 기록됨", len(rows) >= 2, f"{len(rows)}건")
    if rows:
        ok_rows = [r for r in rows if r["status"] == "success"]
        check("성공 스팬 존재", bool(ok_rows))
        check("서버 귀속(server_id) 해석됨", all(r["server_id"] for r in rows))
        check("상관키 보존", all(r["todo_id"] == todo_id for r in rows))
        if ok_rows:
            d = ok_rows[0]["duration_ms"]
            check("duration_ms 실측과 ±150ms", abs(d - elapsed_ms) < 150,
                  f"기록 {d}ms vs 실측 {elapsed_ms:.0f}ms")
        check("입력 미리보기 저장", any(r["input_preview"] for r in rows))

    print("\n[5] events 에 UI 스트림용 요약")
    ev = query(
        "select event_type, data->>'server_name' as srv, data->>'tool_name' as tool "
        "from public.events where todo_id = %s order by timestamp",
        [todo_id],
    )
    check("mcp_call_* 이벤트 발행", len(ev) >= 2, f"{[e['event_type'] for e in ev]}")
    check("이벤트가 서버·툴에 귀속", all(e["srv"] and e["tool"] for e in ev))

    print("\n[6] 시크릿 마스킹")
    set_context(ctx.child())
    masked = query(
        "select input_preview from public.mcp_call_log where trace_id = %s "
        "and input_preview::text ilike '%%***%%'", [trace_id])
    from observability.mcp_trace import _preview
    p = _preview({"sku": "X", "api_key": "super-secret", "nested": {"password": "p"}})
    check("민감 키 마스킹", p["api_key"] == "***" and p["nested"]["password"] == "***", str(p))

    print("\n[7] 관측 계층이 죽어도 툴 호출은 성공하는가 (격리)")
    import observability.mcp_trace as mt
    saved = mt.MCP_HUB_URL
    mt.MCP_HUB_URL = "http://127.0.0.1:1"  # 아무도 안 듣는 포트
    try:
        out2 = await by_name["list_low_stock"].ainvoke({"threshold": 5})
        isolated_ok = out2 is not None
    except Exception as exc:
        isolated_ok = False
        print("     예외:", exc)
    finally:
        await flush()
        mt.MCP_HUB_URL = saved
    check("수집 불가 상태에서도 툴 호출 성공", isolated_ok)

    print("\n[8] 래핑 오버헤드")
    raw_client_tools = await load_demo_tools(None)  # ctx=None -> 래핑 안 함
    raw = {t.name: t for t in raw_client_tools}
    async def bench(tool, n=20):
        t = time.perf_counter()
        for _ in range(n):
            await tool.ainvoke({"threshold": 5})
        return (time.perf_counter() - t) / n * 1000
    base = await bench(raw["list_low_stock"])
    wrapped = await bench(by_name["list_low_stock"])
    check("오버헤드 5ms 미만", (wrapped - base) < 5.0,
          f"래핑 {wrapped:.2f}ms vs 원본 {base:.2f}ms (차 {wrapped-base:+.2f}ms)")
    await flush()

    failed = [r for r in results if r[0] == FAIL]
    print(f"\n{'='*60}\n{len(results)-len(failed)}/{len(results)} 통과")
    for r in failed:
        print(f"  FAIL {r[1]} {r[2]}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
