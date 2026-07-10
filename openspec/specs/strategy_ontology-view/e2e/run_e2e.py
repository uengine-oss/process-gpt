#!/usr/bin/env python
"""strategy_ontology-view E2E 러너.

상시 소스 실행 서버(8114)를 대상으로 4레이어(전략/프로세스/리소스/스킬) 온톨로지를
전략 API + POST /api/ontology/sync 로 구성한 뒤, GET /api/ontology/graph(전체/레이어
필터)와 GET /api/ontology/nodes/{id}/neighbors(depth1/2/404)를 검증한다.

실행:
  services/strategy/.venv/bin/python \
    openspec/specs/strategy_ontology-view/e2e/run_e2e.py

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
create table if not exists public.configuration (key text, value jsonb, tenant_id text);
create table if not exists public.todolist (id uuid primary key, user_id text, proc_def_id text, activity_id text, status text, start_date timestamptz, end_date timestamptz, duration integer, tenant_id text);
create table if not exists public.agent_skills (user_id text, tenant_id text, skill_name text);
create table if not exists public.skills (id uuid primary key default gen_random_uuid(), tenant_id text, name text, description text, updated_at timestamptz default now());
"""


def ensure_tables():
    for stmt in DDL.split(";"):
        if stmt.strip():
            db(stmt)


def labels(p):
    return {n["label"] for n in p["nodes"]}


def rel_types(p):
    return {e["rel_type"] for e in p["edges"]}


def has_edge(p, rel, src, dst):
    return any(e["rel_type"] == rel and e["source"] == src and e["target"] == dst for e in p["edges"])


