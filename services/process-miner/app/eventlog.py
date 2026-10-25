"""handover_events → 프로세스 마이닝용 이벤트 로그.

인계 로그 한 줄은 "누가 → 누구에게, 무슨 일을" 이다. 이걸 케이스별 활동 시퀀스로
편다. 활동 라벨은 인계한 사람이 적은 '다음에 할 일'(next_activity_label)을 쓴다 —
관측된 사실이고, 다음 담당자가 실제로 그 일을 받았다는 증거이기 때문이다.

케이스 키는 origin_room_id(스레드 뿌리)다. 이메일 forward 묶음과 같은 단위.
"""
from __future__ import annotations

import re
from collections import defaultdict
from dataclasses import dataclass


@dataclass
class Event:
    case_id: str
    activity: str
    resource: str
    resource_name: str
    is_agent: bool
    agent_orch: str | None
    occurred_at: object
    source: str
    role: str = ""
    tools: tuple = ()
    skills: tuple = ()


_WS = re.compile(r"\s+")
_TRAILING = re.compile(r"[\s.·…]+$")


def normalize_label(raw: str | None) -> str:
    """활동명을 비교 가능한 형태로 정규화한다.

    LLM 없이 되는 부분만 결정론적으로 처리한다(공백·따옴표·말꼬리).
    의미 단위 통합(예: '견적서 검토' vs '견적 검토')은 labeling 단계의 몫이다.
    """
    if not raw:
        return ""
    s = str(raw).strip().strip("\"'`")
    s = _WS.sub(" ", s)
    s = _TRAILING.sub("", s)
    return s


# 활동명이라 보기 어려운 길이. 이보다 길면 대화 원문이 흘러든 것으로 본다.
MAX_LABEL_LEN = 60


def pick_label(row: dict) -> str:
    """이 이벤트를 대표하는 활동명을 고른다.

    출처마다 신뢰도가 다르다:
      chat_handover    사람이 '다음에 할 일' 로 직접 적었다 → 그대로 신뢰
      todolist         BPMN 활동명이다 → 그대로 신뢰
      agent_delegation activity_label 에는 위임을 유발한 '대화 원문' 이 들어 있어
                       활동명이 아니다. 이 출처에서는 activity_label 을 절대 쓰지 않고,
                       정규화 라벨이나 명시적으로 적힌 다음 단계만 사용한다 —
                       안 그러면 채팅 문장이 활동으로 둔갑해 모델이 망가진다.
    """
    source = (row.get("source") or "").strip()
    candidates = [row.get("norm_activity_label"), row.get("next_activity_label")]
    if source != "agent_delegation":
        candidates.append(row.get("activity_label"))
    for c in candidates:
        label = normalize_label(c)
        if label and len(label) <= MAX_LABEL_LEN:
            return label
    return ""


def _refs(row: dict) -> tuple[tuple, tuple]:
    """산출물 참조에 적힌 도구(캐드크래프트·한글·엑셀 …)와 스킬. 단계마다 무엇으로 일했는지의 근거."""
    tools, skills = [], []
    for r in row.get("artifact_refs") or []:
        if not isinstance(r, dict):
            continue
        if r.get("tool") and r["tool"] not in tools:
            tools.append(str(r["tool"]))
        if r.get("skill") and r["skill"] not in skills:
            skills.append(str(r["skill"]))
    return tuple(tools), tuple(skills)


def build_events(rows: list[dict]) -> list[Event]:
    """handover_events 행 목록 → Event 목록 (시간순).

    활동명을 못 고른 행은 제어 흐름 도출 대상에서 빠진다(네트워크 통계에는 여전히
    포함하고 싶다면 별도 경로로 다뤄야 한다).
    """
    events: list[Event] = []
    for r in rows:
        case_id = r.get("origin_room_id") or r.get("case_id")
        if not case_id:
            continue
        label = pick_label(r)
        if not label:
            continue
        tools, skills = _refs(r)
        events.append(
            Event(
                case_id=case_id,
                activity=label,
                resource=r.get("to_user_id") or "",
                resource_name=r.get("to_user_name") or r.get("to_user_id") or "",
                is_agent=bool(r.get("to_is_agent")),
                agent_orch=r.get("agent_orch"),
                occurred_at=r.get("occurred_at"),
                source=r.get("source") or "",
                role=(r.get("to_role") or "").strip(),
                tools=tools,
                skills=skills,
            )
        )
    events.sort(key=lambda e: (e.case_id, str(e.occurred_at)))
    return events


def to_traces(events: list[Event]) -> dict[str, list[str]]:
    """케이스별 활동 시퀀스. 연속 중복은 접는다(같은 활동 재전송은 반복이 아니다)."""
    traces: dict[str, list[str]] = defaultdict(list)
    for e in events:
        seq = traces[e.case_id]
        if seq and seq[-1] == e.activity:
            continue
        seq.append(e.activity)
    return dict(traces)


def resource_profile(events: list[Event]) -> dict[str, dict]:
    """활동별 수행 리소스 통계 → 역할 추정과 자동화율의 원자료."""
    prof: dict[str, dict] = {}
    for e in events:
        p = prof.setdefault(
            e.activity,
            {"total": 0, "by_agent": 0, "resources": defaultdict(int), "names": {}, "orchs": defaultdict(int),
             "roles": defaultdict(int), "tools": defaultdict(int), "skills": defaultdict(int)},
        )
        p["total"] += 1
        if e.role:
            p["roles"][e.role] += 1
        for t in e.tools:
            p["tools"][t] += 1
        for k in e.skills:
            p["skills"][k] += 1
        if e.is_agent:
            p["by_agent"] += 1
            if e.agent_orch:
                p["orchs"][e.agent_orch] += 1
        p["resources"][e.resource] += 1
        p["names"][e.resource] = e.resource_name
    return prof


def handover_matrix(events: list[Event]) -> dict[tuple[str, str], int]:
    """리소스 간 이관 빈도. 조직 마이닝(핸드오버 네트워크)의 원자료."""
    matrix: dict[tuple[str, str], int] = defaultdict(int)
    by_case: dict[str, list[Event]] = defaultdict(list)
    for e in events:
        by_case[e.case_id].append(e)
    for seq in by_case.values():
        for a, b in zip(seq, seq[1:]):
            if a.resource and b.resource and a.resource != b.resource:
                matrix[(a.resource, b.resource)] += 1
    return dict(matrix)
