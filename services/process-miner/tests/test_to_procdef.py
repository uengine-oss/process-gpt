"""프로세스 트리 → proc_def JSON 변환 계약 테스트."""
import json
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


def _out_conditions(d, minedRole):
    gw = next(g for g in d["gateways"] if json.loads(g["properties"]).get("minedRole") == minedRole)
    return {s["condition"]: json.loads(s["properties"]).get("minedRole") for s in d["sequences"] if s["source"] == gw["id"]}


def test_exclusive_branch_options_are_the_first_step_of_each_branch():
    """실행 때 고를 값이 있어야 생성 단계가 직전 폼에 선택지를 만들고 엔진이 선을 고른다.
    '조건1'·'조건2' 자리표시로 두면 고를 근거가 없어 실행이 멈춘다."""
    traces = [["접수", "검토", "승인", "통보"]] * 4 + [["접수", "검토", "반려", "통보"]] * 3
    assert _out_conditions(_defn(traces), "choice") == {"승인": "branch", "반려": "branch"}


def test_skippable_step_offers_skip_option():
    traces = [["접수", "검토", "통보"]] * 3 + [["접수", "통보"]] * 2
    assert _out_conditions(_defn(traces), "choice") == {"검토": "branch", "건너뜀": "skip"}


def test_loop_exit_offers_redo_and_exit_options():
    """반복 판정은 되돌아가는 값과 빠져나가는 값 둘 다 있어야 한다. 빠져나가는 선에 값이 없으면
    선택지가 하나뿐이라 직전 폼에 판단 필드가 생기지 않는다."""
    traces = [["작성", "검토", "발송"]] * 2 + [["작성", "검토", "수정", "검토", "발송"]] * 2
    d = _defn(traces)
    assert validate_definition(d) == []
    assert _out_conditions(d, "loop_exit") == {"수정 필요": "redo", "완료": "exit"}


def test_events_and_gateways_sit_in_a_lane():
    """다이어그램은 역할(레인)별로 노드를 놓는다. 이벤트·게이트웨이의 역할이 비면 레인 밖에 놓여
    연결선이 깨졌다(전환된 프로세스 다이어그램에서 관측). 시작은 첫 단계, 나머지는 앞 노드의 역할."""
    traces = [["작성", "검토", "발송"]] * 2 + [["작성", "검토", "수정", "검토", "발송"]] * 2
    profile = {
        "작성": {"total": 4, "by_agent": 0, "resources": {"u-hong": 4}, "names": {"u-hong": "홍길동"}},
        "검토": {"total": 6, "by_agent": 0, "resources": {"u-lee": 6}, "names": {"u-lee": "이팀장"}},
        "수정": {"total": 2, "by_agent": 0, "resources": {"u-hong": 2}, "names": {"u-hong": "홍길동"}},
        "발송": {"total": 4, "by_agent": 0, "resources": {"u-park": 4}, "names": {"u-park": "박대리"}},
    }
    d = _defn(traces, profile=profile)
    role = {n["id"]: n["role"] for n in d["events"] + d["gateways"]}
    assert all(role.values()), role
    assert role["start_event"] == "홍길동"
    assert role["end_event"] == "박대리"
    by_mined = {json.loads(g["properties"]).get("minedRole"): g["role"] for g in d["gateways"]}
    assert by_mined["loop_entry"] == "홍길동"  # 앞 노드 = 작성
    assert by_mined["loop_exit"] == "이팀장"  # 앞 노드 = 검토


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
