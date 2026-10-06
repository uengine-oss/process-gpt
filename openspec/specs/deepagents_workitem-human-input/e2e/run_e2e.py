"""E2E — DeepAgents 워크아이템 사람 질문 대기·재개 (spec: deepagents_workitem-human-input).

두 suite 가 있다.

  sdk  : LLM 없음. 실제 SDK 폴러(fetch_pending_task) → 실행 → 결과 저장 경로를
         질문 이벤트를 내는 실행기로 돌린다. HITL-01~06.
  live : 실제 DeepAgents 워커 + 실제 LLM + 워크아이템 화면(Playwright).
         HITL-01, 05, 07, 09, 10, 11.

실행 (process-gpt-agent-sdk 가 설치된 venv — 보통 process-gpt-deepagents/.venv):

  <deepagents>/.venv/bin/python run_e2e.py sdk
  E2E_USER_EMAIL=... E2E_USER_PASSWORD=... <deepagents>/.venv/bin/python run_e2e.py live

설정(환경 변수, 괄호는 기본값)
  PG_CONTAINER      (supabase_db_process-gpt-vue3)  psql 을 실행할 DB 컨테이너
  DEEPAGENTS_DIR    (<ws>/process-gpt-deepagents)
  VUE3_DIR          (<ws>/process-gpt-vue3)  Playwright 를 빌려 쓴다
  APP_URL           (http://localhost:8088)
  WORKER_PORT       (18888)
  E2E_USER_EMAIL / E2E_USER_PASSWORD   live suite 화면 로그인
  E2E_TENANT        (localhost)
  E2E_TEMPLATE_TODO_ID   live suite 가 복제할 deepagents 프로세스 워크아이템(없으면 자동 선택)

SDK 접속 정보(SUPABASE_URL/SUPABASE_KEY)는 sdk suite 에서 DEEPAGENTS_DIR/.env 를 읽는다.
"""
from __future__ import annotations

import asyncio
import json
import os
import signal
import subprocess
import sys
import time
import uuid
from pathlib import Path

HERE = Path(__file__).resolve().parent
WS = HERE.parents[5]  # .../ws
PG_CONTAINER = os.environ.get("PG_CONTAINER", "supabase_db_process-gpt-vue3")
DEEPAGENTS_DIR = Path(os.environ.get("DEEPAGENTS_DIR", WS / "process-gpt-deepagents"))
VUE3_DIR = Path(os.environ.get("VUE3_DIR", WS / "process-gpt-vue3"))
APP_URL = os.environ.get("APP_URL", "http://localhost:8088")
WORKER_PORT = os.environ.get("WORKER_PORT", "18888")
TENANT = os.environ.get("E2E_TENANT", "localhost")

RESULTS: list[tuple[str, str, bool, str]] = []


def check(case: str, title: str, ok: bool, detail: str = "") -> bool:
    RESULTS.append((case, title, bool(ok), detail))
    print(f"  [{'PASS' if ok else 'FAIL'}] {case} {title}" + (f" — {detail}" if detail and not ok else ""))
    return ok


def psql(sql: str) -> str:
    return subprocess.run(
        ["docker", "exec", PG_CONTAINER, "psql", "-U", "postgres", "-At", "-c", sql],
        check=True, capture_output=True, text=True,
    ).stdout.strip()


def row(todo_id: str) -> dict:
    out = psql(f"select row_to_json(t) from (select status, draft_status, consumer, lease_until, output, draft, feedback "
               f"from todolist where id='{todo_id}') t")
    return json.loads(out) if out else {}


def event_types(todo_id: str) -> list[str]:
    out = psql(f"select coalesce(event_type::text,'-') from events where todo_id='{todo_id}' order by timestamp")
    return out.splitlines() if out else []


def cleanup(todo_id: str) -> None:
    psql(f"delete from events where todo_id='{todo_id}'; "
         f"delete from notifications where url like '%{todo_id}%'; "
         f"delete from todolist where id='{todo_id}'")


def load_env_file(path: Path) -> None:
    if not path.exists():
        return
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        os.environ.setdefault(k.strip(), v.strip())


# ---------------------------------------------------------------------------
# sdk suite — LLM 없이 실제 SDK 폴링 경로
# ---------------------------------------------------------------------------

