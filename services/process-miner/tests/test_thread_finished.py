"""끝난 스레드만 도출에 넣는다(2026-10-20 안정화).

실환경 견적 업무에서 에이전트 결과를 못 봐 멈춘 건이 완료 케이스로 들어가
견적 검토 · 고객 발송이 '건너뛸 수 있는 단계' 로 도출됐다.
스레드는 마지막으로 받은 할 일이 완료돼야 끝난 건이다.

아래 네 가지 형태의 업무 기록에서, 도출 결과의 단계와 흐름이 기록에서 관측된 것만으로
이루어지는지도 함께 확인한다.
  반려 후 재검토 반복 · 갈래가 나뉘는 업무 · 에이전트가 중간 단계를 맡는 업무 · 두 사람 사이 단순 인계
"""
import itertools
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app import eventlog, miner  # noqa: E402
from app.discovery.process_tree import ACT, AND, LOOP, SEQ, TAU, XOR  # noqa: E402


# ---------------------------------------------------------------------------
# 기록 만들기
# ---------------------------------------------------------------------------
def _handover(rid, at, frm, to, done, nxt, *, to_agent=False, status="DONE", closed_at=None):
    return dict(
        origin_room_id=rid, source="chat_handover", is_explicit=True,
        from_user_id=frm, from_user_name=frm, to_user_id=to, to_user_name=to, to_is_agent=to_agent,
        activity_label=done, next_activity_label=nxt, occurred_at=at,
        to_task_status=status, closed_at=closed_at,
    )


def _thread(rid, day, steps, *, last_status="DONE", closed=False):
    """steps: [(보낸 사람, 받는 사람, 지금까지 한 일, 다음 할 일, 받는 쪽이 에이전트)] 순서대로."""
    rows = []
    for i, (frm, to, done, nxt, to_agent) in enumerate(steps):
        last = i == len(steps) - 1
        status = last_status if last else ("SUBMITTED" if to_agent else "DONE")
        rows.append(
            _handover(rid, f"{day}T{9 + i:02d}:00", frm, to, done, nxt, to_agent=to_agent, status=status,
                      closed_at=f"{day}T20:00" if (last and closed) else None)
        )
    return rows


def rework_log():
    """반려 후 재검토: 작성 → 검토 → (수정 → 검토)* → 발송"""
    rows = []
    for c, rejects in enumerate([0, 1, 2]):
        steps = [("hong", "lee", "견적서 작성", "견적 검토", False)]
        for _ in range(rejects):
            steps.append(("lee", "hong", "견적 검토", "견적서 수정", False))
            steps.append(("hong", "lee", "견적서 수정", "견적 검토", False))
        steps.append(("lee", "park", "견적 검토", "고객 발송", False))
        rows += _thread(f"rw{c}", f"2026-10-0{c + 1}", steps)
    return rows


def branch_log():
    """갈래: 접수 후 금액에 따라 팀장 검토 또는 본부장 승인, 그 뒤 발송"""
    rows = []
    for c in range(4):
        approver = ("lee", "팀장 검토") if c % 2 == 0 else ("boss", "본부장 승인")
        steps = [
            ("hong", approver[0], "견적 요청 접수", approver[1], False),
            (approver[0], "park", approver[1], "고객 발송", False),
        ]
        rows += _thread(f"br{c}", f"2026-10-1{c}", steps)
    return rows


def agent_middle_log():
    """에이전트 중간 단계: 접수 → 에이전트가 견적서 작성 → (넘긴 사람이 받아) 검토 → 발송"""
    rows = []
    for c in range(3):
        steps = [
            ("hong", "quote-agent", "견적 요청 접수", "견적서 작성", True),
            ("hong", "lee", "견적서 작성", "견적 검토", False),
            ("lee", "park", "견적 검토", "고객 발송", False),
        ]
        rows += _thread(f"ag{c}", f"2026-10-2{c}", steps)
    return rows


def two_person_log():
    """두 사람 사이 단순 인계: 작성 → 검토"""
    rows = []
    for c in range(3):
        rows += _thread(f"tp{c}", f"2026-09-1{c}", [("hong", "lee", "견적서 작성", "견적 검토", False)])
    return rows


def in_progress_threads():
    """끝나지 않은 건들. 어느 형태 로그에 섞여도 결과를 바꾸면 안 된다."""
    return (
        # 사람이 받고 아직 할 일을 끝내지 않음
        _thread("op1", "2026-10-30", [("hong", "lee", "견적서 작성", "견적 검토", False)], last_status="TODO")
        # 에이전트가 마쳤지만 넘긴 사람이 이어 주지도, 업무 종료하지도 않음(실환경 C 건)
        + _thread("op2", "2026-10-30", [("hong", "quote-agent", "견적 요청 접수", "견적서 작성", True)],
                  last_status="SUBMITTED")
        # 반려되어 수정 중
        + _thread("op3", "2026-10-31", [("hong", "lee", "견적서 작성", "견적 검토", False),
                                        ("lee", "hong", "견적 검토", "견적서 수정", False)], last_status="IN_PROGRESS")
    )


LOGS = {
    "반려 후 재검토": rework_log,
    "갈래": branch_log,
    "에이전트 중간 단계": agent_middle_log,
    "두 사람 인계": two_person_log,
}


