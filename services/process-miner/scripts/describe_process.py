"""도출된 프로세스 → 설계 스킬이 먹을 수 있는 자연어 서술.

마이너가 만든 구조(활동·순서·분기·역할·에이전트)를 사람이 읽는 요구사항 문서로 편다.
이 문서를 bpmn-process-generation-skill 에 넣으면 폼·역할·체크포인트까지 갖춘
실행 가능한 프로세스 정의가 나온다.

마이너는 "무엇이 일어났는가"만 알고 "무엇이 필요한가"는 모른다. 그 간극을 사람이
읽을 수 있는 서술로 넘겨서 설계 스킬이 채우게 하는 것이 이 스크립트의 목적이다.

실행: ./.venv/bin/python scripts/describe_process.py mining_result.json > process-brief.md
"""
from __future__ import annotations

import json
import sys
from pathlib import Path


def _flow_order(defn: dict) -> list[dict]:
    """start_event 부터 시퀀스를 따라가며 노드를 편다."""
    by_id = {}
    for a in defn.get("activities", []):
        by_id[a["id"]] = {**a, "_kind": "activity"}
    for g in defn.get("gateways", []):
        by_id[g["id"]] = {**g, "_kind": "gateway"}
    for e in defn.get("events", []):
        by_id[e["id"]] = {**e, "_kind": "event"}

    nxt: dict[str, list[str]] = {}
    for s in defn.get("sequences", []):
        nxt.setdefault(s["source"], []).append(s["target"])

    out, seen, queue = [], set(), ["start_event"]
    while queue:
        nid = queue.pop(0)
        if not nid or nid in seen:
            continue
        seen.add(nid)
        node = by_id.get(nid)
        if node:
            out.append(node)
        queue.extend(nxt.get(nid, []))
    return out


def describe(result: dict) -> str:
    defn = result["definition"]
    stats = result["stats"]
    acts = defn.get("activities", [])
    lines: list[str] = []

    lines.append(f"# {defn.get('processDefinitionName') or '도출된 프로세스'}")
    lines.append("")
    lines.append("## 배경")
    lines.append(
        f"실제 업무 현장에서 오간 인계 기록 {stats['event_count']}건(업무 케이스 {stats['case_count']}건)을 "
        "분석해 반복되는 공통 흐름을 찾아냈습니다. 아래는 그 관측 결과이며, 이를 정식 프로세스로 "
        "만들려고 합니다."
    )
    lines.append("")

    lines.append("## 실제로 관측된 업무 흐름")
    for v in stats.get("variants", []):
        lines.append(f"- ({v['count']}건) {' → '.join(v['trace'])}")
    lines.append("")

    lines.append("## 단계별 상세")
    for i, a in enumerate(acts, 1):
        who = a.get("role") or "담당자"
        lines.append(f"{i}. **{a['name']}**")
        lines.append(f"   - 담당: {who}")
        if a.get("agent"):
            lines.append(
                f"   - 이 단계는 지금까지 AI 에이전트가 수행해 왔습니다 "
                f"(에이전트: {who}, 실행방식: {a.get('orchestration')}, 모드: {a.get('agentMode')}). "
                "자동화 단계로 유지해 주세요."
            )
        else:
            lines.append("   - 사람이 판단·처리하는 단계입니다.")
        lines.append("")

    optional = _optional_activity_names(defn)
    if optional:
        lines.append("## 조건부 단계")
        for name in optional:
            lines.append(
                f"- **{name}** 은(는) 항상 수행되지 않습니다. 관측된 케이스 중 일부에서만 나타났으므로 "
                "건너뛸 수 있는 분기로 만들어 주세요."
            )
        lines.append("")

    lines.append("## 참여 역할")
    for r in defn.get("roles", []):
        lines.append(f"- {r['name']}")
    lines.append("")

    lines.append("## 요청사항")
    lines.append("- 위 흐름을 그대로 살리되, 각 단계에 필요한 입력 양식(폼)을 설계해 주세요.")
    lines.append("- 분기 조건은 앞 단계의 폼 항목을 기준으로 판단할 수 있게 만들어 주세요.")
    lines.append("- AI 에이전트가 수행하던 단계는 계속 자동으로 처리되게 유지해 주세요.")
    lines.append("- 각 단계에 담당자가 확인해야 할 체크포인트를 넣어 주세요.")
    return "\n".join(lines)


def _optional_activity_names(defn: dict) -> list[str]:
    """배타 '분기'(split) 뒤에 달린 활동 = 건너뛸 수 있는 단계.

    합류(join) 게이트웨이도 exclusiveGateway 라서, 나가는 간선이 2개 이상인
    분기점만 봐야 한다. 안 그러면 합류 뒤에 오는 필수 단계까지 선택적으로 잘못 잡힌다.
    """
    out_deg: dict[str, int] = {}
    for s in defn.get("sequences", []):
        out_deg[s["source"]] = out_deg.get(s["source"], 0) + 1

    split_ids = {
        g["id"]
        for g in defn.get("gateways", [])
        if g.get("type") == "exclusiveGateway" and out_deg.get(g["id"], 0) >= 2
    }
    act_by_id = {a["id"]: a for a in defn.get("activities", [])}
    out: list[str] = []
    for s in defn.get("sequences", []):
        if s["source"] in split_ids and s["target"] in act_by_id:
            name = act_by_id[s["target"]]["name"]
            if name not in out:
                out.append(name)
    return out


def main() -> None:
    src = sys.argv[1] if len(sys.argv) > 1 else "mining_result.json"
    result = json.loads(Path(src).read_text(encoding="utf-8"))
    print(describe(result))


if __name__ == "__main__":
    main()
