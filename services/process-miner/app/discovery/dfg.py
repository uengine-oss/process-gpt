"""Directly-Follows Graph 생성과 노이즈 필터.

이벤트 로그(케이스별 활동 시퀀스)에서 "a 다음에 바로 b 가 왔다" 는 관계를 센다.
프로세스 도출의 모든 판단은 이 그래프 위에서만 이뤄지므로, 여기서 통계적으로
믿을 수 없는 간선을 걷어내는 것이 결과 품질을 좌우한다.
"""
from __future__ import annotations

from collections import Counter, defaultdict
from dataclasses import dataclass, field


@dataclass
class Dfg:
    """활동 집합 + 직후관계 빈도 + 시작/종료 활동."""

    activities: set[str] = field(default_factory=set)
    edges: Counter = field(default_factory=Counter)  # (a, b) -> 빈도
    starts: Counter = field(default_factory=Counter)
    ends: Counter = field(default_factory=Counter)
    case_count: int = 0

    def successors(self, a: str) -> set[str]:
        return {b for (x, b) in self.edges if x == a}

    def predecessors(self, b: str) -> set[str]:
        return {a for (a, y) in self.edges if y == b}

    def project(self, keep: set[str]) -> "Dfg":
        """활동 부분집합으로 좁힌 DFG. 컷 탐지의 재귀 단계에서 쓴다."""
        sub = Dfg(activities=set(keep), case_count=self.case_count)
        for (a, b), n in self.edges.items():
            if a in keep and b in keep:
                sub.edges[(a, b)] += n
        for a, n in self.starts.items():
            if a in keep:
                sub.starts[a] += n
        for a, n in self.ends.items():
            if a in keep:
                sub.ends[a] += n
        # 부분집합으로 자르면 바깥에서 들어오/나가던 지점이 새 시작/종료가 된다.
        # 바깥에 선행자가 있으면(=밖에서 이 부분집합으로 들어오는 입구) 시작으로 본다.
        # 부분집합 안에서만 따지면 서로를 가리키는 병렬 갈래가 시작/종료를 하나도
        # 갖지 못해 병렬 컷이 영영 성립하지 않는다.
        for a in keep:
            preds, succs = self.predecessors(a), self.successors(a)
            if not (preds & keep) or (preds - keep):
                sub.starts[a] += 1
            if not (succs & keep) or (succs - keep):
                sub.ends[a] += 1
        return sub


def build_dfg(traces: list[list[str]], concurrent: set[tuple[str, str]] | None = None) -> Dfg:
    """케이스별 활동 시퀀스 목록 → DFG.

    concurrent 는 한 번의 인계로 나눠 준 서로 다른 갈래에서 동시에 진행된 활동 쌍이다.
    시간순 흐름에는 한쪽 순서만 남으므로, 이 로그에 둘 다 있으면 양방향 직후관계로 더해
    병렬로 읽히게 한다.
    """
    dfg = Dfg()
    for trace in traces:
        seq = [a for a in trace if a]
        if not seq:
            continue
        dfg.case_count += 1
        dfg.activities.update(seq)
        dfg.starts[seq[0]] += 1
        dfg.ends[seq[-1]] += 1
        for a, b in zip(seq, seq[1:]):
            dfg.edges[(a, b)] += 1
    for a, b in concurrent or ():
        if a in dfg.activities and b in dfg.activities and a != b:
            dfg.edges[(a, b)] += 1
    return dfg


def filter_noise(dfg: Dfg, min_freq: int = 1, dependency_threshold: float = 0.0) -> Dfg:
    """빈도와 의존성 측도로 간선을 거른다.

    의존성 측도 (Heuristics Miner):
        dep(a,b) = (|a>b| - |b>a|) / (|a>b| + |b>a| + 1)
    양방향으로 비슷하게 오간 간선(= 순서 관계라 보기 어려운 것)은 0 에 가까워진다.
    단, 자기 루프(a==b)는 반복 구조의 증거이므로 의존성 필터에서 제외한다.
    """
    out = Dfg(activities=set(dfg.activities), case_count=dfg.case_count)
    out.starts = Counter(dfg.starts)
    out.ends = Counter(dfg.ends)
    for (a, b), n in dfg.edges.items():
        if n < min_freq:
            continue
        if a != b and dependency_threshold > 0:
            rev = dfg.edges.get((b, a), 0)
            dep = (n - rev) / (n + rev + 1)
            if dep < dependency_threshold:
                continue
        out.edges[(a, b)] = n
    return out


def activity_stats(traces: list[list[str]]) -> dict[str, dict]:
    """활동별 등장 케이스 수 / 총 실행 수. 소수 경로 판별에 쓴다."""
    occurrences: Counter = Counter()
    case_hits: defaultdict[str, set[int]] = defaultdict(set)
    for i, trace in enumerate(traces):
        for a in trace:
            occurrences[a] += 1
            case_hits[a].add(i)
    return {
        a: {"occurrences": occurrences[a], "cases": len(case_hits[a])}
        for a in occurrences
    }
