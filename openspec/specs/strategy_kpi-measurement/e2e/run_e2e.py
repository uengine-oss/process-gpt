#!/usr/bin/env python
"""strategy_kpi-measurement E2E 러너.

상시 소스 실행 서버(8114)를 대상으로 정량(instance_count/avg_duration_hours/
form_value_sum)·정성(survey_score)·수동(manual) 측정을 검증한다. bpm_proc_inst 완료
인스턴스와 ANSWERED 설문 요청을 seed 하고 POST /api/measure/run 을 호출한 뒤,
GET /api/map 의 current_value/achievement 와 GET /api/kpis/{id}/measurements 이력을 확인한다.

실행:
  services/strategy/.venv/bin/python \
    openspec/specs/strategy_kpi-measurement/e2e/run_e2e.py

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
create table if not exists public.bpm_proc_inst (proc_inst_id text primary key, proc_inst_name text, proc_def_id text, root_proc_inst_id text, status text, tenant_id text, participants jsonb, start_date timestamptz, end_date timestamptz, is_deleted boolean default false, variables_data jsonb, updated_at timestamptz default now());
create table if not exists public.users (id uuid primary key default gen_random_uuid(), email text, username text, tenant_id text, is_agent boolean default false);
"""


def ensure_tables():
    for stmt in DDL.split(";"):
        if stmt.strip():
            db(stmt)


def seed_proc_def(tid, name):
    pid = f"pd-{uuid.uuid4()}"
    db("insert into public.proc_def (id,name,tenant_id,isdeleted) values (:i,:n,:t,false)", i=pid, n=name, t=tid)
    return pid


def seed_instance(tid, pd, *, duration_hours=None, variables_data=None):
    iid = f"inst-{uuid.uuid4()}"
    db("""insert into public.bpm_proc_inst
          (proc_inst_id, proc_inst_name, proc_def_id, root_proc_inst_id, status, tenant_id,
           participants, start_date, end_date, is_deleted, variables_data, updated_at)
          values (:iid,'실행',:pd,:iid,'COMPLETED',:t,'[]'::jsonb,
                  case when :dur is null then null else now()-make_interval(hours=>:dur) end,
                  case when :dur is null then null else now() end,
                  false, cast(:vd as jsonb), now())""",
       iid=iid, pd=pd, t=tid, dur=duration_hours,
       vd=json.dumps(variables_data) if variables_data is not None else None)
    return iid


