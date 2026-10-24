"""Routing when a user has many contexts: the 22 routing cases with N unrelated, mostly newer
contexts mixed in, under three ways of building the candidate list.

  recent8   the newest 8 (the router before candidate narrowing)
  all25     the newest 25, full summaries (all a letter-keyed decision can hold)
  lex6      the router's own path (``route``) with word-overlap narrowing only
  route6    the router's own path with narrowing by words + meaning (bge-m3) and the
            judge cross-check (current router)

The five real contexts are deliberately not the newest: the trip is 10 hours old, the YouTube
check 3 days, the SNS instance 12 days, the VAT reminder 20 days; the podcast is live client work.

Usage: python eval/scale.py [N ...]   (default 0 25 100 300) → eval/scale.json
"""
import asyncio
import json
import os
import random
import statistics
import sys
import time
from datetime import datetime, timedelta, timezone

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from dotenv import load_dotenv  # noqa: E402

load_dotenv()
from decide import from_env  # noqa: E402
import importlib  # noqa: E402
route_mod = importlib.import_module("router.route")  # the package re-exports route(), shadowing the module
from router import embed  # noqa: E402
from router.route import NEW, Context, _options, route  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
data = json.load(open(os.path.join(HERE, "cases.json"), encoding="utf-8"))
STATE = "사용자가 한 채팅창에서 여러 일을 동시에 진행한다. 아래는 사용자의 진행 중이거나 최근 대화들이다.\n사용자의 새 메시지: \"{m}\""
QUESTION = "이 새 메시지는 어느 대화의 후속인가? 같은 일·같은 대상을 이어 말하면 그 대화, 무관한 새 요청이면 새 주제를 고른다."
NOW = datetime.now(timezone.utc)
AGE_H = {"trip": 10, "yt": 72, "podcast": 1, "sns": 24 * 12, "vat": 24 * 20}
GIST = {"yt": "경제사냥꾼 영상 일정 자막", "trip": "부산 출장 KTX 숙소", "podcast": "NotebookLM 팟캐스트 논문",
        "sns": "크루온 RMF 벤치마킹 구현 영상", "vat": "부가세 납부 리마인드"}

# Everyday work a long-time user piles up; some share words with the real contexts on purpose
# (another YouTube channel, a Seoul trip, a different tax, another podcast) so overlap alone
# cannot settle it. None is about a "new topic" probe (laptops, Excel, exchange rates): a
# distractor on the same subject would make continuing it a right answer, not a mistake.
TOPICS = [
    ("사내 공지 초안 작성", "전사 공지 문안 다듬기"), ("디자인 시안 리뷰", "랜딩 페이지 시안 피드백"),
    ("채용 면접 일정 조율", "백엔드 지원자 면접 시간"), ("3분기 보고서 정리", "매출 표와 요약"),
    ("고객사 미팅 준비", "A사 데모 아젠다"), ("서버 점검 알림", "주말 DB 점검 공지"),
    ("영어 이메일 번역", "해외 파트너 회신"), ("프린터 토너 주문", "3층 프린터 토너"),
    ("팀 회식 장소", "강남역 근처 예약"), ("주차 등록 변경", "새 차량 번호 등록"),
    ("요가 클래스 등록", "주 2회 저녁반"), ("아이 학원 상담", "수학 학원 시간표"),
    ("슈카월드 유튜브 영상 요약", "금리 관련 영상 요약을 받음"), ("서울 본사 출장", "11/5 서울 본사 회의 일정"),
    ("종합소득세 문의", "5월 신고 준비물"), ("사내 팟캐스트 기획", "다음 달 녹음 주제"),
    ("보안 점검 체크리스트", "ISMS 항목 정리"), ("마케팅 문구 작성", "신제품 카피 다섯 개"),
    ("주간 회의록", "월요일 회의 결정 사항"), ("차량 정비 예약", "엔진오일 교체"),
]


def distractors(n, seed=7):
    rnd = random.Random(seed)
    out = []
    for i in range(n):
        t, s = TOPICS[i % len(TOPICS)]
        h = rnd.uniform(0.2, 24 * 25)  # spread over the last 25 days, many newer than the real ones
        out.append(Context(f"d{i}", f"{t} #{i // len(TOPICS) + 1}", f"최근 요청: {s}\n최근 답: 정리해 드렸습니다",
                           "conversation", False, t.split()[0], (NOW - timedelta(hours=h)).isoformat()))
    return out


def real():
    out = []
    for c in data["contexts"]:
        cid = c["conversation_id"]
        out.append(Context(cid, c["title"], f"최근 요청: {c.get('summary', '')}", c.get("kind", "conversation"),
                           bool(c.get("active")), GIST[cid], (NOW - timedelta(hours=AGE_H[cid])).isoformat()))
    return out


