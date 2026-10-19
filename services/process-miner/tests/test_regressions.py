"""분석 문서(2026-10-19)에서 재현한 도출 결함 5개의 회귀 테스트.

데모 데이터에는 없던 입력들이다. 각 테스트는 고치기 전 코드에서 실패한다.
  ① 반려 후 재검토 반복   ② 갈래 안 필수 단계   ③ 컷 없음 대안
  ④ 스레드 시작 단계·두 사람 인계   ⑤ 에이전트 위임의 조직 통계 반영
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app import eventlog, miner, organizational  # noqa: E402
from app.discovery.inductive import discover_from_traces  # noqa: E402
from app.discovery.process_tree import LOOP, TAU, XOR  # noqa: E402
from app.discovery.to_procdef import to_process_definition, validate_definition  # noqa: E402


# ---------------------------------------------------------------------------
# 프로세스 트리
# ---------------------------------------------------------------------------
def test_rework_after_rejection_is_a_loop():
    """① 검토 → 수정 → 검토 가 오가면 '검토와 수정 중 하나' 가 아니라 반복이다."""
    traces = [
        ["작성", "검토", "승인"],
        ["작성", "검토", "수정", "검토", "승인"],
        ["작성", "검토", "수정", "검토", "수정", "검토", "승인"],
    ]
    tree = discover_from_traces(traces)
    assert repr(tree) == "seq('작성', loop('검토', '수정'), '승인')"


def test_rework_loop_definition_routes_back_to_review():
    """① 정의로 옮겨도 수정 다음에 검토로 되돌아가는 흐름이 남는다."""
    traces = [["작성", "검토", "승인"], ["작성", "검토", "수정", "검토", "승인"]] * 2
    defn = to_process_definition(discover_from_traces(traces), process_id="p", process_name="p")
    assert validate_definition(defn) == []
    ids = {a["name"]: a["id"] for a in defn["activities"]}
    assert set(ids) == {"작성", "검토", "수정", "승인"}
    nxt: dict[str, list[str]] = {}
    for s in defn["sequences"]:
        nxt.setdefault(s["source"], []).append(s["target"])

    def reaches(src, dst):
        seen, stack = set(), list(nxt.get(src, []))
        while stack:
            n = stack.pop()
            if n == dst:
                return True
            if n not in seen:
                seen.add(n)
                stack.extend(nxt.get(n, []))
        return False

    assert reaches(ids["수정"], ids["검토"]), "수정 뒤에 검토로 돌아가지 않는다"


def test_steps_always_done_in_a_branch_stay_mandatory():
    """② 한 갈래의 케이스에서 늘 하는 단계는 건너뛸 수 있는 단계가 아니다."""
    traces = [["a", "b", "x", "y"]] * 3 + [["a", "c", "z", "y"]] * 3
    tree = discover_from_traces(traces)
    assert repr(tree) == "seq('a', xor(seq('b', 'x'), seq('c', 'z')), 'y')"


def test_optional_step_inside_a_branch_is_still_optional():
    """② 갈래 기준으로 세도, 그 갈래에서 가끔만 하는 단계는 여전히 선택적이다."""
    traces = [["a", "b", "x", "y"]] * 2 + [["a", "b", "y"]] + [["a", "c", "z", "y"]] * 3
    tree = discover_from_traces(traces)
    assert repr(tree) == "seq('a', xor(seq('b', xor('x', τ)), seq('c', 'z')), 'y')"


def test_no_cut_falls_back_to_unordered_loop_not_exclusive_choice():
    """③ 어떤 구조도 판정하지 못한 활동들을 '하나만 한다' 로 묶지 않는다."""
    traces = [["초안", "수집", "검토"], ["수집", "검토"], ["초안", "보완", "검토", "초안"]]
    tree = discover_from_traces(traces)
    assert tree.kind == LOOP, f"순서 없는 반복이 아니다: {tree}"
    assert tree.children[0].kind == TAU
    assert set(tree.activities()) == {"초안", "수집", "검토", "보완"}
    defn = to_process_definition(tree, process_id="p", process_name="p")
    assert validate_definition(defn) == []


def test_no_cut_fallback_never_returns_bare_exclusive_choice():
    """③ 컷이 없는 하위 로그가 어디에 있든 xor(모든 활동) 이 나오지 않는다."""
    traces = [["c", "a", "b"], ["a", "a"], ["b", "c"], ["b", "c", "a"]]
    tree = discover_from_traces(traces)
    assert not (tree.kind == XOR and {c.kind for c in tree.children} == {"act"}), repr(tree)


# ---------------------------------------------------------------------------
# 이벤트 로그
# ---------------------------------------------------------------------------
def _quote_threads(n=3, with_delegation=False, returned=False):
    """김(견적서 작성) → 이팀장(견적 검토) → 박대리(고객 발송). 이팀장이 법무 에이전트에게 위임하기도 한다."""
    rows = []
    for c in range(n):
        rid, day = f"room{c}", f"2026-10-0{c + 1}"
        rows.append(dict(origin_room_id=rid, source="chat_handover", is_explicit=True,
                         from_user_id="kim", from_user_name="김주임", to_user_id="lee", to_user_name="이팀장",
                         activity_label="견적서 작성", next_activity_label="견적 검토", occurred_at=f"{day}T09:00"))
        if with_delegation:
            rows.append(dict(origin_room_id=rid, source="agent_delegation", is_explicit=False,
                             from_user_id="lee", from_user_name="이팀장", to_user_id="legal-agent",
                             to_user_name="법무 에이전트", to_is_agent=True, agent_orch="deepagents",
                             activity_label="이 견적 기준으로 계약서 초안 써줘", occurred_at=f"{day}T10:00",
                             returned_at=f"{day}T10:05" if returned else None))
        rows.append(dict(origin_room_id=rid, source="chat_handover", is_explicit=True,
                         from_user_id="lee", from_user_name="이팀장", to_user_id="park", to_user_name="박대리",
                         activity_label="견적 검토", next_activity_label="고객 발송", occurred_at=f"{day}T11:00"))
    return rows


def test_thread_starter_and_their_work_become_the_first_step():
    """④ 스레드를 시작한 사람이 한 일이 첫 단계로, 그 사람이 담당으로 들어간다."""
    r = miner.analyze(_quote_threads())
    assert r["ok"]
    assert r["stats"]["variants"] == [{"trace": ["견적서 작성", "견적 검토", "고객 발송"], "count": 3}]
    defn, problems = miner.build_definition(r, process_id="p", process_name="p")
    assert problems == []
    first = next(a for a in defn["activities"] if a["name"] == "견적서 작성")
    assert first["role"] == "김주임"


def test_single_handover_between_two_people_is_analyzed():
    """④ 두 사람 사이의 단순 인계(행 1개)도 단계 2개짜리 케이스로 분석된다."""
    rows = [r for r in _quote_threads() if r["to_user_id"] == "lee"]
    r = miner.analyze(rows)
    assert r["ok"], r.get("reason")
    assert r["stats"]["dropped_short_cases"] == 0
    assert r["stats"]["variants"] == [{"trace": ["견적서 작성", "견적 검토"], "count": 3}]


def test_starter_label_from_agent_delegation_is_not_used():
    """④ 첫 행이 암묵 위임이면 activity_label 은 대화 원문이라 첫 단계로 쓰지 않는다."""
    rows = [dict(origin_room_id="r", source="agent_delegation", from_user_id="kim", to_user_id="bot",
                 to_is_agent=True, activity_label="이거 견적 좀 뽑아줘", occurred_at="2026-10-01T09")]
    events = eventlog.build_events(rows)
    assert all(e.kind != eventlog.START for e in events)
    assert eventlog.to_traces(events) == {}


def test_delegation_before_the_first_handover_belongs_to_the_starting_step():
    """④⑤ 시작한 사람이 인계 전에 에이전트에게 먼저 맡겼어도 시작 단계가 생기고, 위임은 그 단계에 붙는다."""
    rows = []
    for c in range(3):
        rid, day = f"r{c}", f"2026-10-0{c + 1}"
        rows.append(dict(origin_room_id=rid, source="agent_delegation", from_user_id="kim", from_user_name="김주임",
                         to_user_id="doc-agent", to_user_name="문서 에이전트", to_is_agent=True,
                         activity_label="견적서 초안 만들어줘", occurred_at=f"{day}T08:00"))
        rows.append(dict(origin_room_id=rid, source="chat_handover", from_user_id="kim", from_user_name="김주임",
                         to_user_id="lee", to_user_name="이팀장", activity_label="견적서 작성",
                         next_activity_label="견적 검토", occurred_at=f"{day}T09:00"))
    r = miner.analyze(rows)
    assert r["stats"]["variants"] == [{"trace": ["견적서 작성", "견적 검토"], "count": 3}]
    el = {e["activity"]: e for e in organizational.activity_eligibility(eventlog.build_events(rows))}
    assert any(c["user_id"] == "doc-agent" for c in el["견적서 작성"]["candidates"])


def test_agent_delegation_reaches_network_automation_and_eligibility():
    """⑤ 활동명 없는 위임도 인계 네트워크·자동화율·활동별 자격에 들어간다."""
    rows = _quote_threads(with_delegation=True, returned=True)
    events = eventlog.build_events(rows)

    net = {(e["from"], e["to"]): e["count"] for e in organizational.handover_matrix(events)}
    assert net[("lee", "legal-agent")] == 3
    assert net[("legal-agent", "lee")] == 3  # 위임을 마치고 돌려줌
    assert net[("kim", "lee")] == 3 and net[("lee", "park")] == 3
    assert ("legal-agent", "park") not in net  # 넘긴 사람은 이팀장이다

    auto = eventlog.resource_profile(events)["견적 검토"]
    assert auto["by_agent"] == 3 and auto["total"] == 6

    el = {e["activity"]: e for e in organizational.activity_eligibility(events)}
    agents = [c for c in el["견적 검토"]["candidates"] if c["is_agent"]]
    assert agents and agents[0]["user_id"] == "legal-agent" and agents[0]["evidence_count"] == 3
    assert el["견적 검토"]["automation_rate"] == 0.5


def test_agent_delegation_stays_out_of_control_flow():
    """⑤ 위임은 조직 통계에만 들어가고 흐름과 역할은 바꾸지 않는다(대화 원문 차단 유지)."""
    r = miner.analyze(_quote_threads(with_delegation=True))
    assert r["stats"]["variants"] == [{"trace": ["견적서 작성", "견적 검토", "고객 발송"], "count": 3}]
    assert r["stats"]["delegation_count"] == 3
    defn, _ = miner.build_definition(r, process_id="p", process_name="p")
    review = next(a for a in defn["activities"] if a["name"] == "견적 검토")
    assert review["role"] == "이팀장" and review["agent"] == ""
    assert all("계약서 초안" not in a["name"] for a in defn["activities"])
