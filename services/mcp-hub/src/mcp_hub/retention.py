"""프로파일링 원문 보존 관리.

trace_payload 는 프롬프트·툴 인자 원문을 담기 때문에 오래 두면 안 된다.
개인정보 노출면과 용량 양쪽 문제라서, 짧은 보존기간을 두고 주기적으로 지운다.

pg_cron 을 쓰지 않는 이유: DB DDL 미러가 4곳이라 확장 설치를 전부에
요구하게 된다. 허브가 이미 헬스 스케줄러 루프를 갖고 있으므로 여기 얹는다.
"""
import asyncio
import logging
import os

from . import db

logger = logging.getLogger(__name__)

RETENTION_DAYS = int(os.getenv("TRACE_PAYLOAD_RETENTION_DAYS", "14"))
INTERVAL_SEC = int(os.getenv("TRACE_PAYLOAD_PURGE_INTERVAL_SEC", "3600"))
BATCH = int(os.getenv("TRACE_PAYLOAD_PURGE_BATCH", "10000"))
ENABLED = os.getenv("TRACE_PAYLOAD_PURGE_ENABLED", "true").lower() != "false"

_task: asyncio.Task | None = None


async def purge_once() -> int:
    """보존기간이 지난 행을 배치로 지운다. 총 삭제 건수를 돌려준다."""
    total = 0
    while True:
        n = await db.execute(
            """
            delete from public.trace_payload
             where id in (
                 select id from public.trace_payload
                  where created_at < now() - make_interval(days => %s)
                  limit %s
             )
            """,
            [RETENTION_DAYS, BATCH],
        )
        total += n
        if n < BATCH:
            break
    return total


async def _loop() -> None:
    await asyncio.sleep(30)
    while True:
        try:
            n = await purge_once()
            if n:
                logger.info("trace_payload %d건 정리 (보존 %d일)", n, RETENTION_DAYS)
        except asyncio.CancelledError:
            raise
        except Exception as exc:  # noqa: BLE001
            logger.warning("trace_payload 정리 실패: %s", exc)
        await asyncio.sleep(INTERVAL_SEC)


def start() -> None:
    global _task
    if not ENABLED:
        logger.info("페이로드 정리 비활성 (TRACE_PAYLOAD_PURGE_ENABLED=false)")
        return
    if _task is None or _task.done():
        _task = asyncio.create_task(_loop())
        logger.info("페이로드 정리 시작 (보존 %d일, 주기 %ds)",
                    RETENTION_DAYS, INTERVAL_SEC)


async def stop() -> None:
    global _task
    if _task and not _task.done():
        _task.cancel()
        try:
            await _task
        except asyncio.CancelledError:
            pass
    _task = None
