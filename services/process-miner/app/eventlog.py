"""handover_events → 프로세스 마이닝용 이벤트 로그.

인계 로그 한 줄은 "누가 → 누구에게, 무슨 일을" 이다. 이걸 케이스별 활동 시퀀스로
편다. 활동 라벨은 인계한 사람이 적은 '다음에 할 일'(next_activity_label)을 쓴다 —
관측된 사실이고, 다음 담당자가 실제로 그 일을 받았다는 증거이기 때문이다.
스레드의 첫 인계는 넘긴 사람이 '지금까지 한 일'(activity_label)도 첫 단계로 남긴다.

케이스 키는 origin_room_id(스레드 뿌리)다. 이메일 forward 묶음과 같은 단위.
"""
from __future__ import annotations

import re
from collections import defaultdict
from dataclasses import dataclass


# 이벤트 종류
STEP = "step"            # 인계로 넘겨받은 '다음 할 일' — 제어 흐름에 들어간다
START = "start"          # 스레드 첫 인계에서 넘긴 사람이 '지금까지 한 일' — 첫 단계
DELEGATION = "delegation"  # 활동명 없는 에이전트 위임 — 제어 흐름 밖, 조직 통계에만


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
    # 일을 넘긴 리소스. 인계 네트워크는 이 값과 resource 의 쌍으로 센다.
    from_resource: str = ""
    from_name: str = ""
    kind: str = STEP
    returned_at: object = None
    order: int = 1  # 같은 시각이면 START(0) 가 먼저

    @property
    def in_control_flow(self) -> bool:
        return self.kind != DELEGATION and bool(self.activity)


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


# 받은 할 일이 끝났다고 보는 상태. 에이전트는 SUBMITTED, 사람은 DONE 으로 끝낸다.
DONE_STATUSES = {"DONE", "COMPLETED", "SUBMITTED"}


def case_key(row: dict) -> str:
    return row.get("origin_room_id") or row.get("case_id") or ""


def thread_finished(rows: list[dict]) -> bool:
    """한 스레드가 끝났는가.

    마지막으로 받은 할 일이 완료돼야 끝난 건이다. 마지막 담당자는 더 넘기지 않으므로
    '다음 인계가 없다' 로는 끝을 알 수 없다.

    에이전트가 받은 할 일은 에이전트가 마치면 자동으로 완료되지만, 넘긴 사람이 그 방에
    남아 결과를 다음 사람에게 이어 줄 수 있다. 그래서 마지막 인계가 에이전트에게 간
    경우는 넘긴 사람이 '업무 종료' 를 눌러야(closed_at) 끝난 건이다.
    명시적 인계가 없는 스레드(위임만 있는 방)는 기다릴 할 일이 없어 끝난 것으로 본다.
    """
    handovers = [r for r in rows if (r.get("source") or "") == "chat_handover"]
    if not handovers:
        return True
    last = max(handovers, key=lambda r: str(r.get("occurred_at")))
    if last.get("closed_at"):
        return True
    if last.get("to_is_agent"):
        return False
    return str(last.get("to_task_status") or "").upper() in DONE_STATUSES


def finished_rows(rows: list[dict]) -> tuple[list[dict], int]:
    """끝난 스레드의 행만 남긴다. (남긴 행, 진행 중이라 뺀 스레드 수)"""
    by_case: dict[str, list[dict]] = defaultdict(list)
    for r in rows:
        key = case_key(r)
        if key:
            by_case[key].append(r)
    kept: list[dict] = []
    open_cases = 0
    for case_rows in by_case.values():
        if thread_finished(case_rows):
            kept.extend(case_rows)
        else:
            open_cases += 1
    return kept, open_cases


# 첫 단계로 쓸 '지금까지 한 일' 을 믿을 수 있는 출처.
# agent_delegation 의 activity_label 은 대화 원문이라 제외한다.
_START_LABEL_SOURCES = {"chat_handover", "todolist"}


