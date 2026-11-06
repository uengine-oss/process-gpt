"""반복 패턴 찾기 — 한 테넌트의 인계 기록에는 서로 다른 업무가 섞여 있다.

miner.run 은 넘겨받은 케이스 전부를 프로세스 하나로 도출한다. 테넌트 전체를 그대로 넣으면
견적 처리와 설계 제안처럼 서로 다른 업무가 한 모델에 뭉친다. 그래서 먼저 케이스를 활동
집합의 유사도(Jaccard)로 묶고, 묶음마다 따로 도출한다. 이것도 결정론적이다(LLM 없음).

  케이스 → 활동 집합 → 유사도 그래프의 연결 요소 = 패턴 → 패턴별 miner.analyze(case_ids)

패턴 키는 핵심 활동(케이스 절반 이상에 나온 활동) 집합의 해시다 — 같은 업무가 더 쌓여도
키가 바뀌지 않아, 이미 추천한 패턴을 다시 추천하지 않을 수 있다.
"""
from __future__ import annotations

import hashlib
from collections import Counter, defaultdict

from . import eventlog

MIN_CASES = 3
MIN_CASE_LEN = 2
SIMILARITY = 0.6


def _jaccard(a: set, b: set) -> float:
    return len(a & b) / len(a | b) if a or b else 0.0


def pattern_key(core: list[str]) -> str:
    return hashlib.sha1("|".join(sorted(core)).encode("utf-8")).hexdigest()[:12]


def _follows(acts: set, flow: dict) -> bool:
    """이 케이스가 결정된 흐름을 그대로 따랐나 — 흐름에 없는 단계가 없고, 핵심 단계는 모두 거쳤다."""
    return acts <= flow["activities"] and flow["core"] <= acts


def find(rows: list[dict], *, min_cases: int = MIN_CASES, similarity: float = SIMILARITY,
         known: list[dict] | None = None) -> list[dict]:
    """반복되는 업무 묶음. 이미 정의된 프로세스에서 나온 기록(proc_def_id 있음)은 뺀다.

    known: 이미 결정된(정식 등록·보류) 흐름 [{"key", "case_ids"}]. 그 흐름의 사례와, 그 흐름을 그대로
    따른 새 사례(흐름에 없는 단계가 없고 핵심 단계를 모두 거친 것)는 그 흐름의 키로 따로 돌려준다 —
    새 추천이 아니라 그 흐름의 증거다. 나머지 케이스만 유사도로 묶는다. 결정된 흐름의 사례가 남아
    있으면 단계 하나만 다른 업무도 유사도 기준을 넘겨 그 사례들과 한 묶음이 되고, 결정된 흐름에
    흡수돼 새 추천이 되지 못했다.
    """
    defined_cases = {r.get("origin_room_id") or r.get("case_id") for r in rows if r.get("proc_def_id")}
    rows = [r for r in rows if (r.get("origin_room_id") or r.get("case_id")) not in defined_cases]
    events = eventlog.build_events(rows)
    traces = {c: t for c, t in eventlog.to_traces(events).items() if len(t) >= MIN_CASE_LEN}
    by_case: dict[str, list] = defaultdict(list)
    for e in events:
        if e.case_id in traces:
            by_case[e.case_id].append(e)

    cases = sorted(traces)
    sets = {c: set(traces[c]) for c in cases}

    # 결정된 흐름이 어떤 단계로 이뤄졌는지는 그 흐름에 묶인 사례에서 읽는다(핵심 = 사례 절반 이상)
    flows: list[dict] = []
    claimed: dict[str, str] = {}
    for k in known or []:
        mine = [c for c in dict.fromkeys(k.get("case_ids") or []) if c in sets and c not in claimed]
        if not mine or not k.get("key"):
            continue
        freq = Counter(a for c in mine for a in sets[c])
        flows.append({"key": str(k["key"]), "activities": set(freq), "core": {a for a, n in freq.items() if n * 2 >= len(mine)}})
        for c in mine:
            claimed[c] = flows[-1]["key"]
    for c in cases:
        if c in claimed:
            continue
        fits = [f for f in flows if _follows(sets[c], f)]
        if fits:
            claimed[c] = max(fits, key=lambda f: _jaccard(sets[c], f["activities"]))["key"]

    free = [c for c in cases if c not in claimed]
    adj: dict[str, set[str]] = {c: set() for c in free}
    for i, a in enumerate(free):
        for b in free[i + 1:]:
            if _jaccard(sets[a], sets[b]) >= similarity:
                adj[a].add(b)
                adj[b].add(a)

    groups: list[tuple[list[str], str | None]] = []
    for f in flows:
        groups.append(([c for c in cases if claimed.get(c) == f["key"]], f["key"]))
    seen: set[str] = set()
    for c in free:
        if c in seen:
            continue
        comp, stack = [], [c]
        while stack:
            x = stack.pop()
            if x in seen:
                continue
            seen.add(x)
            comp.append(x)
            stack.extend(adj[x] - seen)
        if len(comp) >= min_cases:
            groups.append((comp, None))

    out = [_describe(comp, key, sets, traces, by_case) for comp, key in groups]
    out.sort(key=lambda p: (-p["case_count"], p["last_seen"] or ""), reverse=False)
    return out


def _describe(comp: list[str], key: str | None, sets: dict, traces: dict, by_case: dict) -> dict:
    """케이스 묶음 하나 → 패턴(핵심 활동·주 변형·단계별 담당·도구). key 가 없으면 핵심 활동의 해시."""
    freq = Counter(a for x in comp for a in sets[x])
    core = [a for a, n in freq.items() if n * 2 >= len(comp)]
    variants = Counter(tuple(traces[x]) for x in comp)
    main = list(variants.most_common(1)[0][0])
    evs = [e for x in comp for e in by_case[x]]
    when = sorted(str(e.occurred_at) for e in evs)
    steps = []
    for a in main:
        mine = [e for e in evs if e.activity == a]
        roles = Counter(e.role for e in mine if e.role)
        people = Counter(e.resource_name for e in mine if e.resource_name)
        steps.append({
            "activity": a,
            "cases": freq[a],
            "by_agent": sum(1 for e in mine if e.is_agent),
            "total": len(mine),
            "role": roles.most_common(1)[0][0] if roles else "",
            "performers": [n for n, _ in people.most_common(3)],
            "tools": [t for t, _ in Counter(t for e in mine for t in e.tools).most_common()],
            "skills": [k for k, _ in Counter(k for e in mine for k in e.skills).most_common()],
        })
    key = key or pattern_key(core)
    return {
        "key": key,
        "process_id": f"mined_{key}",
        "case_ids": sorted(comp, key=lambda x: str(by_case[x][0].occurred_at)),
        "case_count": len(comp),
        "event_count": len(evs),
        "core_activities": sorted(core, key=main.index) if all(a in main for a in core) else sorted(core),
        "main_variant": main,
        "variants": [{"trace": list(t), "count": n} for t, n in variants.most_common()],
        "steps": steps,
        "first_seen": when[0] if when else None,
        "last_seen": when[-1] if when else None,
        "automation_rate": round(sum(1 for e in evs if e.is_agent) / len(evs), 3) if evs else 0,
    }
