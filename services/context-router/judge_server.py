"""Reference typed-decision (judge) server for the ``judge`` strategy.

Wraps open-alternative-jev (``so1``): an open-weight chat model reads the options as letters
and the decision is the softmax over those letters' next-token logits -- no text generated,
no answer outside the options. Speaks the contract ``JudgeModelStrategy`` expects:

  POST /judge {"state", "question", "options": [{"key", "label"}]}
       -> {"choice": key, "probabilities": {key: p}, "model": id}

With EMBED_MODEL set (e.g. BAAI/bge-m3) it also serves OpenAI-style embeddings, which the
router uses to narrow a user's many contexts to the few worth deciding among:

  POST /embeddings {"input": [text, ...]} -> {"data": [{"index", "embedding"}], "model": id}

Run: .venv-judge/bin/python judge_server.py   (JUDGE_MODEL, JUDGE_DEVICE, PORT)
"""
from __future__ import annotations

import os
import time

import uvicorn
from so1 import Choice, Decider
from starlette.applications import Starlette
from starlette.requests import Request
from starlette.responses import JSONResponse
from starlette.routing import Route

MODEL = os.getenv("JUDGE_MODEL", "Qwen/Qwen3-1.7B")
DEVICE = os.getenv("JUDGE_DEVICE", "mps")
decider = Decider.from_pretrained(MODEL, backend="hf", device_map=DEVICE, dtype="auto",
                                  permutations=int(os.getenv("JUDGE_PERMUTATIONS", "1")))


async def judge(request: Request):
    b = await request.json()
    options = b.get("options") or []
    labels = [str(o.get("label") or o["key"])[:200] for o in options]
    t = time.perf_counter()
    d = decider.decide(b.get("state") or None, [Choice(b.get("question", ""), labels)])[0]
    probs = {o["key"]: float(p) for o, p in zip(options, d.probabilities)}
    return JSONResponse({"choice": options[d.index]["key"], "probabilities": probs, "model": MODEL,
                         "latency_ms": int((time.perf_counter() - t) * 1000)})


EMBED_MODEL = os.getenv("EMBED_MODEL", "")
if EMBED_MODEL:
    import torch
    from transformers import AutoModel, AutoTokenizer
    etok = AutoTokenizer.from_pretrained(EMBED_MODEL)
    emodel = AutoModel.from_pretrained(EMBED_MODEL, torch_dtype=torch.float16).to(DEVICE).eval()


async def embeddings(request: Request):
    b = await request.json()
    texts = b.get("input") or []
    texts = [texts] if isinstance(texts, str) else texts
    out = []
    with torch.no_grad():
        for i in range(0, len(texts), 32):
            enc = etok(texts[i:i + 32], padding=True, truncation=True, max_length=256, return_tensors="pt").to(DEVICE)
            cls = emodel(**enc).last_hidden_state[:, 0]  # bge: the [CLS] vector, normalized
            out += torch.nn.functional.normalize(cls.float(), dim=-1).cpu().tolist()
    return JSONResponse({"object": "list", "model": EMBED_MODEL,
                         "data": [{"object": "embedding", "index": i, "embedding": e} for i, e in enumerate(out)]})


async def health(_):
    return JSONResponse({"status": "ok", "model": MODEL, "device": DEVICE, "embed_model": EMBED_MODEL or None})

app = Starlette(routes=[Route("/judge", judge, methods=["POST"]), Route("/health", health)]
                + ([Route("/embeddings", embeddings, methods=["POST"])] if EMBED_MODEL else []))

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=int(os.getenv("PORT", "8896")))
