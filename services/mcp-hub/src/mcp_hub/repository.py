"""정본 테이블에 대한 데이터 접근.

여기가 enabled / 권한 / 상태 필터가 실제로 강제되는 유일한 곳이다.
세 엔진(completion, deepagents, cli-agent)은 모두 resolve_agent_tools()
를 거치므로 플래그 준수가 구조적으로 보장된다.
"""
import logging
from typing import Any
from uuid import UUID

from . import db
from .validator_client import config_hash, sanitize_tool_name, validator_client

logger = logging.getLogger(__name__)

_SERVER_COLS = """
    s.id, s.tenant_id, s.name, s.display_name, s.description, s.category,
    s.tags, s.department_id, s.owner_email, s.doc_url, s.status, s.enabled,
    s.is_default, s.source, s.source_ref, s.current_version_id,
    s.created_at, s.updated_at
"""


# --------------------------------------------------------------------------
# 조회
# --------------------------------------------------------------------------
async def list_servers(
    tenant_id: str,
    category: str | None = None,
    department_id: str | None = None,
    status: str | None = None,
    health_state: str | None = None,
    q: str | None = None,
) -> list[dict]:
    sql = f"""
        select {_SERVER_COLS},
               v.version, v.transport,
               (select count(*) from public.mcp_tool t
                 where t.server_id = s.id and t.is_available) as tool_count,
               h.state as health_state, h.checked_at as health_checked_at,
               h.latency_ms, h.consecutive_failures, h.availability_24h,
               h.error_message as health_error,
               coalesce(st.calls, 0)      as calls_24h,
               st.error_rate               as error_rate_24h,
               st.p95_ms                   as p95_ms
          from public.mcp_server s
          left join public.mcp_server_version v on v.id = s.current_version_id
          left join public.mcp_server_health_current h on h.server_id = s.id
          left join lateral (
              select count(*)::int as calls,
                     round(100.0 * count(*) filter (where c.status <> 'success')
                           / nullif(count(*), 0), 2) as error_rate,
                     percentile_disc(0.95) within group (order by c.duration_ms)::int as p95_ms
                from public.mcp_call_log c
               where c.server_id = s.id
                 and c.started_at > now() - interval '24 hours'
          ) st on true
         where s.tenant_id = %s
           and s.is_deleted = false
           and (%s::text is null or s.category = %s)
           and (%s::text is null or s.department_id = %s)
           and (%s::text is null or s.status::text = %s)
           and (%s::text is null or coalesce(h.state::text, 'unknown') = %s)
           and (%s::text is null or s.name ilike '%%' || %s || '%%'
                                 or coalesce(s.description, '') ilike '%%' || %s || '%%')
         order by s.name
    """
    params = [
        tenant_id,
        category, category,
        department_id, department_id,
        status, status,
        health_state, health_state,
        q, q, q,
    ]
    return await db.fetch_all(sql, params)


async def get_server(tenant_id: str, server_id: UUID) -> dict | None:
    rows = await db.fetch_all(
        f"""
        select {_SERVER_COLS},
               v.version, v.transport, v.command, v.args, v.url, v.headers,
               v.env, v.timeout_ms, v.semver, v.config_hash, v.validated_at,
               h.state as health_state, h.checked_at as health_checked_at,
               h.latency_ms, h.consecutive_failures, h.availability_24h,
               h.error_message as health_error,
               (select count(*) from public.mcp_tool t
                 where t.server_id = s.id and t.is_available) as tool_count
          from public.mcp_server s
          left join public.mcp_server_version v on v.id = s.current_version_id
          left join public.mcp_server_health_current h on h.server_id = s.id
         where s.tenant_id = %s and s.id = %s and s.is_deleted = false
        """,
        [tenant_id, server_id],
    )
    return rows[0] if rows else None


async def get_server_by_name(tenant_id: str, name: str) -> dict | None:
    rows = await db.fetch_all(
        "select id, name from public.mcp_server "
        "where tenant_id = %s and name = %s and is_deleted = false",
        [tenant_id, name],
    )
    return rows[0] if rows else None


