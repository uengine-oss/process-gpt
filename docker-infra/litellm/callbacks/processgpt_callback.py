"""LiteLLM 프록시 -> Process GPT 관측 콜백.

모든 LLM 트래픽이 이미 이 프록시 하나를 지나가는데, 그동안 콜백이 하나도
걸려 있지 않았다. 여기서 상관키를 뽑아 mcp-hub 로 넘기면, 같은 trace_id 로
MCP 스팬과 LLM 스팬이 한 줄로 이어진다.

상관키는 두 경로 중 하나로 온다:
  1. litellm_params.metadata  (extra_body 로 넘긴 경우)
  2. x-processgpt-trace 헤더  (프록시 요청 헤더로 넘긴 경우)
둘 다 지원한다 — 클라이언트마다 넣기 쉬운 방식이 다르기 때문.

프록시 지연에 영향을 주지 않도록 비동기 큐에 쌓아 배치로 보낸다.
상관키가 없는 호출도 버리지 않고 tenant_id='unattributed' 로 남겨,
계측 누락을 나중에 추적할 수 있게 한다.
"""
import asyncio
import json
import logging
import os
import random
import re
import time

try:
    from litellm.integrations.custom_logger import CustomLogger
except Exception:  # noqa: BLE001 - 로컬 단위 테스트용 폴백
    class CustomLogger:  # type: ignore[no-redef]
        pass

logger = logging.getLogger("processgpt_callback")

HUB_URL = os.getenv("MCP_HUB_URL", "http://mcp-hub:8500").rstrip("/")
FLUSH_INTERVAL = float(os.getenv("PROCESSGPT_LLM_FLUSH_SEC", "0.5"))
FLUSH_SIZE = int(os.getenv("PROCESSGPT_LLM_FLUSH_SIZE", "50"))
QUEUE_MAX = int(os.getenv("PROCESSGPT_LLM_QUEUE_MAX", "5000"))

_CORRELATION_KEYS = (
    "tenant_id", "trace_id", "span_id", "parent_span_id", "proc_inst_id",
    "todo_id", "job_id", "agent_id", "engine", "user_id", "capture",
)

# ---------------------------------------------------------------------------
# 프로파일러용 원문 캡처
#   off     : 보내지 않음
#   sampled : 오류·느린 호출은 항상, 나머지는 SAMPLE_RATE 확률 (기본)
#   on      : 전부
# 헤더의 capture=true 는 샘플링을 건너뛴다 (화면에서 켠 실행).
# ---------------------------------------------------------------------------
PAYLOAD_CAPTURE = os.getenv("PROCESSGPT_LLM_PAYLOAD_CAPTURE", "sampled").lower()
PAYLOAD_SAMPLE_RATE = float(os.getenv("PROCESSGPT_LLM_PAYLOAD_SAMPLE_RATE", "0.1"))
PAYLOAD_SLOW_MS = int(os.getenv("PROCESSGPT_LLM_PAYLOAD_SLOW_MS", "10000"))
PAYLOAD_MSG_CHARS = int(os.getenv("PROCESSGPT_LLM_PAYLOAD_MSG_CHARS", "4000"))
PAYLOAD_MAX_MSGS = int(os.getenv("PROCESSGPT_LLM_PAYLOAD_MAX_MSGS", "30"))
PAYLOAD_MAX_BYTES = int(os.getenv("PROCESSGPT_LLM_PAYLOAD_MAX_BYTES", str(128 * 1024)))

# mcp_trace._MASK_KEYS 와 같은 목록. 두 곳이 다른 서비스라 공유 패키지가 없어
# 복제한다 — 한쪽을 고치면 다른 쪽도 고칠 것.
_MASK_KEYS = ("password", "token", "secret", "authorization", "api_key", "apikey",
              "credential", "passwd", "private_key")

# 본문 텍스트 안에 섞여 들어온 자격증명. 키 이름 마스킹만으로는 안 잡힌다.
_SCRUB_PATTERNS = [
    re.compile(r"sk-[A-Za-z0-9_\-]{20,}"),
    re.compile(r"Bearer\s+[A-Za-z0-9._\-]{16,}"),
    re.compile(r"eyJ[\w-]+\.[\w-]+\.[\w-]+"),        # JWT
    re.compile(r"AKIA[0-9A-Z]{16}"),                    # AWS access key
]


def _scrub(text: str) -> str:
    """본문에서 자격증명 패턴을 지운다. 이메일은 업무 데이터라 두고 본다."""
    for pat in _SCRUB_PATTERNS:
        text = pat.sub("***", text)
    return text


