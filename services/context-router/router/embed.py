"""Optional semantic similarity for candidate narrowing (``ROUTER_EMBED_URL``).

Any OpenAI-style ``/embeddings`` endpoint works: the reference judge server with
``EMBED_MODEL=BAAI/bge-m3``, OpenAI ``text-embedding-3-small``, a vLLM embedding model. Without
one, narrowing falls back to word overlap alone (``tokens`` cannot tell that 세금계산서 is about
부가세; an embedding can).

Context vectors are cached by their text, so each context is embedded once per process and a
routing call embeds only the new message.
"""
from __future__ import annotations

import hashlib
import logging
import os
from collections import OrderedDict

import httpx

logger = logging.getLogger(__name__)
URL = os.getenv("ROUTER_EMBED_URL", "").rstrip("/")
KEY = os.getenv("ROUTER_EMBED_KEY", "")
MODEL = os.getenv("ROUTER_EMBED_MODEL", "BAAI/bge-m3")
_cache: OrderedDict[str, list[float]] = OrderedDict()
_CAP = 20000


def doc_text(c) -> str:
    return f"{c.title}\n{c.gist}\n{c.summary}"[:600]


async def _embed(texts: list[str]) -> list[list[float]]:
    headers = {"Authorization": f"Bearer {KEY}"} if KEY else {}
    async with httpx.AsyncClient(timeout=20) as cl:
        r = await cl.post(f"{URL}/embeddings", headers=headers, json={"model": MODEL, "input": texts})
        r.raise_for_status()
        return [d["embedding"] for d in sorted(r.json()["data"], key=lambda d: d["index"])]


async def similarities(message: str, contexts: list) -> list[float] | None:
    """Cosine of the message with each context, or None when no embedder is configured or it
    did not answer (narrowing then uses word overlap only)."""
    if not URL or not contexts:
        return None
    keys = [hashlib.sha1(doc_text(c).encode()).hexdigest() for c in contexts]
    missing = [(k, doc_text(c)) for k, c in zip(keys, contexts) if k not in _cache]
    try:
        vecs = await _embed([message] + [t for _, t in missing])
    except Exception as exc:  # noqa: BLE001 - narrowing degrades, routing goes on
        logger.warning("embedding failed: %s", exc)
        return None
    for (k, _), v in zip(missing, vecs[1:]):
        _cache[k] = v
        if len(_cache) > _CAP:
            _cache.popitem(last=False)
    m = vecs[0]

    def cos(v):
        dot = sum(a * b for a, b in zip(m, v))
        na = sum(a * a for a in m) ** 0.5
        nb = sum(b * b for b in v) ** 0.5
        return dot / (na * nb or 1)
    return [cos(_cache[k]) for k in keys]
