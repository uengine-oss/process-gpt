-- =====================================================================
-- completion_process-workitem-submission E2E seed
-- ---------------------------------------------------------------------
-- Prepares the minimum, deterministic data the suite needs:
--   1. tenants: `localhost` (browser tenant) and `tenant-b` (isolation)
--   2. configuration: `proc_map` tree so /definition-map lists the
--      executable process as a clickable sub-process card
--   3. proc_def: executable + error-path + version + tenant-b definitions
--   4. proc_def_version: explicit major v1/v2 rows for `e2e_pws_versioned`
--   5. form_def: a simple textarea form rendered by FormWorkItem
--   6. bpm_proc_inst + todolist: an existing TODO workitem for the
--      "기존 워크아이템 갱신 제출" browser scenario (task_id update path)
--
-- The login user (e2e@uengine.org, uid 1111...1111, tenant `localhost`)
-- is seeded by the shared completion_agent-memory-chat suite seed.
--
-- The frontend resolves its tenant from the host name; on localhost
-- every row must live in the `localhost` tenant. `tenant-b` rows exist
-- only to prove tenant isolation in scenario 03.
--
-- Idempotent: delete-then-insert keeps every row deterministic.
-- =====================================================================
set search_path to public, extensions;

-- ---------------------------------------------------------------------
-- 1. Tenants
-- ---------------------------------------------------------------------
insert into public.tenants (id, owner) values ('localhost', null)
on conflict (id) do nothing;
insert into public.tenants (id, owner) values ('tenant-b', null)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------
-- 2. proc_def - process definitions
--    All ids lowercase (getExecutionDefinition lowercases lookups).
-- ---------------------------------------------------------------------
delete from public.proc_def
where id in (
    'e2e_pws_leave', 'e2e_pws_no_initial', 'e2e_pws_no_user',
    'e2e_pws_versioned', 'e2e_pws_tenant_b'
);

-- 2a. e2e_pws_leave - main executable definition (localhost)
--     start_event -> apply_leave (userTask) -> end_event
insert into public.proc_def (id, name, tenant_id, isdeleted, definition, bpmn) values (
  'e2e_pws_leave', 'E2E 휴가 신청 프로세스', 'localhost', false,
  $json$
  {
    "processDefinitionName": "E2E 휴가 신청 프로세스",
    "processDefinitionId": "e2e_pws_leave",
    "description": "E2E 검증용 휴가 신청 프로세스",
    "data": [],
    "roles": [
      {"name": "담당자", "default": "11111111-1111-1111-1111-111111111111",
       "endpoint": "", "resolutionRule": "휴가를 신청하는 본인"}
    ],
    "activities": [
      {"id": "apply_leave", "name": "휴가 신청서 작성", "role": "담당자",
       "type": "userTask", "tool": "formHandler:e2e_pws_form", "duration": 1,
       "description": "휴가 사유와 기간을 입력한다",
       "instruction": "휴가 사유와 기간을 입력하세요",
       "inputData": [], "outputData": [], "checkpoints": [], "properties": "{}"}
    ],
    "gateways": [
      {"id": "start_event", "name": "프로세스 시작", "role": "담당자",
       "type": "startEvent", "process": "Process_1", "condition": {},
       "properties": "{}", "description": "start event"},
      {"id": "end_event", "name": "프로세스 종료", "role": "담당자",
       "type": "endEvent", "process": "Process_1", "condition": {},
       "properties": "{}", "description": "end event"}
    ],
    "sequences": [
      {"id": "seq_start_apply", "source": "start_event", "target": "apply_leave",
       "condition": "", "properties": "{}"},
      {"id": "seq_apply_end", "source": "apply_leave", "target": "end_event",
       "condition": "", "properties": "{}"}
    ],
    "subProcesses": []
  }
  $json$::jsonb,
  $bpmn$<?xml version="1.0" encoding="UTF-8"?>
<bpmn:definitions xmlns:bpmn="http://www.omg.org/spec/BPMN/20100524/MODEL" xmlns:bpmndi="http://www.omg.org/spec/BPMN/20100524/DI" xmlns:dc="http://www.omg.org/spec/DD/20100524/DC" xmlns:di="http://www.omg.org/spec/DD/20100524/DI" id="Definitions_e2e_pws_leave" targetNamespace="http://bpmn.io/schema/bpmn">
  <bpmn:process id="Process_1" isExecutable="true">
    <bpmn:startEvent id="start_event" name="프로세스 시작"><bpmn:outgoing>seq_start_apply</bpmn:outgoing></bpmn:startEvent>
    <bpmn:userTask id="apply_leave" name="휴가 신청서 작성"><bpmn:incoming>seq_start_apply</bpmn:incoming><bpmn:outgoing>seq_apply_end</bpmn:outgoing></bpmn:userTask>
    <bpmn:endEvent id="end_event" name="프로세스 종료"><bpmn:incoming>seq_apply_end</bpmn:incoming></bpmn:endEvent>
    <bpmn:sequenceFlow id="seq_start_apply" sourceRef="start_event" targetRef="apply_leave" />
    <bpmn:sequenceFlow id="seq_apply_end" sourceRef="apply_leave" targetRef="end_event" />
  </bpmn:process>
  <bpmndi:BPMNDiagram id="BPMNDiagram_1">
    <bpmndi:BPMNPlane id="BPMNPlane_1" bpmnElement="Process_1">
      <bpmndi:BPMNShape id="start_event_di" bpmnElement="start_event"><dc:Bounds x="160" y="100" width="36" height="36" /></bpmndi:BPMNShape>
      <bpmndi:BPMNShape id="apply_leave_di" bpmnElement="apply_leave"><dc:Bounds x="260" y="78" width="100" height="80" /></bpmndi:BPMNShape>
      <bpmndi:BPMNShape id="end_event_di" bpmnElement="end_event"><dc:Bounds x="420" y="100" width="36" height="36" /></bpmndi:BPMNShape>
      <bpmndi:BPMNEdge id="seq_start_apply_di" bpmnElement="seq_start_apply"><di:waypoint x="196" y="118" /><di:waypoint x="260" y="118" /></bpmndi:BPMNEdge>
      <bpmndi:BPMNEdge id="seq_apply_end_di" bpmnElement="seq_apply_end"><di:waypoint x="360" y="118" /><di:waypoint x="420" y="118" /></bpmndi:BPMNEdge>
    </bpmndi:BPMNPlane>
  </bpmndi:BPMNDiagram>
</bpmn:definitions>$bpmn$
);