def _mask_value(value):
    if isinstance(value, dict):
        return {
            k: ("***" if any(m in str(k).lower() for m in _MASK_KEYS)
                else _mask_value(v))
            for k, v in value.items()
        }
    if isinstance(value, list):
        return [_mask_value(v) for v in value]
    if isinstance(value, str):
        return _scrub(value)
    return value


def _header_bags(kwargs: dict):
    """LiteLLM 버전마다 원본 요청 헤더를 두는 자리가 다르다.

    proxy_server_request 가 최상위 kwargs 에 있기도 하고 litellm_params
    아래에 있기도 하며, metadata.headers 로 들어오기도 한다. 한 곳만
    보면 상관키를 놓쳐 전부 unattributed 로 떨어진다.
    """
    lp = kwargs.get("litellm_params") or {}
    md = kwargs.get("metadata") or {}
    lp_md = lp.get("metadata") or {}
    for source in (
        kwargs.get("proxy_server_request"),
        lp.get("proxy_server_request"),
        md.get("proxy_server_request"),
        lp_md.get("proxy_server_request"),
    ):
        if isinstance(source, dict) and isinstance(source.get("headers"), dict):
            yield source["headers"]
    for source in (md.get("headers"), lp_md.get("headers"), kwargs.get("headers")):
        if isinstance(source, dict):
            yield source


def _from_headers(kwargs: dict) -> dict:
    """x-processgpt-trace 헤더에서 상관키를 꺼낸다."""
    for bag in _header_bags(kwargs):
        try:
            headers = {str(k).lower(): v for k, v in bag.items()}
            raw = headers.get("x-processgpt-trace")
            if not raw:
                continue
            data = json.loads(raw) if isinstance(raw, str) else raw
            found = {k: v for k, v in data.items() if k in _CORRELATION_KEYS}
            if found:
                return found
        except Exception:  # noqa: BLE001
            continue
    return {}


def _from_metadata(kwargs: dict) -> dict:
    for container in (
        (kwargs.get("litellm_params") or {}).get("metadata") or {},
        kwargs.get("metadata") or {},
    ):
        found = {k: v for k, v in container.items() if k in _CORRELATION_KEYS and v}
        if found:
            return found
    return {}


def extract_correlation(kwargs: dict) -> dict:
    """metadata 와 헤더 두 경로를 모두 본다. metadata 가 우선.

    빈 값은 미리 걸러낸 뒤 합친다 — LiteLLM 이 metadata 에 넣어두는 빈
    키가 헤더로 들어온 진짜 값을 덮어써 버리면 안 된다.
    """
    from_headers = {k: v for k, v in _from_headers(kwargs).items() if v}
    from_metadata = {k: v for k, v in _from_metadata(kwargs).items() if v}
    return {**from_headers, **from_metadata}


def _usage(response_obj) -> dict:
    usage = getattr(response_obj, "usage", None) or {}
    if not isinstance(usage, dict):
        usage = getattr(usage, "model_dump", lambda: {})() or {}
    details = usage.get("prompt_tokens_details") or {}
    if not isinstance(details, dict):
        details = getattr(details, "model_dump", lambda: {})() or {}
    return {
        "prompt_tokens": usage.get("prompt_tokens"),
        "completion_tokens": usage.get("completion_tokens"),
        "total_tokens": usage.get("total_tokens"),
        "cache_read_tokens": details.get("cached_tokens"),
    }


def _tool_calls(response_obj) -> int | None:
    try:
        choices = getattr(response_obj, "choices", None) or []
        n = 0
        for c in choices:
            msg = getattr(c, "message", None)
            n += len(getattr(msg, "tool_calls", None) or [])
        return n
    except Exception:  # noqa: BLE001
        return None


def _tool_call_specs(response_obj) -> list:
    """모델이 요청한 tool_call 의 이름과 인자.

    build_record 는 개수만 세는데, "무엇을 어떤 인자로 부르려 했는가" 가
    프로파일링에서는 핵심이라 따로 뽑는다.
    """
    out = []
    try:
        for c in getattr(response_obj, "choices", None) or []:
            msg = getattr(c, "message", None)
            for tc in (getattr(msg, "tool_calls", None) or []):
                fn = getattr(tc, "function", None)
                out.append({
                    "id": getattr(tc, "id", None),
                    "name": getattr(fn, "name", None),
                    "arguments": getattr(fn, "arguments", None),
                })
    except Exception:  # noqa: BLE001
        pass
    return out


def _finish_reason(response_obj):
    try:
        choices = getattr(response_obj, "choices", None) or []
        return getattr(choices[0], "finish_reason", None) if choices else None
    except Exception:  # noqa: BLE001
        return None


