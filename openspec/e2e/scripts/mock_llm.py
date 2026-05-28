"""Deterministic OpenAI-compatible mock used by the completion service in E2E.

Only the endpoints exercised by mem0 + langchain in this suite are
implemented:
  - POST /v1/embeddings        -> deterministic 1536-d vectors keyed by topic
  - POST /v1/chat/completions  -> learning / query canned responses
  - GET  /health               -> 200 ok
  - POST /control/embed-fail   -> optional failure toggle (unused here,
                                  kept for parity with other suites)

The script intentionally avoids any non-stdlib dependency so the
container can run plain ``python:3.12-slim`` without a build step.
"""
from __future__ import annotations

import hashlib
import json
import math
import re
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

EMBED_DIM = 1536

# ---------------------------------------------------------------------------
# Embedding helpers - deterministic, topic-aware vectors.
# Two messages that mention the same topic keyword collapse to (nearly) the
# same vector so cosine similarity exceeds the mem0 duplicate threshold
# (LEARNING_DUPLICATE_THRESHOLD = 0.92).
# ---------------------------------------------------------------------------
TOPIC_KEYWORDS = {
    "vacation": [
        "휴가", "연차", "월차", "반차", "vacation", "leave", "annual leave",
    ],
    "benefit": [
        "복지", "복리", "benefit", "welfare",
    ],
    "salary": [
        "급여", "월급", "연봉", "salary", "wage", "payroll",
    ],
}


def _classify(text: str) -> str:
    low = (text or "").lower()
    for topic, kws in TOPIC_KEYWORDS.items():
        for kw in kws:
            if kw.lower() in low:
                return topic
    return "default"


def _base_vec(topic: str) -> list[float]:
    """Stable unit vector seeded by topic (NOT by full text)."""
    seed = hashlib.sha256(f"topic::{topic}".encode("utf-8")).digest()
    vec: list[float] = []
    for i in range(EMBED_DIM):
        b = seed[i % len(seed)]
        # map to [-1, 1] in a stable way
        vec.append(((b / 255.0) - 0.5) * 2.0)
    norm = math.sqrt(sum(x * x for x in vec)) or 1.0
    return [x / norm for x in vec]


# Marker words that route a string onto the "B axis" so it becomes
# near-orthogonal to A-axis vectors. The completion backend uses
#   ``_is_duplicate_memory`` -> ``float(score) >= 0.92``
# against mem0's supabase provider, where ``score`` is the **cosine
# distance** returned by pgvector (0 = identical, ~1 = orthogonal).
# Routing two same-topic strings onto orthogonal axes is the
# deterministic way to exercise the duplicate-detection gate.
_B_AXIS_MARKERS = ["연차", "운영"]


def _embed(text: str) -> list[float]:
    """Deterministic, content-routed embedding.

    Strings containing any ``_B_AXIS_MARKERS`` token map to the B-axis
    (odd dimensions); all other strings map to the A-axis (even
    dimensions). cosine_distance(A, B) == 1.0 >= 0.92, which trips the
    backend duplicate gate as required by the spec scenario.
    """
    low = text or ""
    axis_idx = 1 if any(m in low for m in _B_AXIS_MARKERS) else 0
    seed = hashlib.sha256(f"axis::{axis_idx}".encode("utf-8")).digest()
    vec: list[float] = []
    for i in range(EMBED_DIM):
        if (i % 2) == axis_idx:
            b = seed[i % len(seed)]
            vec.append(((b / 255.0) - 0.5) * 2.0)
        else:
            vec.append(0.0)
    norm = math.sqrt(sum(x * x for x in vec)) or 1.0
    return [x / norm for x in vec]