-- 2b. e2e_pws_no_initial - startEvent gateway with no outgoing sequence,
--     so find_initial_activity() returns None -> 400 "No initial activity found"
insert into public.proc_def (id, name, tenant_id, isdeleted, definition) values (
  'e2e_pws_no_initial', 'E2E 초기 활동 없음 프로세스', 'localhost', false,
  $json$
  {
    "processDefinitionName": "E2E 초기 활동 없음 프로세스",
    "processDefinitionId": "e2e_pws_no_initial",
    "data": [], "roles": [], "activities": [], "subProcesses": [],
    "gateways": [
      {"id": "start_event", "name": "프로세스 시작", "role": "담당자",
       "type": "startEvent", "process": "Process_1", "condition": {},
       "properties": "{}", "description": "start event"}
    ],
    "sequences": []
  }
  $json$::jsonb
);

-- 2c. e2e_pws_no_user - initial activity role has no default/endpoint user,
--     so /initiate without email -> 400 "No default user email found"
insert into public.proc_def (id, name, tenant_id, isdeleted, definition) values (
  'e2e_pws_no_user', 'E2E 담당자 미지정 프로세스', 'localhost', false,
  $json$
  {
    "processDefinitionName": "E2E 담당자 미지정 프로세스",
    "processDefinitionId": "e2e_pws_no_user",
    "data": [], "subProcesses": [],
    "roles": [
      {"name": "담당자", "default": null, "endpoint": null,
       "resolutionRule": "담당자 미지정"}
    ],
    "activities": [
      {"id": "apply_leave", "name": "휴가 신청서 작성", "role": "담당자",
       "type": "userTask", "duration": 1,
       "description": "휴가 사유와 기간을 입력한다",
       "inputData": [], "outputData": [], "checkpoints": [], "properties": "{}"}
    ],
    "gateways": [
      {"id": "start_event", "name": "프로세스 시작", "role": "담당자",
       "type": "startEvent", "process": "Process_1", "condition": {},
       "properties": "{}", "description": "start event"}
    ],
    "sequences": [
      {"id": "seq_start_apply", "source": "start_event", "target": "apply_leave",
       "condition": "", "properties": "{}"}
    ]
  }
  $json$::jsonb
);

