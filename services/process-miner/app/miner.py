"""마이닝 파이프라인 오케스트레이션.

handover_events → 이벤트 로그 → DFG → 프로세스 트리 → proc_def JSON → PR.
LLM 은 쓰지 않는다(결정론적). 활동명 정규화·게이트웨이 조건 보강은 후속 단계의 몫.
"""
from __future__ import annotations

import hashlib
from collections import Counter

from . import db, eventlog, proposal
from .discovery.inductive import discover_from_traces
from .discovery.to_procdef import to_process_definition, validate_definition

# 케이스가 이보다 적으면 패턴이라 부를 수 없다
MIN_CASES = 3
# 단계가 1개뿐인 케이스는 순서 정보가 없어 제어 흐름에 기여하지 못한다.
# 오히려 "이 케이스엔 그 단계가 없다"로 읽혀 모든 단계를 선택적으로 만든다.
MIN_CASE_LEN = 2


def analyze(rows: list[dict], min_freq: int = 1) -> dict:
    """이벤트 행들에서 프로세스를 도출한다(DB 쓰기 없음).

    진행 중인 스레드는 뺀다. 넣으면 아직 하지 않은 뒤 단계가 '건너뛸 수 있는 단계' 로 읽힌다.
    """
    rows, open_cases = eventlog.finished_rows(rows)
    events = eventlog.build_events(rows)
    flow_events = eventlog.control_flow_events(events)
    traces_by_case = eventlog.to_traces(events)
    traces = [t for t in traces_by_case.values() if len(t) >= MIN_CASE_LEN]
    dropped = sum(1 for t in traces_by_case.values() if 0 < len(t) < MIN_CASE_LEN)

    variants = Counter(tuple(t) for t in traces)
    stats = {
        "dropped_short_cases": dropped,
        "in_progress_cases": open_cases,
        "event_count": len(flow_events),
        "delegation_count": sum(1 for e in events if e.kind == eventlog.DELEGATION),
        "case_count": len(traces),
        "activity_count": len({a for t in traces for a in t}),
        "variants": [{"trace": list(t), "count": n} for t, n in variants.most_common()],
        "handover_matrix": [
            {"from": a, "to": b, "count": n} for (a, b), n in sorted(eventlog.handover_matrix(events).items(), key=lambda kv: -kv[1])
        ],
    }

    if len(traces) < MIN_CASES:
        return {"ok": False, "reason": f"케이스가 {len(traces)}건뿐입니다(최소 {MIN_CASES}건 필요)", "stats": stats}

    tree = discover_from_traces(traces, min_freq=min_freq)
    # 역할은 그 단계를 넘겨받아 수행한 리소스로 정한다(위임받아 도운 에이전트는 제외).
    profile = eventlog.resource_profile(flow_events)

    return {
        "ok": True,
        "stats": stats,
        "tree": repr(tree),
        "tree_node": tree,
        "profile": profile,
    }


def suggest_identity(result: dict, tenant_id: str) -> tuple[str, str]:
    """화면이 id·이름을 정하지 않았을 때 도출 결과로 정한다(데모 기본값을 쓰지 않는다).

    id 는 테넌트와 활동 집합에서 결정론적으로 만든다 — 같은 흐름을 다시 도출하면 같은
    id 라 제안이 한 정의의 버전으로 쌓이고, 다른 흐름이나 다른 테넌트와는 섞이지 않는다.
    이름은 가장 많이 관측된 흐름의 첫 단계에서 따온다.
    """
    acts = sorted({a for v in result["stats"]["variants"] for a in v["trace"]})
    digest = hashlib.sha1(("\x1f".join([tenant_id, *acts])).encode("utf-8")).hexdigest()[:10]
    variants = result["stats"]["variants"]
    first = variants[0]["trace"][0] if variants and variants[0]["trace"] else "식별된 업무"
    return f"mined_{digest}", f"{first} 프로세스"


def build_definition(result: dict, *, process_id: str, process_name: str) -> tuple[dict, list[str]]:
    defn = to_process_definition(
        result["tree_node"],
        process_id=process_id,
        process_name=process_name,
        description=f"핸드오버 로그 {result['stats']['event_count']}건에서 자동 도출된 프로세스",
        profile=result["profile"],
    )
    return defn, validate_definition(defn)


def run(
    *,
    tenant_id: str,
    process_id: str | None = None,
    process_name: str | None = None,
    min_freq: int = 1,
    dry_run: bool = False,
    requester_id: str | None = None,
) -> dict:
    """전체 파이프라인. dry_run 이면 PR 을 만들지 않는다."""
    rows = db.fetch_handover_events(tenant_id)
    result = analyze(rows, min_freq=min_freq)
    if not result["ok"]:
        return result
    suggested_id, suggested_name = suggest_identity(result, tenant_id)
    process_id = process_id or suggested_id
    process_name = process_name or suggested_name

    defn, problems = build_definition(result, process_id=process_id, process_name=process_name)
    if problems:
        return {"ok": False, "reason": "도출된 정의가 계약 검증에 실패했습니다", "problems": problems, "stats": result["stats"]}

    out = {"ok": True, "stats": result["stats"], "definition": defn, "tree": result["tree"]}
    if dry_run:
        out["pr"] = None
        return out

    out["pr"] = proposal.open_process_pr(
        defn=defn,
        tenant_id=tenant_id,
        proc_def_id=process_id,
        proc_def_name=process_name,
        stats=result["stats"],
        requester_id=requester_id,
    )
    return out
