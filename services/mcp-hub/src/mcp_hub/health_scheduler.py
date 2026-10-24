"""주기 헬스체크.

가벼운 asyncio 루프면 충분하다 — 서버 수가 테넌트당 수십 개 수준이고,
체크 자체는 mcp-validator 가 대신 해준다.
"""
import asyncio
import logging

from . import db, repository
from .config import HEALTH_ENABLED, HEALTH_INTERVAL_SEC

logger = logging.getLogger(__name__)

_task: asyncio.Task | None = None


async def check_once() -> int:
    """등록된 모든 active 서버를 한 바퀴 검사한다."""
    servers = await db.fetch_all(
        """
        select s.id, s.tenant_id, s.name,
               v.transport, v.command, v.args, v.url, v.headers, v.env
          from public.mcp_server s
          join public.mcp_server_version v on v.id = s.current_version_id
         where s.is_deleted = false and s.status = 'active'
        """
    )
    checked = 0
    for s in servers:
        try:
            await repository.validate_and_sync(s["tenant_id"], s["id"])
            checked += 1
        except Exception as exc:  # noqa: BLE001
            logger.warning("헬스체크 실패 (%s): %s", s["name"], exc)
    return checked


async def _loop() -> None:
    # 기동 직후 몰리지 않도록 조금 기다린다
    await asyncio.sleep(10)
    while True:
        try:
            n = await check_once()
            logger.info("헬스체크 %d개 서버 완료", n)
        except asyncio.CancelledError:
            raise
        except Exception as exc:  # noqa: BLE001
            logger.error("헬스체크 루프 오류: %s", exc)
        await asyncio.sleep(HEALTH_INTERVAL_SEC)


def start() -> None:
    global _task
    if not HEALTH_ENABLED:
        logger.info("헬스 스케줄러 비활성 (MCP_HEALTH_ENABLED=false)")
        return
    if _task is None or _task.done():
        _task = asyncio.create_task(_loop())
        logger.info("헬스 스케줄러 시작 (주기 %ds)", HEALTH_INTERVAL_SEC)


async def stop() -> None:
    global _task
    if _task and not _task.done():
        _task.cancel()
        try:
            await _task
        except asyncio.CancelledError:
            pass
    _task = None