-- 2d. e2e_pws_versioned - definition whose explicit version is resolved
--     from proc_def_version (major v1 / v2). proc_def.definition holds a
--     placeholder used only when no version row matches.
insert into public.proc_def (id, name, tenant_id, isdeleted, definition) values (
  'e2e_pws_versioned', 'E2E 버전 검증 프로세스', 'localhost', false,
  $json$
  {
    "processDefinitionName": "E2E 버전 검증 프로세스 (proc_def)",
    "processDefinitionId": "e2e_pws_versioned",
    "data": [], "subProcesses": [],
    "roles": [
      {"name": "담당자", "default": "11111111-1111-1111-1111-111111111111",
       "endpoint": "", "resolutionRule": "본인"}
    ],
    "activities": [
      {"id": "version_activity", "name": "버전 검증 활동 base", "role": "담당자",
       "type": "userTask", "duration": 1, "description": "버전 검증 활동",
       "inputData": [], "outputData": [], "checkpoints": [], "properties": "{}"}
    ],
    "gateways": [
      {"id": "start_event", "name": "프로세스 시작", "role": "담당자",
       "type": "startEvent", "process": "Process_1", "condition": {},
       "properties": "{}", "description": "start event"}
    ],
    "sequences": [
      {"id": "seq_start_va", "source": "start_event", "target": "version_activity",
       "condition": "", "properties": "{}"}
    ]
  }
  $json$::jsonb
);

-- 2e. e2e_pws_tenant_b - executable definition that exists ONLY in tenant-b
insert into public.proc_def (id, name, tenant_id, isdeleted, definition) values (
  'e2e_pws_tenant_b', 'E2E 타 테넌트 전용 프로세스', 'tenant-b', false,
  $json$
  {
    "processDefinitionName": "E2E 타 테넌트 전용 프로세스",
    "processDefinitionId": "e2e_pws_tenant_b",
    "data": [], "subProcesses": [],
    "roles": [
      {"name": "담당자", "default": "11111111-1111-1111-1111-111111111111",
       "endpoint": "", "resolutionRule": "본인"}
    ],
    "activities": [
      {"id": "apply_leave", "name": "타 테넌트 휴가 신청", "role": "담당자",
       "type": "userTask", "duration": 1, "description": "타 테넌트 활동",
       "inputData": [], "outputData": [], "checkpoints": [], "properties": "{}"}
    ],
    "gateways": [
      {"id": "start_event", "name": "프로세스 시작", "role": "담당자",
       "type": "startEvent", "process": "Process_1", "condition": {},
       "properties": "{}", "description": "start event"}
    ],
    "sequences": [
      {"id": "seq_start_apply", "source": "start_event", "target": "apply_leave",
       "condition": "", "properties": "{}"}
    ]
  }
  $json$::jsonb
);

-- ---------------------------------------------------------------------
-- 3. proc_def_version - explicit major versions for e2e_pws_versioned
--    initiate with version_tag=major version=1 -> "버전 검증 활동 v1"
--    initiate with version_tag=major version=2 -> "버전 검증 활동 v2"
-- ---------------------------------------------------------------------
delete from public.proc_def_version where proc_def_id = 'e2e_pws_versioned';

insert into public.proc_def_version
  (arcv_id, proc_def_id, version, version_tag, tenant_id, definition) values
