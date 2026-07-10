#!/usr/bin/env python
"""strategy_ontology-sync E2E 러너.

상시 소스 실행 서버(8114, MEASURE_AUTO_START=false, OPENAI_API_KEY 미설정)를 대상으로
플랫폼 원천 데이터(proc_def/users/조직도/skills/todolist)를 seed 한 뒤
POST /api/ontology/sync 로 인제스천하고, GET /api/ontology/graph 로 4레이어 노드/관계가
반영됐는지 검증한다. LLM 미설정이므로 스킬 관계 추출은 보류(pending) 경로를 검증한다.

실행:
  services/strategy/.venv/bin/python \
    openspec/specs/strategy_ontology-sync/e2e/run_e2e.py

인프라: process-gpt-age-postgres (127.0.0.1:55433).
"""
import json
import os
import sys
import time
import uuid

import httpx
from sqlalchemy import create_engine, text

BASE = os.getenv("E2E_BASE_URL", "http://127.0.0.1:8114")
engine = create_engine("postgresql://postgres:postgres@127.0.0.1:55433/postgres")

RESULTS: list[tuple[str, bool, str]] = []


def check(name: str, cond: bool, detail: str = "") -> None:
    RESULTS.append((name, bool(cond), detail))
    print(("PASS" if cond else "FAIL"), "-", name, "" if cond else f":: {detail}")


def db(sql: str, **p) -> None:
    with engine.begin() as c:
        c.execute(text(sql), p)


DDL = """
create table if not exists public.proc_def (id text primary key, name text, tenant_id text, isdeleted boolean default false);
alter table public.proc_def add column if not exists definition jsonb;
create table if not exists public.users (id uuid primary key, username text, email text, tenant_id text, is_agent boolean default false, skills text, role text);
create table if not exists public.configuration (key text, value jsonb, tenant_id text);
create table if not exists public.todolist (id uuid primary key, user_id text, proc_def_id text, activity_id text, status text, start_date timestamptz, end_date timestamptz, duration integer, tenant_id text);
create table if not exists public.agent_skills (user_id text, tenant_id text, skill_name text);
create table if not exists public.skills (id uuid primary key default gen_random_uuid(), tenant_id text, name text, description text, updated_at timestamptz default now());
"""


def ensure_tables() -> None:
    for stmt in DDL.split(";"):
        if stmt.strip():
            db(stmt)


def seed_user(tid, username, email=None, is_agent=False):
    uid = str(uuid.uuid4())
    db("""insert into public.users (id, username, email, tenant_id, is_agent)
          values (cast(:id as uuid), :u, :e, :t, :a)""",
       id=uid, u=username, e=email, t=tid, a=is_agent)
    return uid


def seed_proc_def(tid, name, definition, pid=None):
    pid = pid or f"pd-{uuid.uuid4()}"
    db("""insert into public.proc_def (id, name, tenant_id, isdeleted, definition)
          values (:id, :name, :t, false, cast(:d as jsonb))
          on conflict (id) do update set name=excluded.name, definition=excluded.definition, isdeleted=false""",
       id=pid, name=name, t=tid, d=json.dumps(definition))
    return pid


def labels(payload):
    return {n["label"] for n in payload["nodes"]}


def rel_types(payload):
    return {e["rel_type"] for e in payload["edges"]}


def has_edge(payload, rel, src=None, dst=None):
    return any(e["rel_type"] == rel and (src is None or e["source"] == src)
               and (dst is None or e["target"] == dst) for e in payload["edges"])


