#!/usr/bin/env python
"""strategy_strategy-map-graph E2E 러너.

상시 소스 실행 서버(8114, GRAPH_STORE=age, GRAPH_NAME=corp_ontology_e2e)를 대상으로
전략맵 CRUD 왕복, 전략간 관계(HAS_SUB_STRATEGY), 삭제 정리(부모 삭제 시 자식 parents
정리 + KPI/이니셔티브 연쇄 삭제), 관계형→그래프 이관(+멱등성), 레거시 BSCard 이관을
검증한다.

실행:
  services/strategy/.venv/bin/python \
    openspec/specs/strategy_strategy-map-graph/e2e/run_e2e.py

인프라: process-gpt-age-postgres (127.0.0.1:55433). DB seed 는 sqlalchemy 로 직접 수행.
"""
import json
import os
import sys
import time
import uuid

import httpx
from sqlalchemy import create_engine, text

BASE = os.getenv("E2E_BASE_URL", "http://127.0.0.1:8114")
DB_URL = "postgresql://postgres:postgres@127.0.0.1:55433/postgres"
engine = create_engine(DB_URL)

RESULTS: list[tuple[str, bool, str]] = []


def check(name: str, cond: bool, detail: str = "") -> None:
    RESULTS.append((name, bool(cond), detail))
    print(("PASS" if cond else "FAIL"), "-", name, "" if cond else f":: {detail}")


def db(sql: str, **p) -> None:
    with engine.begin() as c:
        c.execute(text(sql), p)


def dbq(sql: str, **p) -> list[dict]:
    with engine.connect() as c:
        return [dict(r._mapping) for r in c.execute(text(sql), p)]


DDL = """
create table if not exists public.proc_def (
    id text primary key, name text, tenant_id text,
    isdeleted boolean default false, definition jsonb);
create table if not exists public.configuration (key text, value jsonb, tenant_id text);
"""


def ensure_tables() -> None:
    for stmt in DDL.split(";"):
        if stmt.strip():
            db(stmt)


