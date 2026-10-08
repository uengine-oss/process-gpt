"""체크포인트 재개 e2e 시드 — 로컬 Supabase 에 테스트 전용 계정·에이전트·프로세스를 만든다.

만드는 것(모두 `resume_e2e` 접두어, 다시 돌려도 같은 결과):
  - 로그인 계정 resume-e2e@localhost.dev (auth + users, tenant localhost)
  - 에이전트 사용자 "재개 e2e 에이전트"
  - 프로세스 정의 5개: 사람이 요청을 입력 → 에이전트가 수행 → 종료
지우기: python seed.py --drop  (이 스크립트가 만든 정의·폼·계정과 그 인스턴스만)

    DB_URL=postgresql://postgres:postgres@127.0.0.1:54322/postgres \
    SUPABASE_URL=http://127.0.0.1:54321 SUPABASE_SERVICE_KEY=... python seed.py
"""
from __future__ import annotations

import html
import json
import os
import secrets
import sys
import urllib.request
from pathlib import Path

import psycopg

TENANT = "localhost"
LOGIN_EMAIL = "resume-e2e@localhost.dev"
AGENT_ID = "e2e00000-0000-4000-8000-00000000a9e7"
AGENT_NAME = "재개 e2e 에이전트"
CRED_FILE = Path(__file__).with_name(".e2e-credentials.json")

# 크래시를 끼워 넣을 수 있도록 단계 사이에 시간이 걸리는 작업. 단계마다 흔적(파일·명령)이 남아
# 재개 뒤 "완료된 단계가 다시 실행됐는가" 를 셀 수 있다.
STEPS_SHELL = (
    "다음 세 단계를 순서대로, 각 단계마다 셸(Bash) 명령을 정확히 한 번씩 실행하라. 병렬로 실행하지 마라.\n"
    "1) echo step1 $(date +%s) >> steps.log\n"
    "2) sleep {sleep} && echo step2 $(date +%s) >> steps.log\n"
    "3) echo step3 $(date +%s) >> steps.log\n"
    "모두 끝나면 steps.log 내용을 그대로 result 에 적어라."
)

SCENARIOS = {
    "deepagents": dict(
        name="[재개 e2e] deepagents 크래시 재점유", orch="deepagents", mode="complete",
        instruction=(
            "다음 세 단계를 순서대로 수행하라. 단계마다 write_file 도구를 정확히 한 번씩 호출하고, 여러 도구를 한 번에 병렬로 호출하지 마라.\n"
            "1) write_file 로 /resume_e2e/step1.txt 에 '1단계 완료' 를 쓴다.\n"
            "2) write_file 로 /resume_e2e/step2.txt 에 1부터 400까지의 숫자를 한 줄에 하나씩 모두 쓴다(생략 없이).\n"
            "3) write_file 로 /resume_e2e/step3.txt 에 '3단계 완료' 를 쓴다.\n"
            "모두 끝나면 result 에 만든 파일 세 개의 경로를 적는다."
        ),
    ),
    "cli": dict(
        name="[재개 e2e] cli-agent 크래시 재점유", orch="cliagents", mode="complete",
        instruction=STEPS_SHELL.format(sleep=60),
        agent_config={"agent_cli": "claude-code", "agent_model": "gpt-4.1-mini", "agent_permission": "command_exec"},
    ),
    "cli_hitl": dict(
        name="[재개 e2e] cli-agent 사람 답변", orch="cliagents", mode="complete",
        # workspace_write 권한에서 네트워크 명령은 승인이 필요하다 → 거부 → 사람에게 묻는다
        instruction=(
            "Bash 도구로 `curl -s -o page.html https://example.com` 를 실행하라. "
            "실행이 권한 때문에 거부되면 다른 방법을 시도하지 말고, result 는 비워 둔 채 즉시 종료하라. "
            "실행에 성공했으면 page.html 의 title 과 담당자 응답 원문을 result 에 적어라."
        ),
        agent_config={"agent_cli": "claude-code", "agent_model": "gpt-4.1-mini", "agent_permission": "workspace_write"},
    ),
    "codex": dict(
        name="[재개 e2e] codex 크래시 재점유", orch="codex", mode="complete",
        instruction=STEPS_SHELL.format(sleep=25),
    ),
    "revision": dict(
        name="[재개 e2e] deepagents 반려 재작업", orch="deepagents", mode="draft",
        instruction="요청 내용을 세 줄로 요약해 result 에 적어라. 도구는 쓰지 마라.",
    ),
}


def pid(key: str) -> str:
    return f"resume_e2e_{key}"