async def run_sdk_suite() -> None:
    load_env_file(DEEPAGENTS_DIR / ".env")
    from a2a.helpers import new_text_artifact_update_event, new_text_status_update_event
    from a2a.server.agent_execution import AgentExecutor
    from a2a.types import TaskState
    from google.protobuf.json_format import ParseDict

    from processgpt_agent_sdk.database import get_consumer_id, initialize_db, polling_pending_todos
    from processgpt_agent_sdk.event_coalescer import flush_events_now
    from processgpt_agent_sdk.processgpt_agent_framework import ProcessGPTAgentServer

    orch = f"e2e-hitl-{uuid.uuid4().hex[:6]}"
    question = "결재 금액 상한이 얼마입니까?"

    async def ask(ctx, q, *, artifact=True):
        evt = new_text_status_update_event(
            task_id=ctx.task_id, context_id=ctx.context_id,
            state=TaskState.TASK_STATE_INPUT_REQUIRED,
            text=json.dumps({"question": question, "type": "text"}, ensure_ascii=False),
        )
        ParseDict({"event_type": "human_asked", "job_id": str(uuid.uuid4()), "crew_type": "agent"}, evt.metadata)
        await q.enqueue_event(evt)
        if artifact:
            await final(ctx, q, f"{question}\n\n")

    async def final(ctx, q, text):
        await q.enqueue_event(new_text_artifact_update_event(
            task_id=ctx.task_id, context_id=ctx.context_id, name="assistant_response", text=text, last_chunk=True,
        ))

    class Executor(AgentExecutor):
        def __init__(self, behavior):
            self.behavior = behavior

        async def execute(self, context, event_queue):
            await self.behavior(context, event_queue)

        async def cancel(self, context, event_queue):
            pass

    async def asks(ctx, q):
        await ask(ctx, q)

    async def asks_status_only(ctx, q):
        await ask(ctx, q, artifact=False)

    async def asks_then_continues(ctx, q):
        await ask(ctx, q, artifact=False)
        working = new_text_status_update_event(
            task_id=ctx.task_id, context_id=ctx.context_id, state=TaskState.TASK_STATE_WORKING, text="{}")
        # 실제 에이전트처럼 event_type 을 명시한다. events.event_type 은 NOT NULL 이다.
        ParseDict({"event_type": "task_working"}, working.metadata)
        await q.enqueue_event(working)
        await final(ctx, q, json.dumps({"limit": 5000000}))

    async def cancelled_then_asks(ctx, q):
        psql(f"update todolist set draft_status='CANCELLED' where id='{ctx.task_id}'")
        await ask(ctx, q)

    async def run_case(mode: str, behavior) -> str:
        todo_id = str(uuid.uuid4())
        psql(f"insert into todolist (id, proc_inst_id, activity_name, status, agent_mode, agent_orch, tenant_id, start_date) "
             f"values ('{todo_id}', 'e2e-hitl-{todo_id[:8]}', 'HITL E2E', 'IN_PROGRESS', '{mode}', '{orch}', '{TENANT}', now())")
        picked = await polling_pending_todos(orch, get_consumer_id())
        assert picked and str(picked["id"]) == todo_id, f"poller did not pick {todo_id}: {picked}"
        await ProcessGPTAgentServer(Executor(behavior), orch).process_todolist_item(picked)
        await asyncio.sleep(1.5)  # create_task 로 띄운 저장이 끝나도록
        await flush_events_now()
        await asyncio.sleep(0.5)
        return todo_id

    initialize_db()
    print("\n== sdk suite (LLM 없음) ==")

    # HITL-01 / 05 / 07(DB 측) — COMPLETE
    t = await run_case("COMPLETE", asks)
    r, ev = row(t), event_types(t)
    check("HITL-01", "COMPLETE: 질문하고 끝나면 HUMAN_ASKED", r.get("status") == "IN_PROGRESS" and r.get("draft_status") == "HUMAN_ASKED", str(r))
    check("HITL-01", "COMPLETE: output 비어 있음", r.get("output") is None, str(r.get("output")))
    check("HITL-01", "COMPLETE: human_asked 있고 crew_completed 없음", "human_asked" in ev and "crew_completed" not in ev, str(ev))
    check("HITL-05", "대기 작업의 점유가 풀림", r.get("consumer") is None and r.get("lease_until") is None, str(r))
    idle = await polling_pending_todos(orch, get_consumer_id())
    check("HITL-05", "답 전에는 폴링에 걸리지 않음", not idle, str(idle and idle.get("id")))
    psql(f"""update todolist set feedback='[{{"content":"500만원"}}]', draft_status='FB_REQUESTED' where id='{t}'""")
    again = await polling_pending_todos(orch, get_consumer_id())
    check("HITL-09", "답(FB_REQUESTED) 후 다시 집힘", bool(again) and str(again["id"]) == t)
    cleanup(t)

    # HITL-02 — DRAFT
    t = await run_case("DRAFT", asks)
    r = row(t)
    check("HITL-02", "DRAFT: HUMAN_ASKED, draft 비어 있음", r.get("draft_status") == "HUMAN_ASKED" and r.get("draft") is None, str(r))
    cleanup(t)

    # HITL-03 — 결과 없이 질문만
    t = await run_case("COMPLETE", asks_status_only)
    r = row(t)
    check("HITL-03", "결과 없이 질문만 남겨도 HUMAN_ASKED (STARTED 고아 아님)", r.get("draft_status") == "HUMAN_ASKED", str(r))
    cleanup(t)

    # HITL-04 — 같은 실행 안에서 답을 받아 이어 감
    t = await run_case("COMPLETE", asks_then_continues)
    r, ev = row(t), event_types(t)
    check("HITL-04", "같은 실행에서 이어 가면 결과로 제출", r.get("status") == "SUBMITTED" and r.get("output") == {"limit": 5000000}, str(r))
    check("HITL-04", "crew_completed 기록", "crew_completed" in ev, str(ev))
    cleanup(t)

    # HITL-06 — 취소 우선
    t = await run_case("COMPLETE", cancelled_then_asks)
    r = row(t)
    check("HITL-06", "대기 표시 전 취소는 CANCELLED 유지", r.get("draft_status") == "CANCELLED", str(r))
    cleanup(t)


