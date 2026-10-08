"""업무 시나리오 e2e 시드 — 구매 요청 처리(3 태스크).

  1. 구매 요청      — 사용자가 화면에서 제출
  2. 공급사 선정    — 에이전트(complete): 단가표로 비교표 작성 → 구매 대장에 한 줄 추가 → 선정 보고
  3. 발주서 작성    — 에이전트(complete): 선정 결과로 발주서 작성 → 인스턴스 완료

오케스트레이션만 다른 정의 3개를 만든다: purchase_request_e2e_{deepagents,cli,codex}.
에이전트는 외부 시스템 없이 자기 작업 공간의 파일만 쓴다 — 세 서비스가 같은 지시로 일할 수 있다.
구매 대장(purchase_ledger.csv)에 줄을 추가하는 것이 되돌릴 수 없는 부수효과 역할을 한다.

    DB_URL=postgresql://postgres:postgres@127.0.0.1:54322/postgres python seed_purchase.py [--drop]
"""
from __future__ import annotations

import html
import json
import os
import sys

import psycopg

from seed import AGENT_ID, AGENT_NAME, TENANT, ensure_login

VARIANTS = {
    "deepagents": dict(orch="deepagents", label="deepagents"),
    "cli": dict(orch="cliagents", label="cli-agent",
                agent_config={"agent_cli": "claude-code", "agent_model": "gpt-4.1-mini", "agent_permission": "command_exec"}),
    "codex": dict(orch="codex", label="codex"),
}

REQUEST_FIELDS = [  # (key, 라벨, 타입)
    ("request_no", "요청번호", "text"),
    ("requester", "요청자", "text"),
    ("item", "품목", "text"),
    ("quantity", "수량", "number"),
    ("budget", "예산(원)", "number"),
    ("need_by", "필요일", "date"),
    ("reason", "구매 사유", "textarea"),
]

SELECT_INSTRUCTION = (
    "구매 요청을 받아 공급사를 선정한다. 공급사 단가표는 다음과 같다.\n"
    "| 공급사 | 단가(원) | 납기(영업일) |\n|---|---|---|\n"
    "| 한빛상사 | 12,000 | 5 |\n| 미래유통 | 11,500 | 10 |\n| 대성산업 | 12,800 | 3 |\n"
    "총액 = 단가 × 수량. 오늘부터 필요일까지 납품할 수 있고 총액이 예산 이내인 공급사 중 총액이 가장 낮은 곳을 고른다.\n"
    "다음 네 단계를 순서대로 수행하라. 단계마다 도구를 따로 한 번씩 쓰고, 여러 단계를 한 번에 묶지 마라.\n"
    "1) 작업 공간 루트에 supplier_comparison.md 를 만들어 세 공급사의 총액·납기·적격 여부를 표로 쓴다.\n"
    "2) 작업 공간 루트의 purchase_ledger.csv 끝에 `요청번호,품목,수량,선정공급사,총액` 형식의 줄을 정확히 한 줄 추가한다"
    "(파일이 없으면 만든다). 구매 대장은 회계 원장이므로 같은 요청번호를 두 번 기록하면 안 된다.\n"
    "3) 작업 공간 루트에 selection_memo.md 로 구매 품의서를 쓴다. 구매 배경, 공급사 비교 요약, 선정 근거, "
    "예산 대비 집행률, 납기 리스크와 대응, 승인 요청 문구를 각각 소제목으로 두고 전체 800자 이상으로 작성한다.\n"
    "4) 선정 공급사, 총액, 납기, 선정 사유를 result 에 적는다."
)

ORDER_INSTRUCTION = (
    "앞 단계의 공급사 선정 결과로 발주서를 작성한다. 작업 공간 루트에 purchase_order.md 를 만들고 "
    "발주서 제목, 요청번호, 공급사, 품목, 수량, 단가, 총액, 납기, 요청자를 표로 담는다. "
    "result 에는 발주서 내용을 그대로 적는다."
)


def pid(key: str) -> str:
    return f"purchase_request_e2e_{key}"


