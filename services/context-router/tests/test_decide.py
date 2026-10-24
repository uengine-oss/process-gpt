import math

import httpx
import pytest

from decide import Decider, Option
from decide.base import Decision
from decide.strategies import JsonStrategy, JudgeModelStrategy, LogprobStrategy, _NO_THINKING

OPTS = [Option("podcast", "팟캐스트 제작"), Option("stock", "주식 알림"), Option("__new__", "새 주제")]


def lp_resp(pairs):
    return {"choices": [{"message": {"content": pairs[0][0]}, "logprobs": {"content": [
        {"token": pairs[0][0], "logprob": pairs[0][1], "top_logprobs": [{"token": t, "logprob": v} for t, v in pairs]}]}}]}


@pytest.fixture(autouse=True)
def clear_cache():
    LogprobStrategy._capability.clear()


@pytest.mark.asyncio
async def test_logprob_reads_letter_distribution(monkeypatch):
    s = LogprobStrategy("http://x", "k", "m")
    async def chat(self, prompt, **body):
        assert body["max_tokens"] == 1 and body["logprobs"] is True
        return lp_resp([("A", math.log(0.7)), ("C", math.log(0.2)), (" B", math.log(0.05)), ("The", math.log(0.05))])
    monkeypatch.setattr(LogprobStrategy, "chat", chat)
    d = await s.decide("state", "q", OPTS)
    assert d.choice == "podcast" and d.calibrated and d.strategy == "logprob"
    assert abs(sum(d.probabilities.values()) - 1) < 1e-9
    assert d.probabilities["podcast"] > d.probabilities["__new__"] > d.probabilities["stock"]


@pytest.mark.asyncio
async def test_logprob_switches_thinking_off_and_remembers(monkeypatch):
    calls = []
    async def chat(self, prompt, **body):
        calls.append(body.get("chat_template_kwargs"))
        if body.get("chat_template_kwargs"):
            return lp_resp([("B", math.log(0.9)), ("A", math.log(0.1))])
        return lp_resp([("We", -0.02), ("The", -4.0)])  # a thinking model starts with prose
    monkeypatch.setattr(LogprobStrategy, "chat", chat)
    s = LogprobStrategy("http://x", "k", "qwen")
    d = await s.decide("state", "q", OPTS)
    assert d.choice == "stock" and calls == [None, _NO_THINKING["chat_template_kwargs"]]
    await s.decide("state", "q", OPTS)
    assert calls[-1] == _NO_THINKING["chat_template_kwargs"] and len(calls) == 3  # remembered, no prose retry


@pytest.mark.asyncio
async def test_no_logprobs_falls_through_to_json(monkeypatch):
    async def lp_chat(self, prompt, **body):
        req = httpx.Request("POST", "http://x")
        raise httpx.HTTPStatusError("logprobs unsupported", request=req, response=httpx.Response(400, request=req))
    async def js_chat(self, prompt, **body):
        return {"choices": [{"message": {"content": '```json\n{"choice": "C", "confidence": 0.8}\n```'}}]}
    monkeypatch.setattr(LogprobStrategy, "chat", lp_chat)
    monkeypatch.setattr(JsonStrategy, "chat", js_chat)
    dec = Decider([JudgeModelStrategy(""), LogprobStrategy("http://x", "k", "claude"), JsonStrategy("http://x", "k", "claude")])
    d = await dec.decide("state", "q", OPTS)
    assert d.strategy == "json" and d.choice == "__new__" and not d.calibrated
    assert d.confidence == pytest.approx(0.8)
    assert any("judge" in n and "logprob" in n for n in d.notes)


@pytest.mark.asyncio
async def test_judge_used_first_when_configured(monkeypatch):
    async def judge(self, state, question, options):
        return Decision("stock", {"podcast": 0.1, "stock": 0.85, "__new__": 0.05}, "judge", 3, True, "qwen-judge")
    monkeypatch.setattr(JudgeModelStrategy, "decide", judge)
    dec = Decider([JudgeModelStrategy("http://judge"), LogprobStrategy("http://x", "k", "m")])
    d = await dec.decide("s", "q", OPTS)
    assert d.strategy == "judge" and d.choice == "stock"


@pytest.mark.asyncio
async def test_doubtful_judge_escalates_to_logprob(monkeypatch):
    async def judge(self, state, question, options):
        return Decision("podcast", {"podcast": 0.55, "stock": 0.25, "__new__": 0.2}, "judge", 300, True, "small")
    async def chat(self, prompt, **body):
        return lp_resp([("C", math.log(0.93)), ("A", math.log(0.07))])
    monkeypatch.setattr(JudgeModelStrategy, "decide", judge)
    monkeypatch.setattr(LogprobStrategy, "chat", chat)
    dec = Decider([JudgeModelStrategy("http://judge"), LogprobStrategy("http://x", "k", "m")], escalate_below=0.8)
    d = await dec.decide("s", "q", OPTS)
    assert d.strategy == "logprob" and d.choice == "__new__" and d.latency_ms >= 300
    assert any("escalated from judge" in n for n in d.notes)


@pytest.mark.asyncio
async def test_confident_judge_is_final(monkeypatch):
    async def judge(self, state, question, options):
        return Decision("stock", {"podcast": 0.02, "stock": 0.96, "__new__": 0.02}, "judge", 300, True, "small")
    async def chat(self, prompt, **body):
        raise AssertionError("the bigger model must not be called")
    monkeypatch.setattr(JudgeModelStrategy, "decide", judge)
    monkeypatch.setattr(LogprobStrategy, "chat", chat)
    dec = Decider([JudgeModelStrategy("http://judge"), LogprobStrategy("http://x", "k", "m")], escalate_below=0.8)
    assert (await dec.decide("s", "q", OPTS)).strategy == "judge"
