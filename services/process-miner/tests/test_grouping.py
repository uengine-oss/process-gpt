"""서로 다른 업무를 한 프로세스의 갈래로 그리지 않는다(2026-10-20).

견적·계약·구매 인계가 한 테넌트에 쌓이자 첫 단계부터 "이 업무들 중 하나" 라는 배타 분기가
나왔다. 끝난 스레드를 거친 단계 집합으로 묶고, 묶음마다 따로 도출한다.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app import grouping, miner  # noqa: E402
from app.discovery.process_tree import XOR  # noqa: E402

from test_thread_finished import LOGS, _thread, in_progress_threads  # noqa: E402

TENANT = "acme"


def test_each_business_becomes_its_own_group():
    """계약 · 구매 · 견적처럼 단계를 공유하지 않는 업무는 각각 한 묶음이다."""
    rows = []
    for c in range(3):
        rows += _thread(f"ct{c}", f"2026-09-0{c + 1}", [("hong", "lee", "계약서 작성", "계약서 검토", False)])
        rows += _thread(f"pu{c}", f"2026-09-1{c}", [("hong", "lee", "구매 요청 접수", "팀장 승인", False),
                                                     ("lee", "hong", "팀장 승인", "발주 처리", False)])
    rows += LOGS["반려 후 재검토"]() + in_progress_threads()
    out = miner.processes(rows, TENANT)
    assert sorted(tuple(p["activities"]) for p in out["processes"]) == sorted([
        ("계약서 검토", "계약서 작성"),
        ("구매 요청 접수", "발주 처리", "팀장 승인"),
        ("견적 검토", "견적서 수정", "견적서 작성", "고객 발송"),
    ])
    assert all(p["minable"] for p in out["processes"])
    assert out["in_progress_cases"] == 3


def test_steps_shared_by_the_quote_variants_keep_them_in_one_business():
    """단위 로그의 네 형태 중 견적 작성·검토를 공유하는 셋은 한 업무, 승인자가 갈리는 견적 접수는 따로다."""
    rows = []
    for make in LOGS.values():
        rows += make()
    sizes = sorted(p["case_count"] for p in miner.processes(rows, TENANT)["processes"])
    assert sizes == [4, 9]


def test_variants_of_one_business_stay_together():
    """반려 0·1·2회(겹침 0.75)와 승인자가 갈리는 건(0.5)은 한 업무다."""
    for name in ("반려 후 재검토", "갈래"):
        out = miner.processes(LOGS[name](), TENANT)
        assert len(out["processes"]) == 1, (name, [p["activities"] for p in out["processes"]])


def test_unrelated_businesses_are_split():
    rows = LOGS["갈래"]() + LOGS["반려 후 재검토"]()
    out = miner.processes(rows, TENANT)
    assert len(out["processes"]) == 2


def test_each_group_is_mined_as_if_alone():
    """묶음 하나를 도출한 결과는 그 업무만 있을 때와 같다 — 다른 업무가 갈래로 끼지 않는다."""
    mixed = LOGS["갈래"]() + LOGS["반려 후 재검토"]() + in_progress_threads()
    out = miner.processes(mixed, TENANT)
    for name in ("갈래", "반려 후 재검토"):
        alone = miner.analyze(LOGS[name](), tenant_id=TENANT)
        key = next(
            p["process_key"]
            for p in out["processes"]
            if set(p["activities"]) == {a for v in alone["stats"]["variants"] for a in v["trace"]}
        )
        r = miner.analyze(mixed, process_key=key, tenant_id=TENANT)
        assert r["ok"] and r["tree"] == alone["tree"], (name, r["tree"], alone["tree"])
        assert r["stats"]["process_key"] == key


def test_default_is_the_largest_group_not_a_choice_between_businesses():
    mixed = LOGS["갈래"]() + LOGS["반려 후 재검토"]()
    r = miner.analyze(mixed, tenant_id=TENANT)
    assert r["ok"]
    assert r["stats"]["process_count"] == 2
    # 첫 단계가 업무 간 배타 분기가 아니다
    tree = r["tree_node"]
    assert not (tree.kind == XOR and len(tree.children) == 2), r["tree"]
    assert r["tree"] == miner.analyze(LOGS["갈래"](), tenant_id=TENANT)["tree"]  # 갈래 4건이 가장 큰 묶음


def test_unknown_group_is_reported():
    r = miner.analyze(LOGS["갈래"](), process_key="mined_nope", tenant_id=TENANT)
    assert not r["ok"] and "찾을 수 없습니다" in r["reason"]


def test_group_key_matches_the_proposed_definition_id():
    """묶음 id 와 제안 정의 id 가 같아, 같은 업무를 다시 제안하면 한 정의의 버전으로 쌓인다."""
    r = miner.analyze(LOGS["갈래"](), tenant_id=TENANT)
    pid, _ = miner.suggest_identity(r, TENANT)
    assert pid == r["stats"]["process_key"]


def test_grouping_is_deterministic():
    traces = {"c1": ["a", "b"], "c2": ["a", "b", "c"], "c3": ["x", "y"], "c4": ["x", "y", "z"]}
    assert grouping.group_cases(traces) == grouping.group_cases(dict(reversed(list(traces.items()))))
    assert grouping.group_cases(traces) == [["c1", "c2"], ["c3", "c4"]]


def test_threads_carry_their_business_and_open_ones_the_closest(monkeypatch):
    """/threads — 끝난 스레드는 속한 묶음, 진행 중 스레드는 가장 가까운 묶음(표시용)을 싣는다."""
    from fastapi.testclient import TestClient

    from app import db, server

    rows = LOGS["갈래"]() + LOGS["반려 후 재검토"]() + in_progress_threads()
    monkeypatch.setenv("MINER_AUTH", "off")
    monkeypatch.setattr(db, "fetch_handover_events", lambda tenant, limit=5000: rows)
    body = TestClient(server.app).get("/threads", params={"tenant_id": TENANT}).json()
    by_room = {t["origin_room_id"]: t for t in body["threads"]}
    groups = {tuple(p["activities"]): p["process_key"] for p in miner.processes(rows, TENANT)["processes"]}
    rework = next(k for a, k in groups.items() if "견적서 수정" in a)
    assert by_room["rw0"]["process_key"] == rework and by_room["rw0"]["finished"]
    # 진행 중인 '견적서 작성 → 견적 검토 → 견적서 수정' 건은 반려 업무에 붙는다
    assert by_room["op3"]["finished"] is False and by_room["op3"]["process_key"] == rework
    procs = TestClient(server.app).get("/processes", params={"tenant_id": TENANT}).json()
    assert len(procs["processes"]) == 2 and "cases" not in procs["processes"][0]