def build_events(rows: list[dict]) -> list[Event]:
    """handover_events 행 목록 → Event 목록 (케이스별 시간순).

    한 행은 "from 이 to 에게 다음 할 일을 넘겼다" 다. 여기서 세 종류의 이벤트를 만든다.

    - STEP        to 가 넘겨받은 '다음 할 일'.
    - START       스레드의 첫 인계라면, 넘긴 사람이 그때까지 한 일(activity_label).
                  이게 없으면 업무를 시작한 단계와 사람이 결과에서 빠지고,
                  두 사람 사이의 단순 인계는 단계가 하나뿐이라 분석에서 제외된다.
    - DELEGATION  활동명을 고를 수 없는 에이전트 위임. 대화 원문을 활동명으로 쓰지 않으려고
                  제어 흐름에서는 빼지만, 위임한 사람이 그때 맡고 있던 활동에 귀속시켜
                  인계 네트워크·자동화율·활동별 자격에는 넣는다.
    """
    by_case: dict[str, list[dict]] = defaultdict(list)
    for r in rows:
        case_id = r.get("origin_room_id") or r.get("case_id")
        if case_id:
            by_case[case_id].append(r)

    events: list[Event] = []
    for case_id in sorted(by_case):
        case_rows = sorted(by_case[case_id], key=lambda r: str(r.get("occurred_at")))
        case_events: list[Event] = []
        holding: dict[str, str] = {}  # 리소스 → 지금 맡고 있는 활동
        # 시작 단계: 스레드의 첫 '믿을 수 있는' 인계에서 넘긴 사람이 한 일.
        # 그 전에 있던 에이전트 위임(인계 전에 에이전트에게 먼저 맡긴 경우)은 이 단계에 속한다.
        first = next((r for r in case_rows if (r.get("source") or "") in _START_LABEL_SOURCES), None)
        if first is not None and first.get("from_user_id"):
            done = normalize_label(first.get("activity_label"))
            from_id = first.get("from_user_id")
            if done and len(done) <= MAX_LABEL_LEN:
                start_at = case_rows[0].get("occurred_at")
                case_events.append(
                    Event(
                        case_id=case_id,
                        activity=done,
                        resource=from_id,
                        resource_name=first.get("from_user_name") or from_id,
                        is_agent=bool(first.get("from_is_agent")),
                        agent_orch=None,
                        occurred_at=start_at,
                        source=first.get("source") or "",
                        kind=START,
                        order=0,
                    )
                )
                holding[from_id] = done
        for r in case_rows:
            source = r.get("source") or ""
            from_id = r.get("from_user_id") or ""
            from_name = r.get("from_user_name") or from_id

            label = pick_label(r)
            kind = STEP
            if not label:
                if source != "agent_delegation":
                    continue
                # 위임한 사람이 맡고 있던 활동. 모르면 활동 없이 네트워크에만 남는다.
                label = holding.get(from_id, "")
                kind = DELEGATION
            to_id = r.get("to_user_id") or ""
            case_events.append(
                Event(
                    case_id=case_id,
                    activity=label,
                    resource=to_id,
                    resource_name=r.get("to_user_name") or to_id,
                    is_agent=bool(r.get("to_is_agent")),
                    agent_orch=r.get("agent_orch"),
                    occurred_at=r.get("occurred_at"),
                    source=source,
                    from_resource=from_id,
                    from_name=from_name,
                    kind=kind,
                    returned_at=r.get("returned_at"),
                )
            )
            if kind == STEP and to_id:
                holding[to_id] = label
        events.extend(case_events)
    events.sort(key=lambda e: (e.case_id, str(e.occurred_at), e.order))
    return events


def to_traces(events: list[Event]) -> dict[str, list[str]]:
    """케이스별 활동 시퀀스. 연속 중복은 접는다(같은 활동 재전송은 반복이 아니다)."""
    traces: dict[str, list[str]] = defaultdict(list)
    for e in events:
        if not e.in_control_flow:
            continue
        seq = traces[e.case_id]
        if seq and seq[-1] == e.activity:
            continue
        seq.append(e.activity)
    return dict(traces)


def resource_profile(events: list[Event]) -> dict[str, dict]:
    """활동별 수행 리소스 통계 → 역할 추정과 자동화율의 원자료."""
    prof: dict[str, dict] = {}
    for e in events:
        if not e.activity:
            continue
        p = prof.setdefault(
            e.activity,
            {"total": 0, "by_agent": 0, "resources": defaultdict(int), "names": {}, "orchs": defaultdict(int)},
        )
        p["total"] += 1
        if e.is_agent:
            p["by_agent"] += 1
            if e.agent_orch:
                p["orchs"][e.agent_orch] += 1
        p["resources"][e.resource] += 1
        p["names"][e.resource] = e.resource_name
    return prof


def control_flow_events(events: list[Event]) -> list[Event]:
    return [e for e in events if e.in_control_flow]


def transfers(events: list[Event]) -> list[tuple[Event, str, str]]:
    """리소스 간 이관 목록 (이벤트, 넘긴 리소스, 받은 리소스).

    행에 적힌 from → to 를 그대로 쓴다. from 이 없는 이벤트(직접 만든 로그 등)만
    같은 케이스의 직전 이벤트 수행자에서 넘어온 것으로 본다. 위임을 마치고 돌려준
    경우(returned_at)는 에이전트 → 위임한 사람 이관을 하나 더 센다.
    """
    out: list[tuple[Event, str, str]] = []
    prev: dict[str, Event] = {}
    for e in events:
        if e.kind != START:
            src = e.from_resource or (prev[e.case_id].resource if e.case_id in prev else "")
            if src and e.resource and src != e.resource:
                out.append((e, src, e.resource))
            if e.kind == DELEGATION and e.returned_at and e.from_resource and e.resource != e.from_resource:
                out.append((e, e.resource, e.from_resource))
        if e.kind != DELEGATION:
            prev[e.case_id] = e
    return out


def handover_matrix(events: list[Event]) -> dict[tuple[str, str], int]:
    """리소스 간 이관 빈도. 조직 마이닝(핸드오버 네트워크)의 원자료."""
    matrix: dict[tuple[str, str], int] = defaultdict(int)
    for _, a, b in transfers(events):
        matrix[(a, b)] += 1
    return dict(matrix)
