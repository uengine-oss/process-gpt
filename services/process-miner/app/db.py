"""ProcessGPT 공유 DB(supabase-db) 직접 접속.

instance-classifier 의 접속 패턴을 따른다. 이 서비스는 handover_events / todolist 를
읽기만 한다. 제안(정의 · 버전 · 병합 요청)은 식별 화면이 만든다.
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
    """한 테넌트의 인계 기록. 테넌트 없이 부르면 거부한다(다른 테넌트 기록이 섞이지 않게).

    받은 사람의 할 일 상태(to_task_status)를 함께 읽는다. 스레드가 끝났는지는
    마지막으로 받은 할 일이 완료됐는지로 판단한다(eventlog.thread_finished).
    """
    if not tenant_id or not str(tenant_id).strip():
        raise ValueError("tenant_id 가 필요합니다")
    sql = """
        select e.id, e.tenant_id, e.case_id, e.origin_room_id, e.source, e.is_explicit,
               e.from_user_id, e.from_user_name, e.from_is_agent,
               e.to_user_id, e.to_user_name, e.to_is_agent, e.agent_orch,
               e.activity_label, e.next_activity_label, e.norm_activity_label,
               e.from_room_id, e.to_room_id, e.to_task_id, e.occurred_at, e.returned_at,
               e.closed_at, t.status as to_task_status
        from public.handover_events e
        left join public.todolist t on t.id = e.to_task_id
        where e.tenant_id = %(tenant)s::text
        order by e.origin_room_id, e.occurred_at
        limit %(limit)s
    """
    return query(sql, {"tenant": tenant_id, "limit": limit})
