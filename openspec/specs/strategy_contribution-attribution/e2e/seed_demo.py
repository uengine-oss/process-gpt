"""strategy_contribution-attribution 데모 시드.

라이브 AGE Postgres(127.0.0.1:55433)에 데모 테넌트의 원천 데이터를 심고,
로컬에서 실행 중인 strategy 서비스(:8014) API 로 전략맵을 만든 뒤 측정·온톨로지
동기화를 실행한다. 모든 데이터는 스크래치 테넌트에 격리되며 cleanup_demo.py 로 지운다.

시나리오:
- 전략 "매출 성장"(중요도 5) ← KPI "계약 완료 건수"(instance_count, 계약 관리 프로세스)
- 전략 "운영 효율화"(중요도 2) ← KPI "검토 완료 건수"(instance_count, 내부 검토 프로세스)
- 전략 "브랜드 강화"(중요도 3) ← KPI "브랜드 인지도"(manual → 성과자 추적 불가 데모)
- 계약 관리 3건 완료: 김지은(사람) 2건, 계약검토봇(에이전트) 1건 수행
- 내부 검토 2건 완료: 계약검토봇 2건 수행
  → KPI 단위: 김지은이 계약 KPI 1위(2/3). 중요도 가중 합산: 봇이 역전
    (0.333*5 + 1.0*2 = 3.67 > 김지은 0.667*5 = 3.33) — 사람·에이전트 통합 순위 데모.
- skill_contributions: 김지은 CREATED/MODIFIED, 박민수 PROPOSAL_APPROVED("계약 검토 스킬")
  → 온톨로지 동기화 후 (User)-[:CONTRIBUTED_TO]->(Skill) 엣지 데모.

실행: services/strategy/.venv/bin/python seed_demo.py  (환경변수는 서비스와 동일하게)
출력: demo_ids.json (테넌트/전략/KPI/성과자 id — 데모 페이지와 정리 스크립트가 사용)
"""

import json
import os
import sys
import uuid

os.environ.setdefault("DB_HOST", "127.0.0.1")
os.environ.setdefault("DB_PORT", "55433")
os.environ.setdefault("DB_USER", "postgres")
os.environ.setdefault("DB_PASSWORD", "postgres")
os.environ.setdefault("DB_NAME", "postgres")
os.environ.setdefault("GRAPH_NAME", "demo_contribution_ontology")

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "..", "..", "services", "strategy"))

import httpx  # noqa: E402

from app.database import execute  # noqa: E402

BASE = os.environ.get("STRATEGY_BASE", "http://127.0.0.1:8014")
TENANT = f"demo-{uuid.uuid4().hex[:8]}"
OUT = os.path.join(os.path.dirname(__file__), "demo_ids.json")


def ensure_platform_tables() -> None:
    """테스트 스위트가 만드는 것과 동일한 플랫폼 원천 테이블/컬럼을 보장한다."""
    execute(
        """
        create table if not exists public.proc_def (
            id text primary key, name text, tenant_id text, isdeleted boolean default false
        )
        """
    )
    execute("alter table public.proc_def add column if not exists definition jsonb")
    execute(
        """
        create table if not exists public.bpm_proc_inst (
            proc_inst_id text primary key, proc_inst_name text, proc_def_id text,
            root_proc_inst_id text, status text, tenant_id text, participants jsonb,
            start_date timestamptz, end_date timestamptz, is_deleted boolean default false,
            variables_data jsonb, updated_at timestamptz default now()
        )
        """
    )
    execute(
        """
        create table if not exists public.todolist (
            id uuid primary key, user_id text, proc_def_id text, activity_id text,
            status text, start_date timestamptz, end_date timestamptz, tenant_id text
        )
        """
    )
    for column, ddl in {"proc_inst_id": "text", "duration": "integer"}.items():
        execute(f"alter table public.todolist add column if not exists {column} {ddl}")
    execute(
        """
        create table if not exists public.users (
            id uuid primary key default gen_random_uuid(),
            email text, username text, tenant_id text, is_agent boolean default false
        )
        """
    )
    execute("alter table public.users add column if not exists skills text")
    execute(
        """
        create table if not exists public.skill_contributions (
            id uuid primary key default gen_random_uuid(),
            tenant_id text, skill_name text, contributor_user_id text,
            contributor_name text, contribution_type text,
            source_proposal_id uuid, created_at timestamptz default now()
        )
        """
    )
    execute(
        """
        create table if not exists public.configuration (
            key text, value jsonb, tenant_id text
        )
        """
    )
    # agent_skills 테이블이 존재하면 users.skills 폴백이 무시되므로(ontology_sync),
    # USES_SKILL 쌍은 이 테이블에 직접 넣는다.
    execute(
        """
        create table if not exists public.agent_skills (
            user_id text, tenant_id text, skill_name text
        )
        """
    )