async def list_tools(tenant_id: str, server_id: UUID | None = None) -> list[dict]:
    return await db.fetch_all(
        """
        select t.id, t.server_id, s.name as server_name, t.tool_name,
               t.sanitized_name, t.description, t.input_schema, t.annotations,
               t.is_available, t.last_seen_at
          from public.mcp_tool t
          join public.mcp_server s on s.id = t.server_id
         where t.tenant_id = %s
           and (%s::uuid is null or t.server_id = %s)
           and s.is_deleted = false
         order by s.name, t.tool_name
        """,
        [tenant_id, server_id, server_id],
    )


async def search_tools(tenant_id: str, q: str | None, category: str | None) -> list[dict]:
    return await db.fetch_all(
        """
        select t.id, t.server_id, s.name as server_name, s.category,
               t.tool_name, t.sanitized_name, t.description, t.input_schema,
               t.annotations, t.is_available
          from public.mcp_tool t
          join public.mcp_server s on s.id = t.server_id
         where t.tenant_id = %s
           and s.is_deleted = false
           and (%s::text is null or s.category = %s)
           and (%s::text is null
                or t.tool_name ilike '%%' || %s || '%%'
                or coalesce(t.description, '') ilike '%%' || %s || '%%'
                or s.name ilike '%%' || %s || '%%')
         order by s.name, t.tool_name
        """,
        [tenant_id, category, category, q, q, q, q],
    )


# --------------------------------------------------------------------------
# 엔진용 단일 게이트 — enabled / status / 권한이 여기서 강제된다
# --------------------------------------------------------------------------
async def resolve_agent_tools(
    tenant_id: str, agent_id: str, department_id: str | None = None
) -> list[dict]:
    """에이전트가 실제로 쓸 수 있는 서버와 툴만 반환한다.

    적용되는 필터:
      - 서버가 삭제되지 않았고 status='active'
      - 서버 enabled = true                (기존에 아무도 안 읽던 플래그)
      - 바인딩 enabled = true
      - mcp_can_use(...) 권한 통과
      - 바인딩/권한의 allowed_tools · denied_tools 화이트/블랙리스트
    """
    rows = await db.fetch_all(
        """
        select s.id           as server_id,
               s.name         as server_name,
               v.transport, v.command, v.args, v.url, v.headers, v.env,
               v.timeout_ms,
               b.allowed_tools as binding_allowed
          from public.mcp_agent_binding b
          join public.mcp_server s          on s.id = b.server_id
          join public.mcp_server_version v  on v.id = s.current_version_id
         where b.tenant_id = %s
           and b.agent_id  = %s
           and b.enabled   = true
           and s.is_deleted = false
           and s.status = 'active'
           and s.enabled = true
           and public.mcp_can_use(s.id, %s, %s)
         order by s.name
        """,
        [tenant_id, agent_id, agent_id, department_id],
    )
    if not rows:
        return []

    server_ids = [r["server_id"] for r in rows]
    tools = await db.fetch_all(
        """
        select t.server_id, t.tool_name, t.sanitized_name, t.description,
               t.input_schema, t.annotations
          from public.mcp_tool t
         where t.server_id = any(%s) and t.is_available = true
        """,
        [server_ids],
    )
    perms = await db.fetch_all(
        """
        select server_id, allowed_tools, denied_tools
          from public.mcp_server_permission
         where server_id = any(%s)
        """,
        [server_ids],
    )

    denied: dict[Any, set[str]] = {}
    perm_allowed: dict[Any, set[str] | None] = {}
    for p in perms:
        sid = p["server_id"]
        denied.setdefault(sid, set()).update(p["denied_tools"] or [])
        if p["allowed_tools"] is not None:
            perm_allowed.setdefault(sid, set()).update(p["allowed_tools"])

    by_server: dict[Any, list[dict]] = {}
    for t in tools:
        by_server.setdefault(t["server_id"], []).append(t)

    result = []
    for r in rows:
        sid = r["server_id"]
        allow_binding = set(r["binding_allowed"]) if r["binding_allowed"] else None
        allow_perm = perm_allowed.get(sid)
        deny = denied.get(sid, set())

        visible = []
        for t in by_server.get(sid, []):
            name = t["tool_name"]
            if name in deny:
                continue
            if allow_binding is not None and name not in allow_binding:
                continue
            if allow_perm is not None and name not in allow_perm:
                continue
            visible.append(
                {
                    "tool_name": name,
                    "sanitized_name": t["sanitized_name"],
                    "description": t["description"],
                    "input_schema": t["input_schema"],
                    "annotations": t["annotations"],
                }
            )

        result.append(
            {
                "server_id": str(sid),
                "server_name": r["server_name"],
                "connection": {
                    "transport": r["transport"],
                    "command": r["command"],
                    "args": r["args"] or [],
                    "url": r["url"],
                    "headers": r["headers"] or {},
                    "env": r["env"] or {},
                    "timeout_ms": r["timeout_ms"],
                },
                "allowed_tools": sorted(
                    {t["tool_name"] for t in visible}
                ) if (allow_binding is not None or allow_perm is not None or deny) else None,
                "tools": visible,
            }
        )
    return result


