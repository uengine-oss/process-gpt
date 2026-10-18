"""Inductive Miner — DFG 에서 컷을 재귀 탐지해 프로세스 트리를 만든다.

의존성 없는 자체 구현. 표준 IM 순서대로 컷을 시도한다:
    base case → 배타 선택(XOR) → 순차(SEQ) → 병렬(AND) → 반복(LOOP)
어떤 컷도 못 찾으면 fallback 으로 XOR 묶음을 만든다(구조는 건전하게 유지).

pm4py 대신 직접 구현한 이유: pm4py 는 GPLv3 라 상용 배포에 라이선스 검토가 필요하다.
"""
from __future__ import annotations

from .dfg import Dfg
from .process_tree import AND, LOOP, SEQ, XOR, Node, act, flatten, tau


# ---------------------------------------------------------------------------
# 그래프 유틸
# ---------------------------------------------------------------------------
def _undirected_components(activities: set[str], dfg: Dfg) -> list[set[str]]:
    """방향을 무시한 연결 요소. 서로 전혀 안 닿는 덩어리 = 배타 선택 후보."""
    adj: dict[str, set[str]] = {a: set() for a in activities}
    for (a, b) in dfg.edges:
        if a in activities and b in activities and a != b:
            adj[a].add(b)
            adj[b].add(a)

    seen: set[str] = set()
    comps: list[set[str]] = []
    for a in sorted(activities):
        if a in seen:
            continue
        stack, comp = [a], set()
        while stack:
            x = stack.pop()
            if x in comp:
                continue
            comp.add(x)
            stack.extend(adj[x] - comp)
        seen |= comp
        comps.append(comp)
    return comps


def _reachability(activities: set[str], dfg: Dfg) -> dict[str, set[str]]:
    """각 활동에서 도달 가능한 활동 집합(자기 자신 제외한 전이 폐포)."""
    reach: dict[str, set[str]] = {a: set() for a in activities}
    for (a, b) in dfg.edges:
        if a in activities and b in activities and a != b:
            reach[a].add(b)
    changed = True
    while changed:
        changed = False
        for a in activities:
            add = set()
            for b in reach[a]:
                add |= reach[b] - reach[a] - {a}
            if add:
                reach[a] |= add
                changed = True
    return reach


# ---------------------------------------------------------------------------
# 컷 탐지
# ---------------------------------------------------------------------------
def _xor_cut(activities: set[str], dfg: Dfg) -> list[set[str]] | None:
    comps = _undirected_components(activities, dfg)
    return comps if len(comps) > 1 else None


def _seq_cut(activities: set[str], dfg: Dfg) -> list[set[str]] | None:
    """순차로 쪼갤 수 없는 것끼리 묶고, 그 묶음들을 순서대로 세운다.

    두 활동은 다음 중 하나면 같은 묶음이다:
      - 서로 도달 가능(순환/병렬)
      - 서로 도달 불가(배타 분기의 양 갈래)
    둘 다 순서를 주장할 수 없는 관계이므로 한 덩어리로 남겨 하위 재귀가 판단하게 한다.
    (상호 도달만으로 묶으면 승인/반려 같은 배타 갈래가 순차 단계로 쪼개져 버린다.)
    """
    reach = _reachability(activities, dfg)

    def same_group(a: str, b: str) -> bool:
        ab, ba = b in reach[a], a in reach[b]
        return ab == ba  # 둘 다 참(상호 도달) 또는 둘 다 거짓(상호 미도달)

    # 관계가 전이적이지 않으므로 연결 요소로 묶는다
    adj: dict[str, set[str]] = {a: set() for a in activities}
    for a in activities:
        for b in activities:
            if a != b and same_group(a, b):
                adj[a].add(b)
                adj[b].add(a)

    groups: list[set[str]] = []
    seen: set[str] = set()
    for a in sorted(activities):
        if a in seen:
            continue
        stack, comp = [a], set()
        while stack:
            x = stack.pop()
            if x in comp:
                continue
            comp.add(x)
            stack.extend(adj[x] - comp)
        seen |= comp
        groups.append(comp)
    if len(groups) < 2:
        return None

    def before(g1: set[str], g2: set[str]) -> bool:
        """g1 이 g2 보다 앞선다: 앞으로 닿는 건 있고, 되돌아오는 건 없다."""
        fwd = any(b in reach[a] for a in g1 for b in g2)
        bwd = any(a in reach[b] for a in g1 for b in g2)
        return fwd and not bwd

    ordered: list[set[str]] = []
    remaining = list(groups)
    while remaining:
        head = None
        for g in remaining:
            if not any(before(other, g) for other in remaining if other is not g):
                head = g
                break
        if head is None:  # 순환이라 순차로 못 쪼갬
            return None
        ordered.append(head)
        remaining.remove(head)
    return ordered


