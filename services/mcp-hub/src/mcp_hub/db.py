"""psycopg 비동기 커넥션 풀과 얇은 헬퍼."""
import logging
from contextlib import asynccontextmanager
from typing import Any, Sequence

from psycopg.rows import dict_row
from psycopg_pool import AsyncConnectionPool

from .config import DB_URL

logger = logging.getLogger(__name__)

_pool: AsyncConnectionPool | None = None


async def open_pool() -> None:
    global _pool
    if _pool is None:
        _pool = AsyncConnectionPool(DB_URL, min_size=1, max_size=8, open=False)
        await _pool.open()
        logger.info("DB pool opened")


async def close_pool() -> None:
    global _pool
    if _pool is not None:
        await _pool.close()
        _pool = None


@asynccontextmanager
async def connection():
    if _pool is None:
        raise RuntimeError("DB pool is not open")
    async with _pool.connection() as conn:
        yield conn


async def fetch_all(sql: str, params: Sequence[Any] | None = None) -> list[dict]:
    async with connection() as conn:
        async with conn.cursor(row_factory=dict_row) as cur:
            await cur.execute(sql, params)
            return list(await cur.fetchall())


async def fetch_one(sql: str, params: Sequence[Any] | None = None) -> dict | None:
    async with connection() as conn:
        async with conn.cursor(row_factory=dict_row) as cur:
            await cur.execute(sql, params)
            return await cur.fetchone()


async def execute(sql: str, params: Sequence[Any] | None = None) -> int:
    async with connection() as conn:
        async with conn.cursor() as cur:
            await cur.execute(sql, params)
            return cur.rowcount
