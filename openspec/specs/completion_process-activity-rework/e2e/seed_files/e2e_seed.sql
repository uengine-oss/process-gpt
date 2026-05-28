-- =====================================================================
-- completion_process-activity-rework E2E seed
-- ---------------------------------------------------------------------
-- Seeds the minimum deterministic data for the rework suite:
--   1. tenants.localhost
--   2. auth.users + public.users : reworker-e2e@uengine.org
--      (separate from agent-memory-chat suite to keep suites independent)
--   3. proc_def + proc_def_version : rework_demo_proc with 3 linear
--      activities act_a → act_b → act_c, each owning a formHandler
--   4. form_def rows for each activity (html NOT NULL respected)
--   5. bpm_proc_inst row to satisfy FK and instance navigation
--   6. todolist : three DONE workitems (act_a, act_b, act_c) all owned
--      by the reworker user; rework_count = 0
--   7. mcp_python_code : delete any prior compensation row for
--      (rework_demo_proc, act_b, localhost) so scenario 04 starts clean
--   8. events : delete any prior events for this proc_inst so the
--      compensation-skip branch is exercised deterministically
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
-- 2. Auth + public profile for the reworker user
--    Fixed UUID so the browser session and the public profile stay in
--    lock-step across reruns.
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
    'a1c0ffee-0000-0000-0000-000000000001',
    'authenticated', 'authenticated',
    'reworker-e2e@uengine.org',
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
    'a1c0ffee-0000-0000-0000-000000000001',
    '재작업 테스트 사용자',
    'reworker-e2e@uengine.org',
    'localhost',
    true, 'admin', false
) on conflict (id, tenant_id) do update
  set username = excluded.username,
      email    = excluded.email,
      is_admin = excluded.is_admin,
      role     = excluded.role,
      is_agent = excluded.is_agent;

-- ---------------------------------------------------------------------
-- 3. Process definition (3 linear activities act_a → act_b → act_c)
-- ---------------------------------------------------------------------
do $seed$
declare
  v_def_json jsonb := jsonb_build_object(
    'processDefinitionId',   'rework_demo_proc',
    'processDefinitionName', '재작업 데모 프로세스',
    'description',           '재작업 시나리오 검증용 3단계 직선 프로세스',
    'data',     '[]'::jsonb,
    'roles',    '[]'::jsonb,
    'gateways', '[]'::jsonb,
    'subProcesses','[]'::jsonb,
    'sequences', jsonb_build_array(
       jsonb_build_object('id','seq_ab','source','act_a','target','act_b'),
       jsonb_build_object('id','seq_bc','source','act_b','target','act_c')
    ),
    'activities', jsonb_build_array(
       jsonb_build_object(
         'id','act_a','name','첫 번째 단계','type','userTask',
         'description','초기 입력 단계','role','user',
         'tool','formHandler:form_a'
       ),
       jsonb_build_object(
         'id','act_b','name','두 번째 단계','type','userTask',
         'description','중간 입력 단계','role','user',
         'tool','formHandler:form_b',
         'inputData', jsonb_build_array('form_a.field_x')
       ),
       jsonb_build_object(
         'id','act_c','name','세 번째 단계','type','userTask',
         'description','마지막 입력 단계','role','user',
         'tool','formHandler:form_c',
         'inputData', jsonb_build_array('form_b.field_y')
       )
    )
  );
begin
  insert into public.proc_def (id, name, definition, tenant_id, isdeleted, type)
  values ('rework_demo_proc', '재작업 데모 프로세스', v_def_json, 'localhost', false, 'major')
  on conflict (id, tenant_id) do update
    set definition = excluded.definition,
        name       = excluded.name;

  if not exists (
    select 1 from public.proc_def_version
     where proc_def_id = 'rework_demo_proc' and tenant_id = 'localhost' and version = '1'
  ) then
    insert into public.proc_def_version (
      arcv_id, proc_def_id, version, version_tag, definition, tenant_id, message
    ) values (
      'rework_demo_proc_arcv_1', 'rework_demo_proc', '1', 'major', v_def_json, 'localhost',
      'E2E seed'
    );
  else
    update public.proc_def_version
       set definition = v_def_json
     where proc_def_id = 'rework_demo_proc' and tenant_id = 'localhost' and version = '1';
  end if;
end $seed$;

-- ---------------------------------------------------------------------
-- 4. Form definitions (html NOT NULL — see memory form-def-html-not-null)
-- ---------------------------------------------------------------------
insert into public.form_def (id, proc_def_id, activity_id, tenant_id, fields_json, html)
values
  ('rework_form_a_def', 'rework_demo_proc', 'act_a', 'localhost',
   jsonb_build_array(jsonb_build_object('key','field_x','type','text','label','X 값')),
   '<form><input name="field_x"/></form>'),
  ('rework_form_b_def', 'rework_demo_proc', 'act_b', 'localhost',
   jsonb_build_array(jsonb_build_object('key','field_y','type','text','label','Y 값')),
   '<form><input name="field_y"/></form>'),
  ('rework_form_c_def', 'rework_demo_proc', 'act_c', 'localhost',
   jsonb_build_array(jsonb_build_object('key','field_z','type','text','label','Z 값')),
   '<form><input name="field_z"/></form>')
