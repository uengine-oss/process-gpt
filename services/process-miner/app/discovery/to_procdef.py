"""프로세스 트리 → ProcessGPT flattened proc_def JSON.

스키마 계약의 정본은 skills/bpmn-process-generation-skill/scripts/save_to_supabase.py
의 flatten() 이다. 반드시 지킬 것:
  - properties 는 JSON 객체가 아니라 문자열
  - StartEvent / EndEvent 각각 정확히 1개
  - 활동마다 outputData 최소 1개
  - id 는 lowercase_snake

트리에서 변환하므로 도달 불가 노드나 짝 안 맞는 게이트웨이가 생길 수 없다.
"""
from __future__ import annotations

import json

from .process_tree import ACT, AND, LOOP, SEQ, TAU, XOR, Node

_ACTIVITY_TYPE = "userTask"

# 사람이 읽는 이름·설명은 요청한 쪽(테넌트·요청자)의 언어로 쓴다. 활동 이름은 기록된 그대로다.
_TEXT = {
    "ko": {
        "assignee": "담당자", "role_rule": "핸드오버 로그에서 도출된 역할",
        "activity": "핸드오버 로그에서 도출된 활동 (관측 {n}회)", "result": "{label} 결과",
        "split": "분기", "join": "합류", "psplit": "병렬 분기", "pjoin": "병렬 합류",
        "loop_in": "반복 진입", "loop_check": "반복 판정", "redo": "재수행", "skip": "건너뜀",
        "start": "시작", "end": "종료", "process": "핸드오버 로그 {n}건에서 자동 도출된 프로세스",
        "calls_for": "앞 단계 결과가 '{label}' 을(를) 요구한다",
    },
    "en": {
        "assignee": "Assignee", "role_rule": "Role found in the handover records",
        "activity": "Activity found in the handover records (seen {n} times)", "result": "{label} result",
        "split": "Split", "join": "Join", "psplit": "Parallel split", "pjoin": "Parallel join",
        "loop_in": "Loop entry", "loop_check": "Loop check", "redo": "Redo", "skip": "Skip",
        "start": "Start", "end": "End", "process": "Process found automatically in {n} handover records",
        "calls_for": "The previous step's result calls for '{label}'",
    },
}


def lang_of(labels, lang: str | None = None) -> str:
    """'ko' | 'en'. 정해 주지 않으면 기록된 활동 이름의 언어(한글이 있으면 ko)."""
    v = str(lang or "").strip().lower()
    if v.startswith("en"):
        return "en"
    if v.startswith("ko"):
        return "ko"
    return "ko" if any(any("\uac00" <= ch <= "\ud7a3" for ch in str(x or "")) for x in labels) else "en"


def text(lang: str, key: str, **kw) -> str:
    return _TEXT["en" if lang == "en" else "ko"][key].format(**kw)