# --------------------------------------------------------------------------
# 쓰기
# --------------------------------------------------------------------------
async def create_server(tenant_id: str, payload: dict, actor: str | None) -> UUID:
    conn = payload["connection"]
    async with db.connection() as c:
        async with c.cursor() as cur:
            await cur.execute(
                """
                insert into public.mcp_server
                  (tenant_id, name, display_name, description, category, tags,
                   department_id, owner_email, doc_url, status, enabled,
                   source, source_ref, created_by, updated_by)
                values (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
                returning id
                """,
                [
                    tenant_id, payload["name"], payload.get("display_name"),
                    payload.get("description"), payload.get("category"),
                    payload.get("tags") or [], payload.get("department_id"),
                    payload.get("owner_email"), payload.get("doc_url"),
                    payload.get("status", "active"), payload.get("enabled", True),
                    payload.get("source", "manual"), payload.get("source_ref"),
                    actor, actor,
                ],
            )
            server_id = (await cur.fetchone())[0]

            await cur.execute(
                """
                insert into public.mcp_server_version
                  (server_id, tenant_id, version, semver, transport, command,
                   args, url, headers, env, timeout_ms, config_hash,
                   change_note, created_by)
                values (%s,%s,1,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
                returning id
                """,
                [
                    server_id, tenant_id, conn.get("semver"), conn["transport"],
                    conn.get("command"), _json(conn.get("args") or []),
                    conn.get("url"), _json(conn.get("headers") or {}),
                    _json(conn.get("env") or {}), conn.get("timeout_ms", 30000),
                    config_hash(conn), "최초 등록", actor,
                ],
            )
            version_id = (await cur.fetchone())[0]
            await cur.execute(
                "update public.mcp_server set current_version_id = %s where id = %s",
                [version_id, server_id],
            )
    return server_id