# ---------------------------------------------------------------------------
# live suite — 실제 DeepAgents 워커 + LLM + 화면
# ---------------------------------------------------------------------------

LIVE_QUESTION = "이번 주 납기 지연 허용 기준이 며칠입니까?"
LIVE_ANSWER = "5일까지 허용합니다"
LIVE_QUERY = (
    "이 작업을 시작하기 전에 반드시 request_human_input 도구로 사용자에게 "
    f"\"{LIVE_QUESTION}\" 라고 질문하고 답을 받은 뒤에만 진행하세요. "
    "답을 받으면 그 기준(일수)을 명시해 납기 모니터링 결과를 짧게 작성하세요. "
    "외부 시스템 조회는 하지 말고, 데이터가 없으면 없다고 적으세요."
)


def wait_state(todo_id: str, done, timeout: int, worker: subprocess.Popen) -> dict:
    deadline = time.time() + timeout
    while time.time() < deadline:
        r = row(todo_id)
        if done(r):
            return r
        if worker.poll() is not None:
            raise RuntimeError("deepagents 워커가 종료됨")
        time.sleep(3)
    return row(todo_id)


def claimable_deepagents_rows() -> list[str]:
    out = psql("select id from todolist where status='IN_PROGRESS' and agent_orch='deepagents' and ("
               "(agent_mode in ('DRAFT','COMPLETE') and draft is null and draft_status is null) "
               "or draft_status='FB_REQUESTED' or (draft_status='STARTED' and lease_until < now()))")
    return out.splitlines() if out else []