class _Builder:
    def __init__(self, profile: dict[str, dict] | None, lang: str = "ko", case_count: int = 0):
        self.profile = profile or {}
        self.lang = lang
        self.case_count = case_count
        self.loop_checks: set[str] = set()  # 반복 판정 게이트웨이 — 앞으로 나가는 흐름이 기본
        self.redo_seqs: set[str] = set()
        self.activities: list[dict] = []
        self.gateways: list[dict] = []
        self.events: list[dict] = []
        self.sequences: list[dict] = []
        self.roles: dict[str, dict] = {}
        self._n_act = 0
        self._n_gw = 0
        self._n_seq = 0

    # -- id 생성 (lowercase_snake 보장) -------------------------------------
    def _act_id(self) -> str:
        self._n_act += 1
        return f"activity_{self._n_act:02d}"

    def _gw_id(self, kind: str) -> str:
        self._n_gw += 1
        return f"gateway_{kind}_{self._n_gw:02d}"

    def _seq_id(self) -> str:
        self._n_seq += 1
        return f"sequence_{self._n_seq:02d}"

    def connect(self, source: str, target: str, condition: str = "", name: str = "") -> dict:
        seq = {
            "id": self._seq_id(),
            "name": name,
            "source": source,
            "target": target,
            "condition": condition,
            "properties": "{}",
        }
        self.sequences.append(seq)
        return seq

    def t(self, key: str, **kw) -> str:
        return text(self.lang, key, **kw)

    # -- 배타 분기의 판단 ----------------------------------------------------
    def _weight(self, child: Node) -> int:
        """이 갈래로 간 케이스 수(갈래 활동 중 가장 많이 관측된 수). τ 는 나머지."""
        return max((self.profile.get(a, {}).get("total", 0) for a in child.activities()), default=0)

    def decide(self, branches: list[tuple[Node, dict]]) -> None:
        """배타 분기의 갈래마다 엔진이 평가할 수 있는 조건과 기본 흐름을 둔다.

        "조건1" 같은 자리표시 조건은 엔진(자연어 조건 평가)이 아무렇게나 참으로 읽어, 선택 단계를
        건너뛰거나 두 갈래를 다 내준다. 인계 기록에는 판단 근거(금액 등)가 없으니:
          - 선택적 단계(갈래 하나가 τ): 조건 없이 그 단계를 하는 갈래가 기본 — 건너뛰는 갈래는
            실제 조건(예: 견적 금액 기준)을 정식 등록 때 붙이기 전까지 타지 않는다
          - 실제 단계끼리의 갈래: "앞 단계 결과가 '반려' 을(를) 요구한다"처럼 앞 단계 산출물로
            판단할 수 있는 조건, 아무것도 맞지 않으면 가장 많이 관측된 갈래(기본 흐름)
        우선순위(priority)는 많이 관측된 순 — 둘 이상이 참이어도 하나만 간다."""
        optional = any(c.kind == TAU for c, _ in branches)
        weights = [self._weight(c) for c, _ in branches]
        if optional and self.case_count:
            rest = max(0, self.case_count - sum(w for (c, _), w in zip(branches, weights) if c.kind != TAU))
            weights = [rest if c.kind == TAU else w for (c, _), w in zip(branches, weights)]
        # 선택적 단계는 하는 쪽이 기본(빈 갈래 τ 는 맨 뒤) — 단계를 말없이 건너뛰지 않는 쪽이 안전하다.
        # 실제 단계끼리는 많이 관측된 순.
        order = sorted(range(len(branches)), key=lambda i: (branches[i][0].kind == TAU, -weights[i], i))
        for rank, i in enumerate(order):
            child, seq = branches[i]
            first = next(iter(child.activities()), "")
            seq["name"] = self.t("skip") if child.kind == TAU else first
            seq["condition"] = "" if optional else self.t("calls_for", label=first)
            props = {"priority": rank}
            if rank == 0:
                props["default"] = True
            seq["properties"] = json.dumps(props, ensure_ascii=False)

    def finish_loops(self) -> None:
        """반복 판정: 앞으로 나가는 흐름이 기본이고, 다시 하는 흐름은 조건 없이는 타지 않는다."""
        for s in self.sequences:
            if s["source"] in self.loop_checks:
                redo = s["id"] in self.redo_seqs
                s["properties"] = json.dumps({"priority": 1} if redo else {"priority": 0, "default": True})

    # -- 역할 / 에이전트 ----------------------------------------------------
    def _role_for(self, label: str) -> tuple[str, dict]:
        """이 활동을 가장 많이 수행한 리소스를 역할로 삼는다."""
        p = self.profile.get(label)
        if not p or not p.get("resources"):
            role_name = self.t("assignee")
            self.roles.setdefault(role_name, {"name": role_name, "endpoint": "", "resolutionRule": ""})
            return role_name, {}

        dominant = max(p["resources"].items(), key=lambda kv: kv[1])[0]
        # 인계 때 적힌 역할(to_role)이 있으면 사람 이름 대신 그 역할로 — 다음 케이스는 다른 사람이 맡을 수 있다
        roles = p.get("roles") or {}
        role_name = (max(roles.items(), key=lambda kv: kv[1])[0] if roles else "") or p["names"].get(dominant) or dominant or self.t("assignee")
        role = self.roles.setdefault(
            role_name,
            {"name": role_name, "endpoint": dominant, "resolutionRule": self.t("role_rule")},
        )

        extras: dict = {}
        total, by_agent = p.get("total", 0), p.get("by_agent", 0)
        if total and by_agent / total >= 0.5:
            orchs = p.get("orchs") or {}
            extras["agent"] = dominant
            extras["orchestration"] = max(orchs.items(), key=lambda kv: kv[1])[0] if orchs else "deepagents"
            # 항상 에이전트가 처리한 단계만 완전 자동으로 제안한다
            extras["agentMode"] = "COMPLETE" if by_agent == total else "DRAFT"
        return role["name"], extras

    def add_activity(self, label: str) -> str:
        aid = self._act_id()
        role_name, extras = self._role_for(label)
        p = self.profile.get(label, {})
        top = lambda d: [k for k, _ in sorted((d or {}).items(), key=lambda kv: -kv[1])]  # noqa: E731
        activity = {
            "id": aid,
            "name": label,
            "role": role_name,
            "type": _ACTIVITY_TYPE,
            "tool": "",
            # 관측된 도구·스킬(산출물 참조에서) — 정식 등록 때 단계에 묶을 스킬의 근거
            "observedTools": top(p.get("tools")),
            "agent": extras.get("agent", ""),
            "agentMode": extras.get("agentMode", ""),
            "orchestration": extras.get("orchestration", ""),
            "process": "",
            "duration": 1,
            "skills": top(p.get("skills")),
            "inputData": [],
            "outputData": [self.t("result", label=label)],  # 계약상 최소 1개
            "properties": "{}",
            "attachments": [],
            "checkpoints": [],
            "description": self.t("activity", n=p.get("total", 0)),
            "instruction": "",
            "attachedEvents": [],
            "customProperties": [],
        }
        self.activities.append(activity)
        return aid

    def add_gateway(self, kind: str, name: str) -> str:
        gid = self._gw_id("exclusive" if kind == XOR else "parallel")
        self.gateways.append(
            {
                "id": gid,
                "name": name,
                "role": "",
                "type": "exclusiveGateway" if kind == XOR else "parallelGateway",
                "process": "",
                "conditionData": [],
                "properties": "{}",
                "description": "",
            }
        )
        return gid


