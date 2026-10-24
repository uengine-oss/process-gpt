from datetime import datetime, timedelta, timezone

from router.route import Context
from router.select import gist_of, hint, select, tokens


def ago(**kw):
    return (datetime.now(timezone.utc) - timedelta(**kw)).isoformat()


def ctx(cid, title, summary="", hours=1.0, **kw):
    return Context(cid, title, summary, updated_at=ago(hours=hours), **kw)


def crowd(n):
    return [ctx(f"d{i}", f"{t} 관련 메모 {i}", "일반적인 정리", hours=0.5 + i * 0.1)
            for i, t in enumerate(["사내 공지", "디자인 리뷰", "채용 면접", "분기 보고서", "고객 미팅", "서버 점검"] * (n // 6 + 1))][:n]


def test_old_but_matching_context_survives_a_crowd_of_newer_ones():
    trip = ctx("trip", "부산 출장 준비", "숙소와 교통편 추천", hours=24 * 12)
    picked = select(crowd(60) + [trip], "출장비 정산은 어떻게 해?")
    assert trip in picked and len(picked) == 6


def test_deictic_message_keeps_the_most_recent_and_live_work():
    live = ctx("task", "팟캐스트 제작", hours=50, active=True)
    pool = crowd(30) + [live]
    picked = select(pool, "그거 취소해")
    newest = min(pool, key=lambda c: c.updated_at and -datetime.fromisoformat(c.updated_at).timestamp())
    assert live in picked and newest in picked


def test_small_pool_is_not_narrowed():
    pool = crowd(4)
    assert select(pool, "아무 말") == pool


def test_hint_shrinks_with_age():
    s = "최근 요청: 숙소 추천해줘\n최근 답: 해운대 호텔 세 곳을 찾았습니다 " + "가" * 200
    hot, warm, cold = (ctx("a", "t", s, hours=h, gist="부산 출장 숙소") for h in (2, 24 * 3, 24 * 20))
    assert len(hint(hot)) == 160 and "최근 답" not in hint(warm) and len(hint(cold)) <= 60 and hint(cold).startswith("부산 출장 숙소")


def test_gist_folds_the_replaced_request_into_keywords():
    g = gist_of("부산 출장", "최근 요청: 해운대 숙소 추천해줘\n최근 답: ...")
    assert g.startswith("해운대 숙소") and "부산" in g and "추천해줘" in g and len(gist_of(g * 20, "")) <= 120


def test_korean_tokens_ignore_particles():
    assert tokens("출장비는") & tokens("부산 출장")


def test_search_terms_cut_korean_endings():
    from router.select import search_terms
    assert search_terms("부가세 납부했어, 리마인드 꺼줘")[:2] == ["부가세", "납부했"]
