"""로컬 Supabase 의 Postgres 를 docker exec 로 직접 본다.

워커가 쓰는 경로(PostgREST)를 거치지 않는 이유: 판정은 워커의 말이 아니라 DB 의
상태로 해야 한다. 테스트가 워커와 같은 경로로 읽으면 같은 이유로 같이 틀린다.

안전장치 — 이 DB 에는 개발 데이터가 있다.
  - 이 테스트가 만드는 행은 activity_name 이 MARKER 로 시작한다.
  - 지우는 것은 이 테스트가 만든 id 목록 범위뿐이다. 조건 없는 DELETE 는 없다.
"""

from __future__ import annotations

import os
import subprocess
import uuid
from dataclasses import dataclass

CONTAINER = os.getenv("SB_DB_CONTAINER", "supabase_db_process-gpt-vue3")
MARKER = "[lease-svc]"


def sql(query: str) -> list[list[str]]:
    out = subprocess.run(
        ["docker", "exec", "-i", CONTAINER, "psql", "-U", "postgres", "-d", "postgres",
         "-qAt", "-F", "\t", "-v", "ON_ERROR_STOP=1", "-c", query],
        capture_output=True, text=True, check=True,
    ).stdout
    return [line.split("\t") for line in out.splitlines() if line]


def _lit(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


@dataclass(frozen=True)
class Snapshot:
    """한 시점의 todolist 행. 시각은 모두 DB 시계(epoch 초)다."""

    at: float
    status: str
    draft_status: str
    consumer: str
    lease_until: float | None
    claim_count: int
    has_draft: bool

    @property
    def lease_left(self) -> float | None:
        return None if self.lease_until is None else self.lease_until - self.at

    @property
    def terminal(self) -> bool:
        return self.draft_status in ("COMPLETED", "FAILED", "CANCELLED")


def snapshot(todo_id: str) -> Snapshot:
    rows = sql(
        "SELECT extract(epoch FROM now()), status, coalesce(draft_status::text, ''), "
        "coalesce(consumer, ''), coalesce(extract(epoch FROM lease_until)::text, ''), "
        "coalesce(claim_count, 0), (draft IS NOT NULL) "
        f"FROM todolist WHERE id = {_lit(todo_id)}"
    )
    if not rows:
        raise LookupError(f"todolist {todo_id} 가 없다")
    at, status, ds, consumer, lease, claims, has_draft = rows[0]
    return Snapshot(
        at=float(at), status=status, draft_status=ds, consumer=consumer,
        lease_until=float(lease) if lease else None, claim_count=int(claims),
        has_draft=has_draft == "t",
    )


def template_exists(template_id: str) -> bool:
    return bool(sql(f"SELECT 1 FROM todolist WHERE id = {_lit(template_id)}"))


def claimable_count(agent_orch: str) -> int:
    """이 테스트가 만든 것이 아닌, 지금 워커를 띄우면 집힐 행의 수.

    0 이 아니면 테스트 워커가 개발 데이터를 집어 실행한다. 그 상태에서는 시작하지 않는다.
    """
    rows = sql(
        "SELECT count(*) FROM todolist t "
        f"WHERE t.agent_orch::text = {_lit(agent_orch)} AND t.status = 'IN_PROGRESS' "
        f"AND coalesce(t.activity_name, '') NOT LIKE {_lit(MARKER + '%')} AND ("
        "  (t.agent_mode IN ('DRAFT','COMPLETE') AND t.draft IS NULL AND t.draft_status IS NULL)"
        "  OR t.draft_status = 'FB_REQUESTED'"
        "  OR (t.draft_status = 'STARTED' AND t.lease_until IS NOT NULL AND t.lease_until < now()))"
    )
    return int(rows[0][0])


def clone_task(template_id: str, agent_orch: str, *, legacy_claim_by: str | None = None) -> str:
    """템플릿 행을 복제해 새 작업을 만든다.

    DRAFT 모드로 둔다 — 초안만 저장하고 프로세스를 진행시키지 않는다.
    legacy_claim_by 를 주면 "lease 를 모르는 구버전 워커가 집은 행" 을 만든다
    (STARTED, lease_until NULL).
    """
    todo_id = str(uuid.uuid4())
    if legacy_claim_by:
        claim = (f"'draft_status', 'STARTED', 'consumer', {_lit(legacy_claim_by)}, "
                 "'lease_until', null, 'claim_count', 0")
    else:
        claim = "'draft_status', null, 'consumer', null, 'lease_until', null, 'claim_count', 0"
    sql(
        "INSERT INTO todolist "
        "SELECT (jsonb_populate_record(null::todolist, to_jsonb(t) || jsonb_build_object("
        f"  'id', {_lit(todo_id)}, 'agent_orch', {_lit(agent_orch)},"
        f"  'activity_name', {_lit(MARKER + ' ')} || t.activity_name,"
        "  'status', 'IN_PROGRESS', 'agent_mode', 'DRAFT', 'draft', null, 'output', null,"
        "  'log', null, 'feedback', null, 'temp_feedback', null,"
        "  'start_date', now()::timestamp, 'end_date', null, 'updated_at', now(),"
        f"  {claim}"
        "))).* "
        f"FROM todolist t WHERE t.id = {_lit(template_id)}"
    )
    return todo_id


def event_count(todo_id: str, event_type: str) -> int:
    rows = sql(
        f"SELECT count(*) FROM events WHERE todo_id::text = {_lit(todo_id)} "
        f"AND event_type::text = {_lit(event_type)}"
    )
    return int(rows[0][0])


def remove(todo_ids: list[str]) -> None:
    """이 테스트가 만든 행과, 트리거가 그 행에서 파생시킨 행만 지운다."""
    if not todo_ids:
        return
    ids = ", ".join(_lit(i) for i in todo_ids)
    sql(f"DELETE FROM events WHERE todo_id::text IN ({ids})")
    sql(f"DELETE FROM task_execution_properties WHERE todo_id IN ({ids})")
    sql(f"DELETE FROM notifications WHERE url IN (SELECT '/todolist/' || x FROM unnest(ARRAY[{ids}]) x)")
    sql(f"DELETE FROM todolist WHERE id::text IN ({ids}) AND activity_name LIKE {_lit(MARKER + '%')}")
