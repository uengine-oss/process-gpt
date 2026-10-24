"""계측 수집 엔드포인트.

세 엔진(completion · deepagents · cli-agent)과 LiteLLM 콜백이 공통으로
가진 의존성은 httpx 뿐이다. 그래서 DB 쓰기는 전부 허브가 맡고, 엔진은
HTTP 로 던지기만 한다 — "DB 쓰기는 허브가 소유한다" 원칙과도 맞는다.

수집이 실패해도 절대 호출자에게 예외를 돌려주지 않는다.
"""
import json
import logging
import uuid
from datetime import datetime
from typing import Any

from pydantic import BaseModel, Field

from . import db

logger = logging.getLogger(__name__)


class MCPCallRecord(BaseModel):
    id: str | None = None
    tenant_id: str
    server_id: str | None = None
    server_name: str
    tool_name: str
    trace_id: str | None = None
    span_id: str | None = None
    parent_span_id: str | None = None
    proc_inst_id: str | None = None
    todo_id: str | None = None
    job_id: str | None = None
    agent_id: str | None = None
    user_id: str | None = None
    engine: str | None = None
    started_at: datetime | None = None
    finished_at: datetime | None = None
    duration_ms: int | None = None
    status: str = "success"
    error_type: str | None = None
    error_message: str | None = None
    input_bytes: int | None = None
    output_bytes: int | None = None
    input_preview: dict[str, Any] | None = None
    output_preview: dict[str, Any] | None = None
    emit_event: bool = True


class LLMCallRecord(BaseModel):
    tenant_id: str | None = None
    trace_id: str | None = None
    span_id: str | None = None
    parent_span_id: str | None = None
    proc_inst_id: str | None = None
    todo_id: str | None = None
    job_id: str | None = None
    agent_id: str | None = None
    engine: str | None = None
    call_type: str | None = None
    model: str | None = None
    provider: str | None = None
    litellm_call_id: str | None = None
    started_at: datetime | None = None
    finished_at: datetime | None = None
    duration_ms: int | None = None
    status: str = "success"
    prompt_tokens: int | None = None
    completion_tokens: int | None = None
    total_tokens: int | None = None
    cache_read_tokens: int | None = None
    cost_usd: float | None = None
    error_type: str | None = None
    error_message: str | None = None
    tool_calls_count: int | None = None
    raw: dict[str, Any] | None = None


class PayloadRecord(BaseModel):
    """프로파일러용 원문. llm 스팬과 mcp 스팬이 같은 테이블을 쓴다."""
    span_id: str
    span_kind: str                       # 'llm' | 'mcp'
    tenant_id: str | None = None
    trace_id: str | None = None
    proc_inst_id: str | None = None
    todo_id: str | None = None
    job_id: str | None = None
    messages: Any | None = None
    completion: Any | None = None
    model_params: Any | None = None
    tool_input: Any | None = None
    tool_output: Any | None = None
    truncated: bool = False
    orig_bytes: int | None = None


class PayloadBatch(BaseModel):
    records: list[PayloadRecord] = Field(default_factory=list)


class MCPCallBatch(BaseModel):
    records: list[MCPCallRecord] = Field(default_factory=list)


class LLMCallBatch(BaseModel):
    records: list[LLMCallRecord] = Field(default_factory=list)


async def _resolve_server_ids(records: list[MCPCallRecord]) -> dict[tuple[str, str], str]:
    """server_name -> server_id 를 한 번에 해석한다.

    엔진은 서버 이름만 알아도 되게 하고, 귀속은 허브가 붙인다.
    """
    keys = {(r.tenant_id, r.server_name) for r in records if not r.server_id}
    if not keys:
        return {}
    tenants = list({k[0] for k in keys})
    names = list({k[1] for k in keys})
    rows = await db.fetch_all(
        "select id, tenant_id, name from public.mcp_server "
        "where tenant_id = any(%s) and name = any(%s) and is_deleted = false",
        [tenants, names],
    )
    return {(r["tenant_id"], r["name"]): str(r["id"]) for r in rows}


async def record_mcp_calls(records: list[MCPCallRecord]) -> int:
    if not records:
        return 0
    lookup = await _resolve_server_ids(records)
    written = 0
    async with db.connection() as conn:
        async with conn.cursor() as cur:
            for r in records:
                sid = r.server_id or lookup.get((r.tenant_id, r.server_name))
                try:
                    await cur.execute(
                        """
                        insert into public.mcp_call_log
                          (id, tenant_id, server_id, server_name, tool_name,
                           trace_id, span_id, parent_span_id, proc_inst_id, todo_id,
                           job_id, agent_id, user_id, engine, started_at, finished_at,
                           duration_ms, status, error_type, error_message,
                           input_bytes, output_bytes, input_preview, output_preview)
                        values (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,
                                coalesce(%s, now()),%s,%s,%s,%s,%s,%s,%s,%s,%s)
                        on conflict (id) do update set
                          finished_at = excluded.finished_at,
                          duration_ms = excluded.duration_ms,
                          status = excluded.status,
                          error_type = excluded.error_type,
                          error_message = excluded.error_message,
                          output_bytes = excluded.output_bytes,
                          output_preview = excluded.output_preview
                        """,
                        [
                            r.id or str(uuid.uuid4()), r.tenant_id, sid, r.server_name,
                            r.tool_name, r.trace_id, r.span_id, r.parent_span_id,
                            r.proc_inst_id, r.todo_id, r.job_id, r.agent_id, r.user_id,
                            r.engine, r.started_at, r.finished_at, r.duration_ms,
                            r.status, r.error_type, r.error_message,
                            r.input_bytes, r.output_bytes,
                            _jsonb(r.input_preview), _jsonb(r.output_preview),
                        ],
                    )
                    written += 1
                except Exception as exc:  # noqa: BLE001
                    logger.warning("mcp_call_log 기록 실패 (%s/%s): %s",
                                   r.server_name, r.tool_name, exc)
                    continue

                if r.emit_event and r.status != "running":
                    await _emit_event(cur, r, sid)
    return written


