"""패턴 찾기 — 서로 다른 업무가 섞인 로그를 업무별로 가른다."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app import patterns  # noqa: E402
from app.eventlog import build_events, resource_profile  # noqa: E402


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
