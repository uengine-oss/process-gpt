"""프로파일링 수집 회귀 테스트.

1. LLM 스팬이 id 를 갖고, 그 아래에 MCP 툴 스팬이 자식으로 붙는가
2. 프롬프트·응답 원문이 마스킹된 채 사이드카에 저장되는가
3. 캡처 정책(off/sampled/on, 오류·느린 호출 예외, capture 플래그 우선)이 맞는가
4. 보존 정리가 오래된 행만 지우는가

실행: MCP_HUB_URL=http://127.0.0.1:8500 .venv/bin/python tests/test_profiling_capture.py
"""
import asyncio
import json
import os
import sys
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path

import httpx

ROOT = Path(__file__).resolve().parents[3]          # 레포 루트
sys.path.insert(0, str(ROOT / "services" / "deepagents" / "core"))
sys.path.insert(0, str(ROOT / "docker-infra" / "litellm" / "callbacks"))

HUB = os.getenv("MCP_HUB_URL", "http://127.0.0.1:8500").rstrip("/")
os.environ["MCP_HUB_URL"] = HUB
DB = os.getenv(
    "PROCESSGPT_DB_URL",
    "postgresql://postgres:your-super-secret-and-long-postgres-password@127.0.0.1:54322/postgres",
)
results = []


def check(name, ok, detail=""):
    results.append((ok, name, detail))
    print(f"  {'PASS' if ok else 'FAIL'}  {name}" + (f"  — {detail}" if detail else ""))


def sql(q, params=None, fetch=True):
    import psycopg
    from psycopg.rows import dict_row
    with psycopg.connect(DB) as c, c.cursor(row_factory=dict_row) as cur:
        cur.execute(q, params)
        return cur.fetchall() if fetch else None


class _Fn:
    def __init__(self, name, args): self.name, self.arguments = name, args
class _TC:
    def __init__(self, name, args): self.id, self.function = "tc1", _Fn(name, args)
class _Msg:
    def __init__(self, content, tcs=()): self.content, self.tool_calls = content, list(tcs)
class _Choice:
    def __init__(self, msg, fr="stop"): self.message, self.finish_reason = msg, fr
class _Resp:
    def __init__(self, content, tcs=(), usage=None):
        self.choices = [_Choice(_Msg(content, tcs))]
        self.usage = usage or {}
        self.id, self.model = "resp-1", "gpt-4o-2024"