# ---------------------------------------------------------------------------
# 완료 판정
# ---------------------------------------------------------------------------
def test_last_received_task_done_means_finished():
    assert eventlog.thread_finished(_thread("r", "2026-10-01", [("a", "b", "x", "y", False)], last_status="DONE"))


def test_last_received_task_open_means_in_progress():
    for status in ("TODO", "IN_PROGRESS", None):
        rows = _thread("r", "2026-10-01", [("a", "b", "x", "y", False)], last_status=status)
        assert not eventlog.thread_finished(rows), status


def test_agent_finishing_its_task_does_not_end_the_thread():
    """에이전트 할 일은 자동 완료된다. 넘긴 사람이 결과를 이어 줄 수 있어 그것만으로는 끝이 아니다."""
    rows = _thread("r", "2026-10-01", [("a", "bot", "x", "y", True)], last_status="SUBMITTED")
    assert not eventlog.thread_finished(rows)


def test_closing_the_agent_room_ends_the_thread():
    rows = _thread("r", "2026-10-01", [("a", "bot", "x", "y", True)], last_status="SUBMITTED", closed=True)
    assert eventlog.thread_finished(rows)


def test_only_the_last_handover_decides():
    """앞 단계 할 일이 열려 있어도 마지막으로 받은 할 일이 끝났으면 끝난 건이다(반대도 마찬가지)."""
    rows = _thread("r", "2026-10-01", [("a", "b", "x", "y", False), ("b", "c", "y", "z", False)])
    rows[0]["to_task_status"] = "TODO"
    assert eventlog.thread_finished(rows)
    rows[0]["to_task_status"], rows[1]["to_task_status"] = "DONE", "TODO"
    assert not eventlog.thread_finished(rows)


def test_in_progress_threads_are_reported_not_mined():
    r = miner.analyze(rework_log() + in_progress_threads())
    assert r["ok"]
    assert r["stats"]["in_progress_cases"] == 3
    assert r["stats"]["case_count"] == 3


# ---------------------------------------------------------------------------
# 도출 결과는 관측된 것만으로
# ---------------------------------------------------------------------------
def _shuffles(a, b):
    if not a:
        return [b]
    if not b:
        return [a]
    return [(a[0],) + t for t in _shuffles(a[1:], b)] + [(b[0],) + t for t in _shuffles(a, b[1:])]


def _language(node, loops=2):
    """트리가 허용하는 실행 순서(반복은 loops 번까지)."""
    k = node.kind
    if k == ACT:
        return {(node.label,)}
    if k == TAU:
        return {()}
    langs = [_language(c, loops) for c in node.children]
    if k == SEQ:
        out = {()}
        for lang in langs:
            out = {a + b for a in out for b in lang}
        return out
    if k == XOR:
        return set().union(*langs)
    if k == AND:
        out = {()}
        for lang in langs:
            out = {s for a in out for b in lang for s in _shuffles(a, b)}
        return out
    if k == LOOP:
        body, redo = langs[0], set().union(*langs[1:]) if len(langs) > 1 else {()}
        out, frontier = set(body), set(body)
        for _ in range(loops):
            frontier = {f + r + b for f in frontier for r in redo for b in body}
            out |= frontier
        return out
    raise AssertionError(k)


def _df(traces):
    pairs = set()
    for t in traces:
        pairs |= {("▶", t[0]), (t[-1], "■")} if t else set()
        pairs |= set(zip(t, t[1:]))
    return pairs


def _observed(rows):
    return list(eventlog.to_traces(eventlog.build_events(eventlog.finished_rows(rows)[0])).values())


@pytest.mark.parametrize("name", list(LOGS))
@pytest.mark.parametrize("with_open", [False, True], ids=["끝난 건만", "진행 중 섞임"])
def test_mined_model_contains_only_observed_steps_and_orders(name, with_open):
    rows = LOGS[name]() + (in_progress_threads() if with_open else [])
    r = miner.analyze(rows)
    assert r["ok"], r.get("reason")
    observed = _observed(rows)
    model = _language(r["tree_node"])

    # 단계: 기록에 나온 활동만
    assert {a for t in model for a in t} == {a for t in observed for a in t}, repr(r["tree_node"])
    # 흐름: 모델이 허용하는 '바로 다음' 은 모두 기록에서 관측된 것
    unobserved = _df(model) - _df(observed)
    assert not unobserved, f"관측되지 않은 순서 {unobserved} — {r['tree_node']!r}"
    # 모든 건이 거친 단계는 선택 단계가 아니다
    always = set.intersection(*(set(t) for t in observed))
    for t in model:
        assert always <= set(t), f"필수 단계 {always - set(t)} 를 건너뛰는 경로 {t} — {r['tree_node']!r}"
    # 관측된 모든 건을 모델이 재현한다
    assert all(tuple(t) in model for t in observed), repr(r["tree_node"])


@pytest.mark.parametrize("name", list(LOGS))
def test_in_progress_threads_do_not_change_the_result(name):
    base = miner.analyze(LOGS[name]())
    mixed = miner.analyze(LOGS[name]() + in_progress_threads())
    assert mixed["tree"] == base["tree"]
    assert mixed["stats"]["variants"] == base["stats"]["variants"]
