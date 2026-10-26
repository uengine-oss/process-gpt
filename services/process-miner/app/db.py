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


def end_read(conn: psycopg.Connection | None = None) -> None:
    """읽기만 한 트랜잭션을 닫는다. 연결은 스레드마다 재사용되는데, 읽은 뒤 열린 채(idle in transaction)
    두면 handover_events 등의 공유 잠금이 계속 남아 스키마 변경(설치 번들 migrate 의 트리거 재생성)이
    끝없이 기다리고, 그 뒤의 모든 쓰기도 줄을 선다."""
    conn = conn or getattr(_local, "conn", None)
    if conn is not None and not conn.closed and conn.info.transaction_status != psycopg.pq.TransactionStatus.IDLE:
        conn.rollback()


def close() -> None:
    conn: psycopg.Connection | None = getattr(_local, "conn", None)
    if conn is not None and not conn.closed:
        conn.close()
    _local.conn = None


def fetch_handover_events(tenant_id: str | None = None, limit: int = 5000, case_ids: list[str] | None = None) -> list[dict]:
    """인계 행. case_ids 를 주면 그 케이스(스레드 뿌리)만 — 패턴 하나를 따로 도출할 때 쓴다."""
    sql = """
        select id, tenant_id, case_id, origin_room_id, source, is_explicit,
               from_user_id, from_user_name, from_is_agent,
               to_user_id, to_user_name, to_role, to_is_agent, agent_orch,
               activity_label, next_activity_label, norm_activity_label,
               artifact_refs, proc_def_id,
               from_room_id, to_room_id, occurred_at, returned_at
        from public.handover_events
        where (%(tenant)s::text is null or tenant_id = %(tenant)s::text)
          and (%(cases)s::text[] is null or coalesce(origin_room_id, case_id) = any(%(cases)s::text[]))
        order by origin_room_id, occurred_at
        limit %(limit)s
    """
    try:
        with connect().cursor() as cur:
            cur.execute(sql, {"tenant": tenant_id, "limit": limit, "cases": list(case_ids) if case_ids else None})
            return list(cur.fetchall())
    finally:
        end_read()


def open_mining_prs(tenant_id: str) -> list[dict]:
    """이미 제안된 마이닝 PR — 같은 패턴을 두 번 추천하지 않으려고 읽는다."""
    try:
        with connect().cursor() as cur:
            cur.execute(
                """select id, resource_id, branch_name, title, status, created_at
                   from public.resource_pull_requests
                   where tenant_id = %s and resource_type = 'bpmn' and branch_name like 'mined-%%'""",
                (tenant_id,),
            )
            return list(cur.fetchall())
    finally:
        end_read()


def next_mined_version(proc_def_id: str, tenant_id: str) -> str:
    """이미 있는 마이닝 제안 다음 번호."""
    try:
        with connect().cursor() as cur:
            cur.execute(
                "select count(*) as n from public.proc_def_version where proc_def_id = %s and tenant_id = %s",
                (proc_def_id, tenant_id),
            )
            n = (cur.fetchone() or {}).get("n", 0)
        return f"0.{int(n) + 1}"
    finally:
        end_read()
