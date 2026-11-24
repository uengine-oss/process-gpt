"""Which conversation does a new message belong to?

Candidates are the user's recent contexts (conversations the router routed before) plus any
the client knows about (a running browser task, a scheduled job's latest result...). The
decision is a typed choice among them and "a new topic", made by ``decide``. A confident
pick continues that conversation; a confident "new" opens one; anything in between stays
where the user already is, and says it was unsure.
"""
from __future__ import annotations

import uuid
from dataclasses import asdict, dataclass

from decide import Decider, Option

from . import store
from . import embed
from .select import deictic, hint, search_terms, select

NEW = "__new__"


@dataclass
class Context:
    conversation_id: str
    title: str
    summary: str = ""
    kind: str = "conversation"
    active: bool = False
    gist: str = ""  # earlier turns, folded into keywords
    updated_at: str | None = None
    evidence: dict | None = None  # what in the message points here (set by select)


@dataclass
class RouteResult:
    conversation_id: str
    action: str  # continue | new | stay
    context: dict | None
    decision: dict

    def as_dict(self) -> dict:
        return asdict(self)


def _options(contexts: list[Context]) -> list[Option]:
    opts = [Option(c.conversation_id, f"[{c.kind}{' · 진행 중' if c.active else ''}] {c.title}", hint(c)) for c in contexts]
    return opts + [Option(NEW, "새 주제 — 위 어느 대화와도 이어지지 않는 새 요청")]


async def candidates(tenant_id: str, user_id: str, client_contexts: list[dict] | None, message: str = "") -> list[Context]:
    """Live client contexts plus the user's stored ones that are not dormant, narrowed to the
    few worth deciding among (see ``select``)."""
    seen: dict[str, Context] = {}
    for c in client_contexts or []:
        if c.get("conversation_id") and c.get("title"):
            seen[c["conversation_id"]] = Context(c["conversation_id"], c["title"], c.get("summary", ""), c.get("kind", "task"),
                                                 bool(c.get("active")), c.get("gist", ""), c.get("updated_at"))
    for row in await store.recent(tenant_id, user_id) + await store.search(tenant_id, user_id, search_terms(message)):
        seen.setdefault(row["conversation_id"], Context(row["conversation_id"], row["title"], row.get("summary") or "",
                                                        row.get("kind") or "conversation", False, row.get("gist") or "", row.get("updated_at")))
    pool = list(seen.values())
    # similarity is wanted even for a short list: it is the evidence the judge cross-check reads
    return select(pool, message, sims=await embed.similarities(message, pool))


EVIDENCE_SIM = float(__import__("os").getenv("ROUTER_EVIDENCE_SIM", "0.5"))


def _unsupported(c: Context) -> bool:
    ev = c.evidence or {}
    return ev.get("overlap", 0) == 0 and ev.get("similarity", 0) < EVIDENCE_SIM


async def route(decider: Decider, *, message: str, tenant_id: str, user_id: str, current: str | None,
                client_contexts: list[dict] | None = None, threshold: float = 0.55) -> RouteResult:
    contexts = await candidates(tenant_id, user_id, client_contexts, message)
    if not contexts:
        conv = current or uuid.uuid4().hex
        return RouteResult(conv, "new", None, {"strategy": "none", "choice": NEW, "confidence": 1.0, "notes": ["no prior contexts"]})
    state = (
        "사용자가 한 채팅창에서 여러 일을 동시에 진행한다. 아래는 사용자의 진행 중이거나 최근 대화들이다.\n"
        f"사용자의 새 메시지: \"{message.strip()[:600]}\""
    )
    question = "이 새 메시지는 어느 대화의 후속인가? 같은 일·같은 대상을 이어 말하면 그 대화, 무관한 새 요청이면 새 주제를 고른다."
    d = await decider.decide(state, question, _options(contexts))
    by_id = {c.conversation_id: c for c in contexts}
    # A small judge model sometimes picks a context with full confidence although nothing in the
    # message points there (a new question about lunch "continuing" a business trip). When the
    # pick has no word overlap, low similarity and the message does not point back ("그거"),
    # the judge's answer is not trusted and the next strategy decides.
    if d.strategy == "judge" and d.choice != NEW and not deictic(message) and _unsupported(by_id[d.choice]):
        d2 = await decider.decide(state, question, _options(contexts), skip=("judge",))
        d2.notes.append(f"judge picked {d.choice} ({d.confidence:.2f}) with no evidence in the message; re-decided")
        d2.latency_ms += d.latency_ms
        d = d2
    # a self-reported confidence is not thresholded as strictly as a measured one
    bar = threshold if d.calibrated else min(threshold + 0.15, 0.9)
    if d.choice == NEW and d.confidence >= bar:
        return RouteResult(uuid.uuid4().hex, "new", None, d.as_dict())
    if d.choice != NEW and d.confidence >= bar:
        return RouteResult(d.choice, "continue", asdict(by_id[d.choice]), d.as_dict())
    # unsure: do not move the user somewhere surprising
    conv = current or (d.choice if d.choice != NEW else uuid.uuid4().hex)
    return RouteResult(conv, "stay", asdict(by_id[conv]) if conv in by_id else None, d.as_dict())