async def import_jsonb(
    tenant_id: str, mcp_servers: dict, actor: str | None, prune: bool = True
) -> dict:
    """레거시 {"mcpServers": {...}} 블롭을 정본 테이블에 반영한다.

    JSON 을 통째로 붙여넣는 기존 방식을 그대로 쓰되, 결과가 tenants.mcp 가
    아니라 mcp_server/mcp_server_version 에 남게 한다. 그래야 버전·권한·
    관측이 붙고, sync 트리거가 나중에 덮어써 유실되는 일이 없다.

    - 새 이름   -> 서버 생성 (v1)
    - 기존 이름 -> 연결정보가 바뀐 경우에만 새 버전
    - 빠진 이름 -> prune 이면 소프트 삭제
    """
    created, updated, unchanged, removed = [], [], [], []

    existing = {
        r["name"]: r
        for r in await db.fetch_all(
            "select id, name from public.mcp_server "
            "where tenant_id = %s and is_deleted = false",
            [tenant_id],
        )
    }

    for name, spec in (mcp_servers or {}).items():
        if not isinstance(spec, dict):
            continue
        conn = _conn_from_legacy(spec)
        enabled = spec.get("enabled", True) is not False

        if name not in existing:
            await create_server(
                tenant_id,
                {
                    "name": name,
                    "description": spec.get("description"),
                    "status": "active",
                    "enabled": enabled,
                    "source": "manual",
                    "connection": conn,
                },
                actor,
            )
            created.append(name)
            continue

        server_id = existing[name]["id"]
        result = await add_version(
            tenant_id, server_id, conn, "JSON 편집으로 갱신", actor
        )
        await db.execute(
            "update public.mcp_server set enabled = %s, updated_by = %s where id = %s",
            [enabled, actor, server_id],
        )
        (unchanged if result.get("reused") else updated).append(name)

    if prune:
        for name, row in existing.items():
            if name not in (mcp_servers or {}):
                await soft_delete(tenant_id, row["id"])
                removed.append(name)

    return {
        "created": created, "updated": updated,
        "unchanged": unchanged, "removed": removed,
    }


def _conn_from_legacy(spec: dict) -> dict:
    """레거시 항목을 연결정보로 정규화한다 (백필과 같은 규칙)."""
    if (spec.get("command") or "").strip():
        transport = "stdio"
    else:
        raw = (spec.get("type") or "").strip()
        transport = {
            "http": "streamable-http",
            "streamable_http": "streamable-http",
            "streamable-http": "streamable-http",
            "sse": "sse",
            "stdio": "stdio",
        }.get(raw, "streamable-http" if spec.get("url") else "stdio")
    return {
        "transport": transport,
        "command": spec.get("command"),
        "args": list(spec.get("args") or []),
        "url": spec.get("url"),
        "headers": dict(spec.get("headers") or {}),
        "env": dict(spec.get("env") or {}),
        "timeout_ms": int(spec.get("timeout_ms") or 30000),
    }


async def export_jsonb(tenant_id: str) -> dict:
    """정본 테이블을 레거시 JSON 형태로 내보낸다 (편집기 초기값)."""
    row = await db.fetch_one(
        "select public.mcp_servers_jsonb(%s) as blob", [tenant_id]
    )
    return (row or {}).get("blob") or {"mcpServers": {}}


async def add_version(
    tenant_id: str, server_id: UUID, conn: dict, note: str | None, actor: str | None
) -> dict:
    """새 연결정보 버전을 만들고 current 로 승격한다."""
    new_hash = config_hash(conn)
    existing = await db.fetch_one(
        "select id, version from public.mcp_server_version "
        "where server_id = %s and config_hash = %s order by version desc limit 1",
        [server_id, new_hash],
    )
    if existing:
        # 같은 내용이면 새 버전을 만들지 않고 기존 버전으로 되돌린다
        await db.execute(
            "update public.mcp_server set current_version_id = %s, updated_by = %s where id = %s",
            [existing["id"], actor, server_id],
        )
        return {"id": existing["id"], "version": existing["version"], "reused": True}

    async with db.connection() as c:
        async with c.cursor() as cur:
            await cur.execute(
                "select coalesce(max(version), 0) + 1 from public.mcp_server_version "
                "where server_id = %s",
                [server_id],
            )
            next_version = (await cur.fetchone())[0]
            await cur.execute(
                """
                insert into public.mcp_server_version
                  (server_id, tenant_id, version, semver, transport, command,
                   args, url, headers, env, timeout_ms, config_hash,
                   change_note, created_by)
                values (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
                returning id
                """,
                [
                    server_id, tenant_id, next_version, conn.get("semver"),
                    conn["transport"], conn.get("command"),
                    _json(conn.get("args") or []), conn.get("url"),
                    _json(conn.get("headers") or {}), _json(conn.get("env") or {}),
                    conn.get("timeout_ms", 30000), new_hash, note, actor,
                ],
            )
            version_id = (await cur.fetchone())[0]
            await cur.execute(
                "update public.mcp_server set current_version_id = %s, updated_by = %s where id = %s",
                [version_id, actor, server_id],
            )
    return {"id": version_id, "version": next_version, "reused": False}