def main() -> int:
    ensure_tables()
    ts = int(time.time())
    c = httpx.Client(base_url=BASE, timeout=30)
    tid = f"e2e-sync-{ts}"

    # ------------------------------------------------ seed 4레이어 원천
    human = seed_user(tid, "홍길동", email="hong@x.com", is_agent=False)
    agent = seed_user(tid, "리포트봇", is_agent=True)
    member = seed_user(tid, "팀원", email="m@x.com", is_agent=False)

    definition = {
        "roles": [{"name": "담당자", "default": human}],
        "activities": [
            {"id": "a1", "name": "접수", "role": "담당자"},
            {"id": "a2", "name": "자동 처리", "agent": agent},
            {"id": "a3", "name": "완료"},
        ],
    }
    pd = seed_proc_def(tid, "민원처리", definition)

    # 조직도: 본부 > 1팀 > 팀원
    chart = {
        "id": "root",
        "data": {"id": "team-root", "name": "본부", "isTeam": True},
        "children": [{
            "data": {"id": "team-sub", "name": "1팀", "isTeam": True},
            "children": [{"data": {"id": member, "name": "팀원", "isTeam": False, "email": "m@x.com"}}],
        }],
    }
    db("""insert into public.configuration (key, value, tenant_id)
          values ('organization', cast(:v as jsonb), :t)""",
       v=json.dumps({"chart": chart}), t=tid)

    # 스킬 + agent_skills (USES_SKILL)
    for name, body in (("PPTX 생성", "슬라이드를 만든다"),
                       ("리포트 작성", "PPTX 생성 스킬을 호출해 보고서를 만든다")):
        db("insert into public.skills (tenant_id, name, description) values (:t,:n,:d)",
           t=tid, n=name, d=body)
        db("insert into public.agent_skills (user_id, tenant_id, skill_name) values (:u,:t,:s)",
           u=agent, t=tid, s=name)

    # todolist DONE — PERFORMS 실행 지표(1h, 2h → 평균 1.5h)
    for hours in (1, 2):
        db("""insert into public.todolist
              (id, user_id, proc_def_id, activity_id, status, start_date, end_date, tenant_id)
              values (gen_random_uuid(), :u, :pd, 'a2', 'DONE',
                      now() - make_interval(hours => :h), now(), :t)""",
           u=agent, pd=pd, h=hours, t=tid)

    # ------------------------------------------------ 인제스천
    sync = c.post(f"/api/ontology/sync?tenant_id={tid}").json()
    check("인제스천 결과에 last_synced_at 포함", "last_synced_at" in sync, str(sync.keys()))
    check("인제스천 요약: users/processes merged",
          sync["users"]["merged"] == 3 and sync["processes"]["merged"] == 1, str(sync))

    # LLM 미설정 → 스킬 노드는 생성되고 관계 추출은 보류(pending)로 기록
    check("스킬 관계 추출 보류(pending, LLM 미설정)",
          set(sync["skills"]["pending_extraction"]) == {"PPTX 생성", "리포트 작성"},
          str(sync["skills"]))

    g = c.get(f"/api/ontology/graph?tenant_id={tid}").json()

    # ------------------------------------------------ 노드 라벨 존재 검증
    lbls = labels(g)
    for lbl in ("Process", "Task", "User", "Agent", "Team", "Skill"):
        check(f"노드 라벨 {lbl} 존재", lbl in lbls, f"labels={lbls}")

    # 프로세스/태스크 분해
    task_ids = {n["id"] for n in g["nodes"] if n["label"] == "Task"}
    check("proc_def 3활동 → Task 노드 3개", len(task_ids) == 3, str(task_ids))

    # ------------------------------------------------ 관계 검증
    rts = rel_types(g)
    for rel in ("CONTAINS_TASK", "PERFORMS", "HAS_SUB_TEAM", "MEMBER_OF", "USES_SKILL"):
        check(f"관계 {rel} 존재", rel in rts, f"rel_types={rts}")

    check("CONTAINS_TASK: Process→Task(a1)", has_edge(g, "CONTAINS_TASK", pd, f"{pd}:a1"))
    check("PERFORMS(정의): User(담당자)→Task a1", has_edge(g, "PERFORMS", human, f"{pd}:a1"))
    check("PERFORMS(정의): Agent→Task a2", has_edge(g, "PERFORMS", agent, f"{pd}:a2"))
    check("HAS_SUB_TEAM: 본부→1팀", has_edge(g, "HAS_SUB_TEAM", "team-root", "team-sub"))
    check("MEMBER_OF: 팀원→1팀", has_edge(g, "MEMBER_OF", member, "team-sub"))
    check("USES_SKILL: Agent→Skill(PPTX 생성 slug=pptx-생성)",
          has_edge(g, "USES_SKILL", agent, "pptx-생성"),
          "USES_SKILL 엣지 없음: " + str([(e["source"], e["target"]) for e in g["edges"] if e["rel_type"] == "USES_SKILL"]))

    # PERFORMS 실행 지표(a2, 평균 1.5h)
    perf = next((e for e in g["edges"]
                 if e["rel_type"] == "PERFORMS" and e["source"] == agent and e["target"] == f"{pd}:a2"), None)
    check("PERFORMS 실행 지표 count=2, avg=1.5h",
          perf is not None and int(perf["properties"].get("count", 0)) == 2
          and abs(float(perf["properties"].get("avg_duration_hours", 0)) - 1.5) < 0.01,
          str(perf["properties"] if perf else None))

    # ------------------------------------------------ 수정분 반영(중복 없음)
    db("update public.proc_def set name = :n where id = :id", n="민원처리(개편)", id=pd)
    c.post(f"/api/ontology/sync?tenant_id={tid}")
    g2 = c.get(f"/api/ontology/graph?tenant_id={tid}").json()
    procs = [n for n in g2["nodes"] if n["label"] == "Process"]
    check("수정분 반영: Process 이름 갱신 + 중복 없음",
          len(procs) == 1 and procs[0]["name"] == "민원처리(개편)", str([p["name"] for p in procs]))

    # ------------------------------------------------ 삭제분 반영
    db("update public.proc_def set isdeleted = true where id = :id", id=pd)
    c.post(f"/api/ontology/sync?tenant_id={tid}")
    g3 = c.get(f"/api/ontology/graph?tenant_id={tid}").json()
    check("삭제분 반영: Process/Task 제거",
          not any(n["label"] == "Process" for n in g3["nodes"])
          and not any(n["label"] == "Task" for n in g3["nodes"]),
          str(labels(g3)))

    c.close()
    for tbl in ("proc_def", "users", "configuration", "todolist", "agent_skills", "skills"):
        db(f"delete from public.{tbl} where tenant_id = :t", t=tid)

    total = len(RESULTS)
    passed = sum(1 for _, ok, _ in RESULTS if ok)
    print(f"\n=== SUMMARY: {passed}/{total} PASSED ===")
    return 0 if passed == total else 1


if __name__ == "__main__":
    sys.exit(main())
