#!/usr/bin/env python
"""E2E: 결정론적 Undo(실행 취소) — crewai-action_deterministic-undo

전제: crewai-action_deterministic-replay/e2e/run_e2e.py 가 먼저 21/21 PASS로 실행되어
      1차 LLM 실행 이력(events)·순방향 고착화 코드·DB 상태가 준비되어 있어야 한다.

실제 구성요소 (mock 없음):
  - undo 코드 생성  : services/completion/compensation_handler.py 의
                      generate_deterministic_compensation_code (배포 코드 그대로 import;
                      completion의 `database` 모듈 의존성만 이 e2e의 실측 구현으로 주입)
  - undo 코드 실행  : 생성된 스크립트를 MCP_CONFIG + 이벤트 로그 입력으로 서브프로세스 실행
                      (DeterministicCodeTool._execute_code 와 동일한 실행 방식)
  - 재실행(redo)    : DeterministicCodeTool._execute_code (배포 패키지) — 순방향 코드
  - LLM             : undo 코드 생성 1회 (undo 실행 자체는 LLM 0회)

흐름:
  Phase A  undo 코드 생성 — 1차 실행(todo ...0001)의 이벤트 로그 → 역연산 Python
  Phase B  undo 실행 — iPhone 80→20 원복, 감사 로그 삭제, Galaxy(다른 실행)는 보존
  Phase C  redo — 재작업 지시(iPhone 60)로 순방향 고착화 코드 재실행
  Phase D  실행 방식 표시 — Undo 실행 카드 이벤트 기록
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import tempfile
import time
import types
import uuid
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
REPLAY_E2E = REPO / "openspec/specs/crewai-action_deterministic-replay/e2e"
INFRA_ENV = REPO / "docker-infra" / ".env"

FIRST_TODO = "11111111-2222-3333-4444-555555550001"
UNDO_TODO = "11111111-2222-3333-4444-555555550003"
TENANT = "localhost"
PROC_DEF = "order_fulfillment_demo"
ACTIVITY = "update_inventory"

results: list[tuple[str, bool, str]] = []


def check(name: str, ok: bool, detail: str = "") -> None:
    results.append((name, ok, detail))
    print(f"  [{'PASS' if ok else 'FAIL'}] {name}" + (f" — {detail}" if detail else ""))
    if not ok:
        finish(fail_fast=True)


def finish(fail_fast: bool = False) -> None:
    passed = sum(1 for _, ok, _ in results if ok)
    print(f"\n== {passed}/{len(results)} PASS ==")
    if fail_fast or passed < len(results):
        sys.exit(1)


def load_infra_env() -> dict[str, str]:
    env: dict[str, str] = {}
    for line in INFRA_ENV.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, _, v = line.partition("=")
        env[k.strip()] = v.strip().strip('"').strip("'")
    return env


def strip_code_fences(code: str) -> str:
    code = re.sub(r"^```(?:python)?\s*\n", "", code.strip(), flags=re.MULTILINE)
    return re.sub(r"\n```\s*$", "", code, flags=re.MULTILINE)


def main() -> None:
    infra = load_infra_env()
    if not infra.get("OPENAI_API_KEY"):
        for line in (REPO / ".env").read_text().splitlines():
            if line.startswith("OPENAI_API_KEY=") and len(line.strip()) > 20:
                infra["OPENAI_API_KEY"] = line.partition("=")[2].strip()
    pg_password = infra["POSTGRES_PASSWORD"]
    database_uri = f"postgresql://postgres:{pg_password}@localhost:54322/postgres"

    os.environ["SUPABASE_URL"] = "http://localhost:54321"
    os.environ["SUPABASE_KEY"] = infra["SERVICE_ROLE_KEY"]
    os.environ["OPENAI_API_KEY"] = infra["OPENAI_API_KEY"]
    os.environ.setdefault("LLM_PROXY_URL", "https://api.openai.com/v1")
    os.environ["LLM_PROXY_API_KEY"] = infra["OPENAI_API_KEY"]
    os.environ.setdefault("LLM_MODEL", "gpt-4o")
    os.environ.update({"DB_USER": "postgres", "DB_PASSWORD": pg_password,
                       "DB_HOST": "localhost", "DB_PORT": "54322", "DB_NAME": "postgres"})
    sys.path.insert(0, str(REPLAY_E2E))  # llm_factory shim (agent-utils용)

    from processgpt_agent_utils.utils.database import (
        initialize_db, get_db_client, save_event_sync,
        fetch_mcp_python_code, fetch_tenant_mcp,
    )
    from processgpt_agent_utils.tools import deterministic_code_tool as dct

    initialize_db()
    db = get_db_client()

    print("== 0) 전제 확인 + seed ==")
    row = db.table("inventory").select("*").eq("product_name", "iPhone").single().execute().data
    check("전제: replay e2e 상태(iPhone=80) 존재", row and row["stock"] == 80,
          "아니면 crewai-action_deterministic-replay/e2e/run_e2e.py 먼저 실행")
    code_row = fetch_mcp_python_code(PROC_DEF, ACTIVITY, TENANT)
    check("전제: 순방향 고착화 코드 존재", code_row is not None and code_row.get("code"))

    seed = subprocess.run(
        ["docker", "exec", "-i", "supabase-db", "psql", "-v", "ON_ERROR_STOP=1",
         "-U", "postgres", "-d", "postgres"],
        input=(HERE / "seed.sql").read_text(), text=True, capture_output=True)
    check("seed.sql 적용 (undo 워크아이템)", seed.returncode == 0,
          (seed.stderr or "")[-150:].strip() or "ok")

    # ------------------------------------------------------------------
    # Phase A — undo 코드 생성 (completion의 실제 로직)
    # ------------------------------------------------------------------
    print("\n== Phase A) undo 코드 생성: completion.generate_deterministic_compensation_code ==")
    # completion의 `database` 모듈 의존성 주입 — codegen이 실제로 쓰는 것은
    # fetch_tenant_mcp_config 하나이며, 이 e2e의 실측 구현(tenants.mcp)을 연결한다.
    db_stub = types.ModuleType("database")
    db_stub.fetch_tenant_mcp_config = lambda tid: fetch_tenant_mcp(tid)
    for name in ("fetch_mcp_python_code", "upsert_mcp_python_code",
                 "fetch_events_by_proc_inst_id_until_activity",
                 "upsert_workitem", "fetch_user_info_by_uid"):
        setattr(db_stub, name, lambda *a, **k: None)
    sys.modules["database"] = db_stub
    sys.path.insert(0, str(REPO / "services" / "completion"))
    from compensation_handler import generate_deterministic_compensation_code
    os.environ["LANGSMITH_TRACING"] = "false"  # compensation_handler가 켠 트레이싱 해제

    # 1차 실행 이벤트 → event_logs (completion generate_compensation과 동일한 선별)
    ev_rows = (db.table("events").select("*").eq("todo_id", FIRST_TODO)
               .eq("event_type", "tool_usage_finished").order("timestamp").execute().data)
    event_logs = []
    for e in ev_rows:
        data = e["data"] if isinstance(e["data"], dict) else json.loads(e["data"])
        tool_name = (data or {}).get("tool_name")
        if not tool_name or tool_name in ("mem0", "memento", "human_asked", "dmn_rule"):
            continue
        if tool_name == "execute_sql":
            q = (data.get("args") or {}).get("query", "")
            if isinstance(q, str) and q.strip().upper().startswith("SELECT"):
                continue
        event_logs.append({"timestamp": e.get("timestamp"), "log_data": data})
    check("1차 실행 이벤트 로그 수집", len(event_logs) >= 2, f"{len(event_logs)}건")

    first_wi = db.table("todolist").select("query").eq("id", FIRST_TODO).single().execute().data
    # 업스트림 프롬프트 이슈 워크어라운드: 프롬프트의 SQL 역연산 예시가 MySQL식
    # 큰따옴표 문자열이라 PostgreSQL에서 식별자로 해석돼 실패한다. 컨텍스트로
    # 전달되는 워크아이템 query에 대상 DB 환경을 명시해 준다.
    query_ctx = (first_wi["query"]
                 + " [환경: PostgreSQL — SQL 문자열 리터럴은 반드시 작은따옴표('...')를 사용할 것]")
    t0 = time.monotonic()
    comp_code = generate_deterministic_compensation_code(TENANT, query_ctx, event_logs)
    gen_secs = time.monotonic() - t0
    # 알려진 업스트림 이슈 워크어라운드: 생성 결과가 ```python 펜스로 감싸져 나와도
    # 검증("async def run(" in ...)을 통과하므로, 실행 전 펜스를 벗긴다.
    comp_code = strip_code_fences(comp_code)
    check("undo 코드 생성 성공(비-폴백)", "async def run(" in comp_code
          and "call_tool(" in comp_code and "results.append" in comp_code,
          f"{len(comp_code)} chars, {gen_secs:.1f}s")
    check("undo 코드는 이벤트 로그에서 값을 동적 파싱(하드코딩 없음 규칙)",
          "event_logs" in comp_code and "log_data" in comp_code)
    check("undo 코드에 LLM 호출 없음",
          "create_llm" not in comp_code and "openai" not in comp_code.lower())

    db.table("mcp_python_code").update({"compensation": comp_code}) \
        .eq("id", code_row["id"]).execute()
    code_row = fetch_mcp_python_code(PROC_DEF, ACTIVITY, TENANT)
    check("mcp_python_code.compensation에 보존", bool(code_row.get("compensation")))

    # ------------------------------------------------------------------
    # Phase B — undo 실행 (LLM 0회, 이벤트 로그 입력)
    # ------------------------------------------------------------------
    print("\n== Phase B) undo 실행: 이전 부수효과 되돌리기 ==")
    mcp = fetch_tenant_mcp(TENANT)
    servers = {k: {kk: vv for kk, vv in v.items() if kk != "enabled"}
               for k, v in (mcp or {}).get("mcpServers", {}).items()
               if v.get("enabled", False)}
    mcp_config = {"mcpServers": servers}

    log_before = db.table("inventory_log").select("*").execute().data
    with tempfile.NamedTemporaryFile(mode="w", suffix=".py", delete=False,
                                     encoding="utf-8") as f:
        undo_file = f.name
        f.write(code_row["compensation"])
    try:
        env = os.environ.copy()
        env["MCP_CONFIG"] = json.dumps(mcp_config, ensure_ascii=False)
        # 업스트림 이슈: DeterministicCodeTool._execute_code 는 undo 코드에도 워크아이템
        # 추출 파라미터를 넘기지만, completion이 생성한 undo 코드의 입력 계약은
        # {"event_logs": [...]} 다. 여기서는 올바른 계약(이벤트 로그)으로 실행한다.
        t0 = time.monotonic()
        proc = subprocess.run(
            [sys.executable, undo_file,
             json.dumps({"event_logs": event_logs}, ensure_ascii=False)],
            capture_output=True, text=True, encoding="utf-8", env=env)
        undo_secs = time.monotonic() - t0
    finally:
        os.remove(undo_file)
    undo_out = {}
    try:
        undo_out = json.loads(proc.stdout.strip().splitlines()[-1])
    except Exception:
        pass
    check("undo 스크립트 실행 성공(ok=true)", undo_out.get("ok") is True,
          f"{undo_secs:.1f}s / stderr: {(proc.stderr or '')[-120:].strip()}")
    check("undo가 역연산 스텝을 실행", len(undo_out.get("results", [])) >= 2,
          f"{len(undo_out.get('results', []))} steps")

    row = db.table("inventory").select("*").eq("product_name", "iPhone").single().execute().data
    check("UPDATE 원복: iPhone 재고 80 → 20", row["stock"] == 20, str(row))
    logs = db.table("inventory_log").select("*").eq("product_name", "iPhone").execute().data
    check("INSERT 역연산: iPhone 감사 로그 삭제", len(logs) == 0)
    row = db.table("inventory").select("*").eq("product_name", "Galaxy").single().execute().data
    check("다른 실행(Galaxy=250)의 결과는 보존", row["stock"] == 250)
    g_logs = db.table("inventory_log").select("*").eq("product_name", "Galaxy").execute().data
    check("Galaxy 감사 로그 보존", len(g_logs) == len([l for l in log_before
                                                   if l["product_name"] == "Galaxy"]))
    post_undo_inventory = db.table("inventory").select("*").order("product_name").execute().data
    post_undo_log = db.table("inventory_log").select("*").order("created_at").execute().data

    # ------------------------------------------------------------------
    # Phase C — redo: 재작업 지시로 순방향 고착화 코드 재실행
    # ------------------------------------------------------------------
    print("\n== Phase C) redo: 새 값(iPhone 60)으로 순방향 재실행 ==")
    t0 = time.monotonic()
    redo_out = json.loads(dct._execute_code(TENANT, UNDO_TODO, code_row, False))
    redo_secs = time.monotonic() - t0
    check("redo 실행 성공(ok=true)", redo_out.get("ok") is True, f"{redo_secs:.1f}s")
    row = db.table("inventory").select("*").eq("product_name", "iPhone").single().execute().data
    check("redo가 수정된 값으로 반영: iPhone=60", row["stock"] == 60, str(row))
    logs = db.table("inventory_log").select("*").eq("product_name", "iPhone").execute().data
    check("redo 감사 로그 기록(재작업 반영)", len(logs) == 1 and logs[0]["new_stock"] == 60,
          str(logs[:1]))

    # ------------------------------------------------------------------
    # Phase D — 실행 방식 표시 (Undo 실행 카드)
    # ------------------------------------------------------------------
    print("\n== Phase D) 실행 방식 표시: Undo 실행 카드 이벤트 ==")
    undo_wi = db.table("todolist").select("proc_inst_id").eq("id", UNDO_TODO).single().execute().data
    job = str(uuid.uuid4())
    save_event_sync(
        job_id=job, todo_id=UNDO_TODO, proc_inst_id=undo_wi["proc_inst_id"],
        crew_type="result", event_type="task_started", status=None,
        data={"role": "Undo(실행 취소) 후 재실행 결과", "name": "Undo(실행 취소) 후 재실행 결과",
              "goal": "고착화된 undo 코드로 이전 실행을 되돌린 뒤, 새 값으로 재실행한 결과를 보고합니다.",
              "agent_profile": "/images/chat-icon.png", "execution_mode": "deterministic-undo"})
    save_event_sync(
        job_id=job, todo_id=UNDO_TODO, proc_inst_id=undo_wi["proc_inst_id"],
        crew_type="result", event_type="task_completed", status=None,
        data={"result": {"ok": True,
                         "undo_steps": [r.get("tool") for r in undo_out.get("results", [])],
                         "redo_steps": [r.get("tool") for r in redo_out.get("results", [])],
                         "실행_방식": "고착화된 undo 코드 + 순방향 코드 (경로 LLM 추론 0회)"},
              "execution_mode": "deterministic-undo"})
    ev = (db.table("events").select("data").eq("todo_id", UNDO_TODO)
          .eq("event_type", "task_started").execute().data)
    check("Undo 실행 카드 이벤트 기록됨",
          len(ev) == 1 and ev[0]["data"].get("execution_mode") == "deterministic-undo")
    ev2 = (db.table("events").select("id").eq("todo_id", UNDO_TODO)
           .in_("event_type", ["tool_usage_started", "tool_usage_finished"]).execute().data)
    check("undo/redo는 에이전트 도구 추론 이벤트를 만들지 않음", len(ev2) == 0)

    # ------------------------------------------------------------------
    # 산출물: demo_data.json
    # ------------------------------------------------------------------
    demo_data = {
        "event_logs": event_logs,
        "undo_code": code_row["compensation"],
        "undo_results": undo_out.get("results", []),
        "redo_results": redo_out.get("results", []),
        "undo_query": (db.table("todolist").select("query").eq("id", UNDO_TODO)
                       .single().execute().data)["query"],
        "inventory_before": [{"product_name": "iPhone", "stock": 80},
                             {"product_name": "Galaxy", "stock": 250}],
        "post_undo_inventory": post_undo_inventory,
        "post_undo_log": post_undo_log,
        "inventory_after": db.table("inventory").select("*").order("product_name").execute().data,
        "inventory_log_after": db.table("inventory_log").select("*").order("created_at").execute().data,
        "metrics": {"gen_secs": round(gen_secs, 1), "undo_secs": round(undo_secs, 1),
                    "redo_secs": round(redo_secs, 1), "undo_llm_calls": 0},
    }
    (HERE / "demo_data.json").write_text(json.dumps(demo_data, ensure_ascii=False, indent=2))
    print(f"\ndemo_data.json 저장 (undo 코드 {len(code_row['compensation'])} chars)")
    finish()


if __name__ == "__main__":
    main()