def main() -> int:
    ensure_tables()
    ts = int(time.time())
    c = httpx.Client(base_url=BASE, timeout=30)
    tid = f"e2e-view-{ts}"

    # ---- 원천 seed
    agent = str(uuid.uuid4())
    user = str(uuid.uuid4())
    db("insert into public.users (id,username,tenant_id,is_agent) values (cast(:i as uuid),:u,:t,true)",
       i=agent, u="봇", t=tid)
    db("insert into public.users (id,username,email,tenant_id,is_agent) values (cast(:i as uuid),:u,:e,:t,false)",
       i=user, u="홍길동", e="hong@x.com", t=tid)
    pd = f"pd-{uuid.uuid4()}"
    db("""insert into public.proc_def (id,name,tenant_id,isdeleted,definition)
          values (:id,:n,:t,false,cast(:d as jsonb))""",
       id=pd, n="주문 처리", t=tid,
       d=json.dumps({"activities": [{"id": "a1", "name": "결제 승인"}]}))
    # 조직도: 본부 > 영업팀 > 홍길동 (HAS_SUB_TEAM + MEMBER_OF)
    chart = {"data": {"id": "team-hq", "name": "본부", "isTeam": True},
             "children": [{"data": {"id": "team-sales", "name": "영업팀", "isTeam": True},
                           "children": [{"data": {"id": user, "name": "홍길동", "isTeam": False, "email": "hong@x.com"}}]}]}
    db("insert into public.configuration (key,value,tenant_id) values ('organization',cast(:v as jsonb),:t)",
       v=json.dumps({"chart": chart}), t=tid)
    db("insert into public.skills (tenant_id,name,description) values (:t,'PPTX 생성','슬라이드 생성')", t=tid)
    db("insert into public.agent_skills (user_id,tenant_id,skill_name) values (:u,:t,'PPTX 생성')", u=agent, t=tid)
    # todolist DONE → PERFORMS
    db("""insert into public.todolist (id,user_id,proc_def_id,activity_id,status,start_date,end_date,tenant_id)
          values (gen_random_uuid(),:u,:pd,'a1','DONE',now()-make_interval(hours=>2),now(),:t)""",
       u=agent, pd=pd, t=tid)

    # ---- 전략층 API (Strategy/KPI/Initiative + Process 미러)
    obj = c.post(f"/api/objectives?tenant_id={tid}",
                 json={"name": "매출 성장", "perspective": "financial"}).json()
    kpi = c.post(f"/api/kpis?tenant_id={tid}", json={
        "objective_id": obj["id"], "name": "월 매출", "measure_type": "instance_count",
        "proc_def_id": pd, "direction": "increase", "baseline_value": 0, "target_value": 100}).json()
    init = c.post(f"/api/initiatives?tenant_id={tid}", json={
        "objective_id": obj["id"], "name": "신규 캠페인", "proc_def_id": pd}).json()

    c.post(f"/api/ontology/sync?tenant_id={tid}")

    # ================================================ 전체 조회
    g = c.get(f"/api/ontology/graph?tenant_id={tid}").json()
    lbls = labels(g)
    check("전체 조회: 8개 라벨 존재(Strategy/KPI/Initiative/Process/Task/User/Agent/Team/Skill)",
          {"Strategy", "KPI", "Initiative", "Process", "Task", "User", "Agent", "Team", "Skill"} <= lbls,
          f"labels={lbls}")
    rts = rel_types(g)
    check("전체 조회: 레이어 간 관계 존재",
          {"HAS_KPI", "HAS_INITIATIVE", "IMPACTS_KPI", "CONTAINS_TASK", "PERFORMS",
           "MEMBER_OF", "USES_SKILL", "HAS_SUB_TEAM", "EXECUTED_BY"} <= rts,
          f"rel_types={rts}")
    check("전체 조회: last_synced_at 포함(값 존재)",
          g.get("last_synced_at") is not None, str(g.get("last_synced_at")))
    check("전체 조회: layers=전체 4레이어",
          g["layers"] == ["strategy", "process", "resource", "skill"], str(g["layers"]))
    layer_by_id = {n["id"]: n["layer"] for n in g["nodes"]}
    check("노드 layer 표기(strategy/process/resource/skill)",
          layer_by_id[obj["id"]] == "strategy" and layer_by_id[pd] == "process"
          and layer_by_id[agent] == "resource",
          str({obj["id"]: layer_by_id[obj["id"]], pd: layer_by_id[pd]}))

    # ================================================ 빈 테넌트
    empty = c.get(f"/api/ontology/graph?tenant_id=e2e-view-empty-{ts}").json()
    check("빈 테넌트: 노드/관계 빈 목록",
          empty["nodes"] == [] and empty["edges"] == [] and "last_synced_at" in empty, str(empty))

    # ================================================ layers=strategy
    gs = c.get(f"/api/ontology/graph?tenant_id={tid}&layers=strategy").json()
    check("layers=strategy: 전략층 라벨만",
          labels(gs) <= {"Strategy", "KPI", "Initiative"} and "Process" not in labels(gs),
          f"labels={labels(gs)}")
    check("layers=strategy: HAS_KPI 포함, IMPACTS_KPI 제외(프로세스 끝 없음)",
          "HAS_KPI" in rel_types(gs) and "IMPACTS_KPI" not in rel_types(gs), str(rel_types(gs)))
    check("layers=strategy: layers 에코", gs["layers"] == ["strategy"], str(gs["layers"]))

    # ================================================ layers=strategy,process
    gsp = c.get(f"/api/ontology/graph?tenant_id={tid}&layers=strategy,process").json()
    check("layers=strategy,process: 교차 관계 IMPACTS_KPI(Process→KPI) 포함",
          has_edge(gsp, "IMPACTS_KPI", pd, kpi["id"]), "IMPACTS_KPI 없음")
    check("layers=strategy,process: 리소스/스킬 라벨 제외",
          "Agent" not in labels(gsp) and "Skill" not in labels(gsp), f"labels={labels(gsp)}")

    # 잘못된 레이어 값 → 4xx
    bad = c.get(f"/api/ontology/graph?tenant_id={tid}&layers=strategy,bogus")
    check("잘못된 layers 값 거부(4xx)", bad.status_code in (400, 422), f"status={bad.status_code}")

    # ================================================ 이웃 탐색
    n1 = c.get(f"/api/ontology/nodes/{kpi['id']}/neighbors?tenant_id={tid}&depth=1").json()
    ids1 = {n["id"] for n in n1["nodes"]}
    check("neighbors(KPI, depth1): 시작 KPI + 보유 Strategy + 영향 Process",
          kpi["id"] in ids1 and obj["id"] in ids1 and pd in ids1, str(ids1))
    check("neighbors(KPI, depth1): HAS_KPI/IMPACTS_KPI 관계 포함",
          has_edge(n1, "HAS_KPI", obj["id"], kpi["id"]) and has_edge(n1, "IMPACTS_KPI", pd, kpi["id"]),
          "이웃 관계 누락")

    n2 = c.get(f"/api/ontology/nodes/{obj['id']}/neighbors?tenant_id={tid}&depth=2").json()
    ids2 = {n["id"] for n in n2["nodes"]}
    check("neighbors(Strategy, depth2): KPI(1홉) + Process(2홉) 도달",
          kpi["id"] in ids2 and pd in ids2, str(ids2))

    n404 = c.get(f"/api/ontology/nodes/{uuid.uuid4()}/neighbors?tenant_id={tid}")
    check("neighbors 존재하지 않는 노드 404", n404.status_code == 404, f"status={n404.status_code}")

    c.close()
    for tbl in ("proc_def", "users", "configuration", "todolist", "agent_skills", "skills"):
        db(f"delete from public.{tbl} where tenant_id = :t", t=tid)

    total = len(RESULTS)
    passed = sum(1 for _, ok, _ in RESULTS if ok)
    print(f"\n=== SUMMARY: {passed}/{total} PASSED ===")
    return 0 if passed == total else 1


if __name__ == "__main__":
    sys.exit(main())