def form_html(fid: str, field: str, alias: str) -> str:
    return (
        "<section>\n"
        f'  <row-layout name="{fid}_row" alias="{html.escape(alias)}" is_multidata_mode="false" v-model="formValues" v-slot="slotProps">'
        '<div class="row"><div class="col-sm-12">\n'
        f'      <textarea-field name="{field}" alias="{html.escape(alias)}" rows="6" disabled="false" readonly="false" '
        f"v-model=\"slotProps.modelValue['{field}']\"></textarea-field>\n"
        "    </div></div></row-layout>\n</section>"
    )


def activity(key: str, aid: str, name: str, role: str, form: str, *, agent: dict | None, instruction: str) -> dict:
    a = {
        "id": aid, "name": name, "role": role, "tool": f"formHandler:{form}", "type": "userTask",
        "agent": AGENT_ID if agent else None, "tools": [], "skills": [], "process": pid(key), "duration": 5,
        "menuName": "", "agentMode": agent["mode"] if agent else "none", "inputData": [], "rootAgent": None,
        "outputData": [], "properties": "{}", "systemName": "", "agentConfig": (agent or {}).get("agent_config"),
        "attachments": [], "checkpoints": [], "description": name, "instruction": instruction,
        "manualLinks": [], "orchestration": agent["orch"] if agent else None, "attachedEvents": None,
        "usePresetAgent": bool(agent), "customProperties": [], "agentAssignedFrom": "manual" if agent else None,
    }
    if agent:
        a["inputData"] = [f"{pid(key)}_request_form.request"]
    return a


def definition(key: str, sc: dict) -> dict:
    p = pid(key)
    req = activity(key, "request", "요청 입력", "요청자", f"{p}_request_form", agent=None,
                   instruction="에이전트에게 맡길 요청을 입력한다.")
    act = activity(key, "agent_task", "에이전트 수행", "에이전트", f"{p}_result_form", agent=sc, instruction=sc["instruction"])
    seq = lambda s, t: {"id": f"Flow_{s}_{t}", "source": s, "target": t, "condition": "", "properties": "{}"}
    return {
        "data": [], "roles": [
            {"name": "요청자", "default": "", "endpoint": "", "resolutionRule": "프로세스를 시작한 사용자"},
            {"name": "에이전트", "default": [AGENT_ID], "endpoint": [AGENT_ID], "resolutionRule": AGENT_NAME},
        ],
        "events": [
            {"id": "start_event", "name": "시작", "role": "요청자", "type": "startEvent", "process": "Process_1", "properties": "{}", "description": "start event"},
            {"id": "end_event", "name": "종료", "role": "에이전트", "type": "endEvent", "process": "Process_1", "properties": "{}", "description": "end event"},
        ],
        "version": "1.0", "gateways": [], "sequences": [seq("start_event", "request"), seq("request", "agent_task"), seq("agent_task", "end_event")],
        "activities": [req, act], "description": sc["name"], "version_tag": "major",
        "participants": {"id": "Participant", "name": sc["name"], "processRef": "Process_1"},
        "subProcesses": [], "shortDescription": {"text": ""}, "instanceNamePattern": None,
        "processDefinitionId": p, "processDefinitionName": sc["name"],
    }


