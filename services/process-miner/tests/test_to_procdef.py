"""프로세스 트리 → proc_def JSON 변환 계약 테스트."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.discovery.inductive import discover_from_traces  # noqa: E402
from app.discovery.to_procdef import to_process_definition, validate_definition  # noqa: E402


def _defn(traces, profile=None):
    tree = discover_from_traces(traces)
    return to_process_definition(tree, process_id="mined_test", process_name="테스트", profile=profile)


def test_sequence_definition_is_valid():
    d = _defn([["접수", "검토", "승인"]] * 3)
    assert validate_definition(d) == []
    assert [a["name"] for a in d["activities"]] == ["접수", "검토", "승인"]
    assert len(d["events"]) == 2


def test_exclusive_branch_emits_gateways_with_conditions():
    traces = [["접수", "검토", "승인", "통보"]] * 4 + [["접수", "검토", "반려", "통보"]] * 3
    d = _defn(traces)
    assert validate_definition(d) == []
    assert any(g["type"] == "exclusiveGateway" for g in d["gateways"])
    conds = [s["condition"] for s in d["sequences"] if s["condition"]]
    assert len(conds) >= 2, "배타 분기의 각 갈래에 조건 자리가 있어야 한다"


def test_parallel_branch_emits_parallel_gateways():
    traces = [["시작", "법무검토", "재무검토", "종료"], ["시작", "재무검토", "법무검토", "종료"]] * 4
    d = _defn(traces)
    assert validate_definition(d) == []
    assert any(g["type"] == "parallelGateway" for g in d["gateways"])


def test_agent_activity_gets_orchestration():
    """에이전트가 늘 수행한 활동은 실행 가능한 형태로 나와야 한다."""
    profile = {
        "견적 산출": {
            "total": 5,
            "by_agent": 5,
            "resources": {"a-quote": 5},
            "names": {"a-quote": "견적 산출 에이전트"},
            "orchs": {"deepagents": 5},
        }
    }
    d = _defn([["견적 산출"]] * 5, profile=profile)
    act = d["activities"][0]
    assert act["agent"] == "a-quote"
    assert act["orchestration"] == "deepagents"
    assert act["agentMode"] == "COMPLETE"
    assert any(r["endpoint"] == "a-quote" for r in d["roles"])


def test_mixed_agent_and_human_is_draft_mode():
    profile = {
        "검토": {
            "total": 4,
            "by_agent": 2,
            "resources": {"a-review": 2, "u-bob": 2},
            "names": {"a-review": "검토 에이전트", "u-bob": "박상무"},
            "orchs": {"deepagents": 2},
        }
    }
    d = _defn([["검토"]] * 4, profile=profile)
    assert d["activities"][0]["agentMode"] == "DRAFT"


def test_properties_are_strings_not_objects():
    """엔진 계약: properties 는 JSON 문자열이어야 한다."""
    d = _defn([["A", "B"]] * 2)
    for coll in ("activities", "gateways", "events", "sequences"):
        for n in d[coll]:
            assert isinstance(n["properties"], str), f"{coll}.{n['id']}.properties 가 문자열이 아님"


def test_all_nodes_reachable_from_start():
    traces = [
        ["접수", "검토", "승인", "통보"],
        ["접수", "검토", "반려", "통보"],
        ["접수", "검토", "보류", "통보"],
    ] * 2
    d = _defn(traces)
    assert validate_definition(d) == []