def seed_proc_def(proc_def_id: str, name: str, activity_id: str, activity_name: str) -> None:
    definition = {
        "activities": [{"id": activity_id, "name": activity_name, "type": "userTask"}],
        "roles": [],
    }
    execute(
        """
        insert into public.proc_def (id, name, tenant_id, isdeleted, definition)
        values (:id, :name, :t, false, cast(:d as jsonb))
        """,
        {"id": proc_def_id, "name": name, "t": TENANT, "d": json.dumps(definition)},
    )


def seed_user(name: str, *, is_agent: bool, skills: str | None = None) -> str:
    uid = str(uuid.uuid4())
    execute(
        """
        insert into public.users (id, username, email, tenant_id, is_agent, skills)
        values (cast(:id as uuid), :name, :email, :t, :agent, :skills)
        """,
        {
            "id": uid, "name": name, "email": f"{uid[:8]}@demo.example", "t": TENANT,
            "agent": is_agent, "skills": skills,
        },
    )
    return uid


def seed_instance(proc_def_id: str, name: str) -> str:
    iid = f"inst-{uuid.uuid4().hex[:8]}"
    execute(
        """
        insert into public.bpm_proc_inst
            (proc_inst_id, proc_inst_name, proc_def_id, root_proc_inst_id, status,
             tenant_id, start_date, end_date, is_deleted, updated_at)
        values (:iid, :name, :pdid, :iid, 'COMPLETED', :t,
                now() - interval '2 hours', now() - interval '1 hour', false, now())
        """,
        {"iid": iid, "name": name, "pdid": proc_def_id, "t": TENANT},
    )
    return iid


def seed_task(proc_inst_id: str, proc_def_id: str, activity_id: str, user_id: str, hours: float) -> None:
    execute(
        """
        insert into public.todolist
            (id, user_id, proc_def_id, proc_inst_id, activity_id, status,
             start_date, end_date, tenant_id)
        values (:id, :uid, :pdid, :pi, :aid, 'DONE',
                now() - (cast(:hrs as text) || ' hours')::interval, now() - interval '30 minutes', :t)
        """,
        {
            "id": str(uuid.uuid4()), "uid": user_id, "pdid": proc_def_id, "pi": proc_inst_id,
            "aid": activity_id, "hrs": hours, "t": TENANT,
        },
    )


def seed_skill_contribution(skill_name: str, user_id: str, user_name: str, ctype: str) -> None:
    execute(
        """
        insert into public.skill_contributions
            (tenant_id, skill_name, contributor_user_id, contributor_name, contribution_type)
        values (:t, :skill, :uid, :name, :ctype)
        """,
        {"t": TENANT, "skill": skill_name, "uid": user_id, "name": user_name, "ctype": ctype},
    )


def api(method: str, path: str, **kwargs):
    resp = httpx.request(method, f"{BASE}{path}", params={"tenant_id": TENANT, **kwargs.pop("params", {})}, **kwargs)
    resp.raise_for_status()
    return resp.json()


