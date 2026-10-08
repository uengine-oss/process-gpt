"""실제 서비스 워커가 작업 점유 lease 계약을 지키는가.

각 테스트의 ID(SVC-LEASE-NN)는 스펙 시나리오와 1:1 로 대응한다. docstring 의
GIVEN/WHEN/THEN 은 그 시나리오의 문장 그대로다 — 스펙으로 옮길 때 이것을 쓴다.

판정은 전부 DB 상태(todolist, events)로 한다. 워커 로그는 실패했을 때 원인을
보는 데만 쓴다.
"""

from __future__ import annotations

import time

import pytest

import db
from conftest import HEARTBEAT_SECONDS, LEASE_SECONDS, Run
from services import POLL_IDLE_SECONDS

#: 샘플링 간격과 DB 왕복 때문에 생기는 오차.
SLACK = 1.5


def test_SVC_LEASE_01_점유할_때_만료_시한을_건다(normal_run: Run, harness):
    """
    GIVEN lease 를 아는 워커가 폴링 중이다
    WHEN  대기 작업을 점유한다
    THEN  작업은 그 워커의 점유(STARTED, consumer=워커)가 되고
    AND   점유에는 지금부터 lease 길이만큼의 만료 시한이 걸린다
    AND   점유 횟수는 1 이다
    """
    first = normal_run.started[0] if normal_run.started else None
    assert first is not None, f"STARTED 를 한 번도 관찰하지 못했다: {normal_run.samples[:3]}"
    assert first.consumer == harness.workers["A"].consumer
    assert first.claim_count == 1
    assert first.lease_until is not None, "점유에 만료 시한이 없다 — 이 워커가 죽으면 아무도 회수하지 못한다"
    assert 0 < first.lease_left <= LEASE_SECONDS + SLACK


def test_SVC_LEASE_02_살아_있는_워커는_점유를_연장하고_빼앗기지_않는다(normal_run: Run, reclaim_run: Run, harness):
    """
    GIVEN 워커가 작업을 수행 중이다
    WHEN  수행이 heartbeat 주기보다 길어진다
    THEN  만료 시한이 주기적으로 뒤로 밀린다
    AND   수행이 끝날 때까지 만료 시한이 지나지 않는다
    AND   점유자와 점유 횟수는 바뀌지 않는다(다른 워커가 회수하지 않는다)

    살아서 끝까지 수행한 구간은 두 개다 — 정상 수행의 A, 회수 뒤의 B. 수행 시간은
    LLM 에 달려 있어 한 구간이 짧을 수 있으므로 둘 다 본다. 불변식(점유자·횟수·
    만료)은 두 구간 모두에서 성립해야 하고, 연장은 판정 가능한 길이의 구간에서 본다.
    """
    a, b = harness.workers["A"].consumer, harness.workers["B"].consumer
    segments = {
        "A(정상 수행)": (normal_run.started, 1),
        "B(회수 뒤)": (reclaim_run.by(b), 2),
    }
    judged = []
    for label, (samples, claims) in segments.items():
        owner = a if label.startswith("A") else b
        leased = [s for s in samples if s.lease_until is not None]
        assert all(s.consumer == owner for s in samples), f"{label}: 수행 중 점유자가 바뀌었다"
        assert all(s.claim_count == claims for s in samples), f"{label}: 살아 있는 워커의 작업이 회수됐다"
        assert all(s.lease_left > -SLACK for s in leased), f"{label}: 수행 중에 만료 시한이 지났다 — 연장이 멈췄다"

        span = leased[-1].at - leased[0].at if leased else 0.0
        if span < HEARTBEAT_SECONDS * 2 + SLACK:
            continue
        judged.append(label)
        deadlines = {round(s.lease_until, 1) for s in leased}
        assert len(deadlines) >= 2, f"{label}: {span:.1f}초 수행 중 만료 시한이 한 번도 연장되지 않았다"
        assert leased[-1].lease_until > leased[0].lease_until, f"{label}: 만료 시한이 뒤로 밀리지 않았다"

    if not judged:
        pytest.skip(f"두 구간 모두 heartbeat({HEARTBEAT_SECONDS}초)의 두 배보다 짧아 연장을 판정할 수 없다")


def test_SVC_LEASE_03_수행이_끝나면_종결_상태가_되고_점유가_풀린다(normal_run: Run):
    """
    GIVEN 워커가 작업을 점유해 수행했다
    WHEN  수행이 성공하거나 실패로 끝난다
    THEN  작업은 종결 상태(COMPLETED 또는 FAILED)가 된다
    AND   만료 시한과 점유자가 비워진다
    AND   점유가 풀린 채 STARTED 로 남은 작업(아무도 다시 집지 않는 고아)은 없다
    """
    last = normal_run.last
    assert last.terminal, (
        f"수행이 끝났는데 종결 상태가 아니다: {last}. 점유가 풀린 STARTED 는 다시 집히지 않는다"
    )
    assert last.lease_until is None
    assert last.consumer == ""