async def activate_version(server_id: UUID, version: int) -> bool:
    row = await db.fetch_one(
        "select id from public.mcp_server_version where server_id = %s and version = %s",
        [server_id, version],
    )
    if not row:
        return False
    await db.execute(
        "update public.mcp_server set current_version_id = %s where id = %s",
        [row["id"], server_id],
    )
    return True


async def list_versions(server_id: UUID) -> list[dict]:
    return await db.fetch_all(
        """
        select id, version, semver, transport, command, args, url, headers,
               env, timeout_ms, config_hash, change_note, validated_at,
               created_at, created_by
          from public.mcp_server_version
         where server_id = %s
         order by version desc
        """,
        [server_id],
    )


async def patch_server(tenant_id: str, server_id: UUID, patch: dict, actor: str | None) -> bool:
    fields, params = [], []
    for col in (
        "display_name", "description", "category", "tags", "department_id",
        "owner_email", "doc_url", "status", "enabled",
    ):
        if col in patch and patch[col] is not None:
            fields.append(f"{col} = %s")
            params.append(patch[col])
    if not fields:
        return False
    fields.append("updated_by = %s")
    params.extend([actor, tenant_id, server_id])
    n = await db.execute(
        f"update public.mcp_server set {', '.join(fields)} "
        f"where tenant_id = %s and id = %s and is_deleted = false",
        params,
    )
    return n > 0


async def soft_delete(tenant_id: str, server_id: UUID) -> bool:
    n = await db.execute(
        "update public.mcp_server set is_deleted = true, deleted_at = now() "
        "where tenant_id = %s and id = %s and is_deleted = false",
        [tenant_id, server_id],
    )
    return n > 0


async def sync_tools(
    tenant_id: str, server_id: UUID, version_id: UUID | None, tools: list[dict]
) -> int:
    """tools/list 결과를 카탈로그에 반영한다.

    사라진 툴은 지우지 않고 is_available=false 로 남긴다 — 과거 호출 로그의
    맥락이 필요하고, 일시적 장애로 목록이 비었을 때 카탈로그가 날아가면 안 된다.
    """
    names = [t.get("name") for t in tools if t.get("name")]
    async with db.connection() as c:
        async with c.cursor() as cur:
            for t in tools:
                name = t.get("name")
                if not name:
                    continue
                await cur.execute(
                    """
                    insert into public.mcp_tool
                      (server_id, version_id, tenant_id, tool_name, sanitized_name,
                       description, input_schema, annotations, is_available, last_seen_at)
                    values (%s,%s,%s,%s,%s,%s,%s,%s,true, now())
                    on conflict (server_id, tool_name) do update set
                      version_id = excluded.version_id,
                      description = excluded.description,
                      input_schema = excluded.input_schema,
                      annotations = excluded.annotations,
                      sanitized_name = excluded.sanitized_name,
                      is_available = true,
                      last_seen_at = now()
                    """,
                    [
                        server_id, version_id, tenant_id, name,
                        sanitize_tool_name(name), t.get("description"),
                        _json(t.get("parameters")), _json(t.get("annotations")),
                    ],
                )
            if names:
                await cur.execute(
                    "update public.mcp_tool set is_available = false "
                    "where server_id = %s and not (tool_name = any(%s))",
                    [server_id, names],
                )
    return len(names)


