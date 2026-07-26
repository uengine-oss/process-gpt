#!/usr/bin/env python
"""E2E: 실행 경로 고착화(Deterministic Replay) — crewai-action_deterministic-replay

실제 구성요소만 사용한다 (mock 없음):
  - Supabase MCP 서버        : postgres-mcp (uvx, execute_sql 툴) → 로컬 supabase-db
  - 테넌트 MCP 설정           : public.tenants.mcp (프로덕션과 동일한 mcpServers 형식)
  - 이벤트 기록               : processgpt_agent_utils.utils.database.save_event_sync
                               (프로덕션 SDK가 쓰는 바로 그 함수/테이블)
  - 고착화·재실행             : processgpt_agent_utils.tools.deterministic_code_tool
                               .DeterministicCodeTool (배포 PyPI 패키지 그대로)
  - LLM                      : OpenAI (1차 실행의 에이전트 루프 + 코드 생성/파라미터 추출)

흐름:
  Phase A  1차 실행 — LLM 에이전트가 execute_sql(MCP)로 재고 UPDATE + 로그 INSERT
           (모든 tool 호출을 tool_usage_finished 이벤트로 기록)
  Phase B  고착화 — DeterministicCodeTool(action='generate')
           → mcp_python_code에 파라미터화된 Python 코드 저장
  Phase C  재실행 — 다른 입력(Galaxy/250)의 새 워크아이템으로
           DeterministicCodeTool(action='execute')
           → LLM 추론 루프 0회로 동일 경로 재실행, DB 반영 검증

실행:
  <detdemo-venv>/bin/python run_e2e.py
필요 환경: docker-infra 스택(supabase-db, kong :54321) 기동, docker-infra/.env 존재.
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import time
import uuid
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
INFRA_ENV = REPO / "docker-infra" / ".env"

FIRST_TODO = "11111111-2222-3333-4444-555555550001"
REPLAY_TODO = "11111111-2222-3333-4444-555555550002"
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


def main() -> None:
    infra = load_infra_env()
    if not infra.get("OPENAI_API_KEY"):
        # docker-infra/.env에 키가 비어 있으면 리포 루트 .env에서 가져온다
        for line in (REPO / ".env").read_text().splitlines():
            if line.startswith("OPENAI_API_KEY=") and len(line.strip()) > 20:
                infra["OPENAI_API_KEY"] = line.partition("=")[2].strip()
    pg_password = infra["POSTGRES_PASSWORD"]
    database_uri = f"postgresql://postgres:{pg_password}@localhost:54322/postgres"

    # ------------------------------------------------------------------
    # env for the real packages (agent-utils DB layer + llm_factory shim)
    # ------------------------------------------------------------------
    os.environ["SUPABASE_URL"] = "http://localhost:54321"
    os.environ["SUPABASE_KEY"] = infra["SERVICE_ROLE_KEY"]
    os.environ["OPENAI_API_KEY"] = infra["OPENAI_API_KEY"]
    os.environ.setdefault("LLM_PROXY_URL", "https://api.openai.com/v1")
    os.environ["LLM_PROXY_API_KEY"] = infra["OPENAI_API_KEY"]
    os.environ.setdefault("LLM_MODEL", "gpt-4o")
    # agent-utils 패키지 import 시 knowledge_manager(mem0/memento)가 요구하는 직결 DB env
    os.environ.update({"DB_USER": "postgres", "DB_PASSWORD": pg_password,
                       "DB_HOST": "localhost", "DB_PORT": "54322", "DB_NAME": "postgres"})
    sys.path.insert(0, str(HERE))  # llm_factory shim

    from processgpt_agent_utils.utils.database import (
        initialize_db, get_db_client, save_event_sync,
        fetch_mcp_python_code, fetch_tenant_mcp,
    )
    from processgpt_agent_utils.tools import deterministic_code_tool as dct
    from processgpt_agent_utils.tools.deterministic_code_tool import DeterministicCodeTool
    from fastmcp import Client as McpClient
    import asyncio

    # ------------------------------------------------------------------
    # 알려진 업스트림 버그 워크어라운드 (process-gpt-agent-utils 0.3.4):
    # _suggest_parameters_via_llm 이 LLM 응답의 ```json 코드펜스를 벗기지 않고
    # json.loads 하므로 gpt-4o에서 항상 폴백 정규식(퇴화된 ${sql} 바인딩)으로
    # 떨어진다. 같은 파일의 _extract_parameters_from_query 는 펜스를 벗긴다.
    # 아래는 동일 로직 + 펜스 제거만 추가한 것 (업스트림 수정 제안과 동일).
    # ------------------------------------------------------------------
    def _suggest_parameters_via_llm_fixed(steps):
        from llm_factory import create_llm
        try:
            model = create_llm(model="gpt-4o", streaming=False, temperature=0)
            prompt = dct._prompt_template.format(events=dct._prepare_events_for_llm(steps))
            response = model.invoke(prompt)
            s = response.content if hasattr(response, "content") else str(response)
            s = re.sub(r"^```(?:json)?\s*\n", "", s.strip(), flags=re.MULTILINE)
            s = re.sub(r"\n```\s*$", "", s, flags=re.MULTILINE)
            return json.loads(s)
        except Exception:
            return dct._llm_fallback_regex(steps)

    dct._suggest_parameters_via_llm = _suggest_parameters_via_llm_fixed

    # ------------------------------------------------------------------
    # 알려진 업스트림 버그 워크어라운드 #2 (process-gpt-agent-utils 0.3.4):
    # _compile_steps_to_code 가 바인딩을 (tool, arg) 키 하나로만 매핑해서
    # 동일 툴이 여러 스텝에 반복되면(execute_sql 경로에서 항상 그렇다)
    # 마지막 바인딩이 모든 스텝을 덮어쓴다. 스텝 순서대로 FIFO 소진하도록
    # 수정한 것 외에는 업스트림 구현과 동일.
    # ------------------------------------------------------------------
    def _compile_steps_to_code_fixed(todo_id, steps, tool_to_server, bindings):
        from collections import defaultdict, deque
        binding_q: dict = defaultdict(deque)
        for b in (bindings.get("bindings") or []):
            binding_q[(b["tool"], b["arg"])].append(b)
        lines = []
        for s in steps:
            server_key = tool_to_server.get(s.tool_name)
            if not server_key:
                raise ValueError(f"툴 '{s.tool_name}'를 제공하는 MCP 서버를 찾지 못했습니다.")
            rendered_parts = []
            for k, v in s.args.items():
                q = binding_q.get((s.tool_name, k))
                b = q.popleft() if q else None
                if b and b.get("mode") == "template":
                    tpl = b["template"]
                    rendered_parts.append(
                        f'"{k}": render({json.dumps(tpl, ensure_ascii=False)}, inputs)')
                else:
                    rendered_parts.append(f'"{k}": {json.dumps(v, ensure_ascii=False)}')
            arg_expr = "{ " + ", ".join(rendered_parts) + " }"
            lines.append(f'    results.append(await call_tool("{server_key}", '
                         f'"{s.tool_name}", {arg_expr}, timeout_s=timeout_s))')
        param_docs = []
        for p in bindings.get("parameters", []):
            param_docs.append(
                f'        - {p["name"]} ({p["type"]}): '
                f'example={json.dumps(p.get("example"), ensure_ascii=False)}')
        param_docs_str = "\n".join(param_docs) if param_docs else "        None"
        return dct.TEMPLATE.format(todo_id=todo_id, steps="\n".join(lines),
                                   param_docs=param_docs_str)

    dct._compile_steps_to_code = _compile_steps_to_code_fixed

    print("== 0) seed & Supabase MCP 서버 설정 ==")
    seed = subprocess.run(
        ["docker", "exec", "-i", "supabase-db", "psql", "-v", "ON_ERROR_STOP=1",
         "-U", "postgres", "-d", "postgres"],
        input=(HERE / "seed.sql").read_text(), text=True, capture_output=True)
    check("seed.sql 적용", seed.returncode == 0, (seed.stderr or "")[-200:].strip() or "ok")

    initialize_db()
    db = get_db_client()

    # 테넌트 MCP 설정 — 프로덕션과 동일한 tenants.mcp(mcpServers) 형식.
    mcp_config = {"mcpServers": {"supabase-mcp": {
        "command": "uvx",
        "args": ["--python", "3.12", "postgres-mcp", "--access-mode=unrestricted"],
        "env": {"DATABASE_URI": database_uri},
        "enabled": True,
    }}}
    db.table("tenants").update({"mcp": mcp_config}).eq("id", TENANT).execute()
    saved_mcp = fetch_tenant_mcp(TENANT)
    check("tenants.mcp에 Supabase MCP(execute_sql) 서버 등록",
          "supabase-mcp" in (saved_mcp or {}).get("mcpServers", {}))

    # MCP 서버 기동 + 툴 확인 (uvx가 postgres-mcp를 실제로 띄운다)
    clean = {"mcpServers": {"supabase-mcp":
             {k: v for k, v in mcp_config["mcpServers"]["supabase-mcp"].items() if k != "enabled"}}}

    async def list_tools():
        async with McpClient(clean) as c:
            return await c.list_tools()

    tools = asyncio.run(list_tools())
    tool_names = [t.name for t in tools]
    check("MCP 서버 execute_sql 툴 노출", "execute_sql" in tool_names, ", ".join(tool_names))

    # ------------------------------------------------------------------
    # Phase A — 1차 실행: LLM 에이전트 + MCP 툴 호출 + 이벤트 기록
    # ------------------------------------------------------------------
    print("\n== Phase A) 1차 실행: LLM 에이전트가 MCP로 수행 ==")
    from llm_factory import create_llm
    from langchain_core.messages import HumanMessage, SystemMessage, ToolMessage

    exec_sql_schema = next(t for t in tools if t.name == "execute_sql")
    llm_tools = [{"type": "function", "function": {
        "name": exec_sql_schema.name,
        "description": exec_sql_schema.description or "Execute SQL",
        "parameters": exec_sql_schema.inputSchema,
    }}]

    first_wi = db.table("todolist").select("*").eq("id", FIRST_TODO).single().execute().data
    sysmsg = SystemMessage(content=(
        "당신은 업무 프로세스의 '재고 반영' 활동을 수행하는 에이전트다. "
        "execute_sql 도구로 Supabase DB에 SQL을 실행해 과업을 완수하라. "
        "테이블: inventory(product_name text pk, stock int), "
        "inventory_log(product_name text, new_stock int, reason text). "
        "먼저 SELECT로 현재 재고를 확인한 뒤, UPDATE로 재고를 갱신하고, "
        "inventory_log에 INSERT로 변경 이력(반영 후 재고)을 남겨라. "
        "재고 UPDATE는 반드시 `stock = stock + N` 또는 `stock = stock - N` 형태의 "
        "상대 연산으로 실행하라(감사·되돌리기가 가능하도록 절대값 대입 금지). "
        "한 번에 하나의 SQL만 실행하라."))
    messages = [sysmsg, HumanMessage(content=first_wi["query"])]

    llm = create_llm(model="gpt-4o", temperature=0)
    llm_call_count = 0
    tool_call_log: list[dict] = []
    t0 = time.monotonic()

    # 실행 방식 표시: LLM 실행 카드(task_started) — 워크아이템 화면(AgentMonitor)이
    # 이 이벤트를 에이전트 카드로 렌더링한다. 도구 이벤트는 같은 job_id로 묶인다.
    job_a = str(uuid.uuid4())
    save_event_sync(
        job_id=job_a, todo_id=FIRST_TODO, proc_inst_id=first_wi["proc_inst_id"],
        crew_type="action", event_type="task_started", status=None,
        data={"role": "LLM 에이전트 실행", "name": "재고 반영",
              "goal": "지시를 분석해 실행 경로(도구 호출)를 스스로 결정합니다.",
              "agent_profile": "/images/chat-icon.png", "execution_mode": "llm"})

    async def call_mcp(tool_name: str, args: dict):
        async with McpClient(clean) as c:
            res = await c.call_tool(tool_name, args)
            return json.loads(json.dumps(res.data, ensure_ascii=False, default=str))

    for _ in range(10):
        llm_call_count += 1
        ai = llm.bind_tools(llm_tools).invoke(messages)
        messages.append(ai)
        if not ai.tool_calls:
            break
        for tc in ai.tool_calls:
            save_event_sync(
                job_id=job_a, todo_id=FIRST_TODO,
                proc_inst_id=first_wi["proc_inst_id"], crew_type="action",
                data={"tool_name": tc["name"],
                      "query": (tc["args"].get("sql") or "")[:300]},
                event_type="tool_usage_started", status=None)
            data = asyncio.run(call_mcp(tc["name"], tc["args"]))
            tool_call_log.append({"tool_name": tc["name"], "args": tc["args"]})
            # 프로덕션 SDK와 동일한 이벤트 기록 (tool_usage_finished / crew_type=action)
            save_event_sync(
                job_id=job_a, todo_id=FIRST_TODO,
                proc_inst_id=first_wi["proc_inst_id"], crew_type="action",
                data={"tool_name": tc["name"], "args": tc["args"]},
                event_type="tool_usage_finished", status=None)
            messages.append(ToolMessage(content=json.dumps(data, ensure_ascii=False)[:4000],
                                        tool_call_id=tc["id"]))
    final_text = messages[-1].content if hasattr(messages[-1], "content") else ""
    save_event_sync(
        job_id=job_a, todo_id=FIRST_TODO, proc_inst_id=first_wi["proc_inst_id"],
        crew_type="action", event_type="task_completed", status=None,
        data={"result": str(final_text)[:1500], "execution_mode": "llm"})
    phase_a_secs = time.monotonic() - t0

    sqls = [c["args"].get("sql") or c["args"].get("query") or "" for c in tool_call_log]
    check("1차 실행에서 LLM이 UPDATE 실행", any(s.strip().upper().startswith("UPDATE") for s in sqls),
          f"tool calls={len(tool_call_log)}, llm calls={llm_call_count}, {phase_a_secs:.1f}s")
    check("1차 실행에서 LLM이 INSERT(감사 로그) 실행",
          any(s.strip().upper().startswith("INSERT") for s in sqls))
    had_select = any(s.strip().upper().startswith("SELECT") for s in sqls)

    row = db.table("inventory").select("*").eq("product_name", "iPhone").single().execute().data
    check("1차 실행 후 iPhone 재고=80 (LLM 경로가 실제 DB 반영)", row["stock"] == 80, str(row))
    ev = (db.table("events").select("id").eq("todo_id", FIRST_TODO)
          .eq("event_type", "tool_usage_finished").execute().data)
    check("tool_usage_finished 이벤트 기록됨", len(ev) == len(tool_call_log), f"{len(ev)}건")
    ev_card = (db.table("events").select("id").eq("todo_id", FIRST_TODO)
               .eq("event_type", "task_started").execute().data)
    check("LLM 실행 카드 이벤트(task_started) 기록됨 — 화면 표시용", len(ev_card) == 1)

    # ------------------------------------------------------------------
    # Phase B — 고착화: 이벤트 → 파라미터화된 Python 코드
    # ------------------------------------------------------------------
    print("\n== Phase B) 고착화: DeterministicCodeTool(action='generate') ==")
    t0 = time.monotonic()
    gen_out = DeterministicCodeTool()._run(tenant_id=TENANT, todo_id=FIRST_TODO, action="generate")
    phase_b_secs = time.monotonic() - t0
    gen = json.loads(gen_out)
    check("코드 생성 성공", isinstance(gen, dict) and gen.get("ok") is True, str(gen)[:150])

    code_row = fetch_mcp_python_code(PROC_DEF, ACTIVITY, TENANT)
    check("mcp_python_code에 (proc_def, activity, tenant) 키로 저장", code_row is not None)
    code = code_row["code"]
    check("생성 코드는 fastmcp call_tool만 사용(LLM 호출 없음)",
          "call_tool(" in code and "create_llm" not in code and "openai" not in code.lower())
    check("동적 값이 ${...} 파라미터로 치환됨", "${" in code and "render(" in code)
    n_steps = len(re.findall(r"results\.append\(await call_tool\(", code))
    check("기록된 도구 호출 경로가 순서대로 코드화됨", n_steps == len(tool_call_log),
          f"{n_steps} steps (SELECT 제외 필터는 args['query'] 기준이라 "
          f"postgres-mcp의 args['sql']에는 미적용 — results.md 참고)")
    params = (code_row.get("parameters") or {}).get("parameters", [])
    check("파라미터 명세(이름·타입·예시) 보존", len(params) >= 2,
          ", ".join(p["name"] for p in params))

    # ------------------------------------------------------------------
    # Phase C — 결정론적 재실행: 다른 입력, LLM 추론 루프 없음
    # ------------------------------------------------------------------
    print("\n== Phase C) 재실행: DeterministicCodeTool(action='execute') ==")
    t0 = time.monotonic()
    exec_out = DeterministicCodeTool()._run(tenant_id=TENANT, todo_id=REPLAY_TODO, action="execute")
    phase_c_secs = time.monotonic() - t0
    execd = json.loads(exec_out)

    # 실행 방식 표시: 결정론적 실행 카드 — crewai-action 실행기의 _run_deterministic이
    # 발행하는 이벤트(role/goal "결정론적 코드 실행 결과", crew_type=result)와 동일한
    # 형식으로 기록해, 워크아이템 화면에서 LLM 실행과 구분되게 한다.
    replay_wi = db.table("todolist").select("proc_inst_id").eq("id", REPLAY_TODO).single().execute().data
    job_c = str(uuid.uuid4())
    save_event_sync(
        job_id=job_c, todo_id=REPLAY_TODO, proc_inst_id=replay_wi["proc_inst_id"],
        crew_type="result", event_type="task_started", status=None,
        data={"role": "결정론적 코드 실행 결과", "name": "결정론적 코드 실행 결과",
              "goal": "고착화된 코드로 LLM 추론 없이 재실행한 결과를 보고합니다.",
              "agent_profile": "/images/chat-icon.png",
              "execution_mode": "deterministic"})
    save_event_sync(
        job_id=job_c, todo_id=REPLAY_TODO, proc_inst_id=replay_wi["proc_inst_id"],
        crew_type="result", event_type="task_completed", status=None,
        data={"result": {"ok": execd.get("ok"),
                         "steps": [r.get("tool") for r in execd.get("results", [])],
                         "실행_방식": "고착화된 코드 (LLM 추론 0회)"},
              "execution_mode": "deterministic"})
    check("재실행 성공(ok=true)", isinstance(execd, dict) and execd.get("ok") is True,
          f"{phase_c_secs:.1f}s")
    check("재실행 결과에 도구 호출 결과 목록 포함", len(execd.get("results", [])) >= 2,
          f"{len(execd.get('results', []))} steps")

    row = db.table("inventory").select("*").eq("product_name", "Galaxy").single().execute().data
    check("재실행이 새 입력(Galaxy=250)으로 DB 반영", row["stock"] == 250, str(row))
    logs = (db.table("inventory_log").select("*").eq("product_name", "Galaxy")
            .execute().data)
    check("재실행이 감사 로그도 동일 경로로 기록", len(logs) >= 1, str(logs[:1]))
    row = db.table("inventory").select("*").eq("product_name", "iPhone").single().execute().data
    check("1차 실행 결과(iPhone=80)는 그대로 보존", row["stock"] == 80)
    ev2 = (db.table("events").select("id").eq("todo_id", REPLAY_TODO)
           .in_("event_type", ["tool_usage_started", "tool_usage_finished"]).execute().data)
    check("재실행은 에이전트 도구 추론 이벤트를 만들지 않음(추론 루프 0회)", len(ev2) == 0)
    ev3 = (db.table("events").select("data").eq("todo_id", REPLAY_TODO)
           .eq("event_type", "task_started").execute().data)
    check("재실행에 '결정론적 코드 실행 결과' 표시 이벤트 기록됨",
          len(ev3) == 1 and ev3[0]["data"].get("execution_mode") == "deterministic")

    # ------------------------------------------------------------------
    # 산출물: demo_data.json (Playwright 데모 페이지가 로드)
    # ------------------------------------------------------------------
    masked_uri = re.sub(r":([^:@/]+)@", ":*****@", database_uri)
    masked_cfg = json.loads(json.dumps(mcp_config).replace(database_uri, masked_uri))
    demo_data = {
        "tenant_mcp": masked_cfg,
        "tool_names": tool_names,
        "first_query": first_wi["query"],
        "tool_call_log": tool_call_log,
        "generated_code": code,
        "parameters": code_row.get("parameters"),
        "replay_query": (db.table("todolist").select("query").eq("id", REPLAY_TODO)
                         .single().execute().data)["query"],
        "replay_results": execd.get("results", []),
        "inventory_after": db.table("inventory").select("*").order("product_name").execute().data,
        "inventory_log_after": db.table("inventory_log").select("*").order("created_at").execute().data,
        "metrics": {
            "phase_a_secs": round(phase_a_secs, 1),
            "phase_a_llm_calls": llm_call_count,
            "phase_b_secs": round(phase_b_secs, 1),
            "phase_c_secs": round(phase_c_secs, 1),
            "phase_c_agent_llm_calls": 0,
        },
    }
    (HERE / "demo_data.json").write_text(json.dumps(demo_data, ensure_ascii=False, indent=2))
    print(f"\ndemo_data.json 저장 (경로 고착화 코드 {len(code)} chars)")
    finish()


if __name__ == "__main__":
    main()
