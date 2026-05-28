-- =====================================================================
-- completion_process-workitem-submission E2E seed
-- ---------------------------------------------------------------------
-- Two tenants:
--   localhost: 정상 정의(`wis_basic_process`), 결함 정의(`wis_no_initial_process`,
--              `wis_no_user_process`), 버전 정의(`wis_versioned_process`),
--              기존 TODO 워크아이템(`wis_existing_todo`).
--   altten:    `wis_altten_only_process` — 다른 테넌트로 보이지 않아야 함.
--
-- Idempotent.
-- =====================================================================
set search_path to public, extensions;

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- 1. Tenants
-- ---------------------------------------------------------------------
insert into public.tenants (id, owner) values ('localhost', null)
  on conflict (id) do nothing;
insert into public.tenants (id, owner) values ('altten', null)
  on conflict (id) do nothing;

-- ---------------------------------------------------------------------
-- 2. users table optional columns (other seeds already create these)
-- ---------------------------------------------------------------------
alter table public.users add column if not exists agent_type text;
alter table public.users add column if not exists alias text;

-- ---------------------------------------------------------------------
-- 3. Test user (auth.users + public.users)
-- ---------------------------------------------------------------------
insert into auth.users (
    instance_id, id, aud, role,
    email, encrypted_password,
    email_confirmed_at, recovery_sent_at,
    raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at, last_sign_in_at,
    confirmation_token, email_change, email_change_token_new, recovery_token
) values (
    '00000000-0000-0000-0000-000000000000',
    '33333333-3333-3333-3333-333333333333',
    'authenticated', 'authenticated',
    'e2e-wis@uengine.org',
    crypt('e2epassword', gen_salt('bf')),
    now(), null,
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{}'::jsonb,
    now(), now(), now(),
    '', '', '', ''
) on conflict (id) do update
  set encrypted_password = excluded.encrypted_password,
      email_confirmed_at = excluded.email_confirmed_at,
      updated_at         = now();

insert into public.users (id, username, email, tenant_id, is_admin, role, is_agent)
values (
    '33333333-3333-3333-3333-333333333333',
    'WIS 사용자', 'e2e-wis@uengine.org', 'localhost', true, 'admin', false
) on conflict (id, tenant_id) do update
  set username = excluded.username,
      email    = excluded.email;

-- ---------------------------------------------------------------------
-- 4. proc_def rows
-- ---------------------------------------------------------------------

-- Clear prior WIS rows so re-seed can apply schema fixes
delete from public.todolist where id = '11111111-1111-1111-1111-111111111111'::uuid;
delete from public.bpm_proc_inst where proc_inst_id like 'wis-%';
delete from public.proc_def_version where proc_def_id like 'wis_%';
delete from public.form_def where proc_def_id like 'wis_%';
delete from public.proc_def where id like 'wis_%';

-- 4a. wis_basic_process (정상): startEvent -> submit_request 활동
insert into public.proc_def (uuid, id, name, definition, bpmn, tenant_id, type)
values (
    'aaaaaaaa-0000-0000-0000-000000000001'::uuid,
    'wis_basic_process',
    'WIS 기본 프로세스',
    jsonb_build_object(
      'processDefinitionId', 'wis_basic_process',
      'processDefinitionName', 'WIS 기본 프로세스',
      'roles', jsonb_build_array(
        jsonb_build_object('name', 'requester', 'default', 'e2e-wis@uengine.org', 'resolutionRule', 'submitting user')
      ),
      'activities', jsonb_build_array(
        jsonb_build_object(
          'id', 'submit_request',
          'name', '신청서 제출',
          'role', 'requester',
          'type', 'UserActivity',
          'description', '휴가 신청서를 제출합니다',
          'instruction', 'leave_days 값을 채워 제출하세요',
          'duration', 1,
          'tool', null,
          'inputData', '[]'::jsonb,
          'outputData', '[]'::jsonb,
          'checkpoints', '[]'::jsonb
        )
      ),
      'sequences', jsonb_build_array(
        jsonb_build_object('id', 'seq_start_submit', 'source', 'start_event_1', 'target', 'submit_request')
      ),
      'events', jsonb_build_array(
        jsonb_build_object('id', 'start_event_1', 'type', 'startEvent', 'name', 'start')
      )
    ),
    '<bpmn />',
    'localhost',
    'process'
) on conflict do nothing;

