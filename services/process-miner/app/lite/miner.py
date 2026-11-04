"""Lite 의 도출 파이프라인 — 고른 케이스(패턴 하나)만 프로세스로 도출한다. DB 에 쓰지 않는다.

handover_events → 이벤트 로그 → DFG → 프로세스 트리 → proc_def JSON.
LLM 은 쓰지 않는다(결정론적).
"""
from __future__ import annotations

from collections import Counter

from .. import db
from . import eventlog
from .discovery.dfg import build_dfg, filter_noise
from .discovery.inductive import discover
from .discovery.to_procdef import lang_of, text, to_process_definition, validate_definition

# 케이스가 이보다 적으면 패턴이라 부를 수 없다
MIN_CASES = 3
# 단계가 1개뿐인 케이스는 순서 정보가 없어 제어 흐름에 기여하지 못한다.
MIN_CASE_LEN = 2

_COLUMNS = """
    id, tenant_id, case_id, origin_room_id, source, is_explicit,
    from_user_id, from_user_name, from_is_agent,
    to_user_id, to_user_name, to_role, to_is_agent, agent_orch,
    activity_label, next_activity_label, norm_activity_label,
    artifact_refs, proc_def_id,
    from_room_id, to_room_id, occurred_at, returned_at
"""


def fetch_events(tenant_id: str, case_ids: list[str] | None = None, limit: int = 5000) -> list[dict]:
    """한 테넌트의 인계 기록. case_ids 를 주면 그 케이스(스레드 뿌리)만. 테넌트 없이는 거부한다."""
    if not tenant_id or not str(tenant_id).strip():
        raise ValueError("tenant_id 가 필요합니다")
    sql = f"""
        select {_COLUMNS}
        from public.handover_events
        where tenant_id = %(tenant)s::text
          and (%(cases)s::text[] is null or coalesce(origin_room_id, case_id) = any(%(cases)s::text[]))
        order by origin_room_id, occurred_at
        limit %(limit)s
    """
    return db.query(sql, {"tenant": tenant_id, "limit": limit, "cases": list(case_ids) if case_ids else None})


def analyze(rows: list[dict], min_freq: int = 1) -> dict:
    """이벤트 행들에서 프로세스를 도출한다(DB 쓰기 없음)."""
    events = eventlog.build_events(rows)
    traces_by_case = eventlog.to_traces(events)
    traces = [t for t in traces_by_case.values() if len(t) >= MIN_CASE_LEN]
    dropped = sum(1 for t in traces_by_case.values() if 0 < len(t) < MIN_CASE_LEN)

    variants = Counter(tuple(t) for t in traces)
    stats = {
        "dropped_short_cases": dropped,
        "event_count": len(events),
        "case_count": len(traces),
        "activity_count": len({a for t in traces for a in t}),
        "variants": [{"trace": list(t), "count": n} for t, n in variants.most_common()],
        "handover_matrix": [
            {"from": a, "to": b, "count": n} for (a, b), n in sorted(eventlog.handover_matrix(events).items(), key=lambda kv: -kv[1])
        ],
    }

    if len(traces) < MIN_CASES:
        return {"ok": False, "reason": f"케이스가 {len(traces)}건뿐입니다(최소 {MIN_CASES}건 필요)", "stats": stats}

    dfg = filter_noise(build_dfg(traces), min_freq=min_freq)
    tree = discover(dfg, traces=traces)
    profile = eventlog.resource_profile(events)
    return {"ok": True, "stats": stats, "tree": repr(tree), "tree_node": tree, "profile": profile}


def build_definition(result: dict, *, process_id: str, process_name: str, lang: str | None = None) -> tuple[dict, list[str]]:
    """lang: 이름·설명을 쓸 언어(요청한 테넌트·사람의 언어). 없으면 기록된 활동 이름의 언어."""
    lang = lang_of(result["tree_node"].activities(), lang)
    defn = to_process_definition(
        result["tree_node"],
        process_id=process_id,
        process_name=process_name,
        description=text(lang, "process", n=result["stats"]["event_count"]),
        profile=result["profile"],
        lang=lang,
        case_count=result["stats"]["case_count"],
    )
    return defn, validate_definition(defn)


def run(*, tenant_id: str, process_id: str, process_name: str, case_ids: list[str], min_freq: int = 1, lang: str | None = None) -> dict:
    """고른 케이스만으로 도출한다. 제안(PR)은 만들지 않는다 — Lite 가 정식 등록 때 자기 경로로 저장한다."""
    result = analyze(fetch_events(tenant_id, case_ids=case_ids), min_freq=min_freq)
    if not result["ok"]:
        return result
    defn, problems = build_definition(result, process_id=process_id, process_name=process_name, lang=lang)
    if problems:
        return {"ok": False, "reason": "도출된 정의가 계약 검증에 실패했습니다", "problems": problems, "stats": result["stats"]}
    return {"ok": True, "stats": result["stats"], "definition": defn, "tree": result["tree"]}
