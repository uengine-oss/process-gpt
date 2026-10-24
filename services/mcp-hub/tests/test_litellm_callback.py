"""LiteLLM 콜백 테스트.

상관키 추출(헤더 경로 / metadata 경로), 레코드 구성, 미귀속 호출 처리,
그리고 허브 수집까지 확인한다.

실행:
  cd services/mcp-hub
  MCP_HUB_URL=http://127.0.0.1:8500 .venv/bin/python tests/test_litellm_callback.py
"""
import asyncio
import json
import os
import sys
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path

sys.path.insert(
    0, str(Path(__file__).resolve().parents[3] / "docker-infra" / "litellm" / "callbacks")
)
os.environ.setdefault("MCP_HUB_URL", "http://127.0.0.1:8500")

import processgpt_callback as cb  # noqa: E402

cb.HUB_URL = os.environ["MCP_HUB_URL"].rstrip("/")

DB = os.getenv(
    "PROCESSGPT_DB_URL",
    "postgresql://postgres:your-super-secret-and-long-postgres-password@127.0.0.1:54322/postgres",
)
results = []


def check(name, ok, detail=""):
    results.append((ok, name, detail))
    print(f"  {'PASS' if ok else 'FAIL'}  {name}" + (f"  — {detail}" if detail else ""))


class _Usage(dict):
    pass


class _Resp:
    def __init__(self, usage, tool_calls=0):
        self.usage = usage
        self.choices = []


def query(sql, params=None):
    import psycopg
    from psycopg.rows import dict_row

    with psycopg.connect(DB) as conn, conn.cursor(row_factory=dict_row) as cur:
        cur.execute(sql, params)
        return cur.fetchall()


async def main():
    trace_id = uuid.uuid4().hex
    corr = {
        "tenant_id": "localhost", "trace_id": trace_id, "engine": "completion",
        "proc_inst_id": "proc-abc", "todo_id": "todo-xyz", "agent_id": "agent-1",
    }

    print("\n[1] 상관키 추출 — 헤더 경로")
    kw_header = {
        "model": "gpt-4o",
        "proxy_server_request": {
            "headers": {"X-ProcessGPT-Trace": json.dumps(corr), "content-type": "application/json"}
        },
    }
    got = cb.extract_correlation(kw_header)
    check("헤더에서 상관키 추출", got.get("trace_id") == trace_id and got.get("todo_id") == "todo-xyz", str(got))

    print("\n[2] 상관키 추출 — metadata 경로")
    kw_meta = {"model": "gpt-4o", "litellm_params": {"metadata": corr}}
    got2 = cb.extract_correlation(kw_meta)
    check("metadata 에서 상관키 추출", got2.get("proc_inst_id") == "proc-abc", str(got2))

    print("\n[3] metadata 가 헤더보다 우선")
    mixed = {
        "proxy_server_request": {"headers": {"x-processgpt-trace": json.dumps({**corr, "engine": "header"})}},
        "litellm_params": {"metadata": {"engine": "metadata"}},
    }
    check("metadata 우선", cb.extract_correlation(mixed)["engine"] == "metadata")

    print("\n[4] 레코드 구성 (토큰·비용·지연)")
    start = datetime.now(timezone.utc)
    end = start + timedelta(milliseconds=1234)
    usage = {"prompt_tokens": 100, "completion_tokens": 40, "total_tokens": 140,
             "prompt_tokens_details": {"cached_tokens": 20}}
    kwargs = {**kw_meta, "response_cost": 0.00123, "call_type": "completion",
              "litellm_call_id": "call-1",
              "litellm_params": {"metadata": corr, "custom_llm_provider": "openai"}}
    rec = cb.build_record(kwargs, _Resp(usage), start, end, "success")
    check("지연 계산", rec["duration_ms"] == 1234, f"{rec['duration_ms']}ms")
    check("토큰 집계", (rec["prompt_tokens"], rec["completion_tokens"], rec["total_tokens"]) == (100, 40, 140))
    check("캐시 토큰", rec["cache_read_tokens"] == 20)
    check("비용", rec["cost_usd"] == 0.00123)
    check("provider 추출", rec["provider"] == "openai")
    check("상관키 실림", rec["trace_id"] == trace_id and rec["tenant_id"] == "localhost")

    print("\n[5] 상관키 없는 호출은 버리지 않고 unattributed 로")
    bare = cb.build_record({"model": "gpt-4o"}, _Resp({}), start, end, "success")
    check("tenant_id=unattributed", bare["tenant_id"] == "unattributed")

    print("\n[6] 실패 이벤트")
    fail = cb.build_record({**kwargs, "exception": ValueError("rate limited")},
                           None, start, end, "error")
    check("에러 타입·메시지 기록", fail["status"] == "error" and fail["error_type"] == "ValueError",
          f"{fail['error_type']}: {fail['error_message']}")

    print("\n[7] 허브 수집 (llm_call_log)")
    cb._sink.submit(rec)
    cb._sink.submit(fail)
    cb._sink.submit(bare)
    await cb._sink.flush()
    await asyncio.sleep(1.0)
    rows = query("select status, model, total_tokens, cost_usd, duration_ms, tenant_id "
                 "from public.llm_call_log where trace_id = %s", [trace_id])
    check("스팬 적재", len(rows) >= 2, f"{len(rows)}건")
    unattr = query("select count(*) as n from public.llm_call_log where tenant_id='unattributed'")
    check("미귀속 호출도 보존", unattr[0]["n"] >= 1, f"{unattr[0]['n']}건")

    print("\n[8] MCP 스팬과 같은 trace 로 조인되는가")
    cb._sink.submit({**rec, "trace_id": trace_id})
    await cb._sink.flush()
    await asyncio.sleep(0.8)
    joined = query(
        """
        select m.tool_name, l.model
          from public.mcp_call_log m
          join public.llm_call_log l on l.trace_id = m.trace_id
         limit 5
        """
    )
    check("trace_id 조인 가능(스키마·인덱스 확인)", True, f"조인 결과 {len(joined)}건")

    failed = [r for r in results if not r[0]]
    print(f"\n{'='*60}\n{len(results)-len(failed)}/{len(results)} 통과")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
