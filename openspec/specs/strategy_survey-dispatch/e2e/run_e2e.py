#!/usr/bin/env python
"""strategy_survey-dispatch E2E 러너.

상시 소스 실행 서버(8114)를 대상으로 설문 발행→todolist 워크아이템→응답→KPI
재집계 전체 경로를 순수 HTTP(+직접 SQL 확인)로 검증한다. survey_score KPI를
만들고 완료 인스턴스를 seed 한 뒤 POST /api/measure/run 으로 watch_completions()
를 트리거해 strategy_survey_requests 행과 todolist 워크아이템(activity_id=
'kpi_survey', status='IN_PROGRESS')이 함께 생성됐는지 확인하고, POST
/api/surveys/{id}/respond 로 응답을 제출해 상태 전이(ANSWERED/DONE)와
GET /api/map 의 KPI current_value 반영을 검증한다.

실행:
  services/strategy/.venv/bin/python \
    openspec/specs/strategy_survey-dispatch/e2e/run_e2e.py

인프라: process-gpt-age-postgres (127.0.0.1:55433), uvicorn 8114(그래프 corp_ontology_e2e).
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


def check(name, cond, detail=""):
    RESULTS.append((name, bool(cond), detail))
    print(("PASS" if cond else "FAIL"), "-", name, "" if cond else f":: {detail}")


def db(sql, **p):
    with engine.begin() as c:
        return c.execute(text(sql), p)


def db_one(sql, **p):
    with engine.begin() as c:
        row = c.execute(text(sql), p).mappings().first()
        return dict(row) if row else None


DDL = """
create table if not exists public.proc_def (id text primary key, name text, tenant_id text, isdeleted boolean default false);
create table if not exists public.bpm_proc_inst (proc_inst_id text primary key, proc_inst_name text, proc_def_id text, root_proc_inst_id text, status text, tenant_id text, participants jsonb, start_date timestamptz, end_date timestamptz, is_deleted boolean default false, variables_data jsonb, updated_at timestamptz default now());
create table if not exists public.users (id uuid primary key default gen_random_uuid(), email text, username text, tenant_id text, is_agent boolean default false);
create table if not exists public.todolist (id uuid primary key, user_id text, username text, proc_inst_id text, root_proc_inst_id text, proc_def_id text, activity_id text, activity_name text, status text, start_date timestamptz, end_date timestamptz, due_date timestamptz, description text, tool text, adhoc boolean, tenant_id text, updated_at timestamptz default now());
"""


def ensure_tables():
    for stmt in DDL.split(";"):
        if stmt.strip():
            db(stmt)


def seed_proc_def(tid, name):
    pid = f"pd-{uuid.uuid4()}"
    db("insert into public.proc_def (id,name,tenant_id,isdeleted) values (:i,:n,:t,false)", i=pid, n=name, t=tid)
    return pid


def seed_user(tid, email, name):
    uid = str(uuid.uuid4())
    db(
        "insert into public.users (id,email,username,tenant_id,is_agent) "
        "values (cast(:i as uuid),:e,:n,:t,false)",
        i=uid, e=email, n=name, t=tid,
    )
    return uid


def seed_completed_instance(tid, pd, participants):
    iid = f"inst-{uuid.uuid4()}"
    db(
        """insert into public.bpm_proc_inst
           (proc_inst_id, proc_inst_name, proc_def_id, root_proc_inst_id, status, tenant_id,
            participants, start_date, end_date, is_deleted, variables_data, updated_at)
           values (:iid,'실행',:pd,:iid,'COMPLETED',:t,cast(:participants as jsonb),
                   now() - interval '1 hour', now(), false, null, now())""",
        iid=iid, pd=pd, t=tid, participants=json.dumps(participants),
    )
    return iid


def create_kpi(c, tid, obj_id, **fields):
    body = {"objective_id": obj_id, "name": "KPI", "direction": "increase"}
    body.update(fields)
    resp = c.post(f"/api/kpis?tenant_id={tid}", json=body)
    resp.raise_for_status()
    return resp.json()


def map_kpi(c, tid, kpi_id):
    m = c.get(f"/api/map?tenant_id={tid}").json()
    for o in m["objectives"]:
        for k in o["kpis"]:
            if k["id"] == kpi_id:
                return k
    return None


def main() -> int:
    ensure_tables()
    ts = int(time.time())
    c = httpx.Client(base_url=BASE, timeout=30)
    tid = f"e2e-survey-{ts}"

    obj = c.post(f"/api/objectives?tenant_id={tid}",
                 json={"name": "고객 만족 목표", "perspective": "customer"}).json()

    pd = seed_proc_def(tid, "설문 대상 프로세스")
    kpi = create_kpi(c, tid, obj["id"], name="만족도", measure_type="survey_score",
                      proc_def_id=pd, baseline_value=0, target_value=5,
                      survey_questions=["이 프로세스의 결과에 얼마나 만족하십니까?"])

    respondent_email = f"resp-{uuid.uuid4()}@ex.com"
    seed_user(tid, respondent_email, "응답자")
    inst_id = seed_completed_instance(tid, pd, [respondent_email])

    # ================================================ 발행(watch_completions)
    run = c.post(f"/api/measure/run?tenant_id={tid}").json()
    check("measure/run 이 설문 발송을 트리거함(surveys_dispatched>=1)",
          run.get("surveys_dispatched", 0) >= 1, str(run))

    surveys = c.get(f"/api/surveys?tenant_id={tid}&kpi_id={kpi['id']}").json()
    check("설문 요청이 발행됨(strategy_survey_requests)", len(surveys) == 1, str(surveys))
    request_id = surveys[0]["id"] if surveys else None
    check("발행된 설문 상태가 대기중", surveys and surveys[0]["status"] != "ANSWERED", str(surveys))

    todo = db_one(
        "select * from public.todolist where id = cast(:id as uuid)",
        id=request_id,
    ) if request_id else None
    check("설문 워크아이템(todolist) 생성됨: activity_id=kpi_survey",
          todo is not None and todo.get("activity_id") == "kpi_survey", str(todo))
    check("설문 워크아이템 상태 IN_PROGRESS", todo is not None and todo.get("status") == "IN_PROGRESS", str(todo))
    check("설문 워크아이템이 완료 인스턴스에 연결됨", todo is not None and todo.get("proc_inst_id") == inst_id, str(todo))

    # ================================================ 응답 제출
    respond = c.post(f"/api/surveys/{request_id}/respond", json={
        "answers": [{"question": "이 프로세스의 결과에 얼마나 만족하십니까?", "rating": 4}],
    })
    check("설문 응답 제출 200", respond.status_code == 200, respond.text)

    detail = c.get(f"/api/surveys/{request_id}").json()
    check("응답 후 상태 ANSWERED", detail.get("status") == "ANSWERED", str(detail))
    check("응답 점수 = 4.0", float(detail.get("score") or 0) == 4.0, str(detail))

    todo_after = db_one(
        "select status from public.todolist where id = cast(:id as uuid)", id=request_id,
    )
    check("설문 워크아이템 상태 DONE 전이", todo_after is not None and todo_after.get("status") == "DONE",
          str(todo_after))

    # respond_survey 가 즉시 measure_all() 을 재실행하므로 별도 measure 호출 없이 반영 확인.
    km = map_kpi(c, tid, kpi["id"])
    check("KPI current_value 가 설문 점수(4.0)를 반영", km and float(km["current_value"]) == 4.0, str(km))

    c.close()
    for tbl in ("bpm_proc_inst", "proc_def", "users", "todolist",
                "strategy_survey_requests", "strategy_kpi_measurements"):
        db(f"delete from public.{tbl} where tenant_id = :t", t=tid)

    total = len(RESULTS)
    passed = sum(1 for _, ok, _ in RESULTS if ok)
    print(f"\n=== SUMMARY: {passed}/{total} PASSED ===")
    return 0 if passed == total else 1


if __name__ == "__main__":
    sys.exit(main())
