"""Deterministic OpenAI-compatible mock for completion_process-data-query.

Endpoints:
  - POST /v1/embeddings        -> deterministic 1536-d zero-axis vectors
  - POST /v1/chat/completions  -> SQL / HTML table / empty canned responses
  - GET  /control/last-prompt  -> returns the most recent prompt content
                                  joined from `messages[].content`, used
                                  by scenario 04 to verify tenant scoping.
  - GET  /health               -> 200 ok

The script avoids non-stdlib deps so the container can run plain
``python:3.12-slim`` without a build step.
"""
from __future__ import annotations

import hashlib
import json
import math
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

EMBED_DIM = 1536
_state_lock = threading.Lock()
_last_prompt: str = ""


def _embed(_text: str) -> list[float]:
    """Stable unit vector — content doesn't matter for this suite."""
    seed = hashlib.sha256(b"pdq").digest()
    vec = [((seed[i % len(seed)] / 255.0) - 0.5) * 2.0 for i in range(EMBED_DIM)]
    norm = math.sqrt(sum(x * x for x in vec)) or 1.0
    return [x / norm for x in vec]


def _build_chat_text(prompt: str) -> str:
    """Return assistant text per prompt shape.

    The completion service sends two distinct prompt templates from
    `process_var_sql_gen.py`:
      - process_var_sql `prompt`: contains 'SQL을 생성해줘' marker -> SQL block
      - draw_table_prompt (/process-data-query): contains '_EMPTY_' to opt
        into the empty-result branch, otherwise an HTML table block.
    """
    if "SQL을 생성해줘" in prompt or ("Existing Table Schemas" in prompt and "resolution_rule" not in prompt.split("\n")[0]):
        return (
            "다음 SQL을 사용하시면 됩니다:\n"
            "```sql\n"
            "CREATE TABLE total_vacation_days_remains (\n"
            "    user_id text NOT NULL,\n"
            "    days_remaining integer NOT NULL DEFAULT 0,\n"
            "    PRIMARY KEY (user_id)\n"
            ");\n"
            "```\n"
        )

    # process-data-query draw_table_prompt path (English template
    # contains "Please create an HTML table").
    if "_EMPTY_" in prompt:
        return "표로 만들 수 있는 결과가 없습니다.\n```html\n\n```\n"

    if "Please create an HTML table" in prompt or "HTML table" in prompt:
        return (
            "다음과 같이 표를 생성했습니다:\n"
            "```html\n"
            "<table>\n"
            "  <thead><tr><th>프로세스</th><th>상태</th></tr></thead>\n"
            "  <tbody><tr><td>vacation_request_process</td><td>RUNNING</td></tr></tbody>\n"
            "</table>\n"
            "```\n"
        )

    return "응답"


def _chat_envelope(text: str, model: str = "gpt-4o") -> dict:
    return {
        "id": f"chatcmpl-{int(time.time()*1000)}",
        "object": "chat.completion",
        "created": int(time.time()),
        "model": model,
        "choices": [
            {
                "index": 0,
                "message": {"role": "assistant", "content": text},
                "finish_reason": "stop",
            }
        ],
        "usage": {"prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2},
    }


class Handler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):  # noqa: A002
        return

    def _send_json(self, status: int, body: dict) -> None:
        data = json.dumps(body, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _read_json(self) -> dict:
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length) if length else b""
        if not raw:
            return {}
        try:
            return json.loads(raw.decode("utf-8"))
        except Exception:
            return {}

    def do_GET(self):  # noqa: N802
        if self.path == "/health":
            self._send_json(200, {"status": "ok"})
            return
        if self.path == "/control/last-prompt":
            with _state_lock:
                prompt = _last_prompt
            self._send_json(200, {"prompt": prompt, "length": len(prompt)})
            return
        self._send_json(404, {"error": "not found", "path": self.path})

    def do_POST(self):  # noqa: N802
        global _last_prompt
        path = self.path.split("?", 1)[0]

        if path == "/v1/embeddings":
            body = self._read_json()
            inputs = body.get("input")
            if isinstance(inputs, str):
                inputs = [inputs]
            if not isinstance(inputs, list):
                inputs = [""]
            data = [
                {"object": "embedding", "index": i, "embedding": _embed(str(t))}
                for i, t in enumerate(inputs)
            ]
            self._send_json(
                200,
                {
                    "object": "list",
                    "data": data,
                    "model": body.get("model", "text-embedding-3-small"),
                    "usage": {"prompt_tokens": 1, "total_tokens": 1},
                },
            )
            return

        if path == "/v1/chat/completions":
            body = self._read_json()
            messages = body.get("messages") or []
            prompt = "\n".join(str(m.get("content") or "") for m in messages)
            with _state_lock:
                _last_prompt = prompt
            text = _build_chat_text(prompt)
            model = body.get("model", "gpt-4o")
            if body.get("stream"):
                created = int(time.time())
                chat_id = f"chatcmpl-{int(time.time()*1000)}"
                self.send_response(200)
                self.send_header("Content-Type", "text/event-stream")
                self.send_header("Cache-Control", "no-cache")
                self.send_header("Connection", "close")
                self.end_headers()
                self.close_connection = True
                chunk = {
                    "id": chat_id,
                    "object": "chat.completion.chunk",
                    "created": created,
                    "model": model,
                    "choices": [
                        {
                            "index": 0,
                            "delta": {"role": "assistant", "content": text},
                            "finish_reason": None,
                        }
                    ],
                }
                self.wfile.write(
                    f"data: {json.dumps(chunk, ensure_ascii=False)}\n\n".encode("utf-8")
                )
                final = {
                    "id": chat_id,
                    "object": "chat.completion.chunk",
                    "created": created,
                    "model": model,
                    "choices": [{"index": 0, "delta": {}, "finish_reason": "stop"}],
                }
                self.wfile.write(
                    f"data: {json.dumps(final, ensure_ascii=False)}\n\n".encode("utf-8")
                )
                self.wfile.write(b"data: [DONE]\n\n")
                self.wfile.flush()
                return
            self._send_json(200, _chat_envelope(text, model))
            return

        self._send_json(404, {"error": "not found", "path": self.path})


def main() -> None:
    server = ThreadingHTTPServer(("0.0.0.0", 8080), Handler)
    print("[mock-llm-pdq] listening on :8080", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
