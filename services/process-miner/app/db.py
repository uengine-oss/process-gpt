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
    """스레드별 연결. 읽기는 autocommit 으로 돌려 트랜잭션이 열린 채 남지 않게 한다.

    쓰기(제안 등록)는 `with conn.transaction():` 으로 묶는다. 깨진 연결은 버리고 새로 연다.
    """
    conn: psycopg.Connection | None = getattr(_local, "conn", None)
    if conn is not None and not conn.closed and not conn.broken:
        return conn
    if conn is not None:
        close()
    conn = psycopg.connect(conninfo(), autocommit=True, row_factory=dict_row)
    _local.conn = conn
    return conn


def close() -> None:
    conn: psycopg.Connection | None = getattr(_local, "conn", None)
    if conn is not None and not conn.closed:
        try:
            conn.close()
        except Exception:  # noqa: BLE001
            pass
    _local.conn = None


def query(sql: str, params: dict | tuple | None = None) -> list[dict]:
    """읽기 쿼리 하나. 실패해도 다음 요청이 같은 연결로 계속 실패하지 않게 정리한다."""
    conn = connect()
    try:
        with conn.cursor() as cur:
            cur.execute(sql, params)
            return list(cur.fetchall()) if cur.description else []
    except psycopg.Error:
        if conn.broken or conn.closed:
            close()
        elif conn.info.transaction_status != psycopg.pq.TransactionStatus.IDLE:
            conn.rollback()
        raise


def fetch_handover_events(tenant_id: str, limit: int = 5000) -> list[dict]:
    """한 테넌트의 인계 기록. 테넌트 없이 부르면 거부한다(다른 테넌트 기록이 섞이지 않게)."""
    if not tenant_id or not str(tenant_id).strip():
        raise ValueError("tenant_id 가 필요합니다")
    sql = """
        select id, tenant_id, case_id, origin_room_id, source, is_explicit,
               from_user_id, from_user_name, from_is_agent,
               to_user_id, to_user_name, to_is_agent, agent_orch,
               activity_label, next_activity_label, norm_activity_label,
               from_room_id, to_room_id, occurred_at, returned_at
        from public.handover_events
        where tenant_id = %(tenant)s::text
        order by origin_room_id, occurred_at
        limit %(limit)s
    """
    return query(sql, {"tenant": tenant_id, "limit": limit})


def next_mined_version(proc_def_id: str, tenant_id: str, cur=None) -> str:
    """이미 있는 마이닝 제안 다음 번호. 개수가 아니라 가장 큰 번호 다음을 쓴다."""
    sql = "select version from public.proc_def_version where proc_def_id = %s and tenant_id = %s"
    if cur is not None:
        cur.execute(sql, (proc_def_id, tenant_id))
        rows = cur.fetchall()
    else:
        rows = query(sql, (proc_def_id, tenant_id))
    highest = 0
    for r in rows:
        v = str(r.get("version") or "")
        major, _, minor = v.partition(".")
        if major == "0" and minor.isdigit():
            highest = max(highest, int(minor))
    return f"0.{highest + 1}"
