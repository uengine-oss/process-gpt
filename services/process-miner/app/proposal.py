"""도출 결과를 기존 리소스 PR 승인 틀로 제안한다.

살아 있는 proc_def 는 건드리지 않는다. proc_def_version 에 draft 를 넣고
resource_pull_requests 에 resource_type='bpmn' PR 을 연다 —
ProcessDefinitionVersionDialog 가 만드는 PR 과 레코드 모양이 같아서
기존 승인 UI 가 그대로 동작한다.
"""
from __future__ import annotations

import json
import uuid as uuidlib

from . import db


def _summary_lines(defn: dict, stats: dict, lang: str = "ko") -> list[str]:
    acts = defn.get("activities", [])
    gws = defn.get("gateways", [])
    agent_acts = [a for a in acts if a.get("agent")]
    en = lang == "en"
    lines = [
        (f"Found in {stats['event_count']} handover records / {stats['case_count']} cases." if en
         else f"핸드오버 로그 {stats['event_count']}건 / 케이스 {stats['case_count']}건에서 도출했습니다."),
        "",
        f"- {len(acts)} activities, {len(gws)} gateways" if en else f"- 활동 {len(acts)}개, 게이트웨이 {len(gws)}개",
        f"- {len(defn.get('roles', []))} roles" if en else f"- 참여 역할 {len(defn.get('roles', []))}개",
    ]
    if agent_acts:
        names = ", ".join(a["name"] for a in agent_acts)
        lines.append(f"- {len(agent_acts)} activities agents did (can run automatically): {names}" if en
                     else f"- 에이전트가 수행하던 활동 {len(agent_acts)}개(자동 실행 가능): {names}")
    lines.append("")
    lines.append("Observed flows:" if en else "관측된 흐름:")
    for v in stats.get("variants", [])[:5]:
        lines.append(f"  - {' → '.join(v['trace'])}  ({v['count']} {'case' if v['count'] == 1 else 'cases'})" if en
                     else f"  - {' → '.join(v['trace'])}  ({v['count']}건)")
    return lines


def pr_title(proc_def_name: str, lang: str = "ko") -> str:
    return f"[Mining] {proc_def_name}" if lang == "en" else f"[마이닝] {proc_def_name}"


def open_process_pr(
    *,
    defn: dict,
    tenant_id: str,
    proc_def_id: str,
    proc_def_name: str,
    stats: dict,
    requester_id: str | None = None,
    lang: str = "ko",
) -> dict:
    """draft 버전 + PR 을 만들고 식별자를 돌려준다. lang: 제목·설명의 언어('ko' | 'en')."""
    conn = db.connect()
    version = db.next_mined_version(proc_def_id, tenant_id)
    arcv_id = f"{proc_def_id}_{version}"
    description = "\n".join(_summary_lines(defn, stats, lang))
    title = pr_title(proc_def_name, lang)

    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                insert into public.proc_def_version
                    (arcv_id, proc_def_id, version, version_tag, definition, message, tenant_id, is_draft)
                values (%s, %s, %s, 'minor', %s, %s, %s, true)
                returning uuid
                """,
                (arcv_id, proc_def_id, version, json.dumps(defn, ensure_ascii=False), title, tenant_id),
            )
            version_uuid = cur.fetchone()["uuid"]

            pr_id = str(uuidlib.uuid4())
            # requester_id 는 uuid[] 이고 users 를 참조하지 않는다(마이너는 사람이 아니다).
            requesters = [requester_id] if requester_id else []
            cur.execute(
                """
                insert into public.resource_pull_requests
                    (id, tenant_id, resource_type, resource_id, branch_name, base_branch,
                     title, description, status, requester_id)
                values (%s, %s, 'bpmn', %s, %s, 'main', %s, %s, 'OPEN', %s::uuid[])
                returning id
                """,
                (pr_id, tenant_id, proc_def_id, f"mined-v{version}", title, description, requesters),
            )
            pr = cur.fetchone()
    except Exception:
        conn.rollback()  # a failed write must not leave the shared connection in an aborted transaction
        raise
    conn.commit()

    return {
        "pr_id": pr["id"],
        "proc_def_id": proc_def_id,
        "version": version,
        "version_uuid": str(version_uuid),
        "title": title,
        "description": description,
    }
