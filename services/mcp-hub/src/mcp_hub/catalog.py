"""갤러리(내장) + 공식 MCP Registry.

갤러리가 1차 소스다 — 폐쇄망에서도 동작해야 하므로 레포에 JSON 으로 들어있다.
Registry 는 보강일 뿐이고, 접근이 안 되면 조용히 비활성화된다.
"""
import json
import logging
from functools import lru_cache
from pathlib import Path
from typing import Any

import httpx

from .config import REGISTRY_ENABLED, REGISTRY_URL

logger = logging.getLogger(__name__)

_GALLERY = Path(__file__).parent / "gallery" / "servers.json"


@lru_cache(maxsize=1)
def gallery_entries() -> list[dict[str, Any]]:
    try:
        data = json.loads(_GALLERY.read_text(encoding="utf-8"))
    except Exception as exc:  # noqa: BLE001
        logger.error("갤러리 파일을 읽지 못했습니다: %s", exc)
        return []
    out = []
    for e in data.get("entries", []):
        out.append({**e, "source": "gallery"})
    return out


def gallery_entry(slug: str) -> dict[str, Any] | None:
    return next((e for e in gallery_entries() if e["slug"] == slug), None)


async def registry_search(q: str, limit: int = 30) -> dict[str, Any]:
    """공식 MCP Registry 검색.

    실패해도 예외를 던지지 않는다 — 갤러리 탭은 계속 살아있어야 한다.
    """
    if not REGISTRY_ENABLED:
        return {"available": False, "reason": "레지스트리 연동이 꺼져 있습니다", "entries": []}
    try:
        async with httpx.AsyncClient(timeout=10) as client:
            resp = await client.get(
                f"{REGISTRY_URL.rstrip('/')}/v0/servers",
                params={"search": q, "limit": limit} if q else {"limit": limit},
            )
            resp.raise_for_status()
            payload = resp.json()
    except Exception as exc:  # noqa: BLE001
        logger.info("MCP Registry 접근 불가: %s", exc)
        return {
            "available": False,
            "reason": f"레지스트리에 접근할 수 없습니다 ({exc.__class__.__name__}). "
                      f"내장 갤러리를 사용하세요.",
            "entries": [],
        }

    entries = []
    for item in payload.get("servers", payload.get("data", [])) or []:
        entries.append(_registry_to_entry(item))
    return {"available": True, "entries": [e for e in entries if e]}


def _registry_to_entry(item: dict[str, Any]) -> dict[str, Any] | None:
    """Registry 응답을 갤러리와 같은 모양으로 정규화한다."""
    server = item.get("server", item)
    name = server.get("name") or item.get("name")
    if not name:
        return None
    slug = str(name).replace("/", "-").replace(" ", "-").lower()

    template: dict[str, Any] = {}
    remotes = server.get("remotes") or []
    packages = server.get("packages") or []
    if remotes:
        r = remotes[0]
        transport = r.get("type") or r.get("transport") or "streamable-http"
        template = {
            "transport": "sse" if transport == "sse" else "streamable-http",
            "url": r.get("url"),
        }
    elif packages:
        p = packages[0]
        registry_name = (p.get("registry_type") or p.get("registry_name") or "").lower()
        ident = p.get("identifier") or p.get("name")
        if registry_name in ("npm", "npmjs"):
            template = {"transport": "stdio", "command": "npx", "args": ["-y", ident]}
        elif registry_name in ("pypi", "pip"):
            template = {"transport": "stdio", "command": "uvx", "args": [ident]}
        else:
            template = {"transport": "stdio", "command": ident, "args": []}
    if not template:
        return None

    return {
        "slug": slug,
        "source": "registry",
        "name": str(name).split("/")[-1],
        "description": server.get("description"),
        "category": None,
        "tags": [],
        "publisher": str(name).split("/")[0] if "/" in str(name) else None,
        "homepage_url": server.get("repository", {}).get("url")
        if isinstance(server.get("repository"), dict) else server.get("websiteUrl"),
        "install_template": template,
        "required_env": [],
        "registry_payload": item,
    }


def resolve_template(template: dict[str, Any], env: dict[str, str],
                     headers: dict[str, str]) -> dict[str, Any]:
    """설치 템플릿에 사용자가 입력한 값을 채워 실제 연결정보를 만든다.

    ${SECRET:KEY} 자리표시자는 헤더에서 치환한다. env 값은 그대로 실린다.
    """
    conn = {
        "transport": template.get("transport", "stdio"),
        "command": template.get("command"),
        "args": list(template.get("args") or []),
        "url": template.get("url"),
        "headers": dict(template.get("headers") or {}),
        "env": dict(template.get("env") or {}),
    }
    conn["env"].update(env or {})
    for k, v in (headers or {}).items():
        conn["headers"][k] = v
    # 템플릿 헤더의 ${SECRET:X} 를 입력받은 env 로 치환
    for k, v in list(conn["headers"].items()):
        if isinstance(v, str) and "${SECRET:" in v:
            for env_k, env_v in (env or {}).items():
                v = v.replace(f"${{SECRET:{env_k}}}", env_v)
            conn["headers"][k] = v
    return conn