# ---------------------------------------------------------------------------
# Chat-completion canned responses.
# ---------------------------------------------------------------------------
def _build_chat_text(prompt: str) -> str:
    """Return the assistant text the LLM would normally produce.

    The completion service templates several distinct prompts handled here:
      - learning_response_prompt:   contains '학습 결과:'                 (agent-memory-chat)
      - response_generation_prompt: contains '검색 결과:'                 (agent-memory-chat)
      - feedback_prompt:            contains 'provide feedback on a process' (process-definition-feedback)
      - diff_prompt:                contains 'detailed comparison of the modifiable properties' (process-definition-feedback)

    Feedback / diff responses must be wrapped in ``​```json ... ​``` ``
    fences because process_engine.CustomJsonOutputParser only accepts
    fenced JSON. The agent-memory branches keep their plain-text shape
    because mem0/langchain in that suite uses a different parser path.
    """
    # ---- process-definition-feedback: /get-feedback ------------------
    if "provide feedback on a process" in prompt:
        payload = {
            "feedback": [
                "설명을 더 구체적으로 보강해 주세요.",
                "체크포인트에 검증 단계를 추가해 주세요.",
            ]
        }
        return "```json\n" + json.dumps(payload, ensure_ascii=False) + "\n```"

    # ---- process-definition-feedback: /get-feedback-diff -------------
    if "detailed comparison of the modifiable properties" in prompt:
        payload = {
            "modifications": {
                "inputData": {"before": [], "after": [], "changed": False},
                "checkpoints": {
                    "before": ["기본 점검"],
                    "after": ["기본 점검", "추가 검증 단계"],
                    "changed": True,
                },
                "description": {
                    "before": "기본 설명",
                    "after": "피드백을 반영해 보강된 설명",
                    "changed": True,
                },
                "instruction": {
                    "before": "기본 지시",
                    "after": "보강된 상세 지시",
                    "changed": True,
                },
                "conditionExamples": {
                    "sequenceId": "seq_one_to_two",
                    "before": {"good_example": [], "bad_example": []},
                    "after": {"good_example": [], "bad_example": []},
                    "changed": False,
                },
            },
            "summary": "피드백 반영하여 설명을 보강함",
        }
        return "```json\n" + json.dumps(payload, ensure_ascii=False) + "\n```"

    if "학습 결과:" in prompt:
        if "저장함" in prompt:
            return "학습한 내용을 잘 기억해 두었습니다."
        if "비슷한 내용이 있어 저장하지 않음" in prompt:
            return "비슷한 내용이 이미 저장되어 있어 새로 저장하지 않았습니다."
        return "학습 내용을 처리했습니다."

    if "검색 결과:" in prompt:
        # Extract the user question that follows '질문:' line.
        m = re.search(r"질문:\s*(.+?)\n", prompt)
        question = m.group(1).strip() if m else "질문"
        # Return a JSON-shaped string (process_mem0_message json.loads it).
        payload = {
            "content": f"검색 결과를 바탕으로 답변드리면, {question} 에 대한 정책 정보를 메모리에서 찾았습니다.",
            "html_content": (
                "<div>검색 결과 기반 답변: "
                "<span class='search-result'>관련 메모리"
                "<span class='search-result-index'>0</span></span>"
                "</div>"
            ),
            "search_results": [
                {"index": 0, "score": 0.71, "memory": "메모리에 저장된 관련 정보"}
            ],
        }
        return json.dumps(payload, ensure_ascii=False)

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


# ---------------------------------------------------------------------------
# HTTP handler
# ---------------------------------------------------------------------------
class Handler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):  # noqa: A002 - keep stdout clean
        return

    def _send_json(self, status: int, body: dict) -> None:
        data = json.dumps(body).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
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
            prompt = "\n".join(
                str(m.get("content") or "") for m in messages
            )
            text = _build_chat_text(prompt)
            model = body.get("model", "gpt-4o")
            if body.get("stream"):
                # Emit OpenAI-compatible SSE chunks. langchain expects
                # 'choices[0].delta.content' tokens followed by [DONE].
                created = int(time.time())
                chat_id = f"chatcmpl-{int(time.time()*1000)}"
                self.send_response(200)
                self.send_header("Content-Type", "text/event-stream")
                self.send_header("Cache-Control", "no-cache")
                self.send_header("Connection", "close")
                self.end_headers()
                self.close_connection = True
                # single content chunk (langchain reassembles deltas)
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

        if path == "/control/embed-fail":
            # Accepted for parity with other suites; not used here.
            self._send_json(200, {"ok": True})
            return

        self._send_json(404, {"error": "not found", "path": self.path})


def main() -> None:
    server = ThreadingHTTPServer(("0.0.0.0", 8080), Handler)
    print("[mock-llm] listening on :8080", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