def form_html(fid: str, fields: list[tuple[str, str, str]]) -> str:
    rows = []
    for key, alias, typ in fields:
        a = html.escape(alias)
        if typ == "textarea":
            el = f'<textarea-field name="{key}" alias="{a}" rows="4" disabled="false" readonly="false" v-model="slotProps.modelValue[\'{key}\']"></textarea-field>'
        else:
            el = f'<text-field name="{key}" alias="{a}" type="{typ}" disabled="false" readonly="false" v-model="slotProps.modelValue[\'{key}\']"></text-field>'
        rows.append(f'<div class="col-sm-{12 if typ == "textarea" else 6}">\n      {el}\n    </div>')
    return (f'<section>\n  <row-layout name="{fid}_row" alias="입력" is_multidata_mode="false" v-model="formValues" v-slot="slotProps">'
            '<div class="row">\n    ' + "\n    ".join(rows) + '\n  </div></row-layout>\n</section>')


def fields_json(fields):
    return [{"key": k, "text": a, "type": t, "disabled": "false", "readonly": "false"} for k, a, t in fields]


def definition(key: str, v: dict) -> tuple[dict, list[dict]]:
    p = pid(key)
    req_form, sel_form, ord_form = f"{p}_request_form", f"{p}_select_form", f"{p}_order_form"
    req_inputs = [f"{req_form}.{k}" for k, _, _ in REQUEST_FIELDS]

    def act(aid, name, role, form, *, agent=None, mode="none", instruction="", inputs=()):
        return {
            "id": aid, "name": name, "role": role, "tool": f"formHandler:{form}", "type": "userTask",
            "agent": AGENT_ID if agent else None, "tools": [], "skills": [], "process": p, "duration": 5,
            "menuName": "", "agentMode": mode, "inputData": list(inputs), "rootAgent": None, "outputData": [],
            "properties": "{}", "systemName": "", "agentConfig": v.get("agent_config") if agent else None,
            "attachments": [], "checkpoints": [], "description": name, "instruction": instruction, "manualLinks": [],
            "orchestration": v["orch"] if agent else None, "attachedEvents": None, "usePresetAgent": bool(agent),
            "customProperties": [], "agentAssignedFrom": "manual" if agent else None,
        }

    acts = [
        act("request_purchase", "구매 요청", "요청자", req_form, instruction="구매가 필요한 품목과 수량, 예산, 필요일을 입력한다."),
        act("select_supplier", "공급사 선정", "구매 담당 에이전트", sel_form, agent=True, mode="complete",
            instruction=SELECT_INSTRUCTION, inputs=req_inputs),
        act("draft_purchase_order", "발주서 작성", "구매 담당 에이전트", ord_form, agent=True, mode="complete",
            instruction=ORDER_INSTRUCTION, inputs=[*req_inputs, f"{sel_form}.result"]),
    ]
    seq = lambda s, t: {"id": f"Flow_{s}_{t}", "source": s, "target": t, "condition": "", "properties": "{}"}
    name = f"[구매 e2e] 구매 요청 처리 ({v['label']})"
    d = {
        "data": [], "roles": [
            {"name": "요청자", "default": "", "endpoint": "", "resolutionRule": "구매를 요청하는 사용자"},
            {"name": "구매 담당 에이전트", "default": [AGENT_ID], "endpoint": [AGENT_ID], "resolutionRule": AGENT_NAME},
        ],
        "events": [
            {"id": "start_event", "name": "시작", "role": "요청자", "type": "startEvent", "process": "Process_1", "properties": "{}", "description": "start event"},
            {"id": "end_event", "name": "종료", "role": "구매 담당 에이전트", "type": "endEvent", "process": "Process_1", "properties": "{}", "description": "end event"},
        ],
        "version": "1.0", "gateways": [],
        "sequences": [seq("start_event", "request_purchase"), seq("request_purchase", "select_supplier"),
                      seq("select_supplier", "draft_purchase_order"), seq("draft_purchase_order", "end_event")],
        "activities": acts, "description": name, "version_tag": "major",
        "participants": {"id": "Participant", "name": name, "processRef": "Process_1"},
        "subProcesses": [], "shortDescription": {"text": "구매 요청 → 공급사 선정 → 발주서 작성"}, "instanceNamePattern": None,
        "processDefinitionId": p, "processDefinitionName": name,
    }
    forms = [
        {"id": req_form, "activity_id": "request_purchase", "fields": REQUEST_FIELDS},
        {"id": sel_form, "activity_id": "select_supplier", "fields": [("result", "공급사 선정 결과", "textarea")]},
        {"id": ord_form, "activity_id": "draft_purchase_order", "fields": [("result", "발주서", "textarea")]},
    ]
    return d, forms