on conflict (id, tenant_id) do update
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
    'rework_demo_proc',
    'rework_demo_proc.e2e-instance-0001',
    '재작업 데모 인스턴스',
    ARRAY['act_c'],
    ARRAY['a1c0ffee-0000-0000-0000-000000000001'],
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
-- 6a. Reset todolist for this instance so prior rework rows (created by
--     previous test runs) do not leave the get_reference_workitems
--     "most-recent" lookup pointing at IN_PROGRESS instead of DONE.
-- ---------------------------------------------------------------------
delete from public.todolist
 where proc_inst_id = 'rework_demo_proc.e2e-instance-0001';

-- ---------------------------------------------------------------------
-- 6. Todolist rows — three DONE workitems owned by the reworker user.
--    Fixed UUIDs so Playwright can navigate /todolist/<taskId> for act_b.
-- ---------------------------------------------------------------------
insert into public.todolist (
    id, user_id, username,
    proc_inst_id, root_proc_inst_id, execution_scope,
    proc_def_id, version_tag, version,
    activity_id, activity_name,
    start_date, end_date,
    status, description, tool, due_date,
    tenant_id, retry, consumer, output,
    rework_count
) values
  (
    'a0c00001-0000-0000-0000-000000000001'::uuid,
    'a1c0ffee-0000-0000-0000-000000000001',
    '재작업 테스트 사용자',
    'rework_demo_proc.e2e-instance-0001',
    'rework_demo_proc.e2e-instance-0001',
    '0',
    'rework_demo_proc', 'major', '1',
    'act_a', '첫 번째 단계',
    now(), now(),
    'DONE', '첫 단계 완료', 'formHandler:form_a', null,
    'localhost', 0, null,
    jsonb_build_object('form_a', jsonb_build_object('field_x','초기값')),
    0
  ),
  (
    'a0c00002-0000-0000-0000-000000000002'::uuid,
    'a1c0ffee-0000-0000-0000-000000000001',
    '재작업 테스트 사용자',
    'rework_demo_proc.e2e-instance-0001',
    'rework_demo_proc.e2e-instance-0001',
    '0',
    'rework_demo_proc', 'major', '1',
    'act_b', '두 번째 단계',
    now(), now(),
    'DONE', '중간 단계 완료', 'formHandler:form_b', null,
    'localhost', 0, null,
    jsonb_build_object('form_b', jsonb_build_object('field_y','중간값')),
    0
  ),
  (
    'a0c00003-0000-0000-0000-000000000003'::uuid,
    'a1c0ffee-0000-0000-0000-000000000001',
    '재작업 테스트 사용자',
    'rework_demo_proc.e2e-instance-0001',
    'rework_demo_proc.e2e-instance-0001',
    '0',
    'rework_demo_proc', 'major', '1',
    'act_c', '세 번째 단계',
    now(), now(),
    'DONE', '마지막 단계 완료', 'formHandler:form_c', null,
    'localhost', 0, null,
    jsonb_build_object('form_c', jsonb_build_object('field_z','마지막값')),
    0
  )
on conflict (id) do update
  set status        = excluded.status,
      output        = excluded.output,
      end_date      = excluded.end_date,
      retry         = excluded.retry,
      tool          = excluded.tool,
      activity_id   = excluded.activity_id,
      activity_name = excluded.activity_name,
      rework_count  = 0;

-- ---------------------------------------------------------------------
-- 7. Ensure mcp_python_code table exists (not part of root init.sql in
--    every checkout) so compensation_handler.fetch_mcp_python_code does
--    not 404 and short-circuit the rework-complete handler. Then clear
--    any prior compensation row so scenario 04 starts deterministic.
-- ---------------------------------------------------------------------
create table if not exists public.mcp_python_code (
    id           uuid primary key default gen_random_uuid(),
    proc_def_id  text not null,
    activity_id  text not null,
    tenant_id    text not null,
    compensation text,
    created_at   timestamp with time zone default now(),
    updated_at   timestamp with time zone default now()
);

-- Allow PostgREST anon/service_role to read the table (mirrors other
-- tables seeded for E2E suites — broad grants are fine in the throwaway
-- e2e database).
grant all on public.mcp_python_code to anon, authenticated, service_role, supabase_admin;
notify pgrst, 'reload schema';

delete from public.mcp_python_code
 where proc_def_id = 'rework_demo_proc'
   and tenant_id   = 'localhost';

-- ---------------------------------------------------------------------
-- 8. Clear events for this instance so the compensation-skip branch is
--    exercised (no tool_usage_finished events → generate_compensation
--    returns early without calling the LLM).
-- ---------------------------------------------------------------------
do $cleanup_events$
begin
  if exists (
    select 1 from information_schema.tables
     where table_schema = 'public' and table_name = 'events'
  ) then
    execute $sql$
      delete from public.events
       where proc_inst_id = 'rework_demo_proc.e2e-instance-0001'
    $sql$;
  end if;
end $cleanup_events$;
