"""Inductive Miner — DFG 에서 컷을 재귀 탐지해 프로세스 트리를 만든다.

의존성 없는 자체 구현. 표준 IM 순서대로 컷을 시도한다:
    base case → 배타 선택(XOR) → 순차(SEQ) → 병렬(AND) → 반복(LOOP)
컷을 찾으면 로그도 그 컷대로 나눠(하위 로그) 각 부분을 다시 도출한다.
어떤 컷도 못 찾으면 표준 IM 처럼 순서 없는 반복(flower, ⟲(τ, a, b, …))으로 둔다 —
"이 중 하나만 한다" 는 배타 관계는 로그에 근거가 없으므로 만들지 않는다.

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
    """본체(시작·종료 활동을 품은 부분) + 되돌아가는 부분(redo)으로 나눈다.

    표준 IM 의 반복 컷이다. 시작·종료 활동을 본체로 두고, 나머지를 연결 요소로 나눈 뒤
    redo 가 될 수 없는 요소를 본체로 합친다. redo 는
      - 종료 활동에서만 들어가고(모든 종료 활동에서 들어가야 한다)
      - 시작 활동으로만 돌아와야 한다(모든 시작 활동으로 돌아와야 한다).
    예) 작성 → 검토 → 수정 → 검토 → 승인 의 {검토, 수정} 에서는 본체 = 검토, redo = 수정.
    """
    starts = set(dfg.starts) & activities
    ends = set(dfg.ends) & activities
    if not starts or not ends:
        return None
    edges = {(a, b) for (a, b) in dfg.edges if a in activities and b in activities}

    body = starts | ends
    comps = _undirected_components(activities - body, dfg)
    changed = True
    while changed:
        changed = False
        for c in list(comps):
            entered_from = {a for (a, b) in edges if b in c and a not in c}
            exits_to = {b for (a, b) in edges if a in c and b not in c}
            ok = entered_from <= ends and exits_to <= starts
            # 완전성: 한 종료 활동에서 들어가면 모든 종료 활동에서, 한 시작 활동으로 돌아오면 모든 시작 활동으로
            for x in c:
                src = {a for a in ends if (a, x) in edges}
                dst = {b for b in starts if (x, b) in edges}
                if (src and src != ends) or (dst and dst != starts):
                    ok = False
            if not ok:
                body |= c
                comps.remove(c)
                changed = True
    redo = activities - body
    if not redo:
        return None
    return [body, redo]


# ---------------------------------------------------------------------------
# 메인
# ---------------------------------------------------------------------------
def _make_optional(child: Node, part: set[str], traces: list[list[str]] | None) -> Node:
    """이 하위 로그의 모든 케이스에 나타나지 않는 구간은 건너뛸 수 있게 xor(구간, τ) 로 감싼다.

    이걸 안 하면 8건 중 3건에만 있던 '견적 재산출' 이 순차 단계로 굳어져
    모든 케이스가 그 단계를 반드시 거치는 모델이 나온다(= 로그와 안 맞는 모델).
    traces 는 전체 로그가 아니라 지금 도출 중인 부분의 하위 로그여야 한다 —
    배타 분기의 한 갈래에서 늘 하는 단계는 그 갈래의 케이스만으로 세야 필수로 남는다.
    """
    if not traces:
        return child
    covering = sum(1 for t in traces if part & set(t))
    if covering == 0 or covering >= len(traces):
        return child
    return Node(XOR, children=[child, tau()])


def _flower(acts: set[str]) -> Node:
    """순서를 주장하지 않는 반복 ⟲(τ, a, b, …). 컷을 못 찾았을 때의 표준 대안."""
    return Node(LOOP, children=[tau(), flatten(Node(XOR, children=[act(a) for a in sorted(acts)]))])


def _project(traces: list[list[str]], part: set[str]) -> list[list[str]]:
    return [[a for a in t if a in part] for t in traces]


def _segments(traces: list[list[str]], part: set[str]) -> list[list[str]]:
    """반복 컷용 로그 분할: 각 케이스에서 part 에 속한 활동이 연달아 나온 구간들."""
    out: list[list[str]] = []
    for t in traces:
        run: list[str] = []
        for a in t:
            if a in part:
                run.append(a)
            elif run:
                out.append(run)
                run = []
        if run:
            out.append(run)
    return out


def _split_log(kind: str, parts: list[set[str]], traces: list[list[str]]) -> list[list[list[str]]]:
    """컷에 맞춰 로그를 부분별 하위 로그로 나눈다."""
    if kind == XOR:
        # 각 케이스는 자기 활동이 속한 갈래에만 간다
        return [[[a for a in t if a in p] for t in traces if p & set(t)] for p in parts]
    if kind == LOOP:
        return [_segments(traces, p) for p in parts]
    return [_project(traces, p) for p in parts]


def _discover_log(
    traces: list[list[str]],
    min_freq: int,
    dependency_threshold: float,
    depth: int,
    concurrent: set[tuple[str, str]] | None = None,
) -> Node:
    """하위 로그 하나에서 트리를 도출한다(표준 IM 재귀)."""
    from .dfg import build_dfg, filter_noise

    traces = [t for t in traces if t]
    acts = {a for t in traces for a in t}
    if not acts:
        return tau()
    if len(acts) == 1:
        only = next(iter(acts))
        # 한 케이스 안에서 여러 번 나오면 반복으로 표현한다
        if any(len(t) > 1 for t in traces):
            return Node(LOOP, children=[act(only), tau()])
        return act(only)
    if depth > 24:  # 병리적 로그 방어
        return _flower(acts)

    dfg = filter_noise(build_dfg(traces, concurrent), min_freq=min_freq, dependency_threshold=dependency_threshold)
    for kind, finder in ((XOR, _xor_cut), (SEQ, _seq_cut), (AND, _and_cut), (LOOP, _loop_cut)):
        parts = finder(acts, dfg)
        if not parts:
            continue
        children = []
        for p, sub_log in zip(parts, _split_log(kind, parts, traces)):
            sub = _discover_log(sub_log, min_freq, dependency_threshold, depth + 1, concurrent)
            # 배타 분기는 갈래 자체가 선택이므로 다시 선택적으로 만들지 않는다
            if kind in (SEQ, AND):
                sub = _make_optional(sub, p, sub_log)
            children.append(sub)
        return flatten(Node(kind, children=children))

    return _flower(acts)


def discover(
    dfg: Dfg,
    activities: set[str] | None = None,
    traces: list[list[str]] | None = None,
    _depth: int = 0,
    *,
    min_freq: int = 1,
    dependency_threshold: float = 0.0,
) -> Node:
    """DFG → 프로세스 트리.

    traces 를 주면 표준 IM 대로 컷마다 로그를 나눠 재귀한다. 선택적 단계 판정과
    반복 판정이 하위 로그 기준으로 이뤄진다. traces 가 없으면 DFG 만으로 도출한다.
    """
    if traces is not None:
        if activities is not None:
            traces = _project(traces, set(activities))
        return _discover_log(traces, min_freq, dependency_threshold, _depth)

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
        return _flower(acts)

    for kind, finder in ((XOR, _xor_cut), (SEQ, _seq_cut), (AND, _and_cut), (LOOP, _loop_cut)):
        parts = finder(acts, dfg)
        if not parts:
            continue
        children = [discover(dfg.project(p), p, None, _depth + 1) for p in parts]
        return flatten(Node(kind, children=children))

    return _flower(acts)


def discover_from_traces(
    traces: list[list[str]],
    min_freq: int = 1,
    dependency_threshold: float = 0.0,
    concurrent: set[tuple[str, str]] | None = None,
) -> Node:
    """concurrent: 서로 다른 갈래에서 동시에 진행된 활동 쌍(eventlog.discovery_log). 없으면 예전과 같다."""
    return _discover_log([list(t) for t in traces], min_freq, dependency_threshold, 0, concurrent)
