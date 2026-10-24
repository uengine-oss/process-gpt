"""MCP · LLM 호출 집계.

집계는 전부 SQL 쪽에서 끝낸다 — 파이썬으로 끌어와 계산하면 호출 로그가
수십만 건이 되는 순간 무너진다.
"""
from typing import Any

from . import db

_RANGES = {
    "1h": "1 hour", "24h": "24 hours", "7d": "7 days", "30d": "30 days",
}


def _interval(rng: str) -> str:
    return _RANGES.get(rng, "24 hours")


async def server_stats(tenant_id: str, rng: str = "24h") -> list[dict]:
    return await db.fetch_all(
        f"""
        select c.server_name,
               c.server_id,
               count(*)::int                                             as calls,
               count(*) filter (where c.status = 'success')::int          as ok,
               count(*) filter (where c.status not in ('success','running'))::int as failed,
               round(100.0 * count(*) filter (where c.status not in ('success','running'))
                     / nullif(count(*) filter (where c.status <> 'running'), 0), 2) as error_rate,
               percentile_disc(0.50) within group (order by c.duration_ms)::int as p50_ms,
               percentile_disc(0.95) within group (order by c.duration_ms)::int as p95_ms,
               percentile_disc(0.99) within group (order by c.duration_ms)::int as p99_ms,
               max(c.started_at)                                          as last_call_at,
               (array_agg(c.error_message order by c.started_at desc)
                  filter (where c.error_message is not null))[1]          as last_error
          from public.mcp_call_log c
         where c.tenant_id = %s
           and c.started_at > now() - interval '{_interval(rng)}'
         group by c.server_name, c.server_id
         order by calls desc
        """,
        [tenant_id],
    )


async def tool_stats(tenant_id: str, rng: str = "24h", limit: int = 50) -> list[dict]:
    return await db.fetch_all(
        f"""
        select c.server_name, c.tool_name,
               count(*)::int as calls,
               count(*) filter (where c.status not in ('success','running'))::int as failed,
               round(100.0 * count(*) filter (where c.status not in ('success','running'))
                     / nullif(count(*) filter (where c.status <> 'running'), 0), 2) as error_rate,
               percentile_disc(0.50) within group (order by c.duration_ms)::int as p50_ms,
               percentile_disc(0.95) within group (order by c.duration_ms)::int as p95_ms
          from public.mcp_call_log c
         where c.tenant_id = %s
           and c.started_at > now() - interval '{_interval(rng)}'
         group by c.server_name, c.tool_name
         order by calls desc
         limit %s
        """,
        [tenant_id, limit],
    )


async def summary(tenant_id: str, rng: str = "24h") -> dict[str, Any]:
    row = await db.fetch_one(
        f"""
        select count(*)::int as calls,
               round(100.0 * count(*) filter (where c.status = 'success')
                     / nullif(count(*) filter (where c.status <> 'running'), 0), 2) as success_rate,
               percentile_disc(0.95) within group (order by c.duration_ms)::int as p95_ms,
               count(distinct c.server_id)::int as active_servers
          from public.mcp_call_log c
         where c.tenant_id = %s and c.started_at > now() - interval '{_interval(rng)}'
        """,
        [tenant_id],
    ) or {}
    health = await db.fetch_one(
        """
        select count(*) filter (where state = 'healthy')::int   as healthy,
               count(*) filter (where state = 'degraded')::int  as degraded,
               count(*) filter (where state = 'unhealthy')::int as unhealthy,
               count(*) filter (where state = 'unknown')::int   as unknown
          from public.mcp_server_health_current where tenant_id = %s
        """,
        [tenant_id],
    ) or {}
    llm = await db.fetch_one(
        f"""
        select count(*)::int as llm_calls,
               coalesce(sum(total_tokens), 0)::bigint as total_tokens,
               round(coalesce(sum(cost_usd), 0), 4) as cost_usd
          from public.llm_call_log
         where tenant_id = %s and started_at > now() - interval '{_interval(rng)}'
        """,
        [tenant_id],
    ) or {}
    servers = await db.fetch_one(
        "select count(*)::int as total, "
        "count(*) filter (where enabled and status='active')::int as enabled "
        "from public.mcp_server where tenant_id = %s and is_deleted = false",
        [tenant_id],
    ) or {}
    return {"range": rng, **row, **health, **llm, "servers": servers}


async def calls(
    tenant_id: str,
    server_id: str | None = None,
    tool_name: str | None = None,
    status: str | None = None,
    proc_inst_id: str | None = None,
    todo_id: str | None = None,
    limit: int = 100,
    offset: int = 0,
) -> list[dict]:
    return await db.fetch_all(
        """
        select id, server_id, server_name, tool_name, engine, agent_id,
               trace_id, span_id, proc_inst_id, todo_id, job_id,
               started_at, finished_at, duration_ms, status,
               error_type, error_message, input_preview, output_preview,
               input_bytes, output_bytes
          from public.mcp_call_log
         where tenant_id = %s
           and (%s::uuid is null or server_id = %s)
           and (%s::text is null or tool_name = %s)
           and (%s::text is null or status = %s)
           and (%s::text is null or proc_inst_id = %s)
           and (%s::text is null or todo_id = %s)
         order by started_at desc
         limit %s offset %s
        """,
        [tenant_id, server_id, server_id, tool_name, tool_name,
         status, status, proc_inst_id, proc_inst_id, todo_id, todo_id,
         limit, offset],
    )


async def timeseries(tenant_id: str, rng: str = "24h", bucket: str = "1 hour") -> list[dict]:
    safe_bucket = bucket if bucket in ("5 minutes", "15 minutes", "1 hour", "1 day") else "1 hour"
    return await db.fetch_all(
        f"""
        select date_bin(interval '{safe_bucket}', c.started_at, timestamptz 'epoch') as bucket,
               count(*)::int as calls,
               count(*) filter (where c.status not in ('success','running'))::int as failed,
               percentile_disc(0.95) within group (order by c.duration_ms)::int as p95_ms
          from public.mcp_call_log c
         where c.tenant_id = %s and c.started_at > now() - interval '{_interval(rng)}'
         group by bucket order by bucket
        """,
        [tenant_id],
    )


async def task_observability(tenant_id: str, todo_id: str) -> dict[str, Any]:
    """한 워크아이템의 MCP 스팬 + LLM 스팬을 함께 돌려준다."""
    mcp = await db.fetch_all(
        "select server_name, tool_name, engine, trace_id, span_id, parent_span_id, "
        "started_at, duration_ms, status, error_message, input_preview, output_preview "
        "from public.mcp_call_log where tenant_id = %s and todo_id = %s "
        "order by started_at",
        [tenant_id, todo_id],
    )
    llm = await db.fetch_all(
        "select model, provider, engine, trace_id, span_id, parent_span_id, started_at, "
        "duration_ms, status, prompt_tokens, completion_tokens, total_tokens, cost_usd "
        "from public.llm_call_log where tenant_id = %s and todo_id = %s "
        "order by started_at",
        [tenant_id, todo_id],
    )
    return {"todo_id": todo_id, "mcp_calls": mcp, "llm_calls": llm}
