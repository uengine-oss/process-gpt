"""데모용 사람 사용자와 조직도 배치.

지금까지 로컬 테넌트에는 에이전트만 있고 사람이 demo 하나뿐이라, 인계 대상으로
'기본 LLM' 같은 내장 에이전트가 잡히는 어색한 상황이 됐다. 실제 조직처럼
역할과 부서를 가진 사람을 넣고, 조직도(configuration.organization)의 팀 아래에
배치한다.

실행: cd services/process-miner && ./.venv/bin/python scripts/seed_people.py
"""
from __future__ import annotations

import json
import sys
import uuid
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app import db  # noqa: E402

TENANT = "localhost"

# (id, 이름, 이메일, 역할, 부서, 소속 팀명)
PEOPLE = [
    ("11111111-1111-4111-8111-111111111101", "박상무", "bob@localhost", "영업총괄", "영업본부", "영업팀"),
    ("11111111-1111-4111-8111-111111111102", "김주임", "alice@localhost", "영업담당", "영업본부", "영업팀"),
    ("11111111-1111-4111-8111-111111111103", "이대리", "carol@localhost", "영업담당", "영업본부", "영업팀"),
    ("11111111-1111-4111-8111-111111111104", "최과장", "dan@localhost", "계약검토", "법무팀", "법무팀"),
]

# 역량 사전과 사람별 보유 역량(관리자가 선언한 것)
CAPABILITIES = {
    "견적 산출": "단가표와 할인 규정을 적용해 견적을 계산한다",
    "견적 승인": "할인율과 납기가 사내 한도 안인지 판단하고 승인한다",
    "계약 검토": "표준 약관 대비 특약을 식별하고 계약서를 검토한다",
    "고객 커뮤니케이션": "고객에게 산출물을 발송하고 회신을 관리한다",
}
DECLARED = {
    "박상무": ["견적 승인"],
    "김주임": ["견적 산출", "고객 커뮤니케이션"],
    "이대리": ["고객 커뮤니케이션"],
    "최과장": ["계약 검토"],
}


def main() -> None:
    conn = db.connect()
    with conn.cursor() as cur:
        # 1) 사람 사용자
        for uid, name, email, role, dept, _team in PEOPLE:
            cur.execute(
                """
                insert into public.users (id, tenant_id, username, email, role, is_agent, is_admin, profile)
                values (%s, %s, %s, %s, %s, false, false, '/images/defaultUser.png')
                on conflict (id, tenant_id) do update
                    set username = excluded.username, email = excluded.email, role = excluded.role
                """,
                (uid, TENANT, name, email, role),
            )
            # department_name 컬럼이 없는 배포도 있다. 세이브포인트로 감싸야
            # 실패해도 앞서 넣은 사용자까지 롤백되지 않는다.
            cur.execute("savepoint sp_dept")
            try:
                cur.execute(
                    "update public.users set department_name = %s where id = %s and tenant_id = %s",
                    (dept, uid, TENANT),
                )
                cur.execute("release savepoint sp_dept")
            except Exception:
                cur.execute("rollback to savepoint sp_dept")

        # 2) 역량 사전
        cap_ids: dict[str, str] = {}
        for cname, desc in CAPABILITIES.items():
            cur.execute(
                """
                insert into public.org_capabilities (tenant_id, name, description, origin)
                values (%s, %s, %s, 'declared')
                on conflict (tenant_id, name) do update set description = excluded.description
                returning id
                """,
                (TENANT, cname, desc),
            )
            cap_ids[cname] = cur.fetchone()["id"]

        # 3) 사람별 보유 역량(선언)
        name_to_id = {p[1]: p[0] for p in PEOPLE}
        for pname, caps in DECLARED.items():
            for c in caps:
                cur.execute(
                    """
                    insert into public.user_capabilities
                        (tenant_id, user_id, capability_id, source, proficiency)
                    values (%s, %s, %s, 'declared', 'primary')
                    on conflict (tenant_id, user_id, capability_id) do nothing
                    """,
                    (TENANT, name_to_id[pname], cap_ids[c]),
                )

        # 4) 조직도에 사람 배치 (팀 노드 아래 children 으로)
        cur.execute(
            "select value from public.configuration where key='organization' and tenant_id=%s",
            (TENANT,),
        )
        row = cur.fetchone()
        if row:
            value = row["value"]
            chart = value.get("chart") or {}
            teams = {c.get("data", {}).get("name"): c for c in chart.get("children", [])}

            for uid, name, email, role, dept, team_name in PEOPLE:
                team = teams.get(team_name)
                if team is None:  # 팀이 없으면 새로 만든다
                    team = {
                        "id": str(uuid.uuid4()),
                        "data": {"id": str(uuid.uuid4()), "img": "", "name": team_name, "isTeam": True},
                        "children": [],
                    }
                    chart.setdefault("children", []).append(team)
                    teams[team_name] = team
                team.setdefault("children", [])
                if any(ch.get("id") == uid for ch in team["children"]):
                    continue
                team["children"].append(
                    {
                        "id": uid,
                        "name": name,
                        "data": {
                            "id": uid,
                            "img": "/images/defaultUser.png",
                            "pid": team["id"],
                            "name": name,
                            "email": email,
                            "role": role,
                            "username": name,
                            "department": dept,
                        },
                    }
                )
            value["chart"] = chart
            cur.execute(
                "update public.configuration set value = %s where key='organization' and tenant_id=%s",
                (json.dumps(value, ensure_ascii=False), TENANT),
            )

    conn.commit()
    print(f"사람 {len(PEOPLE)}명 · 역량 {len(CAPABILITIES)}개 · 조직도 배치 완료 (tenant={TENANT})")


if __name__ == "__main__":
    main()
