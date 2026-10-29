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


def _out_of(d, gid):
    return [s for s in d["sequences"] if s["source"] == gid]


def _split(d):
    """처음 나오는 배타 분기(갈래가 둘 이상인 것)."""
    return next(g for g in d["gateways"] if g["type"] == "exclusiveGateway" and len(_out_of(d, g["id"])) > 1)


def test_exclusive_branch_emits_gateways_with_conditions():
    traces = [["접수", "검토", "승인", "통보"]] * 4 + [["접수", "검토", "반려", "통보"]] * 3
    profile = {"승인": {"total": 4}, "반려": {"total": 3}}
    d = _defn(traces, profile=profile)
    assert validate_definition(d) == []
    outs = _out_of(d, _split(d)["id"])
    # 자리표시("조건1")가 아니라 앞 단계 결과로 판단하는 조건, 갈래마다 하나
    assert sorted(s["condition"] for s in outs) == ["앞 단계 결과가 '반려' 을(를) 요구한다", "앞 단계 결과가 '승인' 을(를) 요구한다"]
    props = {s["name"]: json.loads(s["properties"]) for s in outs}
    # 아무것도 맞지 않으면 가장 많이 관측된 갈래(기본 흐름), 둘 다 참이면 우선순위
    assert props["승인"] == {"priority": 0, "default": True}
    assert props["반려"] == {"priority": 1}


def test_optional_step_defaults_to_doing_it():
    """선택적 단계(xor(단계, τ))는 조건 없이 그 단계를 하는 갈래가 기본 — 건너뛰는 갈래는 실제 조건이 붙기 전까지 타지 않는다.

    "조건1"/"조건2" 를 엔진이 둘 다 참으로 읽어 재무 검토와 고객 회신을 함께 내주던 문제."""
    traces = [["Receive request mail", "Prepare quote", "Finance review", "Reply to customer"]] * 4 \
        + [["Receive request mail", "Prepare quote", "Reply to customer"]]
    profile = {"Finance review": {"total": 4}}
    tree = discover_from_traces(traces)
    d = to_process_definition(tree, process_id="mined_test", process_name="Design proposal & quote", profile=profile, case_count=5)
    assert validate_definition(d) == []
    outs = _out_of(d, _split(d)["id"])
    assert [s["condition"] for s in outs] == ["", ""], "no placeholder conditions"
    by = {s["name"]: json.loads(s["properties"]) for s in outs}
    assert by == {"Finance review": {"priority": 0, "default": True}, "Skip": {"priority": 1}}
    # the engine picks exactly one: the default/first-priority branch leads to the review
    first = min(outs, key=lambda s: json.loads(s["properties"])["priority"])
    assert next(a for a in d["activities"] if a["id"] == first["target"])["name"] == "Finance review"


def test_rarely_done_optional_step_is_still_the_default():
    """많이 건너뛴 선택적 단계도 기본은 하는 쪽 — 실제 조건 없이 말없이 건너뛰지 않는다."""
    traces = [["접수", "디자인 검토", "회신"]] * 2 + [["접수", "회신"]] * 5
    d = to_process_definition(discover_from_traces(traces), process_id="mined_test", process_name="테스트", profile={"디자인 검토": {"total": 2}}, case_count=7)
    by = {s["name"]: json.loads(s["properties"]) for s in _out_of(d, _split(d)["id"])}
    assert by == {"디자인 검토": {"priority": 0, "default": True}, "건너뜀": {"priority": 1}}


def test_english_flow_gets_english_names():
    traces = [["Receive request mail", "Draw floor plan", "Finance review", "Reply to customer"]] * 3 \
        + [["Receive request mail", "Draw floor plan", "Reply to customer"]]
    d = to_process_definition(discover_from_traces(traces), process_id="mined_en", process_name="Design proposal & quote", case_count=4)
    words = [g["name"] for g in d["gateways"]] + [e["name"] for e in d["events"]] + [s["name"] for s in d["sequences"]] \
        + [r["resolutionRule"] for r in d["roles"]] + [a["description"] for a in d["activities"]] + sum((a["outputData"] for a in d["activities"]), [])
    assert not any(any("\uac00" <= ch <= "\ud7a3" for ch in w) for w in words), words
    assert {"Split", "Join"} <= {g["name"] for g in d["gateways"]}
    assert [e["name"] for e in d["events"]] == ["Start", "End"]
    # lang wins over the labels' language (an English tenant asking about Korean-labelled records, or the other way)
    k = to_process_definition(discover_from_traces(traces), process_id="mined_en", process_name="x", lang="ko")
    assert [e["name"] for e in k["events"]] == ["시작", "종료"]


def test_loop_exits_by_default():
    traces = [["A", "B", "C"], ["A", "B", "A", "B", "C"], ["A", "B", "C"]] * 2
    d = _defn(traces)
    assert validate_definition(d) == []
    for g in d["gateways"]:
        outs = _out_of(d, g["id"])
        if len(outs) > 1:
            defaults = [s for s in outs if json.loads(s["properties"]).get("default")]
            assert len(defaults) == 1, f"{g['name']}: exactly one default flow"


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
