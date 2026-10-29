"""마이닝 PR 의 제목·설명은 요청한 쪽의 언어로 ([마이닝] / [Mining])."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.proposal import _summary_lines, pr_title  # noqa: E402

DEFN = {"activities": [{"name": "Draw floor plan", "agent": "a-1"}, {"name": "Reply to customer"}], "gateways": [], "roles": [{}]}
STATS = {"event_count": 29, "case_count": 5, "variants": [{"trace": ["Draw floor plan", "Reply to customer"], "count": 4}]}


def test_title_in_the_requesters_language():
    assert pr_title("Design proposal & quote", "en") == "[Mining] Design proposal & quote"
    assert pr_title("설계 제안·견적 대응") == "[마이닝] 설계 제안·견적 대응"


def test_summary_in_english():
    lines = _summary_lines(DEFN, STATS, "en")
    assert lines[0] == "Found in 29 handover records / 5 cases."
    assert not any(any("\uac00" <= ch <= "\ud7a3" for ch in line) for line in lines), lines
    assert "  - Draw floor plan → Reply to customer  (4 cases)" in lines


def test_summary_in_korean_unchanged():
    assert _summary_lines(DEFN, STATS)[0] == "핸드오버 로그 29건 / 케이스 5건에서 도출했습니다."
