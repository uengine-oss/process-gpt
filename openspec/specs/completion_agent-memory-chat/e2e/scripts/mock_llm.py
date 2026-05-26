#!/usr/bin/env python3
"""Deterministic OpenAI-compatible LLM + embedding stub for the
completion_agent-memory-chat E2E suite.

This is the ONLY stubbed boundary for LLM/embedding behavior. It replaces
the external OpenAI API so that mem0 memory storage/search and the
completion service's learning/query response chains are deterministic.

Endpoints (stdlib only, no pip install needed):
  GET  /health               -> readiness probe
  POST /v1/embeddings        -> deterministic bag-of-words vectors (1536-d)
  POST /v1/chat/completions  -> deterministic chat answers (JSON or SSE)

Embeddings are deterministic: identical text yields an identical vector
(cosine similarity 1.0, above the 0.92 duplicate threshold), and texts
that share words get a positive similarity so memory search stays useful.
"""
import json
import math
import re
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

EMBED_DIM = 1536
PORT = 8080

_TOKEN_RE = re.compile(r"[0-9A-Za-z가-힣]+")

# Explicit failure injection used by the
# completion_process-definition-search E2E suite to exercise the
# completion service's graceful empty-list fallback.
#
# Two triggers, both returning HTTP 400 from /v1/embeddings:
#   1. EMBED_FAIL_TOKEN inside a raw-string embedding input.
#   2. The runtime toggle below, flipped via POST /control/embed-fail
#      {"enabled": true|false}. The toggle is needed because the real
#      caller (langchain OpenAIEmbeddings) tokenizes text before sending,
#      so request-content matching alone cannot target a specific query.
# Normal inputs are unaffected while the toggle is off.
EMBED_FAIL_TOKEN = "__E2E_EMBED_FAIL__"
_EMBED_FAIL = {"enabled": False}


def _fnv(s):
    """Deterministic 64-bit FNV-1a hash of a string."""
    h = 1469598103934665603
    for ch in s:
        h ^= ord(ch)
        h = (h * 1099511628211) & 0xFFFFFFFFFFFFFFFF
    return h


def embed(text):
    """Deterministic L2-normalized vector of length EMBED_DIM.

    Dominant component: a whole-text identity signal so that ONLY an exact
    repeat of a sentence reaches cosine 1.0 (>= the 0.92 duplicate threshold).
    Minor component: a per-word signal so memory search still ranks
    word-sharing texts above unrelated ones without ever looking duplicate.
    """
    norm_text = " ".join(_TOKEN_RE.findall((text or "").lower())) or "_empty_"
    vec = [0.0] * EMBED_DIM

    # Component A - whole-text identity (dominant weight)
    seed = _fnv("DOC::" + norm_text)
    for _ in range(24):
        seed = (seed * 1099511628211 + 12345) & 0xFFFFFFFFFFFFFFFF
        vec[seed % EMBED_DIM] += 3.0

    # Component B - shared-word signal (small weight)
    for tok in _TOKEN_RE.findall(norm_text):
        vec[_fnv("TOK::" + tok) % EMBED_DIM] += 0.4

    norm = math.sqrt(sum(v * v for v in vec)) or 1.0
    return [v / norm for v in vec]


def _flatten_prompt(payload):
    """Concatenate every textual part of a chat-completions request body."""
    parts = []
    for msg in payload.get("messages", []) or []:
        content = msg.get("content")
        if isinstance(content, str):
            parts.append(content)
        elif isinstance(content, list):
            for item in content:
                if isinstance(item, dict) and isinstance(item.get("text"), str):
                    parts.append(item["text"])
    if isinstance(payload.get("prompt"), str):
        parts.append(payload["prompt"])
    return "\n".join(parts)


def _search_snippet(prompt):
    """Pull the first stored-memory line out of the query prompt context."""
    after = prompt.split("검색 결과:", 1)[-1]
    for line in after.splitlines():
        line = line.strip()
        if line.startswith("-"):
            cleaned = line.lstrip("- ").strip()
            cleaned = re.sub(r"\s*\(신뢰도:.*\)$", "", cleaned)
            if cleaned:
                return cleaned
    return ""