async def _emit_event(cur, r: MCPCallRecord, server_id: str | None) -> None:
    """UI 실시간 스트림용 요약을 public.events 에 남긴다.

    tool_usage_started/finished 는 이미 8개 서비스가 일반 진행 메시지로
    쓰고 있어서 재사용하지 않고 mcp_call_* 전용 타입을 쓴다.
    """
    event_type = "mcp_call_finished" if r.status == "success" else "mcp_call_failed"
    payload = {
        "schema": "mcp.call.v1",
        "server_id": server_id,
        "server_name": r.server_name,
        "tool_name": r.tool_name,
        "trace_id": r.trace_id,
        "span_id": r.span_id,
        "parent_span_id": r.parent_span_id,
        "engine": r.engine,
        "agent_id": r.agent_id,
        "duration_ms": r.duration_ms,
        "status": r.status,
        "error_type": r.error_type,
        "error_message": r.error_message,
        "input_preview": r.input_preview,
        "output_bytes": r.output_bytes,
    }
    try:
        await cur.execute(
            """
            insert into public.events
              (id, job_id, todo_id, proc_inst_id, event_type, data, tenant_id)
            values (%s,%s,%s,%s,%s,%s,%s)
            """,
            [
                str(uuid.uuid4()),
                r.job_id or r.span_id or str(uuid.uuid4()),
                r.todo_id, r.proc_inst_id, event_type,
                json.dumps(payload, ensure_ascii=False, default=str),
                r.tenant_id,
            ],
        )
    except Exception as exc:  # noqa: BLE001
        logger.warning("events 기록 실패: %s", exc)


async def record_llm_calls(records: list[LLMCallRecord]) -> int:
    if not records:
        return 0
    written = 0
    async with db.connection() as conn:
        async with conn.cursor() as cur:
            for r in records:
                try:
                    await cur.execute(
                        """
                        insert into public.llm_call_log
                          (tenant_id, trace_id, span_id, parent_span_id, proc_inst_id,
                           todo_id, job_id, agent_id, engine, call_type, model, provider,
                           litellm_call_id, started_at, finished_at, duration_ms, status,
                           prompt_tokens, completion_tokens, total_tokens,
                           cache_read_tokens, cost_usd, error_type, error_message,
                           tool_calls_count, raw)
                        values (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,
                                %s,%s,%s,%s,%s,%s,%s,%s,%s)
                        """,
                        [
                            r.tenant_id or "unattributed", r.trace_id, r.span_id,
                            r.parent_span_id, r.proc_inst_id, r.todo_id, r.job_id,
                            r.agent_id, r.engine, r.call_type, r.model, r.provider,
                            r.litellm_call_id, r.started_at, r.finished_at,
                            r.duration_ms, r.status, r.prompt_tokens,
                            r.completion_tokens, r.total_tokens, r.cache_read_tokens,
                            r.cost_usd, r.error_type, r.error_message,
                            r.tool_calls_count, _jsonb(r.raw),
                        ],
                    )
                    written += 1
                except Exception as exc:  # noqa: BLE001
                    logger.warning("llm_call_log 기록 실패 (%s): %s", r.model, exc)
    return written


async def record_payloads(records: list[PayloadRecord]) -> int:
    """원문을 사이드카에 업서트한다.

    같은 스팬이 재전송돼도 한 행만 남는다. 실패는 삼킨다 — 프로파일링
    데이터가 없다고 업무 흐름이 막히면 안 된다.
    """
    if not records:
        return 0
    written = 0
    async with db.connection() as conn:
        async with conn.cursor() as cur:
            for r in records:
                try:
                    await cur.execute(
                        """
                        insert into public.trace_payload
                          (tenant_id, trace_id, span_id, span_kind, proc_inst_id,
                           todo_id, job_id, messages, completion, model_params,
                           tool_input, tool_output, truncated, orig_bytes)
                        values (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
                        on conflict (span_id, span_kind) do update set
                          messages = coalesce(excluded.messages, trace_payload.messages),
                          completion = coalesce(excluded.completion, trace_payload.completion),
                          model_params = coalesce(excluded.model_params, trace_payload.model_params),
                          tool_input = coalesce(excluded.tool_input, trace_payload.tool_input),
                          tool_output = coalesce(excluded.tool_output, trace_payload.tool_output),
                          truncated = excluded.truncated,
                          orig_bytes = excluded.orig_bytes
                        """,
                        [
                            r.tenant_id or "unattributed", r.trace_id, r.span_id,
                            r.span_kind, r.proc_inst_id, r.todo_id, r.job_id,
                            _jsonb(r.messages), _jsonb(r.completion),
                            _jsonb(r.model_params), _jsonb(r.tool_input),
                            _jsonb(r.tool_output), r.truncated, r.orig_bytes,
                        ],
                    )
                    written += 1
                except Exception as exc:  # noqa: BLE001
                    logger.warning("trace_payload 기록 실패 (%s/%s): %s",
                                   r.span_kind, r.span_id, exc)
    return written


def _jsonb(value: Any) -> Any:
    from psycopg.types.json import Jsonb

    return Jsonb(value) if value is not None else None