async def validate_and_sync(tenant_id: str, server_id: UUID) -> dict:
    """연결 검증 -> 툴 카탈로그 갱신 -> 헬스 기록까지 한 번에."""
    srv = await get_server(tenant_id, server_id)
    if not srv:
        raise LookupError("서버를 찾을 수 없습니다")

    conn = {
        "transport": srv["transport"],
        "command": srv["command"],
        "args": srv["args"] or [],
        "url": srv["url"],
        "headers": srv["headers"] or {},
        "env": srv["env"] or {},
    }
    result = await validator_client.validate(srv["name"], conn)
    tools = result.get("tools") or []

    if result.get("status") == "success":
        await sync_tools(tenant_id, server_id, srv["current_version_id"], tools)
        await db.execute(
            "update public.mcp_server_version set validated_at = now(), "
            "validation_result = %s where id = %s",
            [_json(result), srv["current_version_id"]],
        )

    latency_ms = int((result.get("validation_time") or 0) * 1000) or None
    await record_health(
        tenant_id,
        server_id,
        status=result.get("status", "error"),
        latency_ms=latency_ms,
        tool_count=len(tools),
        error_message=result.get("error_message"),
    )
    return result


async def record_health(
    tenant_id: str,
    server_id: UUID,
    status: str,
    latency_ms: int | None,
    tool_count: int | None,
    error_message: str | None,
    protocol_version: str | None = None,
) -> str:
    """헬스 이력 + 현재상태 갱신. 상태가 바뀌면 events 에 알린다."""
    from .config import HEALTH_DEGRADED_MS

    if status == "success":
        state = "degraded" if (latency_ms or 0) > HEALTH_DEGRADED_MS else "healthy"
    elif status == "timeout":
        state = "unhealthy"
    else:
        state = "unhealthy"

    prev = await db.fetch_one(
        "select state, consecutive_failures from public.mcp_server_health_current "
        "where server_id = %s",
        [server_id],
    )
    prev_state = prev["state"] if prev else "unknown"
    failures = (prev["consecutive_failures"] if prev else 0)
    failures = 0 if state in ("healthy", "degraded") else failures + 1

    async with db.connection() as c:
        async with c.cursor() as cur:
            await cur.execute(
                """
                insert into public.mcp_server_health
                  (server_id, tenant_id, state, latency_ms, tool_count,
                   protocol_version, error_message)
                values (%s,%s,%s,%s,%s,%s,%s)
                """,
                [server_id, tenant_id, state, latency_ms, tool_count,
                 protocol_version, error_message],
            )
            await cur.execute(
                """
                select round(100.0 * count(*) filter (where state in ('healthy','degraded'))
                             / nullif(count(*), 0), 2)
                  from public.mcp_server_health
                 where server_id = %s and checked_at > now() - interval '24 hours'
                """,
                [server_id],
            )
            availability = (await cur.fetchone())[0]
            await cur.execute(
                """
                insert into public.mcp_server_health_current
                  (server_id, tenant_id, state, checked_at, latency_ms,
                   tool_count, consecutive_failures, availability_24h, error_message)
                values (%s,%s,%s, now(), %s,%s,%s,%s,%s)
                on conflict (server_id) do update set
                  state = excluded.state, checked_at = excluded.checked_at,
                  latency_ms = excluded.latency_ms, tool_count = excluded.tool_count,
                  consecutive_failures = excluded.consecutive_failures,
                  availability_24h = excluded.availability_24h,
                  error_message = excluded.error_message
                """,
                [server_id, tenant_id, state, latency_ms, tool_count,
                 failures, availability, error_message],
            )

    if state != prev_state:
        await emit_health_event(tenant_id, server_id, prev_state, state, error_message)
    return state


async def emit_health_event(
    tenant_id: str, server_id: UUID, prev: str, state: str, error: str | None
) -> None:
    """상태 전이를 public.events 에 남겨 UI 가 실시간으로 받게 한다."""
    import json as _json_mod
    import uuid as _uuid

    srv = await db.fetch_one(
        "select name from public.mcp_server where id = %s", [server_id]
    )
    payload = {
        "schema": "mcp.health.v1",
        "server_id": str(server_id),
        "server_name": srv["name"] if srv else None,
        "previous_state": prev,
        "state": state,
        "error_message": error,
    }
    try:
        await db.execute(
            """
            insert into public.events (id, job_id, event_type, data, tenant_id)
            values (%s, %s, 'mcp_server_health_changed', %s, %s)
            """,
            [str(_uuid.uuid4()), f"mcp-health-{server_id}",
             _json_mod.dumps(payload, ensure_ascii=False), tenant_id],
        )
    except Exception as exc:  # noqa: BLE001
        logger.warning("헬스 이벤트 기록 실패: %s", exc)