def answer_for(prompt):
    """Return a deterministic assistant answer string for the given prompt."""
    # Learning-mode response chain (learning_response_prompt)
    if "학습 결과:" in prompt:
        if "저장하지 않음" in prompt:
            return "비슷한 내용이 이미 있어 새로 저장하지 않았습니다."
        return "말씀하신 내용을 잘 기억하고 학습했습니다."

    # Query-mode response chain (response_generation_prompt -> expects JSON)
    if "검색 결과:" in prompt and "질문:" in prompt:
        snippet = _search_snippet(prompt)
        if snippet:
            content = (
                f"저장된 메모리를 검색한 결과를 바탕으로 답변드립니다. {snippet}"
            )
            html = (
                "<div>저장된 메모리를 검색한 결과를 바탕으로 답변드립니다. "
                f"<span class='search-result'>{snippet}"
                "<span class=\"search-result-index\">0</span></span></div>"
            )
            results = [{"index": 0, "score": 0.74, "memory": snippet}]
        else:
            content = "관련된 저장 정보를 찾지 못했습니다."
            html = "<div>관련된 저장 정보를 찾지 못했습니다.</div>"
            results = []
        return json.dumps(
            {"content": content, "html_content": html, "search_results": results},
            ensure_ascii=False,
        )

    # mem0 internal / fallback
    return "확인했습니다."


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):  # quieter logs
        print("[mock-llm]", fmt % args, flush=True)

    def _send_json(self, obj, status=200):
        body = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _read_body(self):
        length = int(self.headers.get("Content-Length") or 0)
        if not length:
            return {}
        raw = self.rfile.read(length)
        try:
            return json.loads(raw.decode("utf-8"))
        except Exception:
            return {}

    def do_GET(self):
        if self.path.rstrip("/") in ("/health", "/healthz", ""):
            self._send_json({"status": "ok"})
            return
        if self.path.startswith("/v1/models"):
            self._send_json({"object": "list", "data": [{"id": "gpt-4o", "object": "model"}]})
            return
        self._send_json({"status": "ok"})

    def do_POST(self):
        payload = self._read_body()

        # Runtime failure-injection toggle (non-user-facing E2E control).
        if self.path.rstrip("/") == "/control/embed-fail":
            _EMBED_FAIL["enabled"] = bool(payload.get("enabled"))
            self._send_json({"embed_fail": _EMBED_FAIL["enabled"]})
            return

        if self.path.startswith("/v1/embeddings"):
            inp = payload.get("input", "")
            items = inp if isinstance(inp, list) else [inp]
            # Explicit failure injection (toggle or raw-string token).
            if _EMBED_FAIL["enabled"] or any(
                EMBED_FAIL_TOKEN in str(t) for t in items
            ):
                self._send_json(
                    {"error": {"message": "embedding failure injected for E2E",
                               "type": "invalid_request_error"}},
                    status=400,
                )
                return
            data = [
                {"object": "embedding", "index": i, "embedding": embed(str(t))}
                for i, t in enumerate(items)
            ]
            self._send_json(
                {
                    "object": "list",
                    "data": data,
                    "model": payload.get("model", "text-embedding-3-small"),
                    "usage": {"prompt_tokens": 0, "total_tokens": 0},
                }
            )
            return

        if self.path.startswith("/v1/chat/completions"):
            content = answer_for(_flatten_prompt(payload))
            if payload.get("stream"):
                self._send_stream(content, payload.get("model", "gpt-4o"))
            else:
                self._send_json(
                    {
                        "id": "chatcmpl-" + uuid.uuid4().hex,
                        "object": "chat.completion",
                        "created": int(time.time()),
                        "model": payload.get("model", "gpt-4o"),
                        "choices": [
                            {
                                "index": 0,
                                "message": {"role": "assistant", "content": content},
                                "finish_reason": "stop",
                            }
                        ],
                        "usage": {
                            "prompt_tokens": 0,
                            "completion_tokens": 0,
                            "total_tokens": 0,
                        },
                    }
                )
            return

        self._send_json({"status": "ok"})

    def _send_stream(self, content, model):
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "close")
        self.end_headers()
        created = int(time.time())
        cid = "chatcmpl-" + uuid.uuid4().hex

        def chunk(delta, finish=None):
            obj = {
                "id": cid,
                "object": "chat.completion.chunk",
                "created": created,
                "model": model,
                "choices": [{"index": 0, "delta": delta, "finish_reason": finish}],
            }
            return ("data: " + json.dumps(obj, ensure_ascii=False) + "\n\n").encode("utf-8")

        self.wfile.write(chunk({"role": "assistant"}))
        self.wfile.write(chunk({"content": content}))
        self.wfile.write(chunk({}, finish="stop"))
        self.wfile.write(b"data: [DONE]\n\n")
        self.wfile.flush()


if __name__ == "__main__":
    print(f"[mock-llm] listening on :{PORT}", flush=True)
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
