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
        # 반복 판정 게이트웨이 id → 빠져나가는 선에 붙일 선택값
        self.exit_conditions: dict[str, str] = {}
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

    def connect(self, source: str, target: str, condition: str = "", name: str = "", role: str = "") -> None:
        """role 은 이 선이 분기에서 맡은 자리(branch · skip · redo · exit). 화면이 이름으로 짐작하지 않게 남긴다."""
        if not condition and source in self.exit_conditions:
            # 반복 판정에서 빠져나가는 선 — 반복 노드 밖(부모 순서)에서 이어지므로 여기서 값을 붙인다
            condition, role = self.exit_conditions[source], "exit"
        self.sequences.append(
            {
                "id": self._seq_id(),
                "name": name,
                "source": source,
                "target": target,
                "condition": condition,
                "properties": json.dumps({"minedRole": role}) if role else "{}",
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

    def add_gateway(self, kind: str, name: str, role: str = "") -> str:
        """role 은 도출 구조에서 이 게이트웨이가 맡은 자리(choice · join · skip · loop_entry · loop_exit).

        화면과 실행 전환이 이름으로 짐작하지 않고 구조를 읽게 properties 에 남긴다.
        """
        gid = self._gw_id("exclusive" if kind == XOR else "parallel")
        self.gateways.append(
            {
                "id": gid,
                "name": name,
                "role": "",
                "type": "exclusiveGateway" if kind == XOR else "parallelGateway",
                "process": "",
                "conditionData": [],
                "properties": json.dumps({"minedRole": role}) if role else "{}",
                "description": "",
            }
        )
        return gid


def _branch_options(children: list[Node]) -> list[str]:
    """배타 분기 갈래마다 고를 값. 첫 단계 이름을 쓰고, 빈 갈래는 '건너뜀', 겹치면 번호를 붙인다."""
    out: list[str] = []
    for i, child in enumerate(children):
        acts = child.activities()
        value = "건너뜀" if child.kind == TAU or not acts else acts[0]
        if value in out:
            value = f"{value} ({i + 1})"
        out.append(value)
    return out


def _emit(node: Node, b: _Builder) -> tuple[str, str]:
    """서브트리를 그려 넣고 (입구, 출구) 노드 id 를 돌려준다."""
    if node.kind == ACT:
        aid = b.add_activity(node.label)
        return aid, aid

    if node.kind == TAU:
        # 보이지 않는 단계는 게이트웨이 사이를 잇는 통과점으로 표현한다
        gid = b.add_gateway(XOR, "", "skip")
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
        split = b.add_gateway(node.kind, "분기" if node.kind == XOR else "병렬 분기", "choice" if node.kind == XOR else "fork")
        join = b.add_gateway(node.kind, "합류" if node.kind == XOR else "병렬 합류", "join")
        options = _branch_options(node.children) if node.kind == XOR else [""] * len(node.children)
        for child, cond in zip(node.children, options):
            cin, cout = _emit(child, b)
            # 배타 분기는 갈래마다 실행 때 고를 값을 붙인다 — 그 갈래의 첫 단계 이름(빈 갈래는 '건너뜀').
            # 생성 단계는 이 값을 그대로 직전 단계 폼의 선택지로 만들고, 엔진은 고른 값으로 선을 정한다.
            role = "" if node.kind == AND else ("skip" if child.kind == TAU else "branch")
            b.connect(split, cin, condition=cond, role=role)
            b.connect(cout, join)
        return split, join

    if node.kind == LOOP:
        body = node.children[0]
        redo = node.children[1] if len(node.children) > 1 else None
        entry = b.add_gateway(XOR, "반복 진입", "loop_entry")
        exit_gw = b.add_gateway(XOR, "반복 판정", "loop_exit")
        if body.kind == TAU:
            # 순서 없는 반복 ⟲(τ, …): 본체가 비어 있으니 진입에서 판정으로 바로 잇는다
            b.connect(entry, exit_gw)
        else:
            bin_, bout = _emit(body, b)
            b.connect(entry, bin_)
            b.connect(bout, exit_gw)
        # 반복 판정은 '되돌아감'과 '빠져나감' 두 값 중 하나를 고른다
        b.exit_conditions[exit_gw] = "완료"
        if redo is not None and redo.kind != TAU:
            rin, rout = _emit(redo, b)
            first = redo.activities()[0] if redo.activities() else "재수행"
            b.connect(exit_gw, rin, condition=f"{first} 필요", role="redo")
            b.connect(rout, entry)
        else:
            b.connect(exit_gw, entry, condition="다시 수행", role="redo")
        return entry, exit_gw

    raise ValueError(f"알 수 없는 노드 종류: {node.kind}")


def _assign_lane_roles(b: _Builder, start_id: str) -> None:
    """이벤트·게이트웨이에도 레인(역할)을 준다 — 시작은 첫 단계의 역할, 나머지는 바로 앞 노드의 역할.

    다이어그램은 노드를 역할(레인)별로 놓는다. 역할이 빈 이벤트·게이트웨이는 어느 레인에도
    들어가지 못해 엉뚱한 자리에 놓이고 연결선이 레인 밖으로 꺾인다. 식별 화면이 그릴 때만
    채우던 규칙을 정의에 남겨, 전환·저장된 다이어그램도 같은 배치가 되게 한다.
    흐름(단계·담당자·연결)은 바꾸지 않는다.
    """
    role: dict[str, str] = {a["id"]: a["role"] for a in b.activities}
    outgoing: dict[str, list[str]] = {}
    incoming: dict[str, list[str]] = {}
    for s in b.sequences:
        outgoing.setdefault(s["source"], []).append(s["target"])
        incoming.setdefault(s["target"], []).append(s["source"])

    # 시작: 처음 닿는 단계의 역할
    seen, queue = {start_id}, list(outgoing.get(start_id, []))
    while queue:
        n = queue.pop(0)
        if n in role:
            role[start_id] = role[n]
            break
        if n not in seen:
            seen.add(n)
            queue.extend(outgoing.get(n, []))

    # 게이트웨이·종료: 역할이 있는 앞 노드의 역할(앞 노드가 게이트웨이면 그것이 정해질 때까지 반복)
    pending = [g["id"] for g in b.gateways] + [e["id"] for e in b.events if e["id"] != start_id]
    changed = True
    while changed:
        changed = False
        for n in pending:
            if n in role:
                continue
            src = next((p for p in incoming.get(n, []) if p in role), None)
            if src is not None:
                role[n] = role[src]
                changed = True

    for node in b.gateways + b.events:
        if not node.get("role") and node["id"] in role:
            node["role"] = role[node["id"]]


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
    _assign_lane_roles(b, start_id)

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