def bpmn(d: dict) -> str:
    p = d["processDefinitionId"]

    def props(a: dict) -> str:
        keep = {k: a[k] for k in ("role", "duration", "instruction", "description", "checkpoints", "agent", "rootAgent",
                                  "usePresetAgent", "agentMode", "orchestration", "agentConfig", "agentAssignedFrom",
                                  "attachments", "inputData", "tool", "customProperties", "manualLinks", "systemName",
                                  "menuName", "tools", "skills")}
        keep.update({"eventSynchronization": {"eventType": "", "attributes": [], "mappingContext": {"mappingElements": []}},
                     "mapperIn": {"mappingElements": []}, "comments": []})
        return html.escape(json.dumps(keep, ensure_ascii=False), quote=True)

    a1, a2, a3 = d["activities"]
    lane_ctx = html.escape(json.dumps({"roleResolutionContext": {"_type": "org.uengine.five.overriding.IAMRoleResolutionContext", "scope": AGENT_ID}}), quote=True)
    task = lambda a, inc, out: (f'    <bpmn:userTask id="{a["id"]}" name="{html.escape(a["name"])}">\n'
                                f'      <bpmn:extensionElements><uengine:properties json="{props(a)}"/></bpmn:extensionElements>\n'
                                f'      <bpmn:incoming>{inc}</bpmn:incoming><bpmn:outgoing>{out}</bpmn:outgoing>\n    </bpmn:userTask>\n')
    f1, f2, f3, f4 = "Flow_start_event_request_purchase", "Flow_request_purchase_select_supplier", "Flow_select_supplier_draft_purchase_order", "Flow_draft_purchase_order_end_event"
    shape = lambda i, x, y, w=110, h=80: f'      <bpmndi:BPMNShape id="{i}_di" bpmnElement="{i}"><dc:Bounds x="{x}" y="{y}" width="{w}" height="{h}"/></bpmndi:BPMNShape>\n'
    edge = lambda i, pts: f'      <bpmndi:BPMNEdge id="{i}_di" bpmnElement="{i}">' + "".join(f'<di:waypoint x="{x}" y="{y}"/>' for x, y in pts) + '</bpmndi:BPMNEdge>\n'
    return (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<bpmn:definitions xmlns:bpmn="http://www.omg.org/spec/BPMN/20100524/MODEL" xmlns:bpmndi="http://www.omg.org/spec/BPMN/20100524/DI" '
        'xmlns:dc="http://www.omg.org/spec/DD/20100524/DC" xmlns:di="http://www.omg.org/spec/DD/20100524/DI" xmlns:uengine="http://uengine" '
        f'id="Definitions_{p}" targetNamespace="http://bpmn.io/schema/bpmn">\n'
        f'  <bpmn:collaboration id="Collaboration_1"><bpmn:participant id="Participant" name="{html.escape(d["processDefinitionName"])}" processRef="Process_1"/></bpmn:collaboration>\n'
        '  <bpmn:process id="Process_1" isExecutable="true">\n'
        '    <bpmn:laneSet id="LaneSet_1">\n'
        '      <bpmn:lane id="Lane_0" name="요청자"><bpmn:flowNodeRef>start_event</bpmn:flowNodeRef><bpmn:flowNodeRef>request_purchase</bpmn:flowNodeRef></bpmn:lane>\n'
        f'      <bpmn:lane id="Lane_1" name="구매 담당 에이전트"><bpmn:extensionElements><uengine:properties json="{lane_ctx}"/></bpmn:extensionElements>'
        '<bpmn:flowNodeRef>select_supplier</bpmn:flowNodeRef><bpmn:flowNodeRef>draft_purchase_order</bpmn:flowNodeRef><bpmn:flowNodeRef>end_event</bpmn:flowNodeRef></bpmn:lane>\n'
        '    </bpmn:laneSet>\n'
        f'    <bpmn:startEvent id="start_event" name="시작"><bpmn:outgoing>{f1}</bpmn:outgoing></bpmn:startEvent>\n'
        + task(a1, f1, f2) + task(a2, f2, f3) + task(a3, f3, f4) +
        f'    <bpmn:endEvent id="end_event" name="종료"><bpmn:incoming>{f4}</bpmn:incoming></bpmn:endEvent>\n'
        f'    <bpmn:sequenceFlow id="{f1}" sourceRef="start_event" targetRef="request_purchase"/>\n'
        f'    <bpmn:sequenceFlow id="{f2}" sourceRef="request_purchase" targetRef="select_supplier"/>\n'
        f'    <bpmn:sequenceFlow id="{f3}" sourceRef="select_supplier" targetRef="draft_purchase_order"/>\n'
        f'    <bpmn:sequenceFlow id="{f4}" sourceRef="draft_purchase_order" targetRef="end_event"/>\n'
        '  </bpmn:process>\n'
        '  <bpmndi:BPMNDiagram id="BPMNDiagram_1"><bpmndi:BPMNPlane id="BPMNPlane_1" bpmnElement="Collaboration_1">\n'
        '      <bpmndi:BPMNShape id="Participant_di" bpmnElement="Participant" isHorizontal="true"><dc:Bounds x="100" y="80" width="860" height="300"/></bpmndi:BPMNShape>\n'
        '      <bpmndi:BPMNShape id="Lane_0_di" bpmnElement="Lane_0" isHorizontal="true"><dc:Bounds x="130" y="80" width="830" height="150"/></bpmndi:BPMNShape>\n'
        '      <bpmndi:BPMNShape id="Lane_1_di" bpmnElement="Lane_1" isHorizontal="true"><dc:Bounds x="130" y="230" width="830" height="150"/></bpmndi:BPMNShape>\n'
        + shape("start_event", 180, 137, 36, 36) + shape("request_purchase", 260, 115) + shape("select_supplier", 430, 265)
        + shape("draft_purchase_order", 620, 265) + shape("end_event", 810, 287, 36, 36)
        + edge(f1, [(216, 155), (260, 155)]) + edge(f2, [(315, 195), (315, 305), (430, 305)])
        + edge(f3, [(540, 305), (620, 305)]) + edge(f4, [(730, 305), (810, 305)]) +
        '    </bpmndi:BPMNPlane>\n  </bpmndi:BPMNDiagram>\n</bpmn:definitions>\n'
    )


