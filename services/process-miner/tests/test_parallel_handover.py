"""병렬 인계(2026-10-23).

한 번의 인계로 여러 사람(에이전트)에게 일을 나눠 줄 수 있다. 받는 사람마다 한 행을 남기고
같은 인계에서 나온 행은 같은 group_id 로 묶는다.

- 묶음 안에서 다음 할 일이 서로 다르면 병렬(AND), 같으면 다중 인스턴스로 도출한다.
- 갈래 끝이 모두 끝나야 스레드가 끝난 건이다. 하나라도 진행 중이면 도출에 들어가지 않는다.
- 묶음이 없는 기록의 도출 결과는 예전과 같다.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app import eventlog, miner  # noqa: E402
from app.discovery.inductive import discover_from_traces  # noqa: E402
from app.discovery.process_tree import AND, SEQ  # noqa: E402


def _row(case, at, frm, to, done, nxt, *, from_room, to_room, group=None, status="DONE", to_agent=False, closed_at=None):
    return dict(
        origin_room_id=case, source="chat_handover", is_explicit=True,
        from_user_id=frm, from_user_name=frm, to_user_id=to, to_user_name=to, to_is_agent=to_agent,
        activity_label=done, next_activity_label=nxt, occurred_at=at,
        from_room_id=from_room, to_room_id=to_room, group_id=group,
        to_task_status=status, closed_at=closed_at,
    )


def parallel_case(case, day, *, first_status="DONE", second_status="DONE"):
    """접수(hong) → [법무 검토(lee) → 법무 의견 회신(hong)] ∥ [재무 검토(park) → 재무 의견 회신(hong)]

    두 갈래가 같은 시각대에 섞여 진행된다. 시간순으로 펴면 갈래 b 의 다음 단계가
    갈래 c 의 첫 단계 뒤에 붙는다.
    """
    root, b, c, bd, ce = (f"{case}-{x}" for x in ("root", "b", "c", "bd", "ce"))
    g = f"{case}-g"
    return [
        _row(case, f"{day}T09:00:00", "hong", "lee", "계약 요청 접수", "법무 검토", from_room=root, to_room=b, group=g),
        _row(case, f"{day}T09:00:01", "hong", "park", "계약 요청 접수", "재무 검토", from_room=root, to_room=c, group=g),
        _row(case, f"{day}T10:00:00", "lee", "hong", "법무 검토", "법무 의견 회신", from_room=b, to_room=bd, status=first_status),
        _row(case, f"{day}T11:00:00", "park", "hong", "재무 검토", "재무 의견 회신", from_room=c, to_room=ce, status=second_status),
    ]


def multi_case(case, day):
    """견적 요청 접수(hong) → 견적 검토를 lee·park 두 명에게 동시에 → 각자 끝"""
    root = f"{case}-root"
    g = f"{case}-g"
    return [
        _row(case, f"{day}T09:00:00", "hong", "lee", "견적 요청 접수", "견적 검토", from_room=root, to_room=f"{case}-b", group=g),
        _row(case, f"{day}T09:00:01", "hong", "park", "견적 요청 접수", "견적 검토", from_room=root, to_room=f"{case}-c", group=g),
    ]


def _tree(rows):
    result = miner.analyze(rows)
    assert result["ok"], result
    return result


def _find(node, kind):
    if node.kind == kind:
        return node
    for c in node.children:
        hit = _find(c, kind)
        if hit is not None:
            return hit
    return None


def test_다른_일을_나눠_준_인계가_반복되면_병렬_단계로_도출된다():
    rows = parallel_case("p1", "2026-10-01") + parallel_case("p2", "2026-10-02") + parallel_case("p3", "2026-10-03")
    result = _tree(rows)
    tree = result["tree_node"]

    assert tree.kind == SEQ
    assert tree.children[0].label == "계약 요청 접수"
    par = _find(tree, AND)
    assert par is not None, result["tree"]
    branches = sorted(sorted(ch.activities()) for ch in par.children)
    assert branches == [["법무 검토", "법무 의견 회신"], ["재무 검토", "재무 의견 회신"]]
    # 갈래 안의 순서는 지킨다
    for ch in par.children:
        assert ch.kind == SEQ
        assert ch.children[0].label in {"법무 검토", "재무 검토"}
    assert result["stats"]["multi_instance_activities"] == []
    # 화면이 쓰는 흐름 목록(시간순)은 케이스 수 그대로다
    assert result["stats"]["case_count"] == 3


def test_병렬_도출_결과는_정의로_변환해도_계약을_지킨다():
    rows = parallel_case("p1", "2026-10-01") + parallel_case("p2", "2026-10-02") + parallel_case("p3", "2026-10-03")
    result = _tree(rows)
    defn, problems = miner.build_definition(result, process_id="p", process_name="계약 요청 접수 프로세스")
    assert problems == []
    kinds = [g["type"] for g in defn["gateways"]]
    assert kinds.count("parallelGateway") == 2


def test_같은_일을_여러_명에게_준_인계가_반복되면_다중_인스턴스로_도출된다():
    rows = multi_case("m1", "2026-10-01") + multi_case("m2", "2026-10-02") + multi_case("m3", "2026-10-03")
    result = _tree(rows)
    assert result["stats"]["multi_instance_activities"] == ["견적 검토"]
    # 같은 일은 한 활동으로 합친다 — 두 번 하는 반복이 아니다
    assert result["tree"] == "seq('견적 요청 접수', '견적 검토')"


def test_갈래_하나라도_진행_중이면_스레드는_끝나지_않았다():
    assert eventlog.thread_finished(parallel_case("p1", "2026-10-01"))
    assert not eventlog.thread_finished(parallel_case("p1", "2026-10-01", second_status="IN_PROGRESS"))
    assert not eventlog.thread_finished(parallel_case("p1", "2026-10-01", first_status="TODO"))


def test_진행_중인_갈래가_있는_스레드는_도출에서_빠진다():
    rows = (
        parallel_case("p1", "2026-10-01")
        + parallel_case("p2", "2026-10-02")
        + parallel_case("p3", "2026-10-03")
        + parallel_case("p4", "2026-10-04", second_status="IN_PROGRESS")
    )
    result = _tree(rows)
    assert result["stats"]["case_count"] == 3
    assert result["stats"]["in_progress_cases"] == 1


def test_에이전트에게_간_갈래는_업무_종료를_눌러야_끝난다():
    case = "a1"
    g = "a1-g"
    rows = [
        _row(case, "2026-10-01T09:00:00", "hong", "doc-agent", "접수", "초안 작성", from_room="r", to_room="b", group=g, to_agent=True, status="SUBMITTED"),
        _row(case, "2026-10-01T09:00:01", "hong", "lee", "접수", "검토", from_room="r", to_room="c", group=g),
    ]
    assert not eventlog.thread_finished(rows)
    rows[0]["closed_at"] = "2026-10-01T12:00:00"
    assert eventlog.thread_finished(rows)


def test_묶음이_없는_기록은_예전과_같은_흐름으로_도출된다():
    """병렬 인계 도입 전 기록: group_id 가 없다. 도출에 쓰는 흐름이 시간순 흐름과 같아야 한다."""
    rows = []
    for i in range(3):
        case = f"s{i}"
        rows += [
            _row(case, f"2026-10-0{i + 1}T09:00", "hong", "lee", "견적 요청 접수", "견적서 초안 작성", from_room=f"{case}-r", to_room=f"{case}-b"),
            _row(case, f"2026-10-0{i + 1}T10:00", "lee", "park", "견적서 초안 작성", "견적서 승인", from_room=f"{case}-b", to_room=f"{case}-c"),
        ]
    rows_done, _ = eventlog.finished_rows(rows)
    events = eventlog.build_events(rows_done)
    by_case = eventlog.to_traces(events)
    log, concurrent, multi = eventlog.discovery_log(events, set(by_case))
    assert log == [by_case[c] for c in sorted(by_case)]
    assert concurrent == set() and multi == set()
    assert repr(discover_from_traces(log)) == repr(discover_from_traces(list(by_case.values())))
