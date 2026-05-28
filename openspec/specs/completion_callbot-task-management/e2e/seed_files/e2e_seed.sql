-- =====================================================================
-- completion_callbot-task-management E2E seed
-- ---------------------------------------------------------------------
-- Seeds the minimum deterministic data for callbot protocol API tests:
--   1. tenants.localhost row exists.
--   2. public.users: a callbot test user (no auth.users needed because
--      the callbot API authenticates via subdomain only).
--   3. public.todolist rows for caller-info/tasks/task-detail/update/
--      submit scenarios.
--   4. public.proc_def + public.proc_def_version with one process
--      definition containing two activities (act_prev, act_target),
--      where act_target has inputData ["prev_form.field_a"], instruction
--      and checkpoints.
--   5. public.form_def row providing fields_json for act_target.
--   6. public.bpm_proc_inst row to satisfy FK / consistency.
--
-- Idempotent: safe to re-run.
-- =====================================================================
set search_path to public, extensions;

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- 1. Tenant
-- ---------------------------------------------------------------------
insert into public.tenants (id, owner) values ('localhost', null)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------
-- 2. Callbot test user
-- ---------------------------------------------------------------------
insert into public.users (id, username, email, tenant_id, is_admin, role, is_agent)
values (
    'c5c11111-1111-1111-1111-111111111111',
    '콜봇테스트사용자',
    'callbot-e2e@uengine.org',
    'localhost',
    false,
    'user',
    false
) on conflict (id, tenant_id) do update
  set username = excluded.username,
      email    = excluded.email,
      is_admin = excluded.is_admin,
      role     = excluded.role,
      is_agent = excluded.is_agent;

-- ---------------------------------------------------------------------
-- 3. Process definition (act_prev DONE 선행 + act_target 콜봇 처리 대상)
-- ---------------------------------------------------------------------
do $seed$
declare
  v_def_json jsonb := jsonb_build_object(
    'processDefinitionId',   'callbot_demo_proc',
    'processDefinitionName', '콜봇 데모 프로세스',
    'description',           '콜봇 task-management 시나리오 검증용',
    'data',     '[]'::jsonb,
    'roles',    '[]'::jsonb,
    'gateways', '[]'::jsonb,
    'sequences','[]'::jsonb,
    'subProcesses','[]'::jsonb,
    'activities', jsonb_build_array(
       jsonb_build_object(
         'id',          'act_prev',
         'name',        '선행 입력 단계',
         'type',        'userTask',
         'description', '이전 단계에서 입력된 값',
         'role',        'user',
         'tool',        'formHandler:prev_form'
       ),
       jsonb_build_object(
         'id',          'act_target',
         'name',        '콜봇 처리 대상',
         'type',        'userTask',
         'description', '콜봇이 폼을 채워 제출하는 대상 작업',
         'role',        'user',
         'tool',        'formHandler:target_form',
         'instruction', '발신자의 음성을 받아 폼 항목을 채우십시오.',
         'checkpoints', jsonb_build_array('이름 확인', '연락처 확인'),
         'inputData',   jsonb_build_array('prev_form.field_a')
       )
    )
  );
begin
  insert into public.proc_def (id, name, definition, tenant_id, isdeleted, type)
  values ('callbot_demo_proc', '콜봇 데모 프로세스', v_def_json, 'localhost', false, 'major')
  on conflict (id, tenant_id) do update
    set definition = excluded.definition,
        name       = excluded.name;

  if not exists (
    select 1 from public.proc_def_version
     where proc_def_id = 'callbot_demo_proc' and tenant_id = 'localhost' and version = '1'
  ) then
    insert into public.proc_def_version (
      arcv_id, proc_def_id, version, version_tag, definition, tenant_id, message
    ) values (
      'callbot_demo_proc_arcv_1', 'callbot_demo_proc', '1', 'major', v_def_json, 'localhost',
      'E2E seed'
    );
  else
    update public.proc_def_version
       set definition = v_def_json
     where proc_def_id = 'callbot_demo_proc' and tenant_id = 'localhost' and version = '1';
  end if;
end $seed$;

-- ---------------------------------------------------------------------
-- 4. Form definition for act_target
-- ---------------------------------------------------------------------
insert into public.form_def (
    id, proc_def_id, activity_id, tenant_id, fields_json, html
) values (
    'callbot_target_form_def',
    'callbot_demo_proc',
    'act_target',
    'localhost',
    jsonb_build_array(
        jsonb_build_object('key', 'customer_name', 'type', 'text', 'label', '고객명'),
        jsonb_build_object('key', 'phone',         'type', 'text', 'label', '연락처')
    ),
    '<form><input name="customer_name"/><input name="phone"/></form>'
) on conflict (id, tenant_id) do update
  set fields_json = excluded.fields_json,
      proc_def_id = excluded.proc_def_id,
      activity_id = excluded.activity_id,
      html        = excluded.html;