def main() -> None:
    ensure_platform_tables()

    # 실제 플랫폼 스키마는 tenants FK 를 강제한다 — 스크래치 테넌트를 먼저 등록한다.
    # (cleanup 시 tenants 행 삭제로 ON DELETE CASCADE 연쇄 정리된다.)
    try:
        execute("insert into public.tenants (id) values (:t) on conflict (id) do nothing", {"t": TENANT})
    except Exception:
        pass  # tenants 테이블이 없는 경량 환경(테스트 DB)에서는 FK 가 없으므로 무시

    pd_contract = f"pd-contract-{uuid.uuid4().hex[:6]}"
    pd_review = f"pd-review-{uuid.uuid4().hex[:6]}"
    seed_proc_def(pd_contract, "계약 관리 프로세스", "sign", "계약 체결")
    seed_proc_def(pd_review, "내부 검토 프로세스", "review", "내부 검토")

    kim = seed_user("김지은", is_agent=False)
    bot = seed_user("계약검토봇", is_agent=True, skills="계약 검토 스킬")
    park = seed_user("박민수", is_agent=False)

    # 전략맵 (importance 포함) — 신규 API 표면으로 생성
    obj_sales = api("POST", "/api/objectives", json={
        "name": "매출 성장", "perspective": "financial", "importance": 5,
    })
    obj_ops = api("POST", "/api/objectives", json={
        "name": "운영 효율화", "perspective": "internal_process", "importance": 2,
        "parents": [obj_sales["id"]],
    })
    obj_brand = api("POST", "/api/objectives", json={
        "name": "브랜드 강화", "perspective": "customer", "importance": 3,
    })

    kpi_contract = api("POST", "/api/kpis", json={
        "objective_id": obj_sales["id"], "name": "계약 완료 건수",
        "measure_type": "instance_count", "proc_def_id": pd_contract,
        "baseline_value": 0, "target_value": 10, "importance": 5,
    })
    kpi_review = api("POST", "/api/kpis", json={
        "objective_id": obj_ops["id"], "name": "검토 완료 건수",
        "measure_type": "instance_count", "proc_def_id": pd_review,
        "baseline_value": 0, "target_value": 5,
    })
    kpi_brand = api("POST", "/api/kpis", json={
        "objective_id": obj_brand["id"], "name": "브랜드 인지도",
        "measure_type": "manual", "baseline_value": 0, "target_value": 100,
    })

    # 실행 이력: 계약 3건(김지은 2, 봇 1) / 검토 2건(봇 2)
    for owner in (kim, kim, bot):
        inst = seed_instance(pd_contract, "계약 실행")
        seed_task(inst, pd_contract, "sign", owner, hours=1.0)
    for _ in range(2):
        inst = seed_instance(pd_review, "검토 실행")
        seed_task(inst, pd_review, "review", bot, hours=0.5)

    # 스킬 기여 이력 (agent-feedback 서비스가 적재하는 테이블과 동일 스키마)
    seed_skill_contribution("계약 검토 스킬", kim, "김지은", "CREATED")
    seed_skill_contribution("계약 검토 스킬", kim, "김지은", "MODIFIED")
    seed_skill_contribution("계약 검토 스킬", park, "박민수", "PROPOSAL_APPROVED")

    # 에이전트-스킬 연결(USES_SKILL 원천) — impact 분석의 스킬 개선 후보 경로에 필요
    try:
        # 실제 플랫폼 스키마: agent_skills 는 (tenant_id, skill_name) → tenant_skills FK 필요
        execute(
            "insert into public.tenant_skills (tenant_id, skill_name, owner_id) "
            "values (:t, :s, cast(:o as uuid)) on conflict do nothing",
            {"t": TENANT, "s": "계약 검토 스킬", "o": bot},
        )
    except Exception:
        pass  # 경량 환경(테스트 DB)에는 tenant_skills 테이블/FK 가 없다
    execute(
        "insert into public.agent_skills (user_id, tenant_id, skill_name) values (cast(:u as uuid), :t, :s)",
        {"u": bot, "t": TENANT, "s": "계약 검토 스킬"},
    )

    # 측정 → current_value/achievement 반영, 온톨로지 동기화 → User/Agent/Skill/CONTRIBUTED_TO
    api("POST", "/api/measure/run")
    api("POST", "/api/kpis/" + kpi_brand["id"] + "/value", json={"value": 42})
    sync = api("POST", "/api/ontology/sync")

    ids = {
        "tenant_id": TENANT,
        "objectives": {"sales": obj_sales["id"], "ops": obj_ops["id"], "brand": obj_brand["id"]},
        "kpis": {"contract": kpi_contract["id"], "review": kpi_review["id"], "brand": kpi_brand["id"]},
        "performers": {"kim": kim, "bot": bot, "park": park},
        "proc_defs": {"contract": pd_contract, "review": pd_review},
        "sync_summary": {k: sync.get(k) for k in ("users", "skill_contributions", "performs")},
    }
    with open(OUT, "w") as f:
        json.dump(ids, f, ensure_ascii=False, indent=2)
    print(json.dumps(ids, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
