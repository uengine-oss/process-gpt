"""마이닝 파이프라인 오케스트레이션.

handover_events → 이벤트 로그 → DFG → 프로세스 트리 → proc_def JSON → PR.
LLM 은 쓰지 않는다(결정론적). 활동명 정규화·게이트웨이 조건 보강은 후속 단계의 몫.
"""
from __future__ import annotations

from collections import Counter

from . import db, eventlog, proposal
from .discovery.dfg import build_dfg, filter_noise
from .discovery.inductive import discover
from .discovery.to_procdef import lang_of, text, to_process_definition, validate_definition

# 케이스가 이보다 적으면 패턴이라 부를 수 없다
MIN_CASES = 3
# 단계가 1개뿐인 케이스는 순서 정보가 없어 제어 흐름에 기여하지 못한다.
# 오히려 "이 케이스엔 그 단계가 없다"로 읽혀 모든 단계를 선택적으로 만든다.
MIN_CASE_LEN = 2


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

    return {
        "ok": True,
        "stats": stats,
        "tree": repr(tree),
        "tree_node": tree,
        "profile": profile,
    }


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


def run(
    *,
    tenant_id: str,
    process_id: str,
    process_name: str,
    min_freq: int = 1,
    dry_run: bool = False,
    case_ids: list[str] | None = None,
    lang: str | None = None,
) -> dict:
    """전체 파이프라인. dry_run 이면 PR 을 만들지 않는다. case_ids 를 주면 그 케이스(패턴 하나)만.
    lang('ko' | 'en'): 정의의 이름·설명과 PR 제목·설명의 언어 — 요청한 쪽의 언어."""
    rows = db.fetch_handover_events(tenant_id, case_ids=case_ids)
    result = analyze(rows, min_freq=min_freq)
    if not result["ok"]:
        return result

    lang = lang_of(result["tree_node"].activities(), lang)
    defn, problems = build_definition(result, process_id=process_id, process_name=process_name, lang=lang)
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
        lang=lang,
    )
    return out
