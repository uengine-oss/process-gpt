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


class _Builder:
    def __init__(self, profile: dict[str, dict] | None):
        self.profile = profile or {}
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

    def connect(self, source: str, target: str, condition: str = "", name: str = "") -> None:
        self.sequences.append(
            {
                "id": self._seq_id(),
                "name": name,
                "source": source,
                "target": target,
                "condition": condition,
                "properties": "{}",
            }
        )

    # -- 역할 / 에이전트 ----------------------------------------------------
    def _role_for(self, label: str) -> tuple[str, dict]:
        """이 활동을 가장 많이 수행한 리소스를 역할로 삼는다."""
        p = self.profile.get(label)
        if not p or not p.get("resources"):
            role_name = "담당자"
            self.roles.setdefault(role_name, {"name": role_name, "endpoint": "", "resolutionRule": ""})
            return role_name, {}

        dominant = max(p["resources"].items(), key=lambda kv: kv[1])[0]
        role_name = p["names"].get(dominant) or dominant or "담당자"
        role = self.roles.setdefault(
            role_name,
            {"name": role_name, "endpoint": dominant, "resolutionRule": "핸드오버 로그에서 도출된 역할"},
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
        activity = {
            "id": aid,
            "name": label,
            "role": role_name,
            "type": _ACTIVITY_TYPE,
            "tool": "",
            "agent": extras.get("agent", ""),
            "agentMode": extras.get("agentMode", ""),
            "orchestration": extras.get("orchestration", ""),
            "process": "",
            "duration": 1,
            "skills": [],
            "inputData": [],
            "outputData": [f"{label} 결과"],  # 계약상 최소 1개
            "properties": "{}",
            "attachments": [],
            "checkpoints": [],
            "description": f"핸드오버 로그에서 도출된 활동 (관측 {p.get('total', 0)}회)",
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
        split = b.add_gateway(node.kind, "분기" if node.kind == XOR else "병렬 분기")
        join = b.add_gateway(node.kind, "합류" if node.kind == XOR else "병렬 합류")
        for i, child in enumerate(node.children):
            cin, cout = _emit(child, b)
            # 배타 분기는 각 갈래에 조건 자리를 남긴다(LLM 보강 단계에서 채운다)
            cond = "" if node.kind == AND else f"조건{i + 1}"
            b.connect(split, cin, condition=cond)
            b.connect(cout, join)
        return split, join

    if node.kind == LOOP:
        body = node.children[0]
        redo = node.children[1] if len(node.children) > 1 else None
        entry = b.add_gateway(XOR, "반복 진입")
        exit_gw = b.add_gateway(XOR, "반복 판정")
        if body.kind == TAU:
            # 순서 없는 반복 ⟲(τ, …): 본체가 비어 있으니 진입에서 판정으로 바로 잇는다
            b.connect(entry, exit_gw)
        else:
            bin_, bout = _emit(body, b)
            b.connect(entry, bin_)
            b.connect(bout, exit_gw)
        if redo is not None and redo.kind != TAU:
            rin, rout = _emit(redo, b)
            b.connect(exit_gw, rin, condition="재수행")
            b.connect(rout, entry)
        else:
            b.connect(exit_gw, entry, condition="재수행")
        return entry, exit_gw

    raise ValueError(f"알 수 없는 노드 종류: {node.kind}")


def to_process_definition(
    tree: Node,
    *,
    process_id: str,
    process_name: str,
    description: str = "",
    profile: dict[str, dict] | None = None,
) -> dict:
    """프로세스 트리를 ProcessGPT 가 실행할 수 있는 정의 JSON 으로 만든다."""
    b = _Builder(profile)

    start_id, end_id = "start_event", "end_event"
    b.events.append(
        {"id": start_id, "name": "시작", "role": "", "type": "startEvent", "process": "", "trigger": "", "properties": "{}", "description": ""}
    )
    b.events.append(
        {"id": end_id, "name": "종료", "role": "", "type": "endEvent", "process": "", "trigger": "", "properties": "{}", "description": ""}
    )

    entry, exit_ = _emit(tree, b)
    b.connect(start_id, entry)
    b.connect(exit_, end_id)

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
