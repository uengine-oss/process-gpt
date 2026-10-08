from __future__ import annotations

import time
from dataclasses import dataclass, field
from pathlib import Path

import pytest

import db
from services import HEARTBEAT_SECONDS, LEASE_SECONDS, SERVICES, Service, Worker, conf

HERE = Path(__file__).resolve().parent
LOG_DIR = HERE / ".logs"
#: 템플릿 작업. 컨텍스트 조립이 실제로 성공하는 행이어야 한다(프로세스 인스턴스·폼·에이전트가 있는 행).
TEMPLATE_TODO = conf("LEASE_SVC_TEMPLATE_TODO", "1ec57f21-0fea-452f-a310-3ff3419d3531")
#: 한 작업이 끝나기를 기다리는 상한.
RUN_TIMEOUT = float(conf("LEASE_SVC_RUN_TIMEOUT", "300"))
SAMPLE_INTERVAL = 0.25
BASE_PORT = {"deepagents": 18881, "cliagents": 18891, "codex": 18901}


def pytest_addoption(parser):
    parser.addoption(
        "--service", action="append", choices=sorted(SERVICES), default=None,
        help="검증할 서비스(여러 번 줄 수 있다). 생략하면 전부.",
    )


def pytest_generate_tests(metafunc):
    if "service_name" in metafunc.fixturenames:
        names = metafunc.config.getoption("service") or sorted(SERVICES)
        metafunc.parametrize("service_name", names, scope="module")


@dataclass
class Run:
    """작업 하나를 처음부터 끝까지 관찰한 기록."""

    todo_id: str
    samples: list[db.Snapshot] = field(default_factory=list)
    killed_at: float | None = None          # DB 시계
    lease_at_kill: float | None = None      # 죽인 워커가 쥐고 있던 lease_until

    @property
    def started(self) -> list[db.Snapshot]:
        return [s for s in self.samples if s.draft_status == "STARTED"]

    @property
    def last(self) -> db.Snapshot:
        return self.samples[-1]

    def by(self, consumer: str) -> list[db.Snapshot]:
        return [s for s in self.started if s.consumer == consumer]


class Harness:
    def __init__(self, service: Service):
        self.service = service
        self.created: list[str] = []
        self.workers: dict[str, Worker] = {}
        self.legacy_id: str | None = None
        self.legacy_before: db.Snapshot | None = None
        LOG_DIR.mkdir(exist_ok=True)

    def worker(self, label: str, env_transform=None) -> Worker:
        """label('A','B',...)의 워커를 살아 있는 상태로 돌려준다."""
        w = self.workers.get(label)
        if w is None or not w.alive:
            port = BASE_PORT[self.service.name] + (ord(label) - ord("A"))
            w = Worker(self.service, f"lease-svc-{self.service.name}-{label}", port, LOG_DIR,
                       env_transform=env_transform).start()
            self.workers[label] = w
        return w

    def stop_workers(self) -> None:
        for w in self.workers.values():
            w.stop()

    def new_task(self) -> str:
        todo_id = db.clone_task(TEMPLATE_TODO, self.service.agent_orch)
        self.created.append(todo_id)
        return todo_id

    def observe(self, run: Run, until, timeout: float = RUN_TIMEOUT) -> db.Snapshot:
        deadline = time.monotonic() + timeout
        while True:
            s = db.snapshot(run.todo_id)
            run.samples.append(s)
            if until(s):
                return s
            if time.monotonic() > deadline:
                raise TimeoutError(f"{timeout}초 안에 조건에 닿지 않았다. 마지막 상태: {s}")
            time.sleep(SAMPLE_INTERVAL)

    def close(self) -> None:
        for w in self.workers.values():
            w.stop()
        db.remove(self.created)


