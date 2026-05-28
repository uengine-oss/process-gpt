-- =====================================================================
-- completion_process-data-query E2E seed
-- ---------------------------------------------------------------------
-- Two tenants are seeded:
--   1. `localhost` - the browser tenant; gets a proc_def, form_def,
--      bpm_proc_inst, and a todolist row for the e2e user.
--   2. `altten` - a sibling tenant whose data MUST NOT leak into
--      /process-data-query when the request comes via the localhost
--      gateway. Used by scenario 04 (tenant isolation).
--
-- Idempotent: safe to re-run.
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
-- 2. Ensure optional columns exist
-- ---------------------------------------------------------------------
alter table public.users add column if not exists agent_type text;
alter table public.users add column if not exists alias text;

-- ---------------------------------------------------------------------
-- 3. Login user (auth.users + public.users)
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
    '22222222-2222-2222-2222-222222222222',
    'authenticated', 'authenticated',
    'e2e@uengine.org',
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
    '22222222-2222-2222-2222-222222222222',
    'E2E 사용자', 'e2e@uengine.org', 'localhost', true, 'admin', false
) on conflict (id, tenant_id) do update
  set username = excluded.username,
      email    = excluded.email;

-- ---------------------------------------------------------------------
-- 4. proc_def rows
--    localhost: vacation_request_process
--    altten:    altten_only_secret_process (must NOT appear in localhost prompt)
-- ---------------------------------------------------------------------
insert into public.proc_def (id, name, definition, bpmn, tenant_id, type)
values (
    'vacation_request_process',
    '휴가 신청 프로세스',
    '{"processDefinitionId":"vacation_request_process","processDefinitionName":"휴가 신청 프로세스","description":"E2E 테스트용","data":[{"name":"leave_days","description":"휴가 일수","type":"Number"}],"roles":[],"activities":[],"sequences":[]}'::jsonb,
    '<bpmn />',
    'localhost',
    'process'
) on conflict do nothing;
update public.proc_def set definition='{"processDefinitionId":"vacation_request_process","processDefinitionName":"휴가 신청 프로세스","description":"E2E 테스트용","data":[{"name":"leave_days","description":"휴가 일수","type":"Number"}],"roles":[],"activities":[],"sequences":[]}'::jsonb
where id='vacation_request_process' and tenant_id='localhost';

insert into public.proc_def (id, name, definition, bpmn, tenant_id, type)
values (
    'altten_only_secret_process',
    '타 테넌트 비공개 프로세스',
    '{"processDefinitionId":"altten_only_secret_process","processDefinitionName":"타 테넌트 프로세스","data":[],"roles":[],"activities":[],"sequences":[]}'::jsonb,
    '<bpmn />',
    'altten',
    'process'
) on conflict do nothing;
update public.proc_def set definition='{"processDefinitionId":"altten_only_secret_process","processDefinitionName":"타 테넌트 프로세스","data":[],"roles":[],"activities":[],"sequences":[]}'::jsonb
where id='altten_only_secret_process' and tenant_id='altten';

-- ---------------------------------------------------------------------
-- 5. form_def rows (html column is NOT NULL — set a placeholder)
-- ---------------------------------------------------------------------
insert into public.form_def (html, proc_def_id, activity_id, tenant_id, id, fields_json)
values (
    '<form><input name="leave_days" /></form>',
    'vacation_request_process',
    'submit_request',
    'localhost',
    'vacation_request_process_submit_request_form',
    '{"fields": [{"key": "leave_days", "type": "number"}]}'::jsonb
) on conflict do nothing;

insert into public.form_def (html, proc_def_id, activity_id, tenant_id, id, fields_json)
values (
    '<form />',
    'altten_only_secret_process',
    'secret_activity',
    'altten',
    'altten_only_secret_process_secret_activity_form',
    '{}'::jsonb
) on conflict do nothing;

-- ---------------------------------------------------------------------
-- 6. bpm_proc_inst for the localhost user
-- ---------------------------------------------------------------------
insert into public.bpm_proc_inst (
    proc_def_id, proc_inst_id, proc_inst_name,
    current_activity_ids, participants, role_bindings, variables_data,
    status, tenant_id, start_date
) values (
    'vacation_request_process',
    'vacation_request_process.pdq-e2e-inst-1',
    '휴가 신청 인스턴스 1',
    array['submit_request'],
    array['e2e@uengine.org'],
    '[]'::jsonb,
    '[{"name":"leave_days","value":3}]'::jsonb,
    'RUNNING',
    'localhost',
    now()
) on conflict (proc_inst_id) do nothing;

-- ---------------------------------------------------------------------
-- 7. todolist for the localhost user
-- ---------------------------------------------------------------------
insert into public.todolist (
    id, user_id, proc_inst_id, proc_def_id, activity_id, activity_name,
    status, description, tenant_id
) values (
    gen_random_uuid(),
    'e2e@uengine.org',
    'vacation_request_process.pdq-e2e-inst-1',
    'vacation_request_process',
    'submit_request',
    '휴가 신청서 제출',
    'IN_PROGRESS',
    '휴가 신청서를 작성해 제출하세요',
    'localhost'
) on conflict do nothing;
