from __future__ import annotations

import json
import logging
import os

from .base import Decision, Option
from .strategies import JsonStrategy, JudgeModelStrategy, LogprobStrategy

logger = logging.getLogger(__name__)


class Decider:
    """Try strategies in order; the first that can serve answers.

    With ``escalate_below`` set, a measured (calibrated) answer whose confidence falls under
    it is passed on to the next strategy -- the fast judge settles the clear cases and only
    the doubtful ones pay for the bigger model. The escalated answer records both.
    """

    def __init__(self, strategies, *, escalate_below: float | None = None):
        self.strategies = list(strategies)
        self.escalate_below = escalate_below

    async def decide(self, state: str, question: str, options: list[Option], skip: tuple[str, ...] = ()) -> Decision:
        if not options:
            raise ValueError("no options")
        if len(options) == 1:
            return Decision(options[0].key, {options[0].key: 1.0}, "trivial", 0)
        skipped: list[str] = []
        doubtful: Decision | None = None
        for i, s in enumerate(self.strategies):
            if s.name in skip:
                skipped.append(s.name)
                continue
            d = await s.decide(state, question, options)
            if d is None:
                skipped.append(s.name)
                continue
            if skipped:
                d.notes.append(f"fell back past: {', '.join(skipped)}")
            if doubtful is not None:
                d.notes.append(f"escalated from {doubtful.strategy} ({doubtful.choice} {doubtful.confidence:.2f})")
                d.latency_ms += doubtful.latency_ms
                return d
            last = i == len(self.strategies) - 1
            if self.escalate_below and d.calibrated and d.confidence < self.escalate_below and not last:
                doubtful = d
                continue
            return d
        if doubtful is not None:
            doubtful.notes.append("no stronger strategy available; kept the doubtful answer")
            return doubtful
        raise RuntimeError(f"no decision strategy could answer ({', '.join(skipped)})")


def from_env(env=os.environ) -> Decider:
    """Build the chain from configuration.

    DECIDE_STRATEGIES   order to try, default ``judge,logprob,json``
    DECIDE_JUDGE_URL    typed-decision endpoint (judge strategy is skipped when empty)
    DECIDE_JUDGE_KEY
    DECIDE_LLM_BASE_URL / DECIDE_LLM_API_KEY / DECIDE_LLM_MODEL
                        chat LLM for logprob/json; defaults to LLM_PROXY_URL / LLM_PROXY_API_KEY / LLM_MODEL
    DECIDE_LLM_EXTRA    JSON merged into every chat request
    DECIDE_PERMUTE      1 to average two option orders (logprob)
    DECIDE_ESCALATE_BELOW  pass a measured answer under this confidence to the next strategy
    """
    base = env.get("DECIDE_LLM_BASE_URL") or env.get("LLM_PROXY_URL") or "https://api.openai.com/v1"
    key = env.get("DECIDE_LLM_API_KEY") or env.get("LLM_PROXY_API_KEY") or env.get("OPENAI_API_KEY", "")
    model = env.get("DECIDE_LLM_MODEL") or env.get("LLM_MODEL") or "gpt-4o-mini"
    extra = json.loads(env.get("DECIDE_LLM_EXTRA") or "{}")
    built = {
        "judge": lambda: JudgeModelStrategy(env.get("DECIDE_JUDGE_URL", ""), api_key=env.get("DECIDE_JUDGE_KEY", "")),
        "logprob": lambda: LogprobStrategy(base, key, model, extra=extra, permute=env.get("DECIDE_PERMUTE") == "1"),
        "json": lambda: JsonStrategy(base, key, model, extra=extra),
    }
    order = [s.strip() for s in (env.get("DECIDE_STRATEGIES") or "judge,logprob,json").split(",") if s.strip()]
    esc = env.get("DECIDE_ESCALATE_BELOW")
    return Decider([built[s]() for s in order if s in built], escalate_below=float(esc) if esc else None)