def _emit(node: Node, b: _Builder) -> tuple[str, str]:
    """서브트리를 그려 넣고 (입구, 출구) 노드 id 를 돌려준다."""
    if node.kind == ACT:
        aid = b.add_activity(node.label)
        return aid, aid

    if node.kind == TAU:
        # 보이지 않는 단계는 게이트웨이 사이를 잇는 통과점으로 표현한다
        gid = b.add_gateway(XOR, "")
        return gid, gid

    if node.kind == SEQ:
        first_in = last_out = None
        for child in node.children:
            cin, cout = _emit(child, b)
            if first_in is None:
                first_in = cin
            else:
                b.connect(last_out, cin)
            last_out = cout
        return first_in, last_out

    if node.kind in (XOR, AND):
        split = b.add_gateway(node.kind, b.t("split") if node.kind == XOR else b.t("psplit"))
        join = b.add_gateway(node.kind, b.t("join") if node.kind == XOR else b.t("pjoin"))
        branches = []
        for child in node.children:
            cin, cout = _emit(child, b)
            branches.append((child, b.connect(split, cin)))
            b.connect(cout, join)
        # 배타 분기: 엔진이 평가할 수 있는 조건과 기본 흐름(_Builder.decide)
        if node.kind == XOR:
            b.decide(branches)
        return split, join

    if node.kind == LOOP:
        body = node.children[0]
        redo = node.children[1] if len(node.children) > 1 else None
        entry = b.add_gateway(XOR, b.t("loop_in"))
        exit_gw = b.add_gateway(XOR, b.t("loop_check"))
        b.loop_checks.add(exit_gw)
        bin_, bout = _emit(body, b)
        b.connect(entry, bin_)
        b.connect(bout, exit_gw)
        if redo is not None and redo.kind != TAU:
            rin, rout = _emit(redo, b)
            b.redo_seqs.add(b.connect(exit_gw, rin, name=b.t("redo"))["id"])
            b.connect(rout, entry)
        else:
            b.redo_seqs.add(b.connect(exit_gw, entry, name=b.t("redo"))["id"])
        return entry, exit_gw

    raise ValueError(f"알 수 없는 노드 종류: {node.kind}")