-- ---------------------------------------------------------------------
-- 5. Process instance
-- ---------------------------------------------------------------------
insert into public.bpm_proc_inst (
    proc_def_id, proc_inst_id, proc_inst_name,
    current_activity_ids, participants, role_bindings,
    variables_data, status, tenant_id,
    version_tag, version,
    start_date, updated_at
) values (
    'callbot_demo_proc',
    'callbot_demo_proc.e2e-instance-0001',
    '콜봇 데모 인스턴스',
    ARRAY['act_target'],
    ARRAY['c5c11111-1111-1111-1111-111111111111'],
    '[]'::jsonb,
    '[]'::jsonb,
    'RUNNING',
    'localhost',
    'major', '1',
    now(), now()
) on conflict (proc_inst_id) do update
  set status                = excluded.status,
      current_activity_ids  = excluded.current_activity_ids,
      updated_at            = excluded.updated_at;

-- ---------------------------------------------------------------------
-- 6. Todolist rows
--    cbe20001 (TODO, 시나리오 02)
--    cbe20002 (IN_PROGRESS, 시나리오 02)
--    cbe20003 (DONE, 시나리오 02 - active 필터에서 제외 확인용)
--    cbe30001 (DONE, 시나리오 03 선행 입력)
--    cbe30002 (TODO, 시나리오 03/04/05 콜봇 처리 대상)
-- ---------------------------------------------------------------------
insert into public.todolist (
    id, user_id, username,
    proc_inst_id, root_proc_inst_id, execution_scope,
    proc_def_id, version_tag, version,
    activity_id, activity_name,
    start_date, end_date,
    status, description, tool, due_date,
    tenant_id, retry, consumer, output
) values
  (
    'cbe20001-0000-0000-0000-000000000001'::uuid,
    'c5c11111-1111-1111-1111-111111111111',
    '콜봇테스트사용자',
    'callbot_demo_proc.e2e-instance-0001',
    'callbot_demo_proc.e2e-instance-0001',
    '0',
    'callbot_demo_proc', 'major', '1',
    'act_target', '첫 번째 할 일',
    now(), null,
    'TODO', '콜봇이 진행할 첫 번째 할 일', 'formHandler:target_form', null,
    'localhost', 0, null, '{}'::jsonb
  ),
  (
    'cbe20002-0000-0000-0000-000000000002'::uuid,
    'c5c11111-1111-1111-1111-111111111111',
    '콜봇테스트사용자',
    'callbot_demo_proc.e2e-instance-0001',
    'callbot_demo_proc.e2e-instance-0001',
    '0',
    'callbot_demo_proc', 'major', '1',
    'act_target', '진행 중 할 일',
    now(), null,
    'IN_PROGRESS', '진행 중인 할 일', 'formHandler:target_form', null,
    'localhost', 0, null, '{}'::jsonb
  ),
  (
    'cbe20003-0000-0000-0000-000000000003'::uuid,
    'c5c11111-1111-1111-1111-111111111111',
    '콜봇테스트사용자',
    'callbot_demo_proc.e2e-instance-0001',
    'callbot_demo_proc.e2e-instance-0001',
    '0',
    'callbot_demo_proc', 'major', '1',
    'act_target', '완료된 할 일',
    now(), now(),
    'DONE', '이미 완료된 할 일 (필터 제외 검증용)', 'formHandler:target_form', null,
    'localhost', 0, null, '{}'::jsonb
  ),
  (
    'cbe30001-0000-0000-0000-000000000001'::uuid,
    'c5c11111-1111-1111-1111-111111111111',
    '콜봇테스트사용자',
    'callbot_demo_proc.e2e-instance-0001',
    'callbot_demo_proc.e2e-instance-0001',
    '0',
    'callbot_demo_proc', 'major', '1',
    'act_prev', '선행 입력 단계',
    now(), now(),
    'DONE', '이전 폼에서 채워진 데이터', 'formHandler:prev_form', null,
    'localhost', 0, null,
    jsonb_build_object(
        'prev_form', jsonb_build_object('field_a', '이전값', 'field_b', '필터링대상'),
        'unrelated_form', jsonb_build_object('x', 'should-be-filtered')
    )
  ),
  (
    'cbe30002-0000-0000-0000-000000000002'::uuid,
    'c5c11111-1111-1111-1111-111111111111',
    '콜봇테스트사용자',
    'callbot_demo_proc.e2e-instance-0001',
    'callbot_demo_proc.e2e-instance-0001',
    '0',
    'callbot_demo_proc', 'major', '1',
    'act_target', '콜봇 처리 대상',
    now(), null,
    'TODO', '콜봇이 채워서 제출할 작업', 'formHandler:target_form', null,
    'localhost', 0, null, '{}'::jsonb
  )
on conflict (id) do update
  set status     = excluded.status,
      output     = excluded.output,
      consumer   = excluded.consumer,
      end_date   = excluded.end_date,
      retry      = excluded.retry,
      tool       = excluded.tool,
      activity_id   = excluded.activity_id,
      activity_name = excluded.activity_name;
