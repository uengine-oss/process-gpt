"""Measure each decision strategy on the routing cases: accuracy, latency, and whether its
confidence separates right from wrong (which is what a routing threshold relies on).

Usage: python eval/bench.py [label=strategy@base_url@model ...]   (see SETUPS below)
Writes eval/results.json and prints a table.
"""
import asyncio
import json
import os
import statistics
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from decide import Decider  # noqa: E402
from decide.strategies import JsonStrategy, JudgeModelStrategy, LogprobStrategy  # noqa: E402
from router.route import Context, _options  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
data = json.load(open(os.path.join(HERE, "cases.json"), encoding="utf-8"))
contexts = [Context(c["conversation_id"], c["title"], c.get("summary", ""), c.get("kind", "conversation"), bool(c.get("active"))) for c in data["contexts"]]
OPTIONS = _options(contexts)
STATE = "사용자가 한 채팅창에서 여러 일을 동시에 진행한다. 아래는 사용자의 진행 중이거나 최근 대화들이다.\n사용자의 새 메시지: \"{m}\""
QUESTION = "이 새 메시지는 어느 대화의 후속인가? 같은 일·같은 대상을 이어 말하면 그 대화, 무관한 새 요청이면 새 주제를 고른다."
EXPECT_NEW = {"__new__": "__new__"}


def setups():
    f, fk = os.environ["FRENTIS_URL"], os.environ["FRENTIS_KEY"]
    o, ok = "https://api.openai.com/v1", os.environ["OPENAI_KEY"]
    out = [
        ("logprob · frentis", LogprobStrategy(f, fk, "frentis-ai-model")),
        ("json · frentis", JsonStrategy(f, fk, "frentis-ai-model", extra={"chat_template_kwargs": {"enable_thinking": False}})),
        ("logprob · gpt-4o-mini", LogprobStrategy(o, ok, "gpt-4o-mini")),
        ("json · gpt-4o-mini", JsonStrategy(o, ok, "gpt-4o-mini")),
        ("logprob · gpt-4.1-nano", LogprobStrategy(o, ok, "gpt-4.1-nano")),
    ]
    if os.environ.get("JUDGE_URL"):
        j = os.environ["JUDGE_URL"]
        jl = os.environ.get("JUDGE_LABEL", "so1")
        out.insert(0, (f"judge · {jl}", JudgeModelStrategy(j, timeout=120)))
        # the policy itself: strategies in order, judge first, doubtful answers escalate
        out += [
            ("policy · judge→logprob(frentis)→json, escalate<0.9",
             Decider([JudgeModelStrategy(j, timeout=120), LogprobStrategy(f, fk, "frentis-ai-model"), JsonStrategy(f, fk, "frentis-ai-model")], escalate_below=0.9)),
            ("policy · judge DOWN→logprob(frentis)→json",
             Decider([JudgeModelStrategy("http://127.0.0.1:1/judge", timeout=2), LogprobStrategy(f, fk, "frentis-ai-model"), JsonStrategy(f, fk, "frentis-ai-model")])),
            ("policy · judge DOWN→logprob(o4-mini: none)→json(o4-mini)",
             Decider([JudgeModelStrategy("http://127.0.0.1:1/judge", timeout=2), LogprobStrategy(o, ok, "o4-mini"), JsonStrategy(o, ok, "o4-mini")])),
        ]
    return out


async def run(label, strategy):
    rows = []
    for c in data["cases"]:
        t = time.perf_counter()
        try:
            d = await strategy.decide(STATE.format(m=c["message"]), QUESTION, OPTIONS)
        except RuntimeError:
            d = None
        ms = int((time.perf_counter() - t) * 1000)
        if d is None:
            rows.append({"message": c["message"], "expect": c["expect"], "choice": None, "confidence": 0, "ms": ms})
            continue
        rows.append({"message": c["message"], "expect": c["expect"], "choice": d.choice, "confidence": round(d.confidence, 3), "ms": ms,
                     "calibrated": d.calibrated, "strategy": d.strategy, "escalated": any("escalated" in n for n in d.notes)})
    graded = [r for r in rows if r["expect"] != "ambiguous"]
    right = [r for r in graded if r["choice"] == r["expect"]]
    wrong = [r for r in graded if r["choice"] != r["expect"]]
    amb = [r for r in rows if r["expect"] == "ambiguous"]
    summary = {
        "label": label,
        "accuracy": round(len(right) / len(graded), 3),
        "p50_ms": int(statistics.median(r["ms"] for r in rows)),
        "conf_right": round(statistics.mean([r["confidence"] for r in right]), 3) if right else None,
        "conf_wrong": round(statistics.mean([r["confidence"] for r in wrong]), 3) if wrong else None,
        "ambiguous_conf": amb[0]["confidence"] if amb else None,
        # at the router's bar (0.55), how many wrong picks would have been held back as "stay"
        "wrong_held_back": sum(1 for r in wrong if r["confidence"] < 0.55),
        "wrong": len(wrong),
        # which strategy actually answered (the proof that the policy picks judge first)
        "decided_by": dict(sorted({k: sum(1 for r in rows if r.get("strategy") == k) for k in {r.get("strategy") for r in rows}}.items(), key=lambda kv: str(kv[0]))),
        "escalated": sum(1 for r in rows if r.get("escalated")),
    }
    return summary, rows


async def main():
    results = []
    for label, s in setups():
        summary, rows = await run(label, s)
        results.append({"summary": summary, "rows": rows})
        print(json.dumps(summary, ensure_ascii=False), flush=True)
    json.dump(results, open(os.path.join(HERE, "results.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)

asyncio.run(main())