def to_process_definition(
    tree: Node,
    *,
    process_id: str,
    process_name: str,
    description: str = "",
    profile: dict[str, dict] | None = None,
    lang: str | None = None,
    case_count: int = 0,
) -> dict:
    """프로세스 트리를 ProcessGPT 가 실행할 수 있는 정의 JSON 으로 만든다.

    lang: 사람이 읽는 이름·설명의 언어('ko' | 'en', 없으면 활동 이름의 언어).
    case_count: 도출에 쓴 케이스 수 — 선택적 단계를 건너뛴 케이스 수를 셀 때 쓴다."""
    b = _Builder(profile, lang_of(tree.activities(), lang), case_count)

    start_id, end_id = "start_event", "end_event"
    b.events.append(
        {"id": start_id, "name": b.t("start"), "role": "", "type": "startEvent", "process": "", "trigger": "", "properties": "{}", "description": ""}
    )
    b.events.append(
        {"id": end_id, "name": b.t("end"), "role": "", "type": "endEvent", "process": "", "trigger": "", "properties": "{}", "description": ""}
    )

    entry, exit_ = _emit(tree, b)
    b.connect(start_id, entry)
    b.connect(exit_, end_id)
    b.finish_loops()

    return {
        "processDefinitionId": process_id,
        "processDefinitionName": process_name,
        "description": description,
        "isHorizontal": True,
        "data": [],
        "roles": list(b.roles.values()),
        "participants": [],
        "subProcesses": [],
        "activities": b.activities,
        "gateways": b.gateways,
        "events": b.events,
        "sequences": b.sequences,
        "dmn_decisions": [],
        "dmn_rules": [],
        "megaProcessId": "",
        "majorProcessId": "",
    }


def validate_definition(defn: dict) -> list[str]:
    """엔진에 넣기 전 계약 위반을 잡는다. 빈 목록이면 통과."""
    problems: list[str] = []
    events = defn.get("events", [])
    starts = [e for e in events if e.get("type") == "startEvent"]
    ends = [e for e in events if e.get("type") == "endEvent"]
    if len(starts) != 1:
        problems.append(f"startEvent 는 정확히 1개여야 한다 (현재 {len(starts)})")
    if len(ends) != 1:
        problems.append(f"endEvent 는 정확히 1개여야 한다 (현재 {len(ends)})")

    node_ids = {n["id"] for n in defn.get("activities", []) + defn.get("gateways", []) + events}
    if len(node_ids) != len(defn.get("activities", [])) + len(defn.get("gateways", [])) + len(events):
        problems.append("노드 id 가 중복되었다")

    for a in defn.get("activities", []):
        if not a.get("outputData"):
            problems.append(f"활동 {a['id']} 에 outputData 가 없다")
        if not isinstance(a.get("properties"), str):
            problems.append(f"활동 {a['id']} 의 properties 가 문자열이 아니다")

    seen_edges = set()
    for s in defn.get("sequences", []):
        for side in ("source", "target"):
            if s[side] not in node_ids:
                problems.append(f"시퀀스 {s['id']} 의 {side} 가 존재하지 않는 노드다: {s[side]}")
        key = (s["source"], s["target"], s.get("condition", ""))
        if key in seen_edges:
            problems.append(f"중복 시퀀스: {key}")
        seen_edges.add(key)

    # 도달성: start 에서 모든 노드에 닿아야 한다
    adj: dict[str, list[str]] = {}
    for s in defn.get("sequences", []):
        adj.setdefault(s["source"], []).append(s["target"])
    reached, stack = set(), [starts[0]["id"]] if starts else []
    while stack:
        n = stack.pop()
        if n in reached:
            continue
        reached.add(n)
        stack.extend(adj.get(n, []))
    unreachable = node_ids - reached
    if unreachable:
        problems.append(f"시작 이벤트에서 도달할 수 없는 노드: {sorted(unreachable)}")

    return problems


def definition_to_json(defn: dict) -> str:
    return json.dumps(defn, ensure_ascii=False, indent=2)
