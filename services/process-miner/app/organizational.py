"""조직 마이닝 — 인계 기록에서 역할·역량·자격을 도출한다.

프로세스 도출이 "무슨 일이 어떤 순서로 일어났나" 를 답한다면, 조직 마이닝은
"그 일을 누가 할 수 있나" 를 답한다. 프로세스의 다음 단계 담당자를 사람 이름으로
못 박지 않고 역량과 자격으로 풀려면 이 정보가 필요하다.

세 가지를 낸다:
  1) 핸드오버 네트워크  누가 누구에게 얼마나 넘겼나 (사람·에이전트를 같은 리소스로)
  2) 역할 클러스터      비슷한 활동을 수행한 리소스끼리 묶어 역할을 도출
  3) 활동별 자격        이 활동을 실제로 수행한 사람들 → 필요한 역량과 자격 요건

역량은 지어내지 않는다. "이 활동을 반복 수행했다" 는 관측 사실에서만 만들고,
근거 건수를 함께 남겨 왜 후보인지 설명할 수 있게 한다.
"""
from __future__ import annotations

import math
from collections import defaultdict

from .eventlog import Event, transfers


def _cosine(a: dict[str, int], b: dict[str, int]) -> float:
    keys = set(a) | set(b)
    dot = sum(a.get(k, 0) * b.get(k, 0) for k in keys)
    na = math.sqrt(sum(v * v for v in a.values()))
    nb = math.sqrt(sum(v * v for v in b.values()))
    return dot / (na * nb) if na and nb else 0.0


def activity_profiles(events: list[Event]) -> dict[str, dict[str, int]]:
    """리소스별 '어떤 활동을 몇 번 했나' 벡터."""
    prof: dict[str, dict[str, int]] = defaultdict(lambda: defaultdict(int))
    for e in events:
        if e.resource and e.activity:
            prof[e.resource][e.activity] += 1
    return {r: dict(v) for r, v in prof.items()}


def role_clusters(events: list[Event], threshold: float = 0.6) -> list[dict]:
    """활동 프로필이 비슷한 리소스끼리 묶어 역할을 도출한다.

    같은 활동을 하는 사람들은 같은 역할이라고 본다. 사람과 에이전트를 가르지
    않는다 — 같은 클러스터에 함께 묶이면 그 역할은 사람/에이전트 겸용이다.
    """
    prof = activity_profiles(events)
    names = {e.resource: e.resource_name for e in events if e.resource}
    is_agent = {e.resource: e.is_agent for e in events if e.resource}

    resources = sorted(prof)
    # 유사도 그래프의 연결 요소 = 역할 클러스터
    adj: dict[str, set[str]] = {r: set() for r in resources}
    for i, a in enumerate(resources):
        for b in resources[i + 1 :]:
            if _cosine(prof[a], prof[b]) >= threshold:
                adj[a].add(b)
                adj[b].add(a)

    seen: set[str] = set()
    clusters: list[dict] = []
    for r in resources:
        if r in seen:
            continue
        stack, comp = [r], set()
        while stack:
            x = stack.pop()
            if x in comp:
                continue
            comp.add(x)
            stack.extend(adj[x] - comp)
        seen |= comp

        acts: dict[str, int] = defaultdict(int)
        for m in comp:
            for a, n in prof[m].items():
                acts[a] += n
        members = [
            {"user_id": m, "name": names.get(m, m), "is_agent": bool(is_agent.get(m))}
            for m in sorted(comp)
        ]
        clusters.append(
            {
                # 역할명은 그 클러스터가 가장 많이 한 활동에서 따온다(지어내지 않는다)
                "role": max(acts.items(), key=lambda kv: kv[1])[0] if acts else "미분류",
                "members": members,
                "activities": sorted(acts, key=lambda a: -acts[a]),
                "mixed": len({m["is_agent"] for m in members}) > 1,
            }
        )
    return clusters


def activity_eligibility(events: list[Event]) -> list[dict]:
    """활동별 수행자 통계 → 필요한 역량과 자격 후보.

    역량 이름은 활동명을 그대로 쓴다. 활동을 수행했다는 것이 그 역량의 근거이고,
    그 이상은 관측으로 알 수 없다(의미 있는 역량명 부여는 LLM 정규화 단계의 몫).
    """
    by_act: dict[str, dict[str, int]] = defaultdict(lambda: defaultdict(int))
    names: dict[str, str] = {}
    agents: dict[str, bool] = {}
    roles: dict[str, str] = {}
    for e in events:
        if not e.resource or not e.activity:
            continue
        by_act[e.activity][e.resource] += 1
        names[e.resource] = e.resource_name
        agents[e.resource] = e.is_agent

    out: list[dict] = []
    for act, performers in by_act.items():
        total = sum(performers.values())
        by_agent = sum(n for r, n in performers.items() if agents.get(r))
        candidates = [
            {
                "user_id": r,
                "name": names.get(r, r),
                "is_agent": bool(agents.get(r)),
                "evidence_count": n,
                "share": round(n / total, 3) if total else 0,
            }
            for r, n in sorted(performers.items(), key=lambda kv: -kv[1])
        ]
        out.append(
            {
                "activity": act,
                "required_capability": act,  # 관측 기반: 이 활동을 할 수 있는 능력
                "observations": total,
                "automation_rate": round(by_agent / total, 3) if total else 0,
                "candidates": candidates,
            }
        )
    return sorted(out, key=lambda x: -x["observations"])


def handover_matrix(events: list[Event]) -> list[dict]:
    """리소스 간 이관 빈도. 사람과 에이전트를 하나의 네트워크로 본다.

    활동명이 없는 에이전트 위임도 이관이므로 함께 센다.
    """
    counts: dict[tuple[str, str], int] = defaultdict(int)
    names: dict[str, str] = {}
    for e in events:
        if e.resource:
            names.setdefault(e.resource, e.resource_name)
        if e.from_resource:
            names.setdefault(e.from_resource, e.from_name or e.from_resource)
    for _, a, b in transfers(events):
        counts[(a, b)] += 1
    return [
        {"from": a, "from_name": names.get(a, a), "to": b, "to_name": names.get(b, b), "count": n}
        for (a, b), n in sorted(counts.items(), key=lambda kv: -kv[1])
    ]


def analyze(events: list[Event]) -> dict:
    return {
        "network": handover_matrix(events),
        "roles": role_clusters(events),
        "eligibility": activity_eligibility(events),
    }