def test_SVC_LEASE_04_점유한_워커가_죽으면_만료_뒤_다른_워커가_회수한다(reclaim_run: Run, harness):
    """
    GIVEN 워커 A 가 작업을 점유한 채 강제 종료됐다(kill -9)
    AND   다른 워커 B 가 폴링 중이다
    WHEN  A 의 만료 시한이 지난다
    THEN  B 가 그 작업을 점유한다(점유 횟수 2)
    AND   만료 시한이 지나기 전에는 회수되지 않는다
    AND   회수는 만료 시한 + 폴링 주기 + 워커 기동 시간 안에 일어난다
    AND   B 가 작업을 종결 상태까지 수행하고 점유를 푼다
    """
    b = harness.workers["B"].consumer
    taken = reclaim_run.by(b)
    assert taken, f"B 가 회수하지 않았다. 마지막 상태: {reclaim_run.last}"
    first = taken[0]
    assert first.claim_count == 2
    assert reclaim_run.lease_at_kill is not None
    assert first.at >= reclaim_run.lease_at_kill - SLACK, "만료 전에 회수됐다 — 살아 있는 점유도 빼앗길 수 있다"
    bound = LEASE_SECONDS + POLL_IDLE_SECONDS + 60 + SLACK  # 60: B 기동 여유
    assert first.at - reclaim_run.killed_at <= bound, f"회수가 {first.at - reclaim_run.killed_at:.1f}초 걸렸다"

    last = reclaim_run.last
    assert last.terminal, f"회수 뒤 종결 상태가 아니다: {last}"
    assert last.lease_until is None


def test_SVC_LEASE_05_회수가_완료를_중복시키지_않는다(reclaim_run: Run, normal_run: Run):
    """
    GIVEN 작업이 한 번 회수되어 두 워커를 거쳤다
    WHEN  작업이 완료된다
    THEN  완료 이벤트(task_completed) 수는 회수 없이 수행한 같은 서비스의 작업과 같다
          (죽은 워커와 회수한 워커가 각각 완료를 남기지 않는다)

    기준을 "1건" 이 아니라 같은 서비스의 정상 수행으로 잡는 이유: 서비스마다 한
    번의 수행에 남기는 완료 이벤트 수가 다르다(deepagents 는 2건). 여기서 보는
    것은 회수가 완료를 **더** 만들었는가이다.
    """
    baseline = db.event_count(normal_run.todo_id, "task_completed")
    reclaimed = db.event_count(reclaim_run.todo_id, "task_completed")
    if not (normal_run.last.draft_status == reclaim_run.last.draft_status == "COMPLETED"):
        pytest.skip(f"두 작업이 모두 COMPLETED 가 아니어서 비교할 수 없다"
                    f"({normal_run.last.draft_status} / {reclaim_run.last.draft_status})")
    assert reclaimed <= baseline, f"회수된 작업의 완료 이벤트 {reclaimed}건 > 정상 수행 {baseline}건"


def test_SVC_LEASE_06_만료_시한이_없는_기존_점유는_회수하지_않는다(reclaim_run: Run, harness):  # noqa: ARG001 — 회수까지 끝난 뒤에 본다
    """
    GIVEN lease 를 모르는 워커(또는 마이그레이션 이전)가 점유한 작업이 있다(만료 시한 없음)
    WHEN  lease 를 아는 워커들이 폴링하고 작업을 회수하는 동안
    THEN  그 작업은 점유자·상태·점유 횟수가 그대로다
    """
    before, after = harness.legacy_before, db.snapshot(harness.legacy_id)
    assert (after.draft_status, after.consumer, after.lease_until, after.claim_count) == (
        before.draft_status, before.consumer, before.lease_until, before.claim_count
    )


def test_SVC_LEASE_07_실행기가_실패만_보고하고_반환해도_종결된다(unfinished_run: Run):
    """
    GIVEN 워커가 작업을 점유해 수행했다
    WHEN  실행기가 예외 없이, 실패 상태만 보고하고(결과 없이) 반환한다
    THEN  작업은 FAILED 로 종결된다 — 점유만 풀린 STARTED 로 남지 않는다
    AND   만료 시한과 점유자가 비워진다
    AND   그 작업에 완료 이벤트(crew_completed)가 기록되지 않는다
    AND   실패를 알리는 오류 이벤트(error)가 남는다
    """
    last = unfinished_run.last
    assert last.draft_status == "FAILED", (
        f"실패를 보고하고 끝난 실행이 종결되지 않았다: {last}. 아무도 다시 집지 않는 고아다"
    )
    assert last.lease_until is None
    assert last.consumer == ""
    # 이벤트는 비동기로 묶어 저장된다(묶음이 거절되면 재시도 뒤 한 건씩). 행이 종결된
    # 시점에 아직 쓰는 중일 수 있으므로 기다린다.
    deadline = time.monotonic() + 30
    while db.event_count(unfinished_run.todo_id, "error") == 0 and time.monotonic() < deadline:
        time.sleep(1)
    assert db.event_count(unfinished_run.todo_id, "error") >= 1, "실패 이유를 알리는 오류 이벤트가 없다"
    assert db.event_count(unfinished_run.todo_id, "crew_completed") == 0, "실패한 실행이 완료로 표시됐다"