def _completion_text(response_obj):
    try:
        choices = getattr(response_obj, "choices", None) or []
        if not choices:
            return None
        return getattr(getattr(choices[0], "message", None), "content", None)
    except Exception:  # noqa: BLE001
        return None


def should_capture(corr: dict, duration_ms, status: str) -> bool:
    if PAYLOAD_CAPTURE == "off":
        return False
    if PAYLOAD_CAPTURE == "on":
        return True
    if str(corr.get("capture")).lower() in ("true", "1"):
        return True                      # 화면에서 켠 실행은 무조건
    if status != "success":
        return True                      # 실패는 항상 — 원인 추적이 목적
    if duration_ms is not None and duration_ms >= PAYLOAD_SLOW_MS:
        return True                      # 느린 호출도 항상
    return random.random() < PAYLOAD_SAMPLE_RATE


def build_payload(kwargs, response_obj, record: dict) -> dict:
    """프롬프트·응답·모델 파라미터를 마스킹해 사이드카로 보낼 형태로 만든다."""
    messages = []
    raw_msgs = kwargs.get("messages") or []
    # 앞 2개(시스템·최초 지시)는 남기고 최근 것 위주로 자른다.
    if len(raw_msgs) > PAYLOAD_MAX_MSGS:
        raw_msgs = raw_msgs[:2] + raw_msgs[-(PAYLOAD_MAX_MSGS - 2):]
    truncated = False
    for m in raw_msgs:
        if not isinstance(m, dict):
            continue
        content = m.get("content")
        if isinstance(content, str) and len(content) > PAYLOAD_MSG_CHARS:
            content = content[:PAYLOAD_MSG_CHARS] + "…(잘림)"
            truncated = True
        messages.append(_mask_value({
            "role": m.get("role"),
            "content": content,
            "tool_calls": m.get("tool_calls"),
            "name": m.get("name"),
        }))

    # 총량 한도를 넘으면 오래된 것부터 본문을 버린다.
    blob = json.dumps(messages, ensure_ascii=False, default=str)
    orig_bytes = len(blob.encode())
    i = 0
    while len(blob.encode()) > PAYLOAD_MAX_BYTES and i < len(messages) - 2:
        messages[i]["content"] = "<용량 초과로 생략>"
        blob = json.dumps(messages, ensure_ascii=False, default=str)
        truncated = True
        i += 1

    params = kwargs.get("optional_params") or {}
    model_params = {
        k: params.get(k) for k in
        ("temperature", "max_tokens", "top_p", "tool_choice",
         "response_format", "stream", "seed")
        if params.get(k) is not None
    }
    # 툴 스키마 전체는 매 호출 반복되는 낭비라 이름만 남긴다.
    tools = params.get("tools") or []
    if tools:
        model_params["tools"] = [
            (t.get("function") or {}).get("name")
            for t in tools if isinstance(t, dict)
        ]

    return {
        "span_kind": "llm",
        "span_id": record.get("span_id"),
        "tenant_id": record.get("tenant_id"),
        "trace_id": record.get("trace_id"),
        "proc_inst_id": record.get("proc_inst_id"),
        "todo_id": record.get("todo_id"),
        "job_id": record.get("job_id"),
        "messages": messages,
        "completion": _mask_value({
            "content": _completion_text(response_obj),
            "tool_calls": _tool_call_specs(response_obj),
            "finish_reason": _finish_reason(response_obj),
        }),
        "model_params": model_params,
        "truncated": truncated,
        "orig_bytes": orig_bytes,
    }


def build_record(kwargs, response_obj, start_time, end_time, status: str) -> dict:
    corr = extract_correlation(kwargs)
    duration_ms = None
    try:
        duration_ms = int((end_time - start_time).total_seconds() * 1000)
    except Exception:  # noqa: BLE001
        pass

    model = kwargs.get("model")
    record = {
        "tenant_id": corr.get("tenant_id") or "unattributed",
        "trace_id": corr.get("trace_id"),
        "span_id": corr.get("span_id"),
        "parent_span_id": corr.get("parent_span_id"),
        "proc_inst_id": corr.get("proc_inst_id"),
        "todo_id": corr.get("todo_id"),
        "job_id": corr.get("job_id"),
        "agent_id": corr.get("agent_id"),
        "engine": corr.get("engine"),
        "call_type": kwargs.get("call_type"),
        "model": model,
        "provider": (kwargs.get("litellm_params") or {}).get("custom_llm_provider"),
        "litellm_call_id": kwargs.get("litellm_call_id"),
        "started_at": start_time.isoformat() if start_time else None,
        "finished_at": end_time.isoformat() if end_time else None,
        "duration_ms": duration_ms,
        "status": status,
        "cost_usd": kwargs.get("response_cost"),
        "tool_calls_count": _tool_calls(response_obj),
        "finish_reason": _finish_reason(response_obj),
        "model_actual": getattr(response_obj, "model", None),
        "request_id": getattr(response_obj, "id", None),
        "api_base": (kwargs.get("litellm_params") or {}).get("api_base"),
        "user_id": corr.get("user_id"),
    }
    record.update(_usage(response_obj))

    if status != "success":
        exc = kwargs.get("exception") or response_obj
        record["error_type"] = type(exc).__name__ if exc is not None else "UNKNOWN"
        record["error_message"] = str(exc)[:1000] if exc is not None else None
    return record