def _and_cut(activities: set[str], dfg: Dfg) -> list[set[str]] | None:
    """서로 양방향으로 오간 활동들은 병렬로 본다.

    보수적으로 판단한다 — 양방향 간선이 하나도 없으면 즉시 포기해서,
    단순 순차 로그를 병렬로 오인하지 않게 한다.
    """
    if len(activities) < 2:
        return None
    both = {(a, b) for a in activities for b in activities if a != b and (a, b) in dfg.edges and (b, a) in dfg.edges}
    if not both:
        return None

    # 양방향이 '아닌' 관계로 연결 요소를 만들면, 그 요소들끼리는 전부 양방향이다.
    adj: dict[str, set[str]] = {a: set() for a in activities}
    for a in activities:
        for b in activities:
            if a != b and (a, b) not in both:
                adj[a].add(b)
                adj[b].add(a)

    seen: set[str] = set()
    parts: list[set[str]] = []
    for a in sorted(activities):
        if a in seen:
            continue
        stack, comp = [a], set()
        while stack:
            x = stack.pop()
            if x in comp:
                continue
            comp.add(x)
            stack.extend(adj[x] - comp)
        seen |= comp
        parts.append(comp)
    if len(parts) < 2:
        return None
    # 각 갈래는 시작과 끝을 모두 가져야 진짜 병렬이다
    for p in parts:
        if not (p & set(dfg.starts)) or not (p & set(dfg.ends)):
            return None
    return parts


def _loop_cut(activities: set[str], dfg: Dfg) -> list[set[str]] | None:
    """본체(시작·종료를 품은 부분) + 되돌아가는 부분으로 나눈다."""
    starts = set(dfg.starts) & activities
    ends = set(dfg.ends) & activities
    if not starts or not ends:
        return None

    body = set(starts) | set(ends)
    # 시작에서 정방향으로 닿고, 종료로도 닿는 활동은 본체에 속한다
    reach = _reachability(activities, dfg)
    for a in activities:
        if any(a in reach[s] for s in starts) and any(e in reach[a] for e in ends):
            body.add(a)
    redo = activities - body
    if not redo or not body:
        return None

    # redo 는 본체의 종료에서만 들어가고 본체의 시작으로만 돌아와야 한다
    for (a, b) in dfg.edges:
        if a in body and b in redo and a not in ends:
            return None
        if a in redo and b in body and b not in starts:
            return None
    return [body, redo]


# ---------------------------------------------------------------------------
# 메인
# ---------------------------------------------------------------------------
def _make_optional(child: Node, part: set[str], traces: list[list[str]] | None) -> Node:
    """모든 케이스에 나타나지 않는 구간은 건너뛸 수 있게 xor(구간, τ) 로 감싼다.

    이걸 안 하면 8건 중 3건에만 있던 '견적 재산출' 이 순차 단계로 굳어져
    모든 케이스가 그 단계를 반드시 거치는 모델이 나온다(= 로그와 안 맞는 모델).
    """
    if not traces:
        return child
    covering = sum(1 for t in traces if part & set(t))
    if covering == 0 or covering >= len(traces):
        return child
    return Node(XOR, children=[child, tau()])


def discover(
    dfg: Dfg,
    activities: set[str] | None = None,
    traces: list[list[str]] | None = None,
    _depth: int = 0,
) -> Node:
    """DFG → 프로세스 트리.

    traces 를 함께 주면 '모든 케이스에 등장하지는 않는 구간' 을 선택적으로 표현한다.
    """
    acts = set(dfg.activities if activities is None else activities)

    if not acts:
        return tau()
    if len(acts) == 1:
        only = next(iter(acts))
        # 자기 루프면 반복으로 표현한다
        if (only, only) in dfg.edges:
            return Node(LOOP, children=[act(only), tau()])
        return act(only)
    if _depth > 24:  # 병리적 로그 방어
        return flatten(Node(XOR, children=[act(a) for a in sorted(acts)]))

    for kind, finder in ((XOR, _xor_cut), (SEQ, _seq_cut), (AND, _and_cut), (LOOP, _loop_cut)):
        parts = finder(acts, dfg)
        if not parts:
            continue
        children = []
        for p in parts:
            sub = discover(dfg.project(p), p, traces, _depth + 1)
            # 배타 분기는 갈래 자체가 선택이므로 다시 선택적으로 만들지 않는다
            if kind in (SEQ, AND):
                sub = _make_optional(sub, p, traces)
            children.append(sub)
        return flatten(Node(kind, children=children))

    # 컷 없음 → 구조는 건전하게 두되 순서는 주장하지 않는다
    return flatten(Node(XOR, children=[act(a) for a in sorted(acts)]))


def discover_from_traces(traces: list[list[str]], min_freq: int = 1, dependency_threshold: float = 0.0) -> Node:
    from .dfg import build_dfg, filter_noise

    dfg = filter_noise(build_dfg(traces), min_freq=min_freq, dependency_threshold=dependency_threshold)
    return discover(dfg, traces=traces)