def bpmn(key: str, sc: dict, d: dict) -> str:
    p = pid(key)

    def props(a: dict) -> str:
        keep = {k: a[k] for k in ("role", "duration", "instruction", "description", "checkpoints", "agent", "rootAgent",
                                  "usePresetAgent", "agentMode", "orchestration", "agentConfig", "agentAssignedFrom",
                                  "attachments", "inputData", "tool", "customProperties", "manualLinks", "systemName",
                                  "menuName", "tools", "skills")}
        keep.update({"eventSynchronization": {"eventType": "", "attributes": [], "mappingContext": {"mappingElements": []}},
                     "mapperIn": {"mappingElements": []}, "comments": []})
        return html.escape(json.dumps(keep, ensure_ascii=False), quote=True)

    req, act = d["activities"]
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<bpmn:definitions xmlns:bpmn="http://www.omg.org/spec/BPMN/20100524/MODEL" xmlns:bpmndi="http://www.omg.org/spec/BPMN/20100524/DI" xmlns:dc="http://www.omg.org/spec/DD/20100524/DC" xmlns:di="http://www.omg.org/spec/DD/20100524/DI" xmlns:uengine="http://uengine" id="Definitions_{p}" targetNamespace="http://bpmn.io/schema/bpmn">
  <bpmn:collaboration id="Collaboration_1">
    <bpmn:participant id="Participant" name="{html.escape(sc['name'])}" processRef="Process_1"/>
  </bpmn:collaboration>
  <bpmn:process id="Process_1" isExecutable="true">
    <bpmn:extensionElements><uengine:properties><uengine:variable name="request" type="Text"/></uengine:properties></bpmn:extensionElements>
    <bpmn:laneSet id="LaneSet_1">
      <bpmn:lane id="Lane_0" name="요청자"><bpmn:extensionElements><uengine:properties json="{html.escape(json.dumps({'roleResolutionContext': {}}), quote=True)}"/></bpmn:extensionElements><bpmn:flowNodeRef>start_event</bpmn:flowNodeRef><bpmn:flowNodeRef>request</bpmn:flowNodeRef></bpmn:lane>
      <bpmn:lane id="Lane_1" name="에이전트"><bpmn:extensionElements><uengine:properties json="{html.escape(json.dumps({'roleResolutionContext': {'_type': 'org.uengine.five.overriding.IAMRoleResolutionContext', 'scope': AGENT_ID}}), quote=True)}"/></bpmn:extensionElements><bpmn:flowNodeRef>agent_task</bpmn:flowNodeRef><bpmn:flowNodeRef>end_event</bpmn:flowNodeRef></bpmn:lane>
    </bpmn:laneSet>
    <bpmn:startEvent id="start_event" name="시작"><bpmn:outgoing>Flow_start_event_request</bpmn:outgoing></bpmn:startEvent>
    <bpmn:userTask id="request" name="요청 입력">
      <bpmn:extensionElements><uengine:properties json="{props(req)}"/></bpmn:extensionElements>
      <bpmn:incoming>Flow_start_event_request</bpmn:incoming><bpmn:outgoing>Flow_request_agent_task</bpmn:outgoing>
    </bpmn:userTask>
    <bpmn:userTask id="agent_task" name="에이전트 수행">
      <bpmn:extensionElements><uengine:properties json="{props(act)}"/></bpmn:extensionElements>
      <bpmn:incoming>Flow_request_agent_task</bpmn:incoming><bpmn:outgoing>Flow_agent_task_end_event</bpmn:outgoing>
    </bpmn:userTask>
    <bpmn:endEvent id="end_event" name="종료"><bpmn:incoming>Flow_agent_task_end_event</bpmn:incoming></bpmn:endEvent>
    <bpmn:sequenceFlow id="Flow_start_event_request" sourceRef="start_event" targetRef="request"/>
    <bpmn:sequenceFlow id="Flow_request_agent_task" sourceRef="request" targetRef="agent_task"/>
    <bpmn:sequenceFlow id="Flow_agent_task_end_event" sourceRef="agent_task" targetRef="end_event"/>
  </bpmn:process>
  <bpmndi:BPMNDiagram id="BPMNDiagram_1">
    <bpmndi:BPMNPlane id="BPMNPlane_1" bpmnElement="Collaboration_1">
      <bpmndi:BPMNShape id="Participant_di" bpmnElement="Participant" isHorizontal="true"><dc:Bounds x="100" y="80" width="700" height="300"/></bpmndi:BPMNShape>
      <bpmndi:BPMNShape id="Lane_0_di" bpmnElement="Lane_0" isHorizontal="true"><dc:Bounds x="130" y="80" width="670" height="150"/></bpmndi:BPMNShape>
      <bpmndi:BPMNShape id="Lane_1_di" bpmnElement="Lane_1" isHorizontal="true"><dc:Bounds x="130" y="230" width="670" height="150"/></bpmndi:BPMNShape>
      <bpmndi:BPMNShape id="start_event_di" bpmnElement="start_event"><dc:Bounds x="180" y="137" width="36" height="36"/></bpmndi:BPMNShape>
      <bpmndi:BPMNShape id="request_di" bpmnElement="request"><dc:Bounds x="270" y="115" width="100" height="80"/></bpmndi:BPMNShape>
      <bpmndi:BPMNShape id="agent_task_di" bpmnElement="agent_task"><dc:Bounds x="440" y="265" width="100" height="80"/></bpmndi:BPMNShape>
      <bpmndi:BPMNShape id="end_event_di" bpmnElement="end_event"><dc:Bounds x="620" y="287" width="36" height="36"/></bpmndi:BPMNShape>
      <bpmndi:BPMNEdge id="Flow_start_event_request_di" bpmnElement="Flow_start_event_request"><di:waypoint x="216" y="155"/><di:waypoint x="270" y="155"/></bpmndi:BPMNEdge>
      <bpmndi:BPMNEdge id="Flow_request_agent_task_di" bpmnElement="Flow_request_agent_task"><di:waypoint x="320" y="195"/><di:waypoint x="320" y="305"/><di:waypoint x="440" y="305"/></bpmndi:BPMNEdge>
      <bpmndi:BPMNEdge id="Flow_agent_task_end_event_di" bpmnElement="Flow_agent_task_end_event"><di:waypoint x="540" y="305"/><di:waypoint x="620" y="305"/></bpmndi:BPMNEdge>
    </bpmndi:BPMNPlane>
  </bpmndi:BPMNDiagram>