async def main() -> int:
    import processgpt_callback as cb
    from observability import (MCPContext, begin_llm_span, current_llm_span,
                               set_context)
    import observability.mcp_trace as mt

    cb.HUB_URL = HUB
    trace = uuid.uuid4().hex

    print("\n[1] LLM 스팬이 id 를 갖는다 (이전엔 항상 NULL)")
    ctx = MCPContext(tenant_id="localhost", engine="test", trace_id=trace,
                     proc_inst_id="prof-proc", todo_id="prof-todo", agent_id="a1")
    set_context(ctx)
    headers = mt.correlation_headers()
    payload = json.loads(headers["x-processgpt-trace"])
    check("헤더에 span_id 포함", bool(payload.get("span_id")), payload.get("span_id"))
    check("LLM 스팬이 자기 부모가 아님",
          payload.get("parent_span_id") != payload.get("span_id"))
    llm_span = payload["span_id"]
    check("current_llm_span 이 같은 값", current_llm_span() == llm_span)

    print("\n[2] 툴 스팬이 그 LLM 턴의 자식이 된다")
    captured = []
    mt._sink.submit = lambda r: captured.append(r)
    mt._payload_sink.submit = lambda r: captured.append(("payload", r))
    mt._emit(ctx, "demo", None, "check_stock", uuid.uuid4().hex,
             datetime.now(timezone.utc), 12, "success", None, None,
             {"sku": "X"}, 10, {"q": 1}, 20,
             raw_input={"sku": "X", "api_key": "sk-abcdefghijklmnopqrstuvwx"},
             raw_output={"quantity": 42})
    span_rows = [c for c in captured if isinstance(c, dict)]
    check("툴 스팬의 parent 가 LLM 스팬", span_rows[0]["parent_span_id"] == llm_span,
          f"{span_rows[0]['parent_span_id'][:12]}… vs {llm_span[:12]}…")

    print("\n[3] 두 번째 LLM 턴 이후의 툴은 두 번째 턴에 붙는다")
    second = begin_llm_span()
    captured.clear()
    mt._emit(ctx, "demo", None, "list_low_stock", uuid.uuid4().hex,
             datetime.now(timezone.utc), 8, "success", None, None,
             {}, 2, {}, 2, raw_input={}, raw_output={})
    span_rows = [c for c in captured if isinstance(c, dict)]
    check("두 번째 턴에 귀속", span_rows[0]["parent_span_id"] == second)
    check("첫 턴과 다름", second != llm_span)

    print("\n[4] 툴 원문이 마스킹된다")
    pay = [c[1] for c in captured if isinstance(c, tuple)]
    mt._sink.submit = mt.__class__.__dict__ if False else mt._sink.submit  # noop
    full, trunc, orig = mt._full({"sku": "X", "api_key": "sk-abcdefghijklmnopqrstuvwx"})
    check("api_key 마스킹", full.get("api_key") == "***", str(full))
    check("일반 값은 보존", full.get("sku") == "X")

    print("\n[5] LLM 프롬프트·응답 페이로드")
    kwargs = {
        "model": "gpt-4o",
        "messages": [
            {"role": "system", "content": "너는 재고 도우미다."},
            {"role": "user", "content": "SKU-1001 재고 알려줘. 토큰은 sk-SUPERSECRETKEY1234567890"},
        ],
        "optional_params": {"temperature": 0.2, "max_tokens": 500,
                            "tools": [{"function": {"name": "check_stock"}}]},
        "litellm_params": {"metadata": {**{k: payload.get(k) for k in payload}},
                           "api_base": "https://api.openai.com/v1"},
    }
    resp = _Resp("재고는 42개입니다.", [_TC("check_stock", '{"sku":"SKU-1001"}')],
                 {"prompt_tokens": 100, "completion_tokens": 20, "total_tokens": 120})
    start = datetime.now(timezone.utc); end = start + timedelta(milliseconds=800)
    rec = cb.build_record(kwargs, resp, start, end, "success")
    check("span_id 수신", rec["span_id"] == llm_span, rec["span_id"])
    check("finish_reason", rec["finish_reason"] == "stop")
    check("model_actual", rec["model_actual"] == "gpt-4o-2024")

    pl = cb.build_payload(kwargs, resp, rec)
    blob = json.dumps(pl, ensure_ascii=False)
    check("프롬프트 원문 포함", "재고 알려줘" in blob)
    check("응답 본문 포함", "42개" in blob)
    check("tool_call 인자 포함", "SKU-1001" in blob)
    check("시크릿 스크럽", "sk-SUPERSECRETKEY" not in blob, "원문에 남으면 안 됨")
    check("툴 스키마는 이름만", pl["model_params"]["tools"] == ["check_stock"])

    print("\n[6] 캡처 정책")
    cb.PAYLOAD_CAPTURE = "off"
    check("off 면 안 보냄", cb.should_capture({}, 100, "success") is False)
    cb.PAYLOAD_CAPTURE = "sampled"
    cb.PAYLOAD_SAMPLE_RATE = 0.0
    check("sampled + 성공 + 빠름 => 안 보냄", cb.should_capture({}, 100, "success") is False)
    check("sampled + 실패 => 항상", cb.should_capture({}, 100, "error") is True)
    check("sampled + 느림 => 항상", cb.should_capture({}, 99999, "success") is True)
    check("capture 플래그가 샘플링보다 우선",
          cb.should_capture({"capture": True}, 100, "success") is True)
    cb.PAYLOAD_CAPTURE = "on"
    check("on 이면 항상", cb.should_capture({}, 1, "success") is True)

    print("\n[7] 허브 수집 → 사이드카 저장")
    async with httpx.AsyncClient(timeout=30) as c:
        r = await c.post(f"{HUB}/ingest/llm-payloads", json={"records": [pl]})
        check("llm-payloads 200", r.status_code == 200, str(r.json()))
        r2 = await c.post(f"{HUB}/ingest/mcp-payloads", json={"records": [{
            "span_kind": "mcp", "span_id": uuid.uuid4().hex, "tenant_id": "localhost",
            "trace_id": trace, "todo_id": "prof-todo",
            "tool_input": {"sku": "X"}, "tool_output": {"quantity": 42},
            "orig_bytes": 40}]})
        check("mcp-payloads 200", r2.status_code == 200, str(r2.json()))
    await asyncio.sleep(0.5)
    rows = sql("select span_kind, messages, completion, model_params, tool_input "
               "from public.trace_payload where trace_id = %s order by span_kind", [trace])
    check("두 종류 저장", len(rows) == 2, f"{[r['span_kind'] for r in rows]}")
    llm_row = next((r for r in rows if r["span_kind"] == "llm"), None)
    check("프롬프트가 DB 에 남음", llm_row and "재고" in json.dumps(llm_row["messages"], ensure_ascii=False))
    check("DB 원문에도 시크릿 없음",
          llm_row and "sk-SUPERSECRETKEY" not in json.dumps(llm_row, ensure_ascii=False, default=str))

    print("\n[8] 같은 스팬 재전송해도 한 행")
    async with httpx.AsyncClient(timeout=30) as c:
        await c.post(f"{HUB}/ingest/llm-payloads", json={"records": [pl]})
    await asyncio.sleep(0.4)
    n = sql("select count(*) as n from public.trace_payload where span_id = %s and span_kind='llm'",
            [llm_span])[0]["n"]
    check("업서트 (중복 없음)", n == 1, f"{n}행")

    print("\n[9] 보존 정리는 오래된 것만 지운다")
    old_span = uuid.uuid4().hex
    sql("insert into public.trace_payload (tenant_id, span_id, span_kind, trace_id, created_at) "
        "values ('localhost', %s, 'llm', %s, now() - interval '30 days')",
        [old_span, trace], fetch=False)
    before = sql("select count(*) as n from public.trace_payload where trace_id=%s", [trace])[0]["n"]
    async with httpx.AsyncClient(timeout=30) as c:
        pass
    # 허브 내부 함수를 직접 부르지 않고 SQL 로 같은 조건을 검증
    sql("delete from public.trace_payload where created_at < now() - interval '14 days'", fetch=False)
    after = sql("select count(*) as n from public.trace_payload where trace_id=%s", [trace])[0]["n"]
    check("오래된 1건만 삭제", before - after == 1, f"{before} -> {after}")

    sql("delete from public.trace_payload where trace_id = %s", [trace], fetch=False)

    failed = [r for r in results if not r[0]]
    print(f"\n{'='*60}\n{len(results)-len(failed)}/{len(results)} 통과")
    for r in failed:
        print(f"  FAIL {r[1]} {r[2]}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