(
  'e2e_pws_versioned_v1', 'e2e_pws_versioned', '1', 'major', 'localhost',
  $json$
  {
    "processDefinitionName": "E2E 버전 검증 프로세스 v1",
    "processDefinitionId": "e2e_pws_versioned",
    "data": [], "subProcesses": [],
    "roles": [
      {"name": "담당자", "default": "11111111-1111-1111-1111-111111111111",
       "endpoint": "", "resolutionRule": "본인"}
    ],
    "activities": [
      {"id": "version_activity", "name": "버전 검증 활동 v1", "role": "담당자",
       "type": "userTask", "duration": 1, "description": "버전 1 활동",
       "inputData": [], "outputData": [], "checkpoints": [], "properties": "{}"}
    ],
    "gateways": [
      {"id": "start_event", "name": "프로세스 시작", "role": "담당자",
       "type": "startEvent", "process": "Process_1", "condition": {},
       "properties": "{}", "description": "start event"}
    ],
    "sequences": [
      {"id": "seq_start_va", "source": "start_event", "target": "version_activity",
       "condition": "", "properties": "{}"}
    ]
  }
  $json$::jsonb
),
(
  'e2e_pws_versioned_v2', 'e2e_pws_versioned', '2', 'major', 'localhost',
  $json$
  {
    "processDefinitionName": "E2E 버전 검증 프로세스 v2",
    "processDefinitionId": "e2e_pws_versioned",
    "data": [], "subProcesses": [],
    "roles": [
      {"name": "담당자", "default": "11111111-1111-1111-1111-111111111111",
       "endpoint": "", "resolutionRule": "본인"}
    ],
    "activities": [
      {"id": "version_activity", "name": "버전 검증 활동 v2", "role": "담당자",
       "type": "userTask", "duration": 1, "description": "버전 2 활동",
       "inputData": [], "outputData": [], "checkpoints": [], "properties": "{}"}
    ],
    "gateways": [
      {"id": "start_event", "name": "프로세스 시작", "role": "담당자",
       "type": "startEvent", "process": "Process_1", "condition": {},
       "properties": "{}", "description": "start event"}
    ],
    "sequences": [
      {"id": "seq_start_va", "source": "start_event", "target": "version_activity",
       "condition": "", "properties": "{}"}
    ]
  }
  $json$::jsonb
);

-- ---------------------------------------------------------------------
-- 4. configuration - proc_map tree for /definition-map listing
--    sub_proc_list[].id must equal proc_def.id (e2e_pws_leave).
-- ---------------------------------------------------------------------
delete from public.configuration
where key = 'proc_map' and tenant_id = 'localhost';

insert into public.configuration (key, value, tenant_id) values (
  'proc_map',
  $json$
  {
    "mega_proc_list": [
      {
        "id": "e2e_mega", "name": "E2E 검증 영역",
        "major_proc_list": [
          {
            "id": "e2e_major", "name": "E2E 워크아이템 제출",
            "sub_proc_list": [
              {"id": "e2e_pws_leave", "name": "E2E 휴가 신청 프로세스"}
            ]
          }
        ]
      }
    ]
  }
  $json$::jsonb,
  'localhost'
);

-- ---------------------------------------------------------------------
-- 5. form_def - simple textarea form for FormWorkItem (id e2e_pws_form)
--    Same proven structure FormWorkItem uses for its default form.
-- ---------------------------------------------------------------------
delete from public.form_def
where id = 'e2e_pws_form' and tenant_id = 'localhost';

insert into public.form_def (id, proc_def_id, activity_id, tenant_id, html) values (
  'e2e_pws_form', 'e2e_pws_leave', 'apply_leave', 'localhost',
  $html$<section>  <row-layout name="leave_section" alias="휴가 신청" is_multidata_mode="false" v-model="formValues" v-slot="slotProps"><div class="row"><div class="col-sm-12">      <textarea-field name="leave_reason" alias="휴가 사유" rows="5" disabled="false" readonly="false" v-model="slotProps.modelValue['leave_reason']"></textarea-field>    </div></div></row-layout></section>$html$
);

-- ---------------------------------------------------------------------
-- 6. bpm_proc_inst + todolist - an existing TODO workitem (scenario 02)
--    Fixed task_id so the task_id update path is deterministic.
-- ---------------------------------------------------------------------
delete from public.todolist where id = 'e2e00002-0000-4000-8000-000000000001';
delete from public.bpm_proc_inst where proc_inst_id = 'e2e_pws_leave.e2eexisting0001';

insert into public.bpm_proc_inst
  (proc_inst_id, proc_def_id, proc_inst_name, tenant_id, status, start_date) values (
  'e2e_pws_leave.e2eexisting0001', 'e2e_pws_leave',
  'E2E 휴가 신청 프로세스', 'localhost', 'RUNNING', now()
);

insert into public.todolist
  (id, user_id, username, proc_inst_id, root_proc_inst_id, proc_def_id,
   activity_id, activity_name, status, description, tool, tenant_id,
   start_date, due_date) values (
  'e2e00002-0000-4000-8000-000000000001',
  '11111111-1111-1111-1111-111111111111', 'E2E 사용자',
  'e2e_pws_leave.e2eexisting0001', 'e2e_pws_leave.e2eexisting0001',
  'e2e_pws_leave', 'apply_leave', '휴가 신청서 작성', 'TODO',
  '휴가 신청서를 작성합니다', 'formHandler:e2e_pws_form', 'localhost',
  now(), now() + interval '1 day'
);
