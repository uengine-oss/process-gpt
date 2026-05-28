"""Deterministic OpenAI-compatible mock that drives the LangGraph react
agent used by completion_automated-task-execution.
"""
from __future__ import annotations

import hashlib
import json
import math
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

EMBED_DIM = 1536


def _log(msg: str) -> None:
    sys.stderr.write(f"[mock-llm-ate] {msg}\n")
    sys.stderr.flush()


def _embed(text: str) -> list[float]:
    seed = hashlib.sha256(f"automated::{text or ''}".encode("utf-8")).digest()
    vec: list[float] = []
    for i in range(EMBED_DIM):
        b = seed[i % len(seed)]
        vec.append(((b / 255.0) - 0.5) * 2.0)
    norm = math.sqrt(sum(x * x for x in vec)) or 1.0
    return [x / norm for x in vec]


def _has_tool_messages(messages):
    for m in messages or []:
        if (m or {}).get("role") == "tool":
            return True
    return False


def _build_tool_calls(tools):
    calls = []
    for idx, tool in enumerate(tools or []):
        fn = (tool or {}).get("function") or {}
        name = fn.get("name") or tool.get("name")
        if not name:
            continue
        calls.append(
            {
                "id": f"call_{idx}_{name}",
                "type": "function",
                "function": {"name": name, "arguments": "{}"},
            }
        )
    return calls


_GENERIC_JSON_REPLY = json.dumps(
    {
        # Default response shape covers run_prompt_and_parse(prompt_completed)
        # (completedActivities), check_role_binding (assignments), and any
        # other CustomJsonOutputParser caller. Empty arrays let the caller
        # fall through to its pre-LLM payloads.
        "completedActivities": [],
        "nextActivities": [],
        "assignments": [],
    },
    ensure_ascii=False,
)


def _chat_response(body):
    messages = body.get("messages") or []
    tools = body.get("tools") or []
    model = body.get("model", "gpt-4o")
    created = int(time.time())
    chat_id = f"chatcmpl-{int(time.time() * 1000)}"

    if not _has_tool_messages(messages) and tools:
        tool_calls = _build_tool_calls(tools)
        if tool_calls:
            return {
                "id": chat_id,
                "object": "chat.completion",
                "created": created,
                "model": model,
                "choices": [
                    {
                        "index": 0,
                        "message": {
                            "role": "assistant",
                            "content": "",
                            "tool_calls": tool_calls,
                        },
                        "finish_reason": "tool_calls",
                    }
                ],
                "usage": {"prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2},
            }

    # Default text body. For the MCP react-agent final turn we keep the
    # Korean confirmation; for the LangChain completion pipeline callers
    # (which run with no tools and expect JSON) we return a generic JSON
    # object so CustomJsonOutputParser succeeds.
    content = _GENERIC_JSON_REPLY if not tools else "자동 실행 결과가 워크아이템에 기록되었습니다."

    return {
        "id": chat_id,
        "object": "chat.completion",
        "created": created,
        "model": model,
        "choices": [
            {
                "index": 0,
                "message": {"role": "assistant", "content": content},
                "finish_reason": "stop",
            }
        ],
        "usage": {"prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2},
    }


class Handler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):  # noqa: A002
        try:
            _log(format % args)
        except Exception:
            pass

    def _send_json(self, status, body):
        data = json.dumps(body, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _read_json(self):
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
        self._send_json(404, {"error": "not found", "path": self.path})

    def do_POST(self):  # noqa: N802
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
            tools = body.get("tools") or []
            stream = bool(body.get("stream"))
            _log(
                f"chat: messages={len(messages)} tools={len(tools)} "
                f"stream={stream} has_tool_msg={_has_tool_messages(messages)}"
            )
            resp = _chat_response(body)
            if not stream:
                self._send_json(200, resp)
                return
            # Stream SSE for LangChain ChatOpenAI(streaming=True)
            choice = (resp.get("choices") or [{}])[0]
            msg = choice.get("message") or {}
            content = msg.get("content") or ""
            tool_calls = msg.get("tool_calls")
            model = resp.get("model")
            created = resp.get("created")
            chat_id = resp.get("id")
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-cache")
            self.send_header("Connection", "close")
            self.end_headers()
            self.close_connection = True
            if tool_calls:
                delta = {"role": "assistant", "tool_calls": tool_calls}
                finish = "tool_calls"
            else:
                delta = {"role": "assistant", "content": content}
                finish = "stop"
            chunk = {
                "id": chat_id,
                "object": "chat.completion.chunk",
                "created": created,
                "model": model,
                "choices": [{"index": 0, "delta": delta, "finish_reason": None}],
            }
            self.wfile.write(
                f"data: {json.dumps(chunk, ensure_ascii=False)}\n\n".encode("utf-8")
            )
            final = {
                "id": chat_id,
                "object": "chat.completion.chunk",
                "created": created,
                "model": model,
                "choices": [{"index": 0, "delta": {}, "finish_reason": finish}],
            }
            self.wfile.write(
                f"data: {json.dumps(final, ensure_ascii=False)}\n\n".encode("utf-8")
            )
            self.wfile.write(b"data: [DONE]\n\n")
            self.wfile.flush()
            return
        self._send_json(404, {"error": "not found", "path": self.path})


def main():
    server = ThreadingHTTPServer(("0.0.0.0", 8080), Handler)
    print("[mock-llm-ate] listening on :8080", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
