#!/usr/bin/env python
"""strategy_impact-analysis E2E 러너.

상시 소스 실행 서버(8114, OPENAI_API_KEY 미설정)를 대상으로, 전략(비용 감소)→목표 미달
KPI(개발 소요 시간)→프로세스→태스크→리소스→스킬 그래프를 전략 API + 원천 seed +
POST /api/ontology/sync 로 구성한 뒤 GET /api/impact/kpi/{id}, GET /api/impact/strategy/{id}
를 검증한다. 실행 지표(PERFORMS.avg_duration_hours)로 병목 태스크(개발, 6h)가 최상위
후보가 되고, LLM 미설정이므로 diagnosis 는 null(결정적 결과는 완전).

실행:
  services/strategy/.venv/bin/python \
    openspec/specs/strategy_impact-analysis/e2e/run_e2e.py

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


def check(name, cond, detail=""):
    RESULTS.append((name, bool(cond), detail))
    print(("PASS" if cond else "FAIL"), "-", name, "" if cond else f":: {detail}")


def db(sql, **p):
    with engine.begin() as c:
        c.execute(text(sql), p)


DDL = """
create table if not exists public.proc_def (id text primary key, name text, tenant_id text, isdeleted boolean default false);
alter table public.proc_def add column if not exists definition jsonb;
create table if not exists public.users (id uuid primary key, username text, email text, tenant_id text, is_agent boolean default false, skills text, role text);
create table if not exists public.todolist (id uuid primary key, user_id text, proc_def_id text, activity_id text, status text, start_date timestamptz, end_date timestamptz, duration integer, tenant_id text);
create table if not exists public.agent_skills (user_id text, tenant_id text, skill_name text);
create table if not exists public.skills (id uuid primary key default gen_random_uuid(), tenant_id text, name text, description text, updated_at timestamptz default now());
"""


def ensure_tables():
    for stmt in DDL.split(";"):
        if stmt.strip():
            db(stmt)


def main() -> int:
    ensure_tables()
    ts = int(time.time())
    c = httpx.Client(base_url=BASE, timeout=30)
    tid = f"e2e-impact-{ts}"

    # ---- 원천 seed: 리소스/프로세스/스킬
    agent = str(uuid.uuid4())
    user = str(uuid.uuid4())
    db("insert into public.users (id,username,tenant_id,is_agent) values (cast(:i as uuid),:u,:t,true)",
       i=agent, u="개발 에이전트", t=tid)
    db("insert into public.users (id,username,tenant_id,is_agent) values (cast(:i as uuid),:u,:t,false)",
       i=user, u="홍길동", t=tid)
    pd = f"pd-{uuid.uuid4()}"
    db("""insert into public.proc_def (id,name,tenant_id,isdeleted,definition)
          values (:id,:n,:t,false,cast(:d as jsonb))""",
       id=pd, n="시스템 개발", t=tid,
       d=json.dumps({"activities": [{"id": "a1", "name": "개발"}, {"id": "a2", "name": "리뷰"}]}))
    db("insert into public.skills (tenant_id,name,description) values (:t,'고급 개발 스킬','아키텍처 설계')", t=tid)
    db("insert into public.agent_skills (user_id,tenant_id,skill_name) values (:u,:t,'고급 개발 스킬')", u=agent, t=tid)
    # 병목: agent 가 a1(개발) 6h × 3건, user 가 a2(리뷰) 1h × 2건
    for _ in range(3):
        db("""insert into public.todolist (id,user_id,proc_def_id,activity_id,status,start_date,end_date,tenant_id)
              values (gen_random_uuid(),:u,:pd,'a1','DONE',now()-make_interval(hours=>6),now(),:t)""",
           u=agent, pd=pd, t=tid)
    for _ in range(2):
        db("""insert into public.todolist (id,user_id,proc_def_id,activity_id,status,start_date,end_date,tenant_id)
              values (gen_random_uuid(),:u,:pd,'a2','DONE',now()-make_interval(hours=>1),now(),:t)""",
           u=user, pd=pd, t=tid)

    # ---- 전략층 API: 전략 + 목표 미달 KPI(개발 소요 시간, decrease 10→2, current 8)
    obj = c.post(f"/api/objectives?tenant_id={tid}",
                 json={"name": "비용 감소", "perspective": "financial"}).json()
    kpi = c.post(f"/api/kpis?tenant_id={tid}", json={
        "objective_id": obj["id"], "name": "개발 소요 시간", "unit": "hours",
        "measure_type": "avg_duration_hours", "proc_def_id": pd,
        "direction": "decrease", "baseline_value": 10, "target_value": 2}).json()
    c.post(f"/api/kpis/{kpi['id']}/value?tenant_id={tid}", json={"value": 8})  # current 8 → 달성률 25%

    c.post(f"/api/ontology/sync?tenant_id={tid}")

    # ================================================ KPI 역추적
    r = c.get(f"/api/impact/kpi/{kpi['id']}?tenant_id={tid}")
    check("KPI 역추적 200", r.status_code == 200, r.text)
    p = r.json()
    check("KPI 요약 + 달성률(<100 목표 미달)",
          p["kpi"]["id"] == kpi["id"] and p["kpi"]["achievement"] is not None and p["kpi"]["achievement"] < 100,
          str(p["kpi"]))
    cands = p["candidates"]
    check("원인 후보 비어있지 않음", bool(cands), "candidates 비어있음")
    first = cands[0] if cands else {}
    check("최상위 후보 = 병목 태스크(개발, score=6.0)",
          first.get("type") == "task" and first.get("name") == "개발" and abs(first.get("score", 0) - 6.0) < 0.01,
          str(first))
    check("모든 후보에 path + metrics 존재",
          all(cand.get("path") and "metrics" in cand for cand in cands), "path/metrics 누락")
    check("경로가 KPI(개발 소요 시간)에서 시작",
          cands and cands[0]["path"][0].endswith("개발 소요 시간"), str(cands[0]["path"][:1]) if cands else "")
    ps = p["paths_summary"]
    check("paths_summary(processes=1,tasks=2,resources=2,skills=1)",
          ps == {"processes": 1, "tasks": 2, "resources": 2, "skills": 1}, str(ps))
    check("no_downstream=false", p["no_downstream"] is False, str(p["no_downstream"]))
    check("LLM 미설정 → diagnosis null(결정적 결과 완전)", p["diagnosis"] is None, str(p["diagnosis"]))

    # 하위 연결 없는 KPI
    obj2 = c.post(f"/api/objectives?tenant_id={tid}",
                  json={"name": "고립 목표", "perspective": "financial"}).json()
    kpi2 = c.post(f"/api/kpis?tenant_id={tid}", json={
        "objective_id": obj2["id"], "name": "고립 KPI", "direction": "increase",
        "baseline_value": 0, "target_value": 10}).json()
    c.post(f"/api/kpis/{kpi2['id']}/value?tenant_id={tid}", json={"value": 3})
    pnd = c.get(f"/api/impact/kpi/{kpi2['id']}?tenant_id={tid}").json()
    check("하위 연결 없는 KPI: candidates=[], no_downstream=true",
          pnd["candidates"] == [] and pnd["no_downstream"] is True and pnd["paths_summary"]["processes"] == 0,
          str(pnd["paths_summary"]))

    # 404
    r404 = c.get(f"/api/impact/kpi/{uuid.uuid4()}?tenant_id={tid}")
    check("존재하지 않는 KPI 404", r404.status_code == 404, f"status={r404.status_code}")

    # 결정성
    a = c.get(f"/api/impact/kpi/{kpi['id']}?tenant_id={tid}").json()
    b = c.get(f"/api/impact/kpi/{kpi['id']}?tenant_id={tid}").json()
    check("결정성: 동일 KPI 두 호출 결과 동일", a == b, "두 응답이 다름")

    # ================================================ 전략 하향 분석
    rs = c.get(f"/api/impact/strategy/{obj['id']}?tenant_id={tid}")
    check("전략 하향 분석 200", rs.status_code == 200, rs.text)
    sp = rs.json()
    check("전략 요약", sp["strategy"]["id"] == obj["id"], str(sp["strategy"]))
    check("목표 미달 KPI(개발 소요 시간) 포함",
          kpi["id"] in {k["id"] for k in sp["lagging_kpis"]}, str(sp["lagging_kpis"]))
    imps = sp["skill_improvements"]
    check("스킬 개선 후보 비어있지 않음", bool(imps), "skill_improvements 비어있음")
    check("개선 스킬 경로(linked_via)가 전략(비용 감소)에서 시작",
          all(imp["linked_via"] and all(chain[0].endswith("비용 감소") for chain in imp["linked_via"]) for imp in imps),
          "경로가 전략에서 시작하지 않음")
    check("고급 개발 스킬이 개선 후보에 포함",
          any(imp["skill"]["name"] == "고급 개발 스킬" for imp in imps), str([i["skill"] for i in imps]))
    check("병목(태스크/리소스) 후보 존재", bool(sp["bottlenecks"]), "bottlenecks 비어있음")
    check("전략 분석 LLM 미설정 → diagnosis null", sp["diagnosis"] is None, str(sp["diagnosis"]))

    rs404 = c.get(f"/api/impact/strategy/{uuid.uuid4()}?tenant_id={tid}")
    check("존재하지 않는 전략 404", rs404.status_code == 404, f"status={rs404.status_code}")

    c.close()
    for tbl in ("proc_def", "users", "todolist", "agent_skills", "skills"):
        db(f"delete from public.{tbl} where tenant_id = :t", t=tid)

    total = len(RESULTS)
    passed = sum(1 for _, ok, _ in RESULTS if ok)
    print(f"\n=== SUMMARY: {passed}/{total} PASSED ===")
    return 0 if passed == total else 1


if __name__ == "__main__":
    sys.exit(main())
