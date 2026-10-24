"""Which of a user's many contexts are worth showing the decision model.

A user who works through one chat window for months accumulates hundreds of contexts. The
decision model cannot take them all (option letters run out at 26, and every option makes the
call slower and the choice harder), and most are irrelevant to the new message anyway. So the
router narrows first, without a model:

* contexts idle longer than ``ROUTER_DORMANT_DAYS`` are not candidates at all (the store query
  leaves them out);
* live work the client sent (a running task) and the most recent few always stay — a deictic
  follow-up ("그거 취소해") has no words in common with anything and usually means the latest;
* the rest are ranked by word overlap with the message (Korean is matched on character
  bigrams so particles do not matter) and, when an embedder is configured, by meaning
  (``embed.similarities``), with a mild recency bonus; near-duplicate titles (the same chore
  repeated every week) take one slot, not all of them.

Each pick carries its ``evidence`` (overlap, similarity) so the router can doubt a decision
that chose a context nothing in the message points to.

What is shown of each pick also shrinks with age: a fresh context keeps its summary, a few
days old keeps one line, older ones keep only their title and gist.
"""
from __future__ import annotations

import math
import os
import re
from datetime import datetime, timezone

TOP_K = int(os.getenv("ROUTER_TOP_K", "6"))
KEEP_RECENT = int(os.getenv("ROUTER_KEEP_RECENT", "2"))
HOT_HOURS = float(os.getenv("ROUTER_HOT_HOURS", "24"))
WARM_DAYS = float(os.getenv("ROUTER_WARM_DAYS", "7"))

_WORD = re.compile(r"[0-9A-Za-z]+|[가-힣]+")
# chat filler that says nothing about which work a message belongs to
_STOP = {"해줘", "알려줘", "보여줘", "찾아줘", "확인해줘", "줄래", "좀", "그", "이", "저", "다시", "지금", "오늘", "같이", "어떻게", "뭐가", "얼마야", "있어", "해", "줘", "the", "a", "to"}


# bigrams of request verbs and endings: "추천해줘" sharing 추천 with "추천을 요청함" says nothing
_STOP_BI = {"추천", "요청", "확인", "정리", "알려", "보여", "해줘", "해주", "찾아", "만들", "하는", "있는", "에서", "으로",
            "어떻", "떻게", "인지", "는지", "해서", "했어", "줘요", "주세", "세요", "니다", "습니", "받음", "했고"}


def tokens(text: str) -> set[str]:
    out: set[str] = set()
    for w in _WORD.findall(text or ""):
        if w in _STOP:
            continue
        if w[0] >= "가":  # Korean: bigrams survive particles and endings (출장비는 ~ 출장)
            out.update(b for b in (w[i:i + 2] for i in range(max(1, len(w) - 1))) if b not in _STOP_BI)
        elif len(w) > 1:
            out.add(w.lower())
    return out


def age_hours(updated_at, now: datetime | None = None) -> float:
    if not updated_at:
        return 0.0
    if isinstance(updated_at, str):
        try:
            updated_at = datetime.fromisoformat(updated_at.replace("Z", "+00:00"))
        except ValueError:
            return 0.0
    if updated_at.tzinfo is None:
        updated_at = updated_at.replace(tzinfo=timezone.utc)
    return max(0.0, ((now or datetime.now(timezone.utc)) - updated_at).total_seconds() / 3600)


def tier(ctx) -> str:
    h = age_hours(ctx.updated_at)
    return "hot" if h <= HOT_HOURS else "warm" if h <= WARM_DAYS * 24 else "cold"


def hint(ctx) -> str:
    """What the decision model sees of a context besides its title, by age."""
    t = tier(ctx)
    if t == "hot":
        return " / ".join(x for x in (ctx.gist, ctx.summary) if x)[:160]
    line = (ctx.summary or "").splitlines()[0] if ctx.summary else ""
    return " / ".join(x for x in (ctx.gist, line) if x)[:100 if t == "warm" else 60]


_DEICTIC = {"그", "그거", "그것", "그건", "이거", "이것", "저거", "아까", "방금", "다음", "계속", "이어서", "위", "위에", "그럼", "그리고"}


def search_terms(message: str, limit: int = 6) -> list[str]:
    """Words to look up older contexts by: content words, Korean ones cut to their stem-ish
    first characters so 납부했어 still finds 납부."""
    out: list[str] = []
    for w in _WORD.findall(message or ""):
        if w in _STOP or w in _DEICTIC or len(w) < 2:
            continue
        t = w[:3] if w[0] >= "가" and len(w) > 3 else w
        if t not in out:
            out.append(t)
    return out[:limit]


def deictic(message: str) -> bool:
    """Points back at something without naming it ("그거 취소해", "다음 영상")."""
    words = _WORD.findall(message or "")
    return any(w in _DEICTIC for w in words) or len(words) <= 2


def _stem(title: str) -> str:
    return re.sub(r"[#\d\s]+", "", title or "")


def select(contexts: list, message: str, top_k: int = TOP_K, keep_recent: int = KEEP_RECENT,
           sims: list[float] | None = None) -> list:
    msg = tokens(message)
    docs = [tokens(f"{c.title} {c.gist} {c.summary}") for c in contexts]
    # rarer shared words count more (idf over this user's own contexts)
    df: dict[str, int] = {}
    for d in docs:
        for w in d & msg:
            df[w] = df.get(w, 0) + 1
    n = len(contexts)
    lex = [sum(math.log(1 + n / df[w]) for w in docs[i] & msg) / math.sqrt(len(docs[i]) or 1) for i in range(n)]
    for i, c in enumerate(contexts):
        c.evidence = {"overlap": round(lex[i], 3), **({"similarity": round(sims[i], 3)} if sims else {})}
    if n <= top_k:
        return contexts
    top_lex = max(lex) or 1
    if sims:
        lo, hi = min(sims), max(sims)
        sem = [(x - lo) / ((hi - lo) or 1) for x in sims]

    def score(i: int) -> float:
        rel = 0.4 * lex[i] / top_lex + 0.6 * sem[i] if sims else lex[i] / top_lex
        return rel + 0.1 / (1 + age_hours(contexts[i].updated_at) / 24)

    by_recent = sorted(range(n), key=lambda i: age_hours(contexts[i].updated_at))
    keep = [i for i in range(n) if contexts[i].active]
    keep += [i for i in by_recent[:keep_recent] if i not in keep]
    stems = {_stem(contexts[i].title) for i in keep}
    picked = list(keep)
    for i in sorted((i for i in range(n) if i not in keep), key=score, reverse=True):
        if len(picked) >= max(top_k, len(keep)):
            break
        if _stem(contexts[i].title) in stems:  # one slot per repeated chore
            continue
        stems.add(_stem(contexts[i].title))
        picked.append(i)
    return [contexts[i] for i in picked]


def gist_of(prev_gist: str, prev_summary: str, limit: int = 120) -> str:
    """Fold the request that is about to be overwritten into the context's one-line gist:
    distinct words, newest first, capped — older turns survive as keywords only."""
    m = re.search(r"최근 요청:\s*(.*)", prev_summary or "")
    words: list[str] = []
    for w in _WORD.findall(m.group(1) if m else "") + _WORD.findall(prev_gist or ""):
        if w not in _STOP and len(w) > 1 and w not in words:
            words.append(w)
    out = ""
    for w in words:
        if len(out) + len(w) + 1 > limit:
            break
        out = f"{out} {w}".strip()
    return out