</bpmn:definitions>
"""


def admin(method: str, path: str, body: dict | None = None) -> dict:
    url = os.environ.get("SUPABASE_URL", "http://127.0.0.1:54321") + path
    key = os.environ["SUPABASE_SERVICE_KEY"]
    req = urllib.request.Request(url, method=method, data=json.dumps(body).encode() if body else None,
                                 headers={"apikey": key, "Authorization": f"Bearer {key}", "Content-Type": "application/json"})
    with urllib.request.urlopen(req) as r:
        return json.loads(r.read() or b"{}")


def ensure_login() -> dict:
    cred = json.loads(CRED_FILE.read_text()) if CRED_FILE.exists() else {"email": LOGIN_EMAIL, "password": "E2e!" + secrets.token_urlsafe(12)}
    users = admin("GET", "/auth/v1/admin/users?per_page=1000").get("users", [])
    found = next((u for u in users if u.get("email") == LOGIN_EMAIL), None)
    if found:
        admin("PUT", f"/auth/v1/admin/users/{found['id']}", {"password": cred["password"], "email_confirm": True})
        cred["id"] = found["id"]
    else:
        cred["id"] = admin("POST", "/auth/v1/admin/users", {"email": LOGIN_EMAIL, "password": cred["password"], "email_confirm": True,
                                                           "user_metadata": {"name": "재개 e2e"}})["id"]
    CRED_FILE.write_text(json.dumps(cred))
    CRED_FILE.chmod(0o600)
    return cred


def main() -> None:
    db = psycopg.connect(os.environ.get("DB_URL", "postgresql://postgres:postgres@127.0.0.1:54322/postgres"), autocommit=True)
    ids = [pid(k) for k in SCENARIOS]
    if "--drop" in sys.argv:
        with db.cursor() as c:
            c.execute("delete from todolist where proc_def_id = any(%s)", (ids,))
            c.execute("delete from bpm_proc_inst where proc_def_id = any(%s)", (ids,))
            c.execute("delete from form_def where proc_def_id = any(%s)", (ids,))
            c.execute("delete from proc_def where id = any(%s)", (ids,))
        print("dropped", ids)
        return

    cred = ensure_login()
    with db.cursor() as c:
        c.execute("""insert into users (id, username, email, is_admin, role, tenant_id, is_agent)
                     values (%s, %s, %s, true, 'user', %s, false)
                     on conflict (id, tenant_id) do update set username=excluded.username, email=excluded.email, is_admin=true""",
                  (cred["id"], "재개 e2e", LOGIN_EMAIL, TENANT))
        c.execute("""insert into users (id, username, tenant_id, is_agent, agent_type, role, goal, persona, description, tools, skills)
                     values (%s, %s, %s, true, 'agent', '업무 수행', '지시받은 단계를 순서대로 수행한다', '정확하고 간결한 업무 에이전트',
                             '체크포인트 재개 e2e 전용 에이전트', '', '')
                     on conflict (id, tenant_id) do update set username=excluded.username, is_agent=true""",
                  (AGENT_ID, AGENT_NAME, TENANT))
        for key, sc in SCENARIOS.items():
            p = pid(key)
            d = definition(key, sc)
            # proc_def 의 키는 uuid 뿐이라 (id, tenant_id) upsert 가 안 된다.
            c.execute("delete from proc_def where id=%s and tenant_id=%s", (p, TENANT))
            c.execute("""insert into proc_def (id, name, definition, bpmn, tenant_id, isdeleted, type)
                         values (%s, %s, %s, %s, %s, false, 'process')""",
                      (p, sc["name"], json.dumps(d, ensure_ascii=False), bpmn(key, sc, d), TENANT))
            for fid, act_id, field, alias in ((f"{p}_request_form", "request", "request", "요청 내용"),
                                              (f"{p}_result_form", "agent_task", "result", "수행 결과")):
                c.execute("delete from form_def where id=%s and tenant_id=%s", (fid, TENANT))
                c.execute("""insert into form_def (id, proc_def_id, activity_id, tenant_id, html, fields_json)
                             values (%s, %s, %s, %s, %s, %s)""",
                          (fid, p, act_id, TENANT, form_html(fid, field, alias),
                           json.dumps([{"key": field, "text": alias, "type": "textarea", "disabled": "false", "readonly": "false"}], ensure_ascii=False)))
    print(json.dumps({"login": LOGIN_EMAIL, "user_id": cred["id"], "agent": AGENT_ID, "proc_defs": ids}, ensure_ascii=False))


if __name__ == "__main__":
    main()
