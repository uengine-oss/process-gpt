from __future__ import annotations

import json
import logging
import math
import re
import time

import httpx

from .base import Decision, Option, lettered, prompt_for

logger = logging.getLogger(__name__)


class JudgeModelStrategy:
    """A dedicated typed-decision endpoint.

    Contract (the bundled ``judge_server`` speaks it; a JEV-style service can be
    fronted by a thin adapter): ``POST {url}`` with
    ``{"state", "question", "options": [{"key", "label"}]}`` →
    ``{"choice": key, "probabilities": {key: p}, "model"?: str}``.
    """

    name = "judge"

    def __init__(self, url: str, *, api_key: str = "", timeout: float = 15.0):
        self.url = url
        self.api_key = api_key
        self.timeout = timeout

    async def decide(self, state, question, options):
        if not self.url:
            return None
        t = time.perf_counter()
        headers = {"Authorization": f"Bearer {self.api_key}"} if self.api_key else {}
        try:
            async with httpx.AsyncClient(timeout=self.timeout) as client:
                r = await client.post(self.url, headers=headers, json={
                    "state": state, "question": question,
                    "options": [{"key": o.key, "label": f"{o.label} — {o.hint}" if o.hint else o.label} for o in options],
                })
                r.raise_for_status()
                body = r.json()
        except Exception as exc:  # noqa: BLE001 - a judge outage falls through to the next strategy
            logger.warning("judge model unavailable: %s", exc)
            return None
        probs = {o.key: float(body.get("probabilities", {}).get(o.key, 0.0)) for o in options}
        choice = body.get("choice") if body.get("choice") in probs else max(probs, key=probs.get)
        return Decision(choice, _normalise(probs), self.name, _ms(t), True, body.get("model", ""))


class _ChatLLM:
    def __init__(self, base_url: str, api_key: str, model: str, *, extra: dict | None = None, timeout: float = 30.0):
        self.base_url = base_url.rstrip("/")
        self.api_key = api_key
        self.model = model
        self.extra = dict(extra or {})
        self.timeout = timeout

    async def chat(self, prompt: str, **body) -> dict:
        payload = {"model": self.model, "messages": [{"role": "user", "content": prompt}],
                   "temperature": 0, **self.extra, **body}
        async with httpx.AsyncClient(timeout=self.timeout) as client:
            for _ in range(3):
                r = await client.post(
                    f"{self.base_url}/chat/completions",
                    headers={"Authorization": f"Bearer {self.api_key}", "Content-Type": "application/json"},
                    json=payload,
                )
                if r.status_code < 400:
                    return r.json()
                text = r.text
                # reasoning models take max_completion_tokens and only their default temperature
                if "max_tokens" in text and "max_tokens" in payload:
                    payload["max_completion_tokens"] = max(payload.pop("max_tokens"), 16) * (8 if payload.get("logprobs") is None else 1)
                    continue
                if "temperature" in text and "temperature" in payload:
                    payload.pop("temperature")
                    continue
                break
        raise httpx.HTTPStatusError(r.text[:300], request=r.request, response=r)


#: Some open-weight chat models (Qwen3 and the like) think aloud first, so the first token
#: is prose rather than a letter. Servers that host them (SGLang, vLLM) accept this switch.
_NO_THINKING = {"chat_template_kwargs": {"enable_thinking": False}}