class _Sink:
    def __init__(self, path: str = "/ingest/llm-calls", label: str = "LLM 트레이스") -> None:
        self.path = path
        self.label = label
        self._queue: asyncio.Queue | None = None
        self._task: asyncio.Task | None = None
        self.dropped = 0
        self.unattributed = 0

    def _ensure(self):
        try:
            asyncio.get_running_loop()
        except RuntimeError:
            return None
        if self._queue is None:
            self._queue = asyncio.Queue(maxsize=QUEUE_MAX)
        if self._task is None or self._task.done():
            self._task = asyncio.create_task(self._run())
        return self._queue

    def submit(self, record: dict) -> None:
        if record.get("tenant_id") == "unattributed":
            self.unattributed += 1
            if self.unattributed % 50 == 1:
                logger.warning(
                    "상관키 없는 LLM 호출 %d건 — 클라이언트가 "
                    "x-processgpt-trace 를 넣고 있는지 확인하세요",
                    self.unattributed,
                )
        q = self._ensure()
        if q is None:
            return
        try:
            q.put_nowait(record)
        except asyncio.QueueFull:
            self.dropped += 1

    async def _run(self) -> None:
        assert self._queue is not None
        while True:
            batch = []
            try:
                batch.append(await self._queue.get())
                deadline = time.monotonic() + FLUSH_INTERVAL
                while len(batch) < FLUSH_SIZE and time.monotonic() < deadline:
                    remaining = deadline - time.monotonic()
                    if remaining <= 0:
                        break
                    try:
                        batch.append(
                            await asyncio.wait_for(self._queue.get(), remaining)
                        )
                    except asyncio.TimeoutError:
                        break
                await self._post(batch)
            except asyncio.CancelledError:
                if batch:
                    await self._post(batch)
                raise
            except Exception as exc:  # noqa: BLE001
                logger.debug("LLM 트레이스 루프 오류: %s", exc)

    async def _post(self, batch: list) -> None:
        if not batch:
            return
        try:
            import httpx

            async with httpx.AsyncClient(timeout=5) as client:
                await client.post(
                    f"{HUB_URL}{self.path}", json={"records": batch}
                )
        except Exception as exc:  # noqa: BLE001
            logger.debug("%s 전송 실패(%d건): %s", self.label, len(batch), exc)

    async def flush(self) -> None:
        if self._queue is None:
            return
        pending = []
        while not self._queue.empty():
            try:
                pending.append(self._queue.get_nowait())
            except asyncio.QueueEmpty:
                break
        await self._post(pending)


_sink = _Sink()
# 원문은 별도 경로로 — 캡처를 꺼도 스칼라 로그는 계속 흘러야 한다.
_payload_sink = _Sink("/ingest/llm-payloads", "LLM 페이로드")


class ProcessGPTLiteLLMLogger(CustomLogger):
    def _handle(self, kwargs, response_obj, start_time, end_time, status: str) -> None:
        record = build_record(kwargs, response_obj, start_time, end_time, status)
        _sink.submit(record)

        # 원문은 스팬 id 가 있어야 되짚을 수 있다. 없으면 보내봐야 못 찾는다.
        if not record.get("span_id"):
            return
        corr = extract_correlation(kwargs)
        if should_capture(corr, record.get("duration_ms"), status):
            _payload_sink.submit(build_payload(kwargs, response_obj, record))

    async def async_log_success_event(self, kwargs, response_obj, start_time, end_time):
        try:
            self._handle(kwargs, response_obj, start_time, end_time, "success")
        except Exception as exc:  # noqa: BLE001
            logger.debug("성공 이벤트 기록 실패: %s", exc)

    async def async_log_failure_event(self, kwargs, response_obj, start_time, end_time):
        try:
            self._handle(kwargs, response_obj, start_time, end_time, "error")
        except Exception as exc:  # noqa: BLE001
            logger.debug("실패 이벤트 기록 실패: %s", exc)


processgpt_handler = ProcessGPTLiteLLMLogger()
