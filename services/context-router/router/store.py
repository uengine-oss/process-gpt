"""context_threads through Supabase REST (service role)."""
from __future__ import annotations

import logging
import os
from datetime import datetime, timedelta, timezone

import httpx

logger = logging.getLogger(__name__)


def _rest() -> tuple[str, dict]:
    url = (os.getenv("SUPABASE_URL") or "http://localhost:54321").rstrip("/") + "/rest/v1"
    key = os.getenv("SUPABASE_KEY") or os.getenv("SUPABASE_SERVICE_ROLE_KEY") or ""
    return url, {"apikey": key, "Authorization": f"Bearer {key}", "Content-Type": "application/json"}


#: contexts idle longer than this are not candidates; the newest SCAN are read and narrowed
DORMANT_DAYS = float(os.getenv("ROUTER_DORMANT_DAYS", "30"))
SCAN = int(os.getenv("ROUTER_SCAN", "200"))


async def recent(tenant_id: str, user_id: str, limit: int = SCAN) -> list[dict]:
    url, h = _rest()
    since = (datetime.now(timezone.utc) - timedelta(days=DORMANT_DAYS)).isoformat()
    try:
        async with httpx.AsyncClient(timeout=5) as c:
            r = await c.get(f"{url}/context_threads", headers=h, params={
                "tenant_id": f"eq.{tenant_id}", "user_id": f"eq.{user_id}", "updated_at": f"gte.{since}",
                "select": "conversation_id,title,summary,gist,kind,updated_at",
                "order": "updated_at.desc", "limit": str(limit)})
            r.raise_for_status()
            return r.json()
    except Exception as exc:  # noqa: BLE001 - no history means "no candidates", not an outage
        logger.warning("context_threads read failed: %s", exc)
        return []


async def search(tenant_id: str, user_id: str, terms: list[str], limit: int = 30) -> list[dict]:
    """Non-dormant contexts naming any of ``terms``, however old: the newest SCAN rows alone
    would miss a context that is three weeks and hundreds of chats back."""
    if not terms:
        return []
    url, h = _rest()
    since = (datetime.now(timezone.utc) - timedelta(days=DORMANT_DAYS)).isoformat()
    safe = [t.replace(",", "").replace("(", "").replace(")", "").replace("*", "") for t in terms]
    cond = ",".join(f"{col}.ilike.*{t}*" for t in safe if t for col in ("title", "gist"))
    try:
        async with httpx.AsyncClient(timeout=5) as c:
            r = await c.get(f"{url}/context_threads", headers=h, params={
                "tenant_id": f"eq.{tenant_id}", "user_id": f"eq.{user_id}", "updated_at": f"gte.{since}",
                "or": f"({cond})", "select": "conversation_id,title,summary,gist,kind,updated_at",
                "order": "updated_at.desc", "limit": str(limit)})
            r.raise_for_status()
            return r.json()
    except Exception as exc:  # noqa: BLE001
        logger.warning("context_threads search failed: %s", exc)
        return []


async def touch(tenant_id: str, user_id: str, conversation_id: str, *, title: str, summary: str, gist: str = "",
                kind: str = "conversation", turns: int = 1) -> None:
    url, h = _rest()
    row = {"tenant_id": tenant_id, "user_id": user_id, "conversation_id": conversation_id,
           "title": title[:120], "summary": summary[:600], "gist": gist[:200], "kind": kind, "turns": turns, "updated_at": "now()"}
    try:
        async with httpx.AsyncClient(timeout=5) as c:
            r = await c.post(f"{url}/context_threads", headers={**h, "Prefer": "resolution=merge-duplicates"},
                             params={"on_conflict": "tenant_id,user_id,conversation_id"}, json=row)
            r.raise_for_status()
    except Exception as exc:  # noqa: BLE001
        logger.warning("context_threads write failed: %s", exc)