def main() -> int:
    ensure_tables()
    ts = int(time.time())
    c = httpx.Client(base_url=BASE, timeout=15)

    # ============================================================ CRUD 왕복
    t1 = f"e2e-map-crud-{ts}"
    proc_def_id = f"pd-{uuid.uuid4()}"
    db("insert into public.proc_def (id, name, tenant_id, isdeleted) values (:i,:n,:t,false)",
       i=proc_def_id, n="매출 관리 프로세스", t=t1)

    obj = c.post(f"/api/objectives?tenant_id={t1}",
                 json={"name": "매출 성장", "perspective": "financial"}).json()
    kpi = c.post(f"/api/kpis?tenant_id={t1}", json={
        "objective_id": obj["id"], "name": "분기 매출",
        "measure_type": "instance_count", "proc_def_id": proc_def_id,
        "direction": "increase", "baseline_value": 0, "target_value": 100}).json()
    init = c.post(f"/api/initiatives?tenant_id={t1}", json={
        "objective_id": obj["id"], "name": "신규 채널", "proc_def_id": proc_def_id}).json()

    m = c.get(f"/api/map?tenant_id={t1}").json()["objectives"]
    o0 = next(o for o in m if o["id"] == obj["id"])
    check("CRUD 목표 생성/조회", o0["name"] == "매출 성장" and o0["perspective"] == "financial", str(o0))
    check("CRUD KPI 중첩(proc_def_id 포함)",
          [k["name"] for k in o0["kpis"]] == ["분기 매출"] and o0["kpis"][0]["proc_def_id"] == proc_def_id,
          str(o0.get("kpis")))
    check("CRUD 이니셔티브 중첩",
          [i["name"] for i in o0["initiatives"]] == ["신규 채널"], str(o0.get("initiatives")))
    check("CRUD 응답 계약 키(objectives/kpis/initiatives/parents/achievement)",
          all(k in o0 for k in ("kpis", "initiatives", "parents", "achievement", "perspective")),
          str(list(o0.keys())))

    # 수정 반영
    c.put(f"/api/objectives/{obj['id']}?tenant_id={t1}",
          json={"name": "매출 성장(수정)", "perspective": "customer"})
    o0b = next(o for o in c.get(f"/api/map?tenant_id={t1}").json()["objectives"] if o["id"] == obj["id"])
    check("수정 결과 반영(name/perspective)",
          o0b["name"] == "매출 성장(수정)" and o0b["perspective"] == "customer", str(o0b))

    # 404 (존재하지 않는 KPI 수정)
    r404 = c.put(f"/api/kpis/{uuid.uuid4()}?tenant_id={t1}",
                 json={"objective_id": obj["id"], "name": "x", "direction": "increase"})
    check("존재하지 않는 KPI 수정 404", r404.status_code == 404, f"status={r404.status_code}")

    # ============================================================ 전략간 관계(HAS_SUB_STRATEGY)
    t2 = f"e2e-map-rel-{ts}"
    parent = c.post(f"/api/objectives?tenant_id={t2}",
                    json={"name": "상위 목표", "perspective": "financial"}).json()
    child = c.post(f"/api/objectives?tenant_id={t2}",
                   json={"name": "하위 목표", "perspective": "customer",
                         "parents": [parent["id"]]}).json()
    check("전략간 계층 생성 응답 parents",
          child["parents"] == [parent["id"]], str(child.get("parents")))
    mm = {o["id"]: o for o in c.get(f"/api/map?tenant_id={t2}").json()["objectives"]}
    check("전략맵 조회 시 하위 parents 에 상위 id",
          mm[child["id"]]["parents"] == [parent["id"]], str(mm[child["id"]]["parents"]))

    # ============================================================ 부모 삭제 → 자식 parents 정리
    c.delete(f"/api/objectives/{parent['id']}?tenant_id={t2}")
    after = {o["id"]: o for o in c.get(f"/api/map?tenant_id={t2}").json()["objectives"]}
    check("부모 삭제 후 부모 노드 제거", parent["id"] not in after, "부모가 남아있음")
    check("부모 삭제 후 자식 parents 잔존 참조 없음",
          child["id"] in after and after[child["id"]]["parents"] == [],
          str(after.get(child["id"], {}).get("parents")))

    # ============================================================ 목표 삭제 → KPI/이니셔티브 연쇄 삭제
    t3 = f"e2e-map-cascade-{ts}"
    o3 = c.post(f"/api/objectives?tenant_id={t3}",
                json={"name": "폐기 목표", "perspective": "financial"}).json()
    k3 = c.post(f"/api/kpis?tenant_id={t3}", json={
        "objective_id": o3["id"], "name": "폐기 KPI", "direction": "increase"}).json()
    i3 = c.post(f"/api/initiatives?tenant_id={t3}", json={
        "objective_id": o3["id"], "name": "폐기 이니셔티브"}).json()
    c.delete(f"/api/objectives/{o3['id']}?tenant_id={t3}")
    m3 = c.get(f"/api/map?tenant_id={t3}").json()["objectives"]
    all_kpi_ids = {k["id"] for o in m3 for k in o["kpis"]}
    all_init_ids = {i["id"] for o in m3 for i in o["initiatives"]}
    check("목표 삭제 시 KPI 연쇄 삭제", k3["id"] not in all_kpi_ids, "KPI 잔존")
    check("목표 삭제 시 이니셔티브 연쇄 삭제", i3["id"] not in all_init_ids, "이니셔티브 잔존")

    # ============================================================ 관계형 → 그래프 이관 + 멱등성
    t4 = f"e2e-map-migrate-{ts}"
    pd4 = f"pd-{uuid.uuid4()}"
    db("insert into public.proc_def (id,name,tenant_id,isdeleted) values (:i,:n,:t,false)",
       i=pd4, n="이관 프로세스", t=t4)
    parent_oid = str(uuid.uuid4())
    child_oid = str(uuid.uuid4())
    db("""insert into public.strategy_objectives (id,tenant_id,name,perspective,parents,sort_order)
          values (cast(:i as uuid),:t,:n,'financial','[]'::jsonb,0)""", i=parent_oid, t=t4, n="상위(관계형)")
    db("""insert into public.strategy_objectives (id,tenant_id,name,perspective,parents,sort_order)
          values (cast(:i as uuid),:t,:n,'customer',cast(:p as jsonb),1)""",
       i=child_oid, t=t4, n="하위(관계형)", p=json.dumps([parent_oid]))
    kid = str(uuid.uuid4())
    db("""insert into public.strategy_kpis
          (id,tenant_id,objective_id,name,measure_type,proc_def_id,direction,baseline_value,target_value)
          values (cast(:i as uuid),:t,cast(:o as uuid),:n,'instance_count',:pd,'increase',0,100)""",
       i=kid, t=t4, o=child_oid, n="이관 KPI", pd=pd4)
    iid = str(uuid.uuid4())
    db("""insert into public.strategy_initiatives (id,tenant_id,objective_id,name,proc_def_id)
          values (cast(:i as uuid),:t,cast(:o as uuid),:n,:pd)""",
       i=iid, t=t4, o=child_oid, n="이관 이니셔티브", pd=pd4)

    mig = c.post(f"/api/migrate-graph?tenant_id={t4}").json()
    check("이관 요약 노드 수(objectives=2,kpis=1,initiatives=1,processes=1)",
          mig.get("objectives") == 2 and mig.get("kpis") == 1
          and mig.get("initiatives") == 1 and mig.get("processes") == 1, str(mig))
    mm4 = {o["id"]: o for o in c.get(f"/api/map?tenant_id={t4}").json()["objectives"]}
    cmap = mm4[child_oid]
    check("이관 후 parents→HAS_SUB_STRATEGY 왕복",
          cmap["parents"] == [parent_oid], str(cmap["parents"]))
    check("이관 후 proc_def_id 유지 + Process 미러 이름",
          cmap["kpis"][0]["proc_def_id"] == pd4, str(cmap["kpis"]))

    # 멱등성: 재실행 시 counts 불변
    mig2 = c.post(f"/api/migrate-graph?tenant_id={t4}").json()
    check("이관 멱등성(counts_before == counts_after)",
          mig2.get("counts_before") == mig2.get("counts_after"), str(mig2))
    mm4b = c.get(f"/api/map?tenant_id={t4}").json()["objectives"]
    total_kpis = sum(len(o["kpis"]) for o in mm4b)
    total_inits = sum(len(o["initiatives"]) for o in mm4b)
    check("이관 멱등성(노드 중복 없음: 목표2/KPI1/이니셔티브1)",
          len(mm4b) == 2 and total_kpis == 1 and total_inits == 1,
          f"objs={len(mm4b)} kpis={total_kpis} inits={total_inits}")

    # ============================================================ 레거시 BSCard 이관(한국어 관점)
    t5 = f"e2e-map-bscard-{ts}"
    payload = {"strategies": [
        {"id": "s1", "name": "재무 성장", "perspective": "재무", "parents": []},
        {"id": "s2", "name": "고객 만족", "perspective": "고객", "parents": ["s1"]},
        {"id": "s3", "name": "프로세스 혁신", "perspective": "내부 프로세스", "parents": ["s1"]},
        {"id": "s4", "name": "인재 육성", "perspective": "학습 및 성장", "parents": []},
    ]}
    db("insert into public.configuration (key,value,tenant_id) values ('strategy',cast(:v as jsonb),:t)",
       v=json.dumps(payload), t=t5)
    imp = c.post(f"/api/import-bscard?tenant_id={t5}").json()
    check("BSCard 이관 imported=4, skipped=0",
          imp.get("imported") == 4 and imp.get("skipped") == 0, str(imp))
    by_name = {o["name"]: o for o in c.get(f"/api/map?tenant_id={t5}").json()["objectives"]}
    check("BSCard 관점 정규화(한국어→표준)",
          by_name["재무 성장"]["perspective"] == "financial"
          and by_name["고객 만족"]["perspective"] == "customer"
          and by_name["프로세스 혁신"]["perspective"] == "internal_process"
          and by_name["인재 육성"]["perspective"] == "learning_growth",
          {n: o["perspective"] for n, o in by_name.items()})
    check("BSCard 부모 관계 이관(HAS_SUB_STRATEGY)",
          by_name["고객 만족"]["parents"] == [by_name["재무 성장"]["id"]]
          and by_name["프로세스 혁신"]["parents"] == [by_name["재무 성장"]["id"]],
          {n: o["parents"] for n, o in by_name.items()})

    c.close()

    # 정리(관계형 원천 행). 그래프 노드는 고유 테넌트라 재실행에 무해.
    for t in (t1, t2, t3, t4, t5):
        for tbl in ("strategy_initiatives", "strategy_kpis", "strategy_objectives",
                    "configuration", "proc_def"):
            db(f"delete from public.{tbl} where tenant_id = :t", t=t)

    total = len(RESULTS)
    passed = sum(1 for _, ok, _ in RESULTS if ok)
    print(f"\n=== SUMMARY: {passed}/{total} PASSED ===")
    return 0 if passed == total else 1


if __name__ == "__main__":
    sys.exit(main())