-- 4b. wis_no_initial_process (결함): startEvent와 활동을 잇는 sequence 없음
insert into public.proc_def (uuid, id, name, definition, bpmn, tenant_id, type)
values (
    'aaaaaaaa-0000-0000-0000-000000000002'::uuid,
    'wis_no_initial_process',
    'WIS 결함 초기활동 없음',
    jsonb_build_object(
      'processDefinitionId', 'wis_no_initial_process',
      'processDefinitionName', 'WIS 결함 초기활동 없음',
      'roles', jsonb_build_array(
        jsonb_build_object('name', 'requester', 'default', 'e2e-wis@uengine.org')
      ),
      'activities', jsonb_build_array(
        jsonb_build_object('id', 'orphan_activity', 'name', '고립된 활동', 'role', 'requester', 'type', 'UserActivity', 'description', '연결되지 않은 활동')
      ),
      'sequences', '[]'::jsonb,
      'events', jsonb_build_array(
        jsonb_build_object('id', 'start_event_1', 'type', 'startEvent', 'name', 'start')
      )
    ),
    '<bpmn />',
    'localhost',
    'process'
) on conflict do nothing;

-- 4c. wis_no_user_process (결함): role default/endpoint 없음
insert into public.proc_def (uuid, id, name, definition, bpmn, tenant_id, type)
values (
    'aaaaaaaa-0000-0000-0000-000000000003'::uuid,
    'wis_no_user_process',
    'WIS 결함 사용자 미지정',
    jsonb_build_object(
      'processDefinitionId', 'wis_no_user_process',
      'processDefinitionName', 'WIS 결함 사용자 미지정',
      'roles', jsonb_build_array(
        jsonb_build_object('name', 'requester')
      ),
      'activities', jsonb_build_array(
        jsonb_build_object('id', 'submit_request', 'name', '신청서 제출', 'role', 'requester', 'type', 'UserActivity', 'description', '신청서 제출 활동')
      ),
      'sequences', jsonb_build_array(
        jsonb_build_object('id', 'seq_start_submit', 'source', 'start_event_1', 'target', 'submit_request')
      ),
      'events', jsonb_build_array(
        jsonb_build_object('id', 'start_event_1', 'type', 'startEvent', 'name', 'start')
      )
    ),
    '<bpmn />',
    'localhost',
    'process'
) on conflict do nothing;

-- 4d. wis_versioned_process: definition은 현재 버전(submit_request_current),
--     proc_def_version(major, 1.0)는 submit_request_v1
insert into public.proc_def (uuid, id, name, definition, bpmn, tenant_id, type)
values (
    'aaaaaaaa-0000-0000-0000-000000000004'::uuid,
    'wis_versioned_process',
    'WIS 버전 프로세스',
    jsonb_build_object(
      'processDefinitionId', 'wis_versioned_process',
      'processDefinitionName', 'WIS 버전 프로세스 (현재)',
      'roles', jsonb_build_array(
        jsonb_build_object('name', 'requester', 'default', 'e2e-wis@uengine.org')
      ),
      'activities', jsonb_build_array(
        jsonb_build_object('id', 'submit_request_current', 'name', '현재 버전 활동', 'role', 'requester', 'type', 'UserActivity', 'description', '현재 버전 활동')
      ),
      'sequences', jsonb_build_array(
        jsonb_build_object('id', 'seq_start_current', 'source', 'start_event_1', 'target', 'submit_request_current')
      ),
      'events', jsonb_build_array(
        jsonb_build_object('id', 'start_event_1', 'type', 'startEvent', 'name', 'start')
      )
    ),
    '<bpmn />',
    'localhost',
    'process'
) on conflict do nothing;

