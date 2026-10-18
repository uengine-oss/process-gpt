"""데모/검증용 핸드오버 로그 시드.

같은 업무(견적 처리)가 여러 번 반복 수행된 상황을 만든다. 각 케이스는 서로 다른
채팅방에서 시작해 origin_room_id 로 묶인 스레드가 되고, 그중 일부는 반려 갈래를 탄다.
마이너가 이 누적에서 공통 프로세스를 찾아낼 수 있는지 보기 위한 것.

실행: cd services/process-miner && python3 scripts/seed_demo_handovers.py
"""
from __future__ import annotations

import sys
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app import db  # noqa: E402

TENANT = "localhost"

PEOPLE = {
    "u-alice": "김주임",
    "u-bob": "박상무",
    "u-carol": "이대리",
    "u-dan": "최과장",
}
AGENTS = {"a-quote": "견적 산출 에이전트", "a-review": "계약검토 에이전트"}

# (활동명, 수행 리소스) — 관측된 흐름
HAPPY = [
    ("견적 산출", "a-quote"),
    ("견적서 검토 및 승인", "u-bob"),
    ("계약서 초안 작성", "a-review"),
    ("고객 발송", "u-carol"),
]
REJECTED = [
    ("견적 산출", "a-quote"),
    ("견적서 검토 및 승인", "u-bob"),
    ("견적 재산출", "u-alice"),
    ("계약서 초안 작성", "a-review"),
    ("고객 발송", "u-carol"),
]

# 8건 중 5건은 정상, 3건은 재산출을 거친다
CASES = [HAPPY] * 5 + [REJECTED] * 3


def main() -> None:
    conn = db.connect()
    base = datetime.now(timezone.utc) - timedelta(days=30)

    with conn.cursor() as cur:
        cur.execute("delete from public.handover_events where tenant_id = %s", (TENANT,))

        total = 0
        for ci, flow in enumerate(CASES):
            origin_room = f"room-quote-{ci + 1:02d}"
            prev_room, prev_user = origin_room, "u-alice"
            t = base + timedelta(days=ci * 3)

            for si, (activity, resource) in enumerate(flow):
                is_agent = resource in AGENTS
                to_room = origin_room if is_agent else str(uuid.uuid4())
                t += timedelta(hours=2 if is_agent else 20)

                cur.execute(
                    """
                    insert into public.handover_events
                        (id, tenant_id, case_id, origin_room_id, source, is_explicit,
                         from_room_id, to_room_id, from_user_id, from_user_name, from_is_agent,
                         to_user_id, to_user_name, to_is_agent, agent_orch,
                         activity_label, next_activity_label, occurred_at, returned_at)
                    values (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
                    """,
                    (
                        str(uuid.uuid4()),
                        TENANT,
                        origin_room,
                        origin_room,
                        "agent_delegation" if is_agent else "chat_handover",
                        not is_agent,
                        prev_room,
                        to_room,
                        prev_user,
                        PEOPLE.get(prev_user, prev_user),
                        prev_user in AGENTS,
                        resource,
                        AGENTS.get(resource) or PEOPLE.get(resource, resource),
                        is_agent,
                        "deepagents" if is_agent else None,
                        flow[si - 1][0] if si else "요청 접수",
                        activity,
                        t,
                        t + timedelta(minutes=8) if is_agent else None,
                    ),
                )
                total += 1
                prev_room, prev_user = to_room, resource

    conn.commit()
    print(f"시드 완료: 케이스 {len(CASES)}건 / 이벤트 {total}건 (tenant={TENANT})")


if __name__ == "__main__":
    main()