class LogprobStrategy(_ChatLLM):
    """One letter, read from next-token log-probabilities.

    Whether the endpoint returns usable log-probabilities is found out on first use and
    remembered: no logprobs at all (Anthropic, many gateways), or prose instead of a letter
    even with thinking switched off, both make this strategy step aside.
    """

    name = "logprob"
    #: (base_url, model) -> extra body that makes letters come out, or None when unusable
    _capability: dict[tuple[str, str], dict | None] = {}

    def __init__(self, *args, permute: bool = False, min_mass: float = 0.5, **kw):
        super().__init__(*args, **kw)
        self.permute = permute
        self.min_mass = min_mass

    async def decide(self, state, question, options):
        cap_key = (self.base_url, self.model)
        if cap_key in self._capability and self._capability[cap_key] is None:
            return None
        t = time.perf_counter()
        notes: list[str] = []
        probs = await self._distribution(state, question, options, cap_key, notes)
        if probs is None:
            return None
        if self.permute and len(options) > 1:
            # position bias: ask again with the order reversed and average
            rev = list(reversed(options))
            probs2 = await self._distribution(state, question, rev, cap_key, notes)
            if probs2:
                probs = {k: (probs[k] + probs2.get(k, 0.0)) / 2 for k in probs}
                notes.append("averaged over 2 option orders")
        choice = max(probs, key=probs.get)
        return Decision(choice, probs, self.name, _ms(t), True, self.model, notes)

    async def _distribution(self, state, question, options, cap_key, notes):
        prompt = prompt_for(state, question, options, answer_line="Answer with the single option letter only.")
        letters = {letter: o.key for letter, o in lettered(options)}
        tries = [self._capability[cap_key]] if cap_key in self._capability else [{}, _NO_THINKING]
        for extra in tries:
            try:
                resp = await self.chat(prompt, max_tokens=1, logprobs=True, top_logprobs=20, **extra)
            except httpx.HTTPStatusError as exc:
                logger.info("logprobs not accepted by %s: %s", self.model, str(exc)[:160])
                continue
            except Exception as exc:  # noqa: BLE001
                logger.warning("logprob call failed: %s", exc)
                return None
            top = _first_token_top(resp)
            if not top:
                continue
            mass: dict[str, float] = {}
            for tok, lp in top:
                letter = tok.strip().upper()
                if letter in letters:
                    mass[letters[letter]] = mass.get(letters[letter], 0.0) + math.exp(lp)
            covered = sum(mass.values())
            if covered < self.min_mass:
                notes.append(f"letters covered only {covered:.2f} of the first token")
                continue
            self._capability[cap_key] = extra
            if extra:
                notes.append("thinking disabled for a single-token answer")
            return _normalise({o.key: mass.get(o.key, 0.0) for o in options})
        self._capability.setdefault(cap_key, None)
        return None


class JsonStrategy(_ChatLLM):
    """The model names its choice in JSON. Always available; its confidence is self-reported."""

    name = "json"

    async def decide(self, state, question, options):
        t = time.perf_counter()
        prompt = prompt_for(state, question, options, answer_line=(
            'Reply with JSON only: {"choice": "<option letter>", "confidence": <0..1>}'))
        letters = {letter: o.key for letter, o in lettered(options)}
        body = {"max_tokens": 200, "response_format": {"type": "json_object"}}
        text = ""
        for attempt in (body, {"max_tokens": 200}, {"max_tokens": 200, **_NO_THINKING}):
            try:
                resp = await self.chat(prompt, **attempt)
                text = resp["choices"][0]["message"].get("content") or ""
                if text.strip():
                    break
            except Exception as exc:  # noqa: BLE001 - e.g. response_format unsupported
                logger.info("json attempt failed: %s", str(exc)[:160])
        data = _loose_json(text)
        letter = str((data or {}).get("choice", "")).strip().upper()[:1]
        if letter not in letters:
            m = re.search(r"\b([A-Z])\b", text)
            letter = m.group(1) if m and m.group(1) in letters else ""
        if not letter:
            return None
        conf = float((data or {}).get("confidence", 0.6) or 0.6)
        conf = min(max(conf, 0.0), 1.0)
        rest = (1 - conf) / max(len(options) - 1, 1)
        probs = {o.key: (conf if o.key == letters[letter] else rest) for o in options}
        return Decision(letters[letter], probs, self.name, _ms(t), False, self.model, ["confidence is self-reported"])


def _first_token_top(resp: dict) -> list[tuple[str, float]]:
    content = ((resp.get("choices") or [{}])[0].get("logprobs") or {}).get("content") or []
    if not content:
        return []
    first = content[0]
    top = first.get("top_logprobs") or [{"token": first.get("token", ""), "logprob": first.get("logprob", 0)}]
    return [(x.get("token", ""), float(x.get("logprob", -99))) for x in top]


def _normalise(probs: dict[str, float]) -> dict[str, float]:
    total = sum(probs.values())
    if total <= 0:
        n = len(probs) or 1
        return {k: 1 / n for k in probs}
    return {k: v / total for k, v in probs.items()}


def _loose_json(text: str) -> dict | None:
    text = (text or "").strip()
    for candidate in (text, *re.findall(r"\{.*?\}", text, re.S)):
        try:
            v = json.loads(candidate)
            if isinstance(v, dict):
                return v
        except Exception:  # noqa: BLE001
            continue
    return None


def _ms(t: float) -> int:
    return int((time.perf_counter() - t) * 1000)