def create_kpi(c, tid, obj_id, **fields):
    body = {"objective_id": obj_id, "name": "KPI", "direction": "increase"}
    body.update(fields)
    return c.post(f"/api/kpis?tenant_id={tid}", json=body).json()


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
    tid = f"e2e-measure-{ts}"
    obj = c.post(f"/api/objectives?tenant_id={tid}",
                 json={"name": "성과 목표", "perspective": "financial"}).json()

    # ---- instance_count: 완료 3건 → 3, 달성률 30 (0→10)
    pd_cnt = seed_proc_def(tid, "건수 프로세스")
    kpi_cnt = create_kpi(c, tid, obj["id"], name="완료 건수", measure_type="instance_count",
                         proc_def_id=pd_cnt, baseline_value=0, target_value=10)
    for _ in range(3):
        seed_instance(tid, pd_cnt)

    # ---- avg_duration_hours: 1h + 3h → 2.0
    pd_dur = seed_proc_def(tid, "처리시간 프로세스")
    kpi_dur = create_kpi(c, tid, obj["id"], name="평균 처리시간", measure_type="avg_duration_hours",
                         proc_def_id=pd_dur, baseline_value=0, target_value=8)
    seed_instance(tid, pd_dur, duration_hours=1)
    seed_instance(tid, pd_dur, duration_hours=3)

    # ---- form_value_sum: 평탄(100) + 중첩(200) → 300
    pd_form = seed_proc_def(tid, "계약 프로세스")
    kpi_form = create_kpi(c, tid, obj["id"], name="계약 금액 합계", measure_type="form_value_sum",
                          form_field="계약금액", proc_def_id=pd_form, baseline_value=0, target_value=1000)
    seed_instance(tid, pd_form, variables_data=[{"key": "계약금액", "name": "계약금액", "value": 100}])
    seed_instance(tid, pd_form, variables_data=[{"key": "form1", "name": "폼", "value": {"계약금액": 200}}])

    # ---- survey_score: ANSWERED 4,5 → 4.5
    kpi_surv = create_kpi(c, tid, obj["id"], name="만족도", measure_type="survey_score",
                          baseline_value=0, target_value=5)
    for score in (4, 5):
        db("""insert into public.strategy_survey_requests
              (tenant_id, kpi_id, proc_inst_id, respondent_email, status, score, answered_at)
              values (:t, cast(:kpi as uuid), :pi, :email, 'ANSWERED', :score, now())""",
           t=tid, kpi=kpi_surv["id"], pi=f"pi-{uuid.uuid4()}", email=f"{uuid.uuid4()}@ex.com", score=score)

    # ---- manual: POST value 50 → 50, 달성률 50 (0→100)
    kpi_man = create_kpi(c, tid, obj["id"], name="수동 실적", measure_type="manual",
                         baseline_value=0, target_value=100)

    # ================================================ 자동 측정 실행
    run = c.post(f"/api/measure/run?tenant_id={tid}").json()
    check("measure/run 측정 수행(kpis_measured>=4)", run.get("kpis_measured", 0) >= 4, str(run))

    # 수동 입력
    man_resp = c.post(f"/api/kpis/{kpi_man['id']}/value?tenant_id={tid}", json={"value": 50})
    check("수동 입력 200", man_resp.status_code == 200, man_resp.text)

    # ================================================ 전략맵 current_value/achievement 검증
    kc = map_kpi(c, tid, kpi_cnt["id"])
    check("instance_count current_value=3, achievement=30.0",
          float(kc["current_value"]) == 3.0 and kc["achievement"] == 30.0, str(kc.get("current_value")))

    kd = map_kpi(c, tid, kpi_dur["id"])
    check("avg_duration_hours current_value=2.0",
          float(kd["current_value"]) == 2.0, str(kd.get("current_value")))

    kf = map_kpi(c, tid, kpi_form["id"])
    check("form_value_sum current_value=300 (평탄+중첩)",
          float(kf["current_value"]) == 300.0, str(kf.get("current_value")))

    ks = map_kpi(c, tid, kpi_surv["id"])
    check("survey_score current_value=4.5",
          float(ks["current_value"]) == 4.5, str(ks.get("current_value")))

    km = map_kpi(c, tid, kpi_man["id"])
    check("manual current_value=50, achievement=50.0",
          float(km["current_value"]) == 50.0 and km["achievement"] == 50.0, str(km.get("current_value")))

    # ================================================ 측정 이력 검증
    h_cnt = c.get(f"/api/kpis/{kpi_cnt['id']}/measurements").json()
    check("instance_count 이력 최신값=3, source=auto",
          h_cnt and float(h_cnt[0]["value"]) == 3.0 and h_cnt[0]["source"] == "auto", str(h_cnt[:1]))

    h_surv = c.get(f"/api/kpis/{kpi_surv['id']}/measurements").json()
    check("survey_score 이력 source=survey",
          h_surv and float(h_surv[0]["value"]) == 4.5 and h_surv[0]["source"] == "survey", str(h_surv[:1]))

    h_man = c.get(f"/api/kpis/{kpi_man['id']}/measurements").json()
    check("manual 이력 source=manual",
          h_man and float(h_man[0]["value"]) == 50.0 and h_man[0]["source"] == "manual", str(h_man[:1]))

    # 전략맵 값과 이력 최신값 일치
    check("전략맵 current_value 와 이력 최신값 일치(instance_count)",
          float(kc["current_value"]) == float(h_cnt[0]["value"]), "불일치")

    c.close()
    for tbl in ("bpm_proc_inst", "proc_def", "users",
                "strategy_survey_requests", "strategy_kpi_measurements"):
        db(f"delete from public.{tbl} where tenant_id = :t", t=tid)

    total = len(RESULTS)
    passed = sum(1 for _, ok, _ in RESULTS if ok)
    print(f"\n=== SUMMARY: {passed}/{total} PASSED ===")
    return 0 if passed == total else 1


if __name__ == "__main__":
    sys.exit(main())
