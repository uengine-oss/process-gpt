"""MCP Hub API.

경로는 게이트웨이에서 /api/mcp-hub/** 로 노출된다.
테넌트는 X-Tenant-Id 헤더 또는 tenant_id 쿼리로 받는다 — 게이트웨이가
JWT 에서 뽑아 넣어주거나, 서비스 간 호출에서는 직접 지정한다.
"""
import logging
from typing import Any
from uuid import UUID

from fastapi import Depends, FastAPI, Header, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware

from . import (
    catalog, db, health_scheduler, ingest, observability, repository, retention,
)
from .config import PORT
from .models import (
    AgentBinding, CatalogInstall, ConnectionConfig, PermissionEntry,
    JsonImport, ServerCreate, ServerPatch, VersionCreate,
)
from .validator_client import validator_client

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(
    title="MCP Hub",
    description="MCP 서버 등록·버전·권한·헬스·관측을 소유하는 서비스",
    version="0.1.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.on_event("startup")
async def _startup() -> None:
    await db.open_pool()
    health_scheduler.start()
    retention.start()


@app.on_event("shutdown")
async def _shutdown() -> None:
    await health_scheduler.stop()
    await retention.stop()
    await db.close_pool()


async def tenant(
    x_tenant_id: str | None = Header(default=None, alias="X-Tenant-Id"),
    tenant_id: str | None = Query(default=None),
) -> str:
    t = x_tenant_id or tenant_id
    if not t:
        raise HTTPException(400, "테넌트를 알 수 없습니다. X-Tenant-Id 헤더를 넣어주세요.")
    return t


async def actor(x_user_email: str | None = Header(default=None, alias="X-User-Email")) -> str | None:
    return x_user_email


# ---------------------------------------------------------------- health
@app.get("/health")
async def health() -> dict[str, Any]:
    validator_ok = await validator_client.ping()
    try:
        await db.fetch_one("select 1 as ok")
        db_ok = True
    except Exception:  # noqa: BLE001
        db_ok = False
    return {
        "status": "healthy" if db_ok else "degraded",
        "service": "mcp-hub",
        "database": db_ok,
        "validator": validator_ok,
    }


# ---------------------------------------------------------------- servers
@app.get("/servers")
async def list_servers(
    t: str = Depends(tenant),
    category: str | None = None,
    department_id: str | None = None,
    status: str | None = None,
    health_state: str | None = None,
    q: str | None = None,
) -> list[dict]:
    return await repository.list_servers(t, category, department_id, status, health_state, q)


@app.post("/servers", status_code=201)
async def create_server(
    body: ServerCreate,
    t: str = Depends(tenant),
    who: str | None = Depends(actor),
    dry_run: bool = Query(False, description="검증만 하고 저장하지 않는다"),
) -> dict[str, Any]:
    try:
        body.connection.require_complete()
    except ValueError as exc:
        raise HTTPException(422, str(exc)) from exc

    conn = body.connection.model_dump()

    if dry_run or body.validate_on_create:
        result = await validator_client.validate(body.name, conn)
        if dry_run:
            return {"dry_run": True, "validation": result}
        if result.get("status") != "success" and not result.get("unreachable_validator"):
            # 연결이 안 되는 서버도 draft 로는 남길 수 있게 한다
            logger.info("검증 실패로 draft 저장: %s — %s", body.name, result.get("error_message"))
            body.status = "draft"

    if await repository.get_server_by_name(t, body.name):
        raise HTTPException(409, f"'{body.name}' 이름의 서버가 이미 있습니다")

    payload = body.model_dump()
    payload["connection"] = conn
    server_id = await repository.create_server(t, payload, who)

    if body.validate_on_create:
        try:
            await repository.validate_and_sync(t, server_id)
        except Exception as exc:  # noqa: BLE001
            logger.warning("등록 후 툴 동기화 실패: %s", exc)

    return await repository.get_server(t, server_id) or {"id": str(server_id)}


# ---------------------------------------------------------------- JSON 편집
@app.get("/servers/export")
async def export_servers(t: str = Depends(tenant)) -> dict[str, Any]:
    """등록된 서버를 레거시 {"mcpServers": {...}} 형태로 돌려준다.

    JSON 편집기의 초기값이며, 다른 테넌트로 옮길 때의 내보내기이기도 하다.
    """
    return await repository.export_jsonb(t)


@app.post("/servers/import")
async def import_servers(
    body: JsonImport, t: str = Depends(tenant), who: str | None = Depends(actor)
) -> dict[str, Any]:
    """JSON 을 통째로 붙여넣어 반영한다 (기존 등록 방식 유지).

    tenants.mcp 에 직접 쓰지 않고 정본 테이블에 반영하므로, 버전·권한·
    관측이 그대로 붙고 동기화 트리거에 덮여 사라지지 않는다.
    """
    result = await repository.import_jsonb(t, body.mcpServers, who, body.prune)

    if body.validate_after:
        touched = set(result["created"]) | set(result["updated"])
        for name in touched:
            srv = await repository.get_server_by_name(t, name)
            if not srv:
                continue
            try:
                await repository.validate_and_sync(t, srv["id"])
            except Exception as exc:  # noqa: BLE001
                logger.warning("가져오기 후 검증 실패 (%s): %s", name, exc)

    result["servers"] = await repository.list_servers(t)
    return result


@app.get("/servers/{server_id}")
async def get_server(server_id: UUID, t: str = Depends(tenant)) -> dict[str, Any]:
    srv = await repository.get_server(t, server_id)
    if not srv:
        raise HTTPException(404, "서버를 찾을 수 없습니다")
    srv["tools"] = await repository.list_tools(t, server_id)
    return srv


@app.patch("/servers/{server_id}")
async def patch_server(
    server_id: UUID, body: ServerPatch,
    t: str = Depends(tenant), who: str | None = Depends(actor),
) -> dict[str, Any]:
    ok = await repository.patch_server(t, server_id, body.model_dump(exclude_none=True), who)
    if not ok:
        raise HTTPException(404, "서버를 찾을 수 없거나 변경할 내용이 없습니다")
    return await repository.get_server(t, server_id)


@app.delete("/servers/{server_id}", status_code=204)
async def delete_server(server_id: UUID, t: str = Depends(tenant)) -> None:
    if not await repository.soft_delete(t, server_id):
        raise HTTPException(404, "서버를 찾을 수 없습니다")


# ---------------------------------------------------------------- versions
@app.get("/servers/{server_id}/versions")
async def list_versions(server_id: UUID, t: str = Depends(tenant)) -> list[dict]:
    if not await repository.get_server(t, server_id):
        raise HTTPException(404, "서버를 찾을 수 없습니다")
    return await repository.list_versions(server_id)


@app.post("/servers/{server_id}/versions", status_code=201)
async def create_version(
    server_id: UUID, body: VersionCreate,
    t: str = Depends(tenant), who: str | None = Depends(actor),
) -> dict[str, Any]:
    if not await repository.get_server(t, server_id):
        raise HTTPException(404, "서버를 찾을 수 없습니다")
    try:
        body.connection.require_complete()
    except ValueError as exc:
        raise HTTPException(422, str(exc)) from exc
    result = await repository.add_version(
        t, server_id, body.connection.model_dump(), body.change_note, who
    )
    try:
        result["validation"] = await repository.validate_and_sync(t, server_id)
    except Exception as exc:  # noqa: BLE001
        logger.warning("새 버전 검증 실패: %s", exc)
    return result


@app.post("/servers/{server_id}/versions/{version}/activate")
async def activate_version(
    server_id: UUID, version: int, t: str = Depends(tenant)
) -> dict[str, Any]:
    if not await repository.get_server(t, server_id):
        raise HTTPException(404, "서버를 찾을 수 없습니다")
    if not await repository.activate_version(server_id, version):
        raise HTTPException(404, f"버전 {version} 을 찾을 수 없습니다")
    return {"activated": version}


@app.get("/servers/{server_id}/versions/{a}/diff/{b}")
async def diff_versions(
    server_id: UUID, a: int, b: int, t: str = Depends(tenant)
) -> dict[str, Any]:
    versions = {v["version"]: v for v in await repository.list_versions(server_id)}
    if a not in versions or b not in versions:
        raise HTTPException(404, "버전을 찾을 수 없습니다")
    keys = ("transport", "command", "args", "url", "headers", "env", "timeout_ms")
    changes = {
        k: {"from": versions[a].get(k), "to": versions[b].get(k)}
        for k in keys
        if versions[a].get(k) != versions[b].get(k)
    }
    return {"from": a, "to": b, "changes": changes}


# ---------------------------------------------------------------- validate
@app.post("/servers/{server_id}/validate")
async def validate_server(server_id: UUID, t: str = Depends(tenant)) -> dict[str, Any]:
    try:
        return await repository.validate_and_sync(t, server_id)
    except LookupError as exc:
        raise HTTPException(404, str(exc)) from exc


@app.post("/servers/{server_id}/refresh-tools")
async def refresh_tools(server_id: UUID, t: str = Depends(tenant)) -> list[dict]:
    try:
        await repository.validate_and_sync(t, server_id)
    except LookupError as exc:
        raise HTTPException(404, str(exc)) from exc
    return await repository.list_tools(t, server_id)


@app.post("/validate-connection")
async def validate_connection(
    body: ConnectionConfig, name: str = Query("preview")
) -> dict[str, Any]:
    """등록 전 연결 미리보기 — 마법사의 '연결 테스트' 버튼이 쓴다."""
    try:
        body.require_complete()
    except ValueError as exc:
        raise HTTPException(422, str(exc)) from exc
    return await validator_client.validate(name, body.model_dump())


# ---------------------------------------------------------------- health
@app.get("/health/summary")
async def health_summary(t: str = Depends(tenant)) -> list[dict]:
    return await db.fetch_all(
        """
        select s.id as server_id, s.name, s.category, s.department_id,
               coalesce(h.state::text, 'unknown') as state,
               h.checked_at, h.latency_ms, h.tool_count,
               h.consecutive_failures, h.availability_24h, h.error_message
          from public.mcp_server s
          left join public.mcp_server_health_current h on h.server_id = s.id
         where s.tenant_id = %s and s.is_deleted = false
         order by (coalesce(h.state::text,'unknown') = 'unhealthy') desc, s.name
        """,
        [t],
    )


@app.get("/servers/{server_id}/health")
async def server_health(
    server_id: UUID, t: str = Depends(tenant), limit: int = 100
) -> list[dict]:
    return await db.fetch_all(
        "select checked_at, state, latency_ms, tool_count, error_message "
        "from public.mcp_server_health where tenant_id = %s and server_id = %s "
        "order by checked_at desc limit %s",
        [t, server_id, limit],
    )


@app.post("/servers/{server_id}/health/check")
async def force_health_check(server_id: UUID, t: str = Depends(tenant)) -> dict[str, Any]:
    try:
        return await repository.validate_and_sync(t, server_id)
    except LookupError as exc:
        raise HTTPException(404, str(exc)) from exc


# ---------------------------------------------------------------- tools
@app.get("/tools")
async def list_tools(
    t: str = Depends(tenant),
    q: str | None = None,
    category: str | None = None,
    server_id: UUID | None = None,
) -> list[dict]:
    if server_id:
        return await repository.list_tools(t, server_id)
    return await repository.search_tools(t, q, category)


@app.get("/agents/{agent_id}/tools")
async def agent_tools(
    agent_id: str,
    t: str = Depends(tenant),
    department_id: str | None = None,
) -> dict[str, Any]:
    """엔진용 단일 게이트.

    enabled / status / 권한 / 화이트·블랙리스트가 모두 적용된 결과만 나온다.
    completion · deepagents · cli-agent 가 이 경로를 쓴다.
    """
    servers = await repository.resolve_agent_tools(t, agent_id, department_id)
    return {
        "agent_id": agent_id,
        "servers": servers,
        "tool_count": sum(len(s["tools"]) for s in servers),
    }


@app.get("/agents/{agent_id}/bindings")
async def get_bindings(agent_id: str, t: str = Depends(tenant)) -> list[dict]:
    return await repository.get_agent_bindings(t, agent_id)


@app.put("/agents/{agent_id}/bindings")
async def put_bindings(
    agent_id: str, bindings: list[AgentBinding], t: str = Depends(tenant)
) -> dict[str, Any]:
    n = await repository.set_agent_bindings(
        t, agent_id, [b.model_dump() for b in bindings]
    )
    return {"agent_id": agent_id, "bindings": n}


# ---------------------------------------------------------------- permissions
@app.get("/servers/{server_id}/permissions")
async def get_permissions(server_id: UUID, t: str = Depends(tenant)) -> list[dict]:
    if not await repository.get_server(t, server_id):
        raise HTTPException(404, "서버를 찾을 수 없습니다")
    return await repository.get_permissions(server_id)


@app.put("/servers/{server_id}/permissions")
async def put_permissions(
    server_id: UUID, entries: list[PermissionEntry], t: str = Depends(tenant)
) -> dict[str, Any]:
    if not await repository.get_server(t, server_id):
        raise HTTPException(404, "서버를 찾을 수 없습니다")
    n = await repository.set_permissions(t, server_id, [e.model_dump() for e in entries])
    return {"server_id": str(server_id), "entries": n}


# ---------------------------------------------------------------- catalog
@app.get("/catalog/gallery")
async def get_gallery() -> dict[str, Any]:
    return {"entries": catalog.gallery_entries()}


@app.get("/catalog/registry/search")
async def search_registry(q: str = "", limit: int = 30) -> dict[str, Any]:
    return await catalog.registry_search(q, limit)


@app.post("/catalog/install", status_code=201)
async def install_from_catalog(
    body: CatalogInstall, t: str = Depends(tenant), who: str | None = Depends(actor)
) -> dict[str, Any]:
    if body.source == "gallery":
        entry = catalog.gallery_entry(body.slug)
    else:
        found = await catalog.registry_search(body.slug, limit=50)
        entry = next((e for e in found["entries"] if e["slug"] == body.slug), None)
    if not entry:
        raise HTTPException(404, f"카탈로그에서 '{body.slug}' 를 찾을 수 없습니다")

    conn = catalog.resolve_template(entry["install_template"], body.env, body.headers)
    name = body.name or entry["slug"]
    if await repository.get_server_by_name(t, name):
        raise HTTPException(409, f"'{name}' 이름의 서버가 이미 있습니다")

    payload = {
        "name": name,
        "display_name": entry.get("name"),
        "description": entry.get("description"),
        "category": entry.get("category"),
        "tags": entry.get("tags") or [],
        "department_id": body.department_id,
        "doc_url": entry.get("homepage_url"),
        "status": "active",
        "enabled": True,
        "source": body.source,
        "source_ref": body.slug,
        "connection": conn,
    }
    server_id = await repository.create_server(t, payload, who)
    if body.validate_on_create:
        try:
            await repository.validate_and_sync(t, server_id)
        except Exception as exc:  # noqa: BLE001
            logger.warning("설치 후 검증 실패: %s", exc)
    return await repository.get_server(t, server_id)


# ---------------------------------------------------------------- observability
@app.get("/observability/summary")
async def obs_summary(t: str = Depends(tenant), range: str = "24h") -> dict[str, Any]:
    return await observability.summary(t, range)


@app.get("/observability/servers")
async def obs_servers(t: str = Depends(tenant), range: str = "24h") -> list[dict]:
    return await observability.server_stats(t, range)


@app.get("/observability/tools")
async def obs_tools(t: str = Depends(tenant), range: str = "24h", limit: int = 50) -> list[dict]:
    return await observability.tool_stats(t, range, limit)


@app.get("/observability/calls")
async def obs_calls(
    t: str = Depends(tenant),
    server_id: str | None = None,
    tool_name: str | None = None,
    status: str | None = None,
    proc_inst_id: str | None = None,
    todo_id: str | None = None,
    limit: int = 100,
    offset: int = 0,
) -> list[dict]:
    return await observability.calls(
        t, server_id, tool_name, status, proc_inst_id, todo_id, limit, offset
    )


@app.get("/observability/timeseries")
async def obs_timeseries(
    t: str = Depends(tenant), range: str = "24h", bucket: str = "1 hour"
) -> list[dict]:
    return await observability.timeseries(t, range, bucket)


@app.get("/observability/tasks/{todo_id}")
async def obs_task(todo_id: str, t: str = Depends(tenant)) -> dict[str, Any]:
    return await observability.task_observability(t, todo_id)


# ---------------------------------------------------------------- ingest
@app.post("/ingest/mcp-calls")
async def ingest_mcp_calls(body: ingest.MCPCallBatch) -> dict[str, Any]:
    """엔진의 ObservedTool 이 보내는 MCP 호출 스팬.

    수집 실패가 툴 호출 실패로 번지면 안 되므로 항상 200 을 돌려준다.
    """
    try:
        n = await ingest.record_mcp_calls(body.records)
        return {"accepted": n}
    except Exception as exc:  # noqa: BLE001
        logger.warning("MCP 호출 수집 실패: %s", exc)
        return {"accepted": 0, "error": str(exc)}


@app.post("/ingest/llm-calls")
async def ingest_llm_calls(body: ingest.LLMCallBatch) -> dict[str, Any]:
    """LiteLLM 프록시 콜백이 보내는 LLM 호출 스팬."""
    try:
        n = await ingest.record_llm_calls(body.records)
        return {"accepted": n}
    except Exception as exc:  # noqa: BLE001
        logger.warning("LLM 호출 수집 실패: %s", exc)
        return {"accepted": 0, "error": str(exc)}


@app.post("/ingest/mcp-payloads")
@app.post("/ingest/llm-payloads")
async def ingest_payloads(body: ingest.PayloadBatch) -> dict[str, Any]:
    """프로파일러용 원문(프롬프트·응답·툴 인자) 수집.

    llm/mcp 스팬이 같은 사이드카 테이블을 쓰므로 핸들러도 하나다.
    수집 실패가 호출자에게 번지면 안 되므로 항상 200 을 돌려준다.
    """
    try:
        n = await ingest.record_payloads(body.records)
        return {"accepted": n}
    except Exception as exc:  # noqa: BLE001
        logger.warning("페이로드 수집 실패: %s", exc)
        return {"accepted": 0, "error": str(exc)}


# ---------------------------------------------------------------- spec
@app.get("/spec/guide")
async def spec_guide() -> dict[str, Any]:
    from .conformance import GUIDE

    return GUIDE


@app.post("/spec/conformance")
async def spec_conformance(body: ConnectionConfig, name: str = Query("candidate")) -> dict[str, Any]:
    from .conformance import check_conformance

    try:
        body.require_complete()
    except ValueError as exc:
        raise HTTPException(422, str(exc)) from exc
    return await check_conformance(name, body.model_dump())


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=PORT)

# 영어 클라이언트에는 이 서비스가 만드는 한국어 표시 문자열을 영어로 바꿔 내보낸다.
from mcp_hub.response_i18n import LocaleResponseMiddleware

app.add_middleware(LocaleResponseMiddleware)