def by_age(pool):
    return sorted(pool, key=lambda c: c.updated_at, reverse=True)


def build(mode, pool):
    live = [c for c in pool if c.active]
    rest = [c for c in by_age(pool) if not c.active]
    # the old router: full summaries of the newest few
    k = 8 if mode == "recent8" else 25
    return [Context(c.conversation_id, c.title, c.summary, c.kind, c.active, "", None) for c in (live + rest)[:k]]


async def via_router(decider, pool, message, use_embed):
    """The real routing path: stored contexts come back from the store, live work from the client."""
    stored = [c for c in pool if not c.active]
    client = [{"conversation_id": c.conversation_id, "title": c.title, "summary": c.summary, "kind": c.kind,
               "active": True, "gist": c.gist, "updated_at": c.updated_at} for c in pool if c.active]

    async def recent(tenant, user, limit=200):
        return [{"conversation_id": c.conversation_id, "title": c.title, "summary": c.summary, "gist": c.gist,
                 "kind": c.kind, "updated_at": c.updated_at} for c in by_age(stored)[:limit]]
    async def search(tenant, user, terms, limit=30):
        hit = [c for c in by_age(stored) if any(t in c.title or t in c.gist for t in terms)]
        return [{"conversation_id": c.conversation_id, "title": c.title, "summary": c.summary, "gist": c.gist,
                 "kind": c.kind, "updated_at": c.updated_at} for c in hit[:limit]]
    route_mod.store.recent = recent
    route_mod.store.search = search
    url = embed.URL
    embed.URL = url if use_embed else ""
    try:
        cands = await route_mod.candidates("t", "u", client, message)
        r = await route(decider, message=message, tenant_id="t", user_id="u", current=None, client_contexts=client)
    finally:
        embed.URL = url
    choice = NEW if r.action == "new" else r.conversation_id if r.action == "continue" else "stay"
    return cands, choice, r.decision


async def run(decider, n, mode):
    pool = real() + distractors(n)
    rows = []
    for case in data["cases"]:
        if case["expect"] == "ambiguous":
            continue
        t = time.perf_counter()
        notes = []
        try:
            if mode in ("recent8", "all25"):
                cands = build(mode, pool)
                d = await decider.decide(STATE.format(m=case["message"]), QUESTION, _options(cands))
                choice, strategy, conf = d.choice, d.strategy, d.confidence
            else:
                cands, choice, d = await via_router(decider, pool, case["message"], mode == "route6")
                strategy, conf, notes = d.get("strategy"), d.get("confidence", 0), d.get("notes", [])
        except RuntimeError:
            cands, choice, strategy, conf = [], None, "error", 0
        ms = (time.perf_counter() - t) * 1000
        opts = _options(cands)
        in_list = case["expect"] == NEW or any(c.conversation_id == case["expect"] for c in cands)
        rows.append({"message": case["message"], "expect": case["expect"], "choice": choice, "ok": choice == case["expect"],
                     "candidate_present": in_list, "options": len(opts), "prompt_chars": sum(len(o.label) + len(o.hint) for o in opts),
                     "strategy": strategy, "confidence": conf, "ms": round(ms),
                     "rechecked": any("re-decided" in n for n in notes)})
    return {"n": n, "mode": mode, "accuracy": sum(r["ok"] for r in rows) / len(rows),
            "recall": sum(r["candidate_present"] for r in rows) / len(rows),
            "median_ms": statistics.median(r["ms"] for r in rows), "p90_ms": sorted(r["ms"] for r in rows)[int(len(rows) * 0.9) - 1],
            "options": statistics.mean(r["options"] for r in rows), "prompt_chars": statistics.mean(r["prompt_chars"] for r in rows),
            "decided_by": {s: sum(r["strategy"] == s for r in rows) for s in {r["strategy"] for r in rows}},
            "rechecked": sum(r["rechecked"] for r in rows), "rows": rows}


async def main():
    ns = [int(x) for x in sys.argv[1:]] or [0, 25, 100, 300]
    decider = from_env()
    out = []
    for n in ns:
        for mode in ("recent8", "all25", "lex6", "route6"):
            r = await run(decider, n, mode)
            out.append(r)
            print(f"N={n:>3} {mode:8} acc {r['accuracy']:.0%}  recall {r['recall']:.0%}  options {r['options']:.1f}  "
                  f"chars {r['prompt_chars']:.0f}  median {r['median_ms']:.0f}ms  p90 {r['p90_ms']}ms  {r['decided_by']} rechecked {r['rechecked']}", flush=True)
    json.dump(out, open(os.path.join(HERE, "scale.json"), "w"), ensure_ascii=False, indent=1)


if __name__ == "__main__":
    asyncio.run(main())