def ended(run: Run):
    """작업이 끝났다고 볼 조건.

    종결 상태(COMPLETED/FAILED/CANCELLED)이거나, **점유가 풀렸는데 STARTED 로 남은**
    상태가 lease 두 배 이상 이어질 때다. 후자는 실행기가 종결 상태를 남기지 않고
    반환해 SDK 가 점유만 해제한 경우로, 아무도 다시 집지 않는 고아다. 끝까지
    기다리지 않고 거기서 멈춰 판정(SVC-LEASE-03)에 넘긴다.
    """
    def until(s: db.Snapshot) -> bool:
        if s.terminal:
            return True
        was_leased = any(x.lease_until is not None for x in run.started)
        if s.draft_status == "STARTED" and s.lease_until is None and was_leased:
            released = [x for x in run.samples if x.draft_status == "STARTED" and x.lease_until is None]
            return s.at - released[0].at >= LEASE_SECONDS * 2
        return False
    return until


@pytest.fixture(scope="module")
def harness(service_name):
    service = SERVICES[service_name]()
    missing = service.missing()
    if missing:
        pytest.skip(f"{service_name}: " + "; ".join(missing))
    if not db.template_exists(TEMPLATE_TODO):
        pytest.skip(f"템플릿 작업 {TEMPLATE_TODO} 가 DB 에 없다(LEASE_SVC_TEMPLATE_TODO)")
    pending = db.claimable_count(service.agent_orch)
    if pending:
        pytest.fail(
            f"개발 DB 에 agent_orch={service.agent_orch} 로 집힐 행이 {pending}건 있다. "
            "테스트 워커가 그 행을 실행하게 되므로 시작하지 않는다."
        )

    h = Harness(service)
    try:
        # lease 를 모르는 구버전 워커가 집은 행. 끝까지 아무도 건드리지 않아야 한다.
        h.legacy_id = db.clone_task(TEMPLATE_TODO, service.agent_orch,
                                    legacy_claim_by="lease-svc-legacy-worker")
        h.created.append(h.legacy_id)
        h.legacy_before = db.snapshot(h.legacy_id)
        yield h
    finally:
        h.close()


@pytest.fixture(scope="module")
def normal_run(harness: Harness) -> Run:
    """살아 있는 워커 A 가 작업 하나를 처음부터 끝까지 수행한다."""
    a = harness.worker("A")
    run = Run(harness.new_task())
    harness.observe(run, ended(run))
    assert a.alive, f"A 가 수행 중에 죽었다. 로그: {a.log_path}"
    return run


@pytest.fixture(scope="module")
def reclaim_run(harness: Harness, normal_run: Run) -> Run:
    """A 가 작업을 쥔 채 죽고(kill -9), B 가 뜬다."""
    a = harness.worker("A")
    run = Run(harness.new_task())
    claimed = harness.observe(run, lambda s: s.draft_status != "" or s.consumer != "", timeout=60)
    if claimed.draft_status != "STARTED":
        pytest.fail(f"점유를 보기 전에 작업이 끝났다(죽일 틈이 없었다): {claimed}")
    a.kill()
    at_kill = db.snapshot(run.todo_id)
    run.samples.append(at_kill)
    run.killed_at, run.lease_at_kill = at_kill.at, at_kill.lease_until
    harness.worker("B")
    harness.observe(run, ended(run))
    return run


@pytest.fixture(scope="module")
def unfinished_run(harness: Harness, reclaim_run: Run) -> Run:
    """실행기가 실패만 보고하고 반환하는 워커 C 가 작업 하나를 수행한다.

    A·B 는 내린다. 살아 있으면 그쪽이 같은 작업을 집어 정상 경로로 끝낸다.
    """
    transform = harness.service.unfinished_env
    if transform is None:
        pytest.skip(f"{harness.service.name}: 실행기가 실패만 보고하고 반환하는 경로를 결정적으로 유도할 방법이 없다")
    harness.stop_workers()
    harness.worker("C", env_transform=transform)
    run = Run(harness.new_task())
    harness.observe(run, ended(run))
    return run


__all__ = ["Run", "Harness", "LEASE_SECONDS", "HEARTBEAT_SECONDS"]
