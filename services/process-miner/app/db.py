"""ProcessGPT 공유 DB(supabase-db) 직접 접속.

instance-classifier 의 접속 패턴을 따른다. 이 서비스는 handover_events / todolist 를
읽고, proc_def_version(draft) 과 resource_pull_requests 에 제안을 쓴다.
살아 있는 proc_def 는 절대 건드리지 않는다 — 승인은 사람의 몫이다.
"""
from __future__ import annotations

import os
import threading

import psycopg
from psycopg.rows import dict_row

_local = threading.local()


def conninfo() -> str:
    return os.environ.get(
        "MINER_DB_URL",
        "postgresql://{u}:{p}@{h}:{port}/{db}".format(
            u=os.environ.get("DB_USER", "postgres"),
            p=os.environ.get("DB_PASSWORD", "postgres"),
            h=os.environ.get("DB_HOST", "127.0.0.1"),
            port=os.environ.get("DB_PORT", "54322"),
            db=os.environ.get("DB_NAME", "postgres"),
        ),
    )


def connect() -> psycopg.Connection:
    conn: psycopg.Connection | None = getattr(_local, "conn", None)
    if conn is not None and not conn.closed:
        return conn
    conn = psycopg.connect(conninfo(), autocommit=False, row_factory=dict_row)
    _local.conn = conn
    return conn


def close() -> None:
    conn: psycopg.Connection | None = getattr(_local, "conn", None)
    if conn is not None and not conn.closed:
        conn.close()
    _local.conn = None


def fetch_handover_events(tenant_id: str | None = None, limit: int = 5000) -> list[dict]:
    sql = """
        select id, tenant_id, case_id, origin_room_id, source, is_explicit,
               from_user_id, from_user_name, from_is_agent,
               to_user_id, to_user_name, to_is_agent, agent_orch,
               activity_label, next_activity_label, norm_activity_label,
               from_room_id, to_room_id, occurred_at, returned_at
        from public.handover_events
        where (%(tenant)s::text is null or tenant_id = %(tenant)s::text)
        order by origin_room_id, occurred_at
        limit %(limit)s
    """
    with connect().cursor() as cur:
        cur.execute(sql, {"tenant": tenant_id, "limit": limit})
        return list(cur.fetchall())


def next_mined_version(proc_def_id: str, tenant_id: str) -> str:
    """이미 있는 마이닝 제안 다음 번호."""
    with connect().cursor() as cur:
        cur.execute(
            "select count(*) as n from public.proc_def_version where proc_def_id = %s and tenant_id = %s",
            (proc_def_id, tenant_id),
        )
        n = (cur.fetchone() or {}).get("n", 0)
    return f"0.{int(n) + 1}"