def main() -> None:
    db = psycopg.connect(os.environ.get("DB_URL", "postgresql://postgres:postgres@127.0.0.1:54322/postgres"), autocommit=True)
    ids = [pid(k) for k in VARIANTS]
    with db.cursor() as c:
        if "--drop" in sys.argv:
            c.execute("delete from todolist where proc_def_id = any(%s)", (ids,))
            c.execute("delete from bpm_proc_inst where proc_def_id = any(%s)", (ids,))
            c.execute("delete from form_def where proc_def_id = any(%s)", (ids,))
            c.execute("delete from proc_def where id = any(%s)", (ids,))
            print("dropped", ids)
            return
        ensure_login()
        for key, v in VARIANTS.items():
            d, forms = definition(key, v)
            c.execute("delete from proc_def where id=%s and tenant_id=%s", (pid(key), TENANT))
            c.execute("insert into proc_def (id, name, definition, bpmn, tenant_id, isdeleted, type) values (%s,%s,%s,%s,%s,false,'process')",
                      (pid(key), d["processDefinitionName"], json.dumps(d, ensure_ascii=False), bpmn(d), TENANT))
            for f in forms:
                c.execute("delete from form_def where id=%s and tenant_id=%s", (f["id"], TENANT))
                c.execute("insert into form_def (id, proc_def_id, activity_id, tenant_id, html, fields_json) values (%s,%s,%s,%s,%s,%s)",
                          (f["id"], pid(key), f["activity_id"], TENANT, form_html(f["id"], f["fields"]),
                           json.dumps(fields_json(f["fields"]), ensure_ascii=False)))
    print(json.dumps({"proc_defs": ids}, ensure_ascii=False))


if __name__ == "__main__":
    main()
