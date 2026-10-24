"""연결 검증 · tools/list 위임 클라이언트.

허브는 MCP 서버 프로세스를 직접 spawn 하지 않는다. stdio 서버를 띄우는
쪽은 services/mcp-validator 컨테이너에 가둬두고, 허브는 HTTP 로 물어본다.
(mcp-validator 는 그동안 어디에서도 호출되지 않던 서비스였다.)
"""
import hashlib
import json
import logging
import re
from typing import Any

import httpx

from .config import VALIDATE_TIMEOUT, VALIDATOR_URL

logger = logging.getLogger(__name__)

# mcp-validator 의 MCPTransportType 은 streamable_http 를 쓴다.
_TO_VALIDATOR = {
    "streamable-http": "streamable_http",
    "http": "streamable_http",
    "sse": "sse",
    "stdio": "stdio",
}

_SAFE = re.compile(r"[^a-zA-Z0-9_-]")


def sanitize_tool_name(name: str) -> str:
    """LLM 함수 이름 제약(영숫자/밑줄/하이픈)에 맞춘 이름."""
    return _SAFE.sub("_", name or "")


def config_hash(conn: dict[str, Any]) -> str:
    """연결정보 정규화 해시 — 같은 내용으로 새 버전이 생기는 걸 막는다."""
    payload = {
        "transport": conn.get("transport"),
        "command": conn.get("command") or None,
        "args": conn.get("args") or [],
        "url": conn.get("url") or None,
        "headers": conn.get("headers") or {},
        "env": conn.get("env") or {},
    }
    blob = json.dumps(payload, sort_keys=True, ensure_ascii=False)
    return hashlib.sha256(blob.encode()).hexdigest()


def to_validator_config(conn: dict[str, Any]) -> dict[str, Any]:
    """정본 연결정보 -> mcp-validator 의 MCPServerConfig 형태."""
    transport = _TO_VALIDATOR.get(conn.get("transport") or "stdio", "stdio")
    cfg: dict[str, Any] = {"transport": transport}
    if transport == "stdio":
        cfg["command"] = conn.get("command")
        if conn.get("args"):
            cfg["args"] = list(conn["args"])
        if conn.get("env"):
            cfg["env"] = dict(conn["env"])
    else:
        cfg["url"] = conn.get("url")
        if conn.get("headers"):
            cfg["headers"] = dict(conn["headers"])
    return cfg


class ValidatorClient:
    def __init__(self, base_url: str = VALIDATOR_URL) -> None:
        self.base_url = base_url.rstrip("/")

    async def validate(
        self, server_name: str, conn: dict[str, Any], timeout: int | None = None
    ) -> dict[str, Any]:
        """단일 서버를 연결해보고 툴 목록을 받아온다.

        검증 서비스가 죽어 있어도 예외를 던지지 않는다 — 상태를 'error' 로
        보고할 뿐이다. 등록 자체가 검증 서비스에 인질로 잡히면 안 된다.
        """
        timeout = timeout or VALIDATE_TIMEOUT
        body = {
            "mcpServers": {server_name: to_validator_config(conn)},
            "timeout": timeout,
        }
        try:
            async with httpx.AsyncClient(timeout=timeout + 10) as client:
                resp = await client.post(f"{self.base_url}/validate", json=body)
                resp.raise_for_status()
                data = resp.json()
        except Exception as exc:  # noqa: BLE001
            logger.warning("mcp-validator 호출 실패 (%s): %s", server_name, exc)
            return {
                "name": server_name,
                "status": "error",
                "tools": [],
                "error_message": f"검증 서비스에 연결할 수 없습니다: {exc}",
                "unreachable_validator": True,
            }

        servers = data.get("servers") or []
        if not servers:
            return {
                "name": server_name,
                "status": "error",
                "tools": [],
                "error_message": "검증 서비스가 결과를 반환하지 않았습니다",
            }
        result = servers[0]
        result["validation_time"] = data.get("validation_time")
        return result

    async def ping(self) -> bool:
        try:
            async with httpx.AsyncClient(timeout=5) as client:
                resp = await client.get(f"{self.base_url}/health")
                return resp.status_code == 200
        except Exception:  # noqa: BLE001
            return False


validator_client = ValidatorClient()