def run_live_suite() -> None:
    print("\n== live suite (실제 DeepAgents + LLM + 화면) ==")
    email, password = os.environ.get("E2E_USER_EMAIL"), os.environ.get("E2E_USER_PASSWORD")
    if not (email and password):
        sys.exit("E2E_USER_EMAIL / E2E_USER_PASSWORD 가 필요하다 (화면 로그인)")
    others = claimable_deepagents_rows()
    if others:
        sys.exit(f"워커가 집을 다른 deepagents 작업이 있어 중단한다: {others}")

    # 워크아이템 화면은 프로세스 정의에 붙은 작업일 때 에이전트 모니터(질문 카드)를 보인다.
    # 정의 없는 작업은 자유입력 화면이 떠서 카드가 없다. 그래서 기존 deepagents 프로세스
    # 작업 하나를 틀로 복제한다(프로세스·활동·폼 연결만 빌리고 상태는 새로 둔다).
    template = os.environ.get("E2E_TEMPLATE_TODO_ID") or psql(
        f"select id from todolist where agent_orch='deepagents' and tenant_id='{TENANT}' "
        "and proc_def_id is not null and proc_inst_id is not null and activity_name not like '[HITL E2E]%' "
        "order by start_date desc nulls last limit 1")
    if not template:
        sys.exit("틀로 쓸 deepagents 프로세스 워크아이템이 없다 — E2E_TEMPLATE_TODO_ID 를 지정하라")
    todo_id = str(uuid.uuid4())
    user_id = psql(f"select id from users where email='{email}' limit 1") or None
    patch = json.dumps({
        "id": todo_id, "status": "IN_PROGRESS", "agent_mode": "COMPLETE", "agent_orch": "deepagents",
        "draft": None, "draft_status": None, "output": None, "feedback": None, "consumer": None,
        "lease_until": None, "claim_count": 0, "activity_name": "[HITL E2E] 납기 모니터링",
        "user_id": user_id, "query": LIVE_QUERY,
    }, ensure_ascii=False).replace("'", "''")
    psql(f"insert into todolist select (jsonb_populate_record(t, '{patch}'::jsonb || "
         f"jsonb_build_object('start_date', now()::timestamp))).* from todolist t where id='{template}'")
    print(f"  todo {todo_id} (template {template})")

    log_path = HERE / "worker.log"
    log = open(log_path, "w")
    worker = subprocess.Popen(
        [str(DEEPAGENTS_DIR / ".venv/bin/python"), "server.py"],
        cwd=DEEPAGENTS_DIR, stdout=log, stderr=subprocess.STDOUT,
        env={**os.environ, "PORT": WORKER_PORT, "PYTHONUNBUFFERED": "1"},
        start_new_session=True,
    )
    try:
        r = wait_state(todo_id, lambda r: r.get("draft_status") not in (None, "STARTED"), 600, worker)
        ev = event_types(todo_id)
        tool_called = psql(f"select count(*) from events where todo_id='{todo_id}' and data->>'tool'='request_human_input'")
        check("HITL-11", "에이전트가 질문 도구로 물음", tool_called != "0" and "human_asked" in ev, str(ev))
        check("HITL-01", "질문 후 IN_PROGRESS / HUMAN_ASKED", r.get("status") == "IN_PROGRESS" and r.get("draft_status") == "HUMAN_ASKED", str(r))
        check("HITL-01", "output 비어 있고 crew_completed 없음", r.get("output") is None and "crew_completed" not in ev, f"{r.get('output')} {ev}")

        time.sleep(15)  # 워커가 돌고 있는 동안 대기 작업이 다시 집히지 않는지
        check("HITL-05", "워커 가동 중에도 대기 작업을 집지 않음", row(todo_id).get("draft_status") == "HUMAN_ASKED")

        ui = subprocess.run(
            ["node", str(HERE / "ui_answer.mjs"), todo_id, LIVE_ANSWER, "납기 지연 허용 기준"],
            capture_output=True, text=True, timeout=180,
            env={**os.environ, "VUE3_DIR": str(VUE3_DIR), "APP_URL": APP_URL,
                 "SHOT_DIR": str(HERE / "screenshots")},
        )
        ui_out = json.loads((ui.stdout.strip().splitlines() or ["{}"])[-1]) if ui.returncode == 0 else {}
        check("HITL-07", "질문 카드에 질문 문구가 보임", ui_out.get("questionShown") is True, ui.stderr[-500:])
        time.sleep(2)
        r = row(todo_id)
        fb = r.get("feedback") or []
        check("HITL-07", "답하면 FB_REQUESTED 또는 이미 재개됨", r.get("draft_status") in ("FB_REQUESTED", "STARTED", "COMPLETED"), str(r))
        check("HITL-07", "feedback 마지막 항목이 입력한 답", bool(fb) and fb[-1].get("content") == LIVE_ANSWER, str(fb))
        check("HITL-07", "human_response 기록", "human_response" in event_types(todo_id))

        r = wait_state(todo_id, lambda r: r.get("status") == "SUBMITTED" or r.get("draft_status") in ("FAILED", "HUMAN_ASKED"), 600, worker)
        time.sleep(4)
        out_text = json.dumps(r.get("output"), ensure_ascii=False)
        check("HITL-09", "재개 후 SUBMITTED / COMPLETED", r.get("status") == "SUBMITTED" and r.get("draft_status") == "COMPLETED", str(r)[:300])
        check("HITL-09", "결과에 답(5일)이 반영됨", "5일" in out_text or "5 일" in out_text, out_text[:300])
        log.flush()
        log_text = log_path.read_text()
        check("HITL-09", "멈춘 지점에서 재개(graph resume)", "HITL 그래프 재개" in log_text)
        ev = event_types(todo_id)
        need = ["task_started", "human_asked", "human_response", "task_completed", "crew_completed"]
        check("HITL-10", "이벤트가 모두 저장됨", all(n in ev for n in need) and ev.count("crew_completed") == 1, str(ev))
        check("HITL-10", "워커 로그에 이벤트 저장 실패 없음",
              "record_events_bulk failed" not in log_text and "event_type_enum" not in log_text)
        print(f"  events: {', '.join(ev)}")
        print(f"  output: {out_text[:400]}")
    finally:
        os.killpg(worker.pid, signal.SIGTERM)
        worker.wait(timeout=30)
        log.close()
        cleanup(todo_id)


def main() -> None:
    suites = sys.argv[1:] or ["sdk"]
    for s in suites:
        if s == "sdk":
            asyncio.run(run_sdk_suite())
        elif s == "live":
            run_live_suite()
        else:
            sys.exit(f"unknown suite: {s}")
    passed = sum(1 for r in RESULTS if r[2])
    print(f"\nRESULT {passed}/{len(RESULTS)} PASS")
    sys.exit(0 if passed == len(RESULTS) else 1)


if __name__ == "__main__":
    main()
