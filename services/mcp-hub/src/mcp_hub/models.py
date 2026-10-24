"""API DTO.

mcp-validator 의 MCPValidationResponse 스키마는 그대로 통과시켜
기존 소비자(웹 UI)의 기대를 깨지 않는다.
"""
from datetime import datetime
from typing import Any, Literal
from uuid import UUID

from pydantic import BaseModel, Field, field_validator

Transport = Literal["stdio", "http", "sse", "streamable-http"]
ServerStatus = Literal["draft", "active", "deprecated", "disabled"]
HealthState = Literal["unknown", "healthy", "degraded", "unhealthy"]
PrincipalType = Literal["tenant", "department", "role", "user", "agent"]
Permission = Literal["none", "use", "manage"]


class ConnectionConfig(BaseModel):
    """한 버전의 연결정보. 등록 후에는 불변이며 수정은 새 버전 생성으로만."""
    transport: Transport
    command: str | None = None
    args: list[str] = Field(default_factory=list)
    url: str | None = None
    headers: dict[str, str] = Field(default_factory=dict)
    env: dict[str, str] = Field(default_factory=dict)
    timeout_ms: int = 30000
    semver: str | None = None

    @field_validator("transport")
    @classmethod
    def _normalize(cls, v: str) -> str:
        return {"streamable_http": "streamable-http"}.get(v, v)

    def require_complete(self) -> None:
        if self.transport == "stdio" and not self.command:
            raise ValueError("stdio 서버에는 command 가 필요합니다")
        if self.transport != "stdio" and not self.url:
            raise ValueError(f"{self.transport} 서버에는 url 이 필요합니다")


class JsonImport(BaseModel):
    """레거시 {"mcpServers": {...}} 붙여넣기 방식의 입력."""
    mcpServers: dict[str, Any] = Field(default_factory=dict)
    prune: bool = True
    validate_after: bool = True


class VersionCreate(BaseModel):
    """새 연결정보 버전. change_note 는 한글이 흔하므로 쿼리가 아니라 본문으로 받는다."""
    connection: ConnectionConfig
    change_note: str | None = None


class ServerCreate(BaseModel):
    name: str
    display_name: str | None = None
    description: str | None = None
    category: str | None = None
    tags: list[str] = Field(default_factory=list)
    department_id: str | None = None
    owner_email: str | None = None
    doc_url: str | None = None
    status: ServerStatus = "active"
    enabled: bool = True
    connection: ConnectionConfig
    source: Literal["manual", "gallery", "registry"] = "manual"
    source_ref: str | None = None
    validate_on_create: bool = True


class ServerPatch(BaseModel):
    """메타만 수정한다 — 연결정보는 새 버전으로."""
    display_name: str | None = None
    description: str | None = None
    category: str | None = None
    tags: list[str] | None = None
    department_id: str | None = None
    owner_email: str | None = None
    doc_url: str | None = None
    status: ServerStatus | None = None
    enabled: bool | None = None


class ToolInfo(BaseModel):
    id: UUID | None = None
    server_id: UUID | None = None
    server_name: str | None = None
    tool_name: str
    sanitized_name: str
    description: str | None = None
    input_schema: dict[str, Any] | None = None
    annotations: dict[str, Any] | None = None
    is_available: bool = True


class VersionInfo(BaseModel):
    id: UUID
    version: int
    semver: str | None = None
    transport: Transport
    command: str | None = None
    args: list[str] = Field(default_factory=list)
    url: str | None = None
    headers: dict[str, str] = Field(default_factory=dict)
    env: dict[str, str] = Field(default_factory=dict)
    timeout_ms: int = 30000
    config_hash: str
    change_note: str | None = None
    validated_at: datetime | None = None
    created_at: datetime


class HealthInfo(BaseModel):
    state: HealthState = "unknown"
    checked_at: datetime | None = None
    latency_ms: int | None = None
    tool_count: int | None = None
    consecutive_failures: int = 0
    availability_24h: float | None = None
    error_message: str | None = None


class ServerSummary(BaseModel):
    id: UUID
    name: str
    display_name: str | None = None
    description: str | None = None
    category: str | None = None
    tags: list[str] = Field(default_factory=list)
    department_id: str | None = None
    owner_email: str | None = None
    status: ServerStatus
    enabled: bool
    is_default: bool
    source: str
    version: int | None = None
    transport: Transport | None = None
    tool_count: int = 0
    health: HealthInfo = Field(default_factory=HealthInfo)
    calls_24h: int = 0
    error_rate_24h: float | None = None
    p95_ms: int | None = None
    updated_at: datetime | None = None


class ServerDetail(ServerSummary):
    doc_url: str | None = None
    connection: ConnectionConfig | None = None
    tools: list[ToolInfo] = Field(default_factory=list)


class PermissionEntry(BaseModel):
    principal_type: PrincipalType
    principal_id: str | None = None
    permission: Permission = "use"
    allowed_tools: list[str] | None = None
    denied_tools: list[str] = Field(default_factory=list)


class AgentBinding(BaseModel):
    server_id: UUID
    allowed_tools: list[str] | None = None
    enabled: bool = True


class CatalogEntry(BaseModel):
    slug: str
    source: str
    name: str
    description: str | None = None
    category: str | None = None
    tags: list[str] = Field(default_factory=list)
    publisher: str | None = None
    homepage_url: str | None = None
    install_template: dict[str, Any]
    required_env: list[dict[str, Any]] = Field(default_factory=list)


class CatalogInstall(BaseModel):
    slug: str
    source: Literal["gallery", "registry"] = "gallery"
    name: str | None = None
    env: dict[str, str] = Field(default_factory=dict)
    headers: dict[str, str] = Field(default_factory=dict)
    department_id: str | None = None
    validate_on_create: bool = True