# --------------------------------------------------------------------------
# 권한 · 바인딩
# --------------------------------------------------------------------------
async def get_permissions(server_id: UUID) -> list[dict]:
    return await db.fetch_all(
        "select principal_type, principal_id, permission, allowed_tools, denied_tools "
        "from public.mcp_server_permission where server_id = %s "
        "order by principal_type, principal_id",
        [server_id],
    )


async def set_permissions(tenant_id: str, server_id: UUID, entries: list[dict]) -> int:
    async with db.connection() as c:
        async with c.cursor() as cur:
            await cur.execute(
                "delete from public.mcp_server_permission where server_id = %s", [server_id]
            )
            for e in entries:
                await cur.execute(
                    """
                    insert into public.mcp_server_permission
                      (server_id, tenant_id, principal_type, principal_id,
                       permission, allowed_tools, denied_tools)
                    values (%s,%s,%s,%s,%s,%s,%s)
                    """,
                    [
                        server_id, tenant_id, e["principal_type"],
                        e.get("principal_id"), e.get("permission", "use"),
                        e.get("allowed_tools"), e.get("denied_tools") or [],
                    ],
                )
    return len(entries)


async def set_agent_bindings(tenant_id: str, agent_id: str, bindings: list[dict]) -> int:
    """바인딩 테이블과 users.tools CSV 를 한 트랜잭션에서 함께 갱신한다.

    전환기 동안 두 표현이 갈라지면 엔진마다 다른 툴을 보게 되므로
    반드시 같이 움직여야 한다.
    """
    async with db.connection() as c:
        async with c.cursor() as cur:
            await cur.execute(
                "delete from public.mcp_agent_binding where tenant_id = %s and agent_id = %s",
                [tenant_id, agent_id],
            )
            for b in bindings:
                await cur.execute(
                    """
                    insert into public.mcp_agent_binding
                      (tenant_id, agent_id, server_id, allowed_tools, enabled)
                    values (%s,%s,%s,%s,%s)
                    on conflict (agent_id, server_id) do update set
                      allowed_tools = excluded.allowed_tools,
                      enabled = excluded.enabled
                    """,
                    [tenant_id, agent_id, b["server_id"],
                     b.get("allowed_tools"), b.get("enabled", True)],
                )
            await cur.execute(
                """
                update public.users u
                   set tools = coalesce((
                         select string_agg(s.name, ',' order by s.name)
                           from public.mcp_agent_binding b
                           join public.mcp_server s on s.id = b.server_id
                          where b.agent_id = u.id::text and b.tenant_id = u.tenant_id
                            and b.enabled and s.is_deleted = false
                       ), '')
                 where u.id::text = %s and u.tenant_id = %s
                """,
                [agent_id, tenant_id],
            )
    return len(bindings)


async def get_agent_bindings(tenant_id: str, agent_id: str) -> list[dict]:
    return await db.fetch_all(
        """
        select b.server_id, s.name as server_name, b.allowed_tools, b.enabled
          from public.mcp_agent_binding b
          join public.mcp_server s on s.id = b.server_id
         where b.tenant_id = %s and b.agent_id = %s and s.is_deleted = false
         order by s.name
        """,
        [tenant_id, agent_id],
    )


def _json(value: Any) -> Any:
    """psycopg 에 jsonb 로 넘기기 위한 어댑터."""
    import json as _j

    from psycopg.types.json import Jsonb

    if value is None:
        return None
    if isinstance(value, (dict, list)):
        return Jsonb(value)
    if isinstance(value, str):
        try:
            return Jsonb(_j.loads(value))
        except Exception:  # noqa: BLE001
            return Jsonb(value)
    return Jsonb(value)
