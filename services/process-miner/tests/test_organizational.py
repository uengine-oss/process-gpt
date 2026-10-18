"""조직 마이닝 단위 테스트 — 결정론적, DB·LLM 불필요."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.eventlog import Event  # noqa: E402
from app.organizational import (  # noqa: E402
    activity_eligibility,
    analyze,
    handover_matrix,
    role_clusters,
)


def ev(case, act, res, name, agent=False):
    return Event(
        case_id=case, activity=act, resource=res, resource_name=name,
        is_agent=agent, agent_orch=None, occurred_at=f"{case}-{act}", source="chat_handover"
    )


def sample():
    """견적 흐름 2케이스. 같은 활동은 같은 사람이 수행한다."""
    out = []
    for c in ("c1", "c2"):
        out += [
            ev(c, "견적 산출", "a-quote", "견적 에이전트", agent=True),
            ev(c, "견적서 검토 및 승인", "u-bob", "박상무"),
            ev(c, "고객 발송", "u-carol", "이대리"),
        ]
    return out


def test_roles_group_by_what_people_actually_do():
    clusters = role_clusters(sample())
    members = {c["role"]: {m["name"] for m in c["members"]} for c in clusters}
    assert members["견적서 검토 및 승인"] == {"박상무"}
    assert members["고객 발송"] == {"이대리"}


def test_eligibility_lists_who_can_do_an_activity():
    el = {e["activity"]: e for e in activity_eligibility(sample())}
    approve = el["견적서 검토 및 승인"]
    assert approve["required_capability"] == "견적서 검토 및 승인"
    assert approve["candidates"][0]["name"] == "박상무"
    assert approve["candidates"][0]["evidence_count"] == 2
    # 사람이 한 단계이므로 자동화율 0
    assert approve["automation_rate"] == 0


def test_agent_step_reports_automation_rate():
    el = {e["activity"]: e for e in activity_eligibility(sample())}
    assert el["견적 산출"]["automation_rate"] == 1.0
    assert el["견적 산출"]["candidates"][0]["is_agent"] is True


def test_handover_network_counts_transfers():
    net = {(e["from"], e["to"]): e["count"] for e in handover_matrix(sample())}
    assert net[("a-quote", "u-bob")] == 2
    assert net[("u-bob", "u-carol")] == 2


def test_mixed_role_is_flagged():
    """사람과 에이전트가 같은 활동을 하면 겸용 역할로 표시한다."""
    evs = sample() + [
        ev("c3", "고객 발송", "a-send", "발송 에이전트", agent=True),
        ev("c4", "고객 발송", "a-send", "발송 에이전트", agent=True),
    ]
    clusters = {c["role"]: c for c in role_clusters(evs)}
    send = clusters.get("고객 발송")
    assert send is not None
    assert send["mixed"] is True


def test_analyze_returns_all_three_views():
    r = analyze(sample())
    assert set(r) == {"network", "roles", "eligibility"}
    assert r["network"] and r["roles"] and r["eligibility"]
