"""끝난 스레드를 업무별로 묶는다.

한 테넌트의 인계 기록에는 견적·계약·구매처럼 서로 다른 업무가 섞여 있다. 모두를 한 로그로
도출하면 첫 단계부터 "이 업무들 중 하나를 한다" 는 배타 분기가 생긴다 — 각 갈래의 흐름은
관측된 그대로지만, 서로 다른 프로세스를 한 프로세스의 갈래로 그린 것이라 업무 관점에서 틀리다.

그래서 도출 전에 스레드가 거친 단계 집합으로 묶는다. 두 스레드의 단계 집합이 절반 이상
겹치면(자카드 유사도 ≥ 0.5) 같은 업무로 잇고, 이어진 것끼리 한 묶음이다(단일 연결).
반려가 있고 없는 건(0.75), 승인자가 갈리는 건(0.5)은 한 업무로 남고, 단계를 공유하지
않는 업무는 갈린다. LLM 을 쓰지 않는 결정론적 규칙이다.
"""
from __future__ import annotations

import hashlib
from collections import Counter

# 같은 업무로 볼 단계 집합의 최소 겹침
SIMILARITY = 0.5


def jaccard(a: frozenset, b: frozenset) -> float:
    union = a | b
    return len(a & b) / len(union) if union else 0.0


def process_key(tenant_id: str, activities) -> str:
    """업무 묶음의 id. 테넌트와 활동 집합에서 결정론적으로 만든다(제안 정의 id 와 같다)."""
    acts = sorted(set(activities))
    digest = hashlib.sha1(("\x1f".join([tenant_id, *acts])).encode("utf-8")).hexdigest()[:10]
    return f"mined_{digest}"


def group_cases(traces_by_case: dict[str, list[str]], threshold: float = SIMILARITY) -> list[list[str]]:
    """케이스 id 묶음 목록. 큰 묶음이 앞, 같은 크기면 첫 케이스 id 순(결정론적)."""
    sets = {c: frozenset(t) for c, t in traces_by_case.items() if t}
    uniq = sorted(set(sets.values()), key=lambda s: sorted(s))
    parent = list(range(len(uniq)))

    def find(i: int) -> int:
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    for i in range(len(uniq)):
        for j in range(i + 1, len(uniq)):
            if jaccard(uniq[i], uniq[j]) >= threshold:
                parent[find(i)] = find(j)
    index = {s: i for i, s in enumerate(uniq)}
    groups: dict[int, list[str]] = {}
    for c in sorted(sets):
        groups.setdefault(find(index[sets[c]]), []).append(c)
    return sorted(groups.values(), key=lambda g: (-len(g), g[0]))


def summarize(tenant_id: str, traces_by_case: dict[str, list[str]], cases: list[str]) -> dict:
    """묶음 하나의 요약 — id · 이름 · 건수 · 관측 흐름."""
    traces = [traces_by_case[c] for c in cases]
    variants = Counter(tuple(t) for t in traces)
    activities = sorted({a for t in traces for a in t})
    top = variants.most_common(1)[0][0] if variants else ()
    return {
        "process_key": process_key(tenant_id, activities),
        "name": f"{top[0]} 프로세스" if top else "식별된 업무",
        "case_count": len(cases),
        "activities": activities,
        "variants": [{"trace": list(t), "count": n} for t, n in variants.most_common()],
        "cases": list(cases),
    }


def closest(activities, groups: list[dict], threshold: float = SIMILARITY) -> str | None:
    """진행 중 스레드가 어느 업무에 가까운가. 표시용이며 도출에는 넣지 않는다."""
    acts = frozenset(activities)
    best, score = None, 0.0
    for g in groups:
        sc = jaccard(acts, frozenset(g["activities"]))
        if sc >= threshold and sc > score:
            best, score = g["process_key"], sc
    return best
