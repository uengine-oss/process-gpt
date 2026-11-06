"""패턴 찾기 — 서로 다른 업무가 섞인 로그를 업무별로 가른다."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.lite import patterns  # noqa: E402
from app.lite.eventlog import build_events, resource_profile  # noqa: E402


def _rows(case, acts, role="", agent=False, tool=None, t0=0, proc=None):
    out = []
    for i, a in enumerate(acts):
        out.append({"case_id": case, "origin_room_id": case, "source": "chat_handover", "norm_activity_label": a,
                    "to_user_id": f"u-{a}", "to_user_name": a, "to_role": role or f"{a} 담당", "to_is_agent": agent,
                    "artifact_refs": [{"tool": tool, "skill": f"{a}-skill"}] if tool else [],
                    "occurred_at": f"2026-10-0{1 + t0}T0{i}:00:00", "proc_def_id": proc})
    return out


DESIGN = ["요청 메일 접수", "평면도 작성", "제안서 작성", "견적서 작성", "재무 검토", "고객 회신"]
QUOTE = ["견적 산출", "견적서 검토 및 승인", "계약서 초안 작성", "고객 발송"]


def test_two_kinds_of_work_become_two_patterns():
    rows = []
    for i in range(4):
        rows += _rows(f"d{i}", DESIGN, tool="캐드크래프트", t0=i)
    for i in range(3):
        rows += _rows(f"q{i}", QUOTE, t0=i)
    found = patterns.find(rows)
    assert len(found) == 2
    big = found[0]
    assert big["case_count"] == 4 and big["main_variant"] == DESIGN
    assert big["steps"][1]["tools"] == ["캐드크래프트"]
    assert big["steps"][1]["role"] == "평면도 작성 담당"


def test_key_is_stable_when_more_cases_arrive():
    rows = [r for i in range(3) for r in _rows(f"d{i}", DESIGN, t0=i)]
    k1 = patterns.find(rows)[0]["key"]
    rows += _rows("d9", DESIGN, t0=5)
    assert patterns.find(rows)[0]["key"] == k1


def test_cases_from_a_defined_process_are_not_suggested_again():
    rows = [r for i in range(3) for r in _rows(f"d{i}", DESIGN, t0=i, proc="mined_x")]
    assert patterns.find(rows) == []


def test_too_few_cases_is_not_a_pattern():
    rows = [r for i in range(2) for r in _rows(f"d{i}", DESIGN, t0=i)]
    assert patterns.find(rows) == []


def test_role_and_tools_reach_the_profile():
    prof = resource_profile(build_events(_rows("d0", DESIGN, tool="한글")))
    assert dict(prof["제안서 작성"]["roles"]) == {"제안서 작성 담당": 1}
    assert dict(prof["제안서 작성"]["tools"]) == {"한글": 1}


# ---- 이미 결정(정식 등록·보류)된 흐름과 단계가 하나 다른 업무 ----
EVENT = ["요청 메일 접수", "견적서 작성", "계약 검토", "고객 회신"]


def _swap(acts, old, new):
    return [new if a == old else a for a in acts]


def _known(found_or_cases, key):
    return {"key": key, "case_ids": list(found_or_cases)}


def test_one_step_different_from_a_registered_flow_is_its_own_pattern():
    # 등록된 흐름의 사례(proc_def_id 없음: 등록 전 ad-hoc 으로 처리한 것)가 남아 있어도,
    # 검토 단계 하나만 다른 업무가 4건 쌓이면 따로 묶인다 — 두 구성 모두(6단계·4단계)
    for flow, old, new in ((DESIGN, "재무 검토", "계약 검토"), (EVENT, "계약 검토", "재무 검토")):
        reg = [f"r{i}" for i in range(5)]
        rows = [r for i, c in enumerate(reg) for r in _rows(c, flow, t0=i % 5)]
        variant = _swap(flow, old, new)
        rows += [r for i in range(4) for r in _rows(f"v{i}", variant, t0=i)]
        # 기준값(Jaccard 0.6)으로는 등록 흐름의 사례와 이어진다 — 결정된 흐름을 모르면 한 묶음
        assert patterns._jaccard(set(flow), set(variant)) >= patterns.SIMILARITY
        assert len(patterns.find(rows, min_cases=4)) == 1
        found = patterns.find(rows, min_cases=4, known=[_known(reg, "regkey")])
        by_key = {p["key"]: p for p in found}
        assert set(by_key["regkey"]["case_ids"]) == set(reg)
        new_one = [p for p in found if p["key"] != "regkey"]
        assert len(new_one) == 1, found
        assert sorted(new_one[0]["case_ids"]) == [f"v{i}" for i in range(4)]
        assert new_one[0]["main_variant"] == variant


def test_three_variant_cases_are_not_yet_a_pattern():
    reg = [f"r{i}" for i in range(5)]
    rows = [r for i, c in enumerate(reg) for r in _rows(c, EVENT, t0=i)]
    rows += [r for i in range(3) for r in _rows(f"v{i}", _swap(EVENT, "계약 검토", "재무 검토"), t0=i)]
    found = patterns.find(rows, min_cases=4, known=[_known(reg, "regkey")])
    assert [p["key"] for p in found] == ["regkey"]


def test_same_steps_as_a_registered_flow_never_become_a_new_pattern():
    # 등록된 흐름과 같은 단계로 처리한 새 사례는 몇 건이 쌓여도 그 흐름의 증거로만 붙는다
    for flow in (DESIGN, EVENT):
        reg = [f"r{i}" for i in range(4)]
        rows = [r for i, c in enumerate(reg) for r in _rows(c, flow, t0=i % 5)]
        rows += [r for i in range(12) for r in _rows(f"s{i}", flow, t0=i % 5)]
        found = patterns.find(rows, min_cases=4, known=[_known(reg, "regkey")])
        assert [p["key"] for p in found] == ["regkey"]
        assert len(found[0]["case_ids"]) == 16


def test_same_steps_and_variants_together_stay_apart():
    # 같은 단계 사례와 변형 사례가 함께 쌓여도 변형만 새 묶음이 된다(같은 단계 사례가 섞이지 않는다)
    reg = [f"r{i}" for i in range(4)]
    rows = [r for i, c in enumerate(reg) for r in _rows(c, EVENT, t0=i)]
    rows += [r for i in range(6) for r in _rows(f"s{i}", EVENT, t0=i % 5)]
    rows += [r for i in range(4) for r in _rows(f"v{i}", _swap(EVENT, "계약 검토", "재무 검토"), t0=i)]
    found = patterns.find(rows, min_cases=4, known=[_known(reg, "regkey")])
    new_one = [p for p in found if p["key"] != "regkey"]
    assert len(new_one) == 1 and sorted(new_one[0]["case_ids"]) == [f"v{i}" for i in range(4)]


def test_skipping_an_optional_step_still_follows_the_flow():
    # 등록 흐름에서 절반 미만의 사례만 거친 단계(선택 단계)는 건너뛰어도 같은 흐름이다
    reg_rows, reg = [], []
    for i in range(4):
        reg.append(f"r{i}")
        reg_rows += _rows(f"r{i}", DESIGN if i == 0 else [a for a in DESIGN if a != "평면도 작성"], t0=i)
    rows = reg_rows + [r for i in range(5) for r in _rows(f"s{i}", [a for a in DESIGN if a != "평면도 작성"], t0=i)]
    found = patterns.find(rows, min_cases=4, known=[_known(reg, "regkey")])
    assert [p["key"] for p in found] == ["regkey"]


def test_two_registered_flows_each_keep_their_cases():
    da = [f"a{i}" for i in range(4)]
    eb = [f"b{i}" for i in range(4)]
    rows = [r for i, c in enumerate(da) for r in _rows(c, DESIGN, t0=i)]
    rows += [r for i, c in enumerate(eb) for r in _rows(c, EVENT, t0=i)]
    rows += [r for i in range(4) for r in _rows(f"dv{i}", _swap(DESIGN, "재무 검토", "계약 검토"), t0=i)]
    rows += [r for i in range(4) for r in _rows(f"ev{i}", _swap(EVENT, "계약 검토", "재무 검토"), t0=i)]
    found = patterns.find(rows, min_cases=4, known=[_known(da, "A"), _known(eb, "B")])
    keys = {p["key"] for p in found}
    assert {"A", "B"} <= keys and len(found) == 4
    news = sorted(sorted(p["case_ids"]) for p in found if p["key"] not in ("A", "B"))
    assert news == [[f"dv{i}" for i in range(4)], [f"ev{i}" for i in range(4)]]