-- 4e. wis_altten_only_process — altten 테넌트 전용
insert into public.proc_def (uuid, id, name, definition, bpmn, tenant_id, type)
values (
    'aaaaaaaa-0000-0000-0000-000000000005'::uuid,
    'wis_altten_only_process',
    '타 테넌트 비공개 프로세스',
    jsonb_build_object(
      'processDefinitionId', 'wis_altten_only_process',
      'processDefinitionName', '타 테넌트 비공개 프로세스',
      'roles', jsonb_build_array(
        jsonb_build_object('name', 'requester', 'default', 'altten-only@uengine.org')
      ),
      'activities', jsonb_build_array(
        jsonb_build_object('id', 'secret_activity', 'name', '비공개 활동', 'role', 'requester', 'type', 'UserActivity', 'description', '비공개 활동')
      ),
      'sequences', jsonb_build_array(
        jsonb_build_object('id', 'seq_start_secret', 'source', 'start_event_1', 'target', 'secret_activity')
      ),
      'events', jsonb_build_array(
        jsonb_build_object('id', 'start_event_1', 'type', 'startEvent', 'name', 'start')
      )
    ),
    '<bpmn />',
    'altten',
    'process'
) on conflict do nothing;

-- ---------------------------------------------------------------------
-- 5. proc_def_version row (major, 1.0) for wis_versioned_process
-- ---------------------------------------------------------------------
insert into public.proc_def_version (arcv_id, proc_def_id, version_tag, version, definition, tenant_id)
select 'wis-versioned-arcv-1', 'wis_versioned_process', 'major', '1.0',
    jsonb_build_object(
      'processDefinitionId', 'wis_versioned_process',
      'processDefinitionName', 'WIS 버전 프로세스 v1',
      'roles', jsonb_build_array(
        jsonb_build_object('name', 'requester', 'default', 'e2e-wis@uengine.org')
      ),
      'activities', jsonb_build_array(
        jsonb_build_object('id', 'submit_request_v1', 'name', 'v1 활동', 'role', 'requester', 'type', 'UserActivity', 'description', 'v1 활동')
      ),
      'sequences', jsonb_build_array(
        jsonb_build_object('id', 'seq_start_v1', 'source', 'start_event_1', 'target', 'submit_request_v1')
      ),
      'events', jsonb_build_array(
        jsonb_build_object('id', 'start_event_1', 'type', 'startEvent', 'name', 'start')
      )
    ),
    'localhost'
where not exists (
    select 1 from public.proc_def_version
    where proc_def_id = 'wis_versioned_process'
      and version_tag = 'major'
      and version = '1.0'
      and tenant_id = 'localhost'
);

-- ---------------------------------------------------------------------
-- 6. form_def — html column NOT NULL, placeholder OK (memory: form-def-html-not-null)
-- ---------------------------------------------------------------------
insert into public.form_def (html, proc_def_id, activity_id, tenant_id, id, fields_json)
values (
    '<form><input name="leave_days" type="number" /></form>',
    'wis_basic_process',
    'submit_request',
    'localhost',
    'wis_basic_process_submit_request_form',
    '{"fields": [{"key": "leave_days", "type": "number"}]}'::jsonb
) on conflict do nothing;

-- ---------------------------------------------------------------------
-- 7. bpm_proc_inst — existing instance with a TODO workitem (scenario 05)
-- ---------------------------------------------------------------------
insert into public.bpm_proc_inst (
    proc_def_id, proc_inst_id, proc_inst_name,
    current_activity_ids, participants, role_bindings, variables_data,
    status, tenant_id, start_date
) values (
    'wis_basic_process',
    'wis-existing-inst',
    'WIS 기존 인스턴스',
    array['submit_request'],
    array['e2e-wis@uengine.org'],
    '[]'::jsonb,
    '{}'::jsonb,
    'RUNNING',
    'localhost',
    now()
) on conflict (proc_inst_id) do nothing;

-- ---------------------------------------------------------------------
-- 8. todolist — existing TODO row that scenario 05 updates via task_id
-- ---------------------------------------------------------------------
insert into public.todolist (
    id, user_id, username, proc_inst_id, proc_def_id, activity_id, activity_name,
    status, description, tenant_id, start_date, due_date, duration
) values (
    '11111111-1111-1111-1111-111111111111',
    '33333333-3333-3333-3333-333333333333',
    'WIS 사용자',
    'wis-existing-inst',
    'wis_basic_process',
    'submit_request',
    '신청서 제출',
    'TODO',
    '기존 휴가 신청서 제출',
    'localhost',
    now(),
    now() + interval '1 day',
    1
) on conflict (id) do nothing;
