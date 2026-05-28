-- =====================================================================
-- completion_automated-task-execution E2E seed
-- ---------------------------------------------------------------------
-- Seeds the minimum deterministic data the polling worker + frontend
-- need to demonstrate automated serviceTask execution:
--   1. tenants.localhost.mcp jsonb (two MCP servers: success_server,
--      failure_server) -- the polling worker reads this column via
--      fetch_tenant_mcp_config.
--   2. auth.users + public.users for the human E2E login
--      (ate-e2e@uengine.org / ate-password).
--   3. Two public.users agent rows (is_agent=true), each with a single
--      MCP server name in `tools` so MultiServerMCPClient connects to
--      exactly one mock server per scenario.
--   4. A proc_def + proc_def_version with two serviceTask activities
--      (act_success, act_failure) under the same processDefinitionId.
--   5. A bpm_proc_inst pointing at that definition.
--   6. Two todolist rows with status='SUBMITTED', user_id formatted as
--      "<agent_uuid>,<human_uuid>" so handle_service_workitem treats the
--      agent as the actor and the frontend kanban (filter user_id LIKE
--      %human_uuid%) still shows the workitems to the test user.
--
-- Idempotent: safe to re-run.
-- =====================================================================
set search_path to public, extensions;

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- 1. Tenant + MCP config
-- ---------------------------------------------------------------------
insert into public.tenants (id, owner) values ('localhost', null)
on conflict (id) do nothing;

update public.tenants
   set mcp = jsonb_build_object(
       'mcpServers', jsonb_build_object(
           'success_server', jsonb_build_object(
               'transport', 'stdio',
               'command',   'python',
               'args',      jsonb_build_array('/mocks/mock_mcp_server.py'),
               'env',       jsonb_build_object('MCP_MODE', 'success')
           ),
           'failure_server', jsonb_build_object(
               'transport', 'stdio',
               'command',   'python',
               'args',      jsonb_build_array('/mocks/mock_mcp_server.py'),
               'env',       jsonb_build_object('MCP_MODE', 'failure')
           )
       )
   )
 where id = 'localhost';

-- ---------------------------------------------------------------------
-- 2. Ensure agent_type column exists on public.users
-- ---------------------------------------------------------------------
alter table public.users add column if not exists agent_type text;
alter table public.users add column if not exists alias text;

-- ---------------------------------------------------------------------
-- 3. Login user (human)
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
    'ate-e2e@uengine.org',
    -- Precomputed bcrypt for 'ate-password'. Avoiding gen_salt() means
    -- re-seeds produce a stable hash, so GoTrue never sees a stale or
    -- regenerated-but-unmatched password value.
    '$2a$06$EdGznFMJOR.0cZcdULG5oOrfQ2hxYy3QZWY1Pp1rYjX9YH1SbC7oq',
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
    'ATE 사용자', 'ate-e2e@uengine.org', 'localhost', true, 'admin', false
) on conflict (id, tenant_id) do update
  set username = excluded.username,
      email    = excluded.email,
      is_admin = excluded.is_admin,
      role     = excluded.role,
      is_agent = excluded.is_agent;

-- ---------------------------------------------------------------------
-- 4. Service agents (one per MCP server)
-- ---------------------------------------------------------------------
insert into public.users (
    id, username, email, tenant_id, is_admin, role,
    is_agent, agent_type, model, tools, goal, persona, description
) values
  (
    'a1111111-0000-0000-0000-000000000001',
    'MCP 성공 에이전트',
    'mcp-success-agent@uengine.org',
    'localhost', false, 'agent',
    true, 'agent', 'gpt-4o',
    'success_server',
    '성공 도구를 실행해 결과를 기록한다.',
    '자동화 서비스 에이전트',
    'E2E 검증용 성공 도구 실행 에이전트'
  ),
  (
    'a2222222-0000-0000-0000-000000000002',
    'MCP 실패 에이전트',
    'mcp-failure-agent@uengine.org',
    'localhost', false, 'agent',
    true, 'agent', 'gpt-4o',
    'failure_server',
    '실패 도구를 실행해 오류 결과를 기록한다.',
    '자동화 서비스 에이전트',
    'E2E 검증용 실패 도구 실행 에이전트'
  )
on conflict (id, tenant_id) do update
  set tools       = excluded.tools,
      is_agent    = excluded.is_agent,
      agent_type  = excluded.agent_type,
      model       = excluded.model,
      goal        = excluded.goal,
      persona     = excluded.persona,
      description = excluded.description;

-- ---------------------------------------------------------------------
-- 5. Process definition: two serviceTask activities under one def
-- ---------------------------------------------------------------------
do $seed$
declare
  v_def_json jsonb := jsonb_build_object(
    'processDefinitionId',   'ate_demo_proc',
    'processDefinitionName', '자동 실행 데모 프로세스',
    'description',           'serviceTask MCP 실행 E2E 시나리오용',
    'data',     '[]'::jsonb,
    'roles',    '[]'::jsonb,
    'gateways', '[]'::jsonb,
    'sequences','[]'::jsonb,
    'subProcesses','[]'::jsonb,
    'activities', jsonb_build_array(
       jsonb_build_object(
         'id',          'act_success',
         'name',        'MCP 성공 도구 실행',
         'type',        'serviceTask',
         'description', 'success_tool 을 실행해 결과를 기록한다.',
         'role',        'agent',
         'tool',        'success_server'
       ),
       jsonb_build_object(
         'id',          'act_failure',
         'name',        'MCP 실패 도구 실행',
         'type',        'serviceTask',
         'description', 'failure_tool 을 실행해 오류 결과를 기록한다.',
         'role',        'agent',
         'tool',        'failure_server'
       )
    )
  );
begin
  insert into public.proc_def (id, name, definition, tenant_id, isdeleted, type)
  values ('ate_demo_proc', '자동 실행 데모 프로세스', v_def_json, 'localhost', false, 'major')
  on conflict (id, tenant_id) do update
    set definition = excluded.definition,
        name       = excluded.name;

  if not exists (
    select 1 from public.proc_def_version
     where proc_def_id = 'ate_demo_proc' and tenant_id = 'localhost' and version = '1'
  ) then
    insert into public.proc_def_version (
      arcv_id, proc_def_id, version, version_tag, definition, tenant_id, message
    ) values (
      'ate_demo_proc_arcv_1', 'ate_demo_proc', '1', 'major', v_def_json, 'localhost',
      'E2E seed'
    );
  else
    update public.proc_def_version
       set definition = v_def_json
     where proc_def_id = 'ate_demo_proc' and tenant_id = 'localhost' and version = '1';
  end if;
end $seed$;

-- ---------------------------------------------------------------------
-- 6. Process instance
-- ---------------------------------------------------------------------
insert into public.bpm_proc_inst (
    proc_def_id, proc_inst_id, proc_inst_name,
    current_activity_ids, participants, role_bindings,
    variables_data, status, tenant_id,
    version_tag, version,
    start_date, updated_at
) values (
    'ate_demo_proc',
    'ate_demo_proc.e2e-instance-0001',
    '자동 실행 데모 인스턴스',
    ARRAY['act_success','act_failure'],
    ARRAY['22222222-2222-2222-2222-222222222222'],
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
-- 7. Two SUBMITTED serviceTask workitems
--    user_id = "<agent_uuid>,<human_uuid>"
--      - handle_service_workitem picks the assignee whose type=='agent'
--      - frontend getWorkList filters with user_id LIKE %<human>% so
--        the kanban board shows these rows to the human user.
-- ---------------------------------------------------------------------
insert into public.todolist (
    id, user_id, username,
    proc_inst_id, root_proc_inst_id, execution_scope,
    proc_def_id, version_tag, version,
    activity_id, activity_name,
    start_date, end_date,
    status, description, tool, due_date,
    tenant_id, retry, consumer
) values
  (
    '11111111-aaaa-aaaa-aaaa-000000000001'::uuid,
    'a1111111-0000-0000-0000-000000000001,22222222-2222-2222-2222-222222222222',
    'MCP 성공 에이전트',
    'ate_demo_proc.e2e-instance-0001',
    'ate_demo_proc.e2e-instance-0001',
    '0',
    'ate_demo_proc', 'major', '1',
    'act_success', 'MCP 성공 도구 실행',
    now(), null,
    'SUBMITTED', 'success_tool 을 실행해 결과를 기록한다.', 'success_server', null,
    'localhost', 0, null
  ),
  (
    '22222222-aaaa-aaaa-aaaa-000000000002'::uuid,
    'a2222222-0000-0000-0000-000000000002,22222222-2222-2222-2222-222222222222',
    'MCP 실패 에이전트',
    'ate_demo_proc.e2e-instance-0001',
    'ate_demo_proc.e2e-instance-0001',
    '0',
    'ate_demo_proc', 'major', '1',
    'act_failure', 'MCP 실패 도구 실행',
    now(), null,
    'SUBMITTED', 'failure_tool 을 실행해 오류 결과를 기록한다.', 'failure_server', null,
    'localhost', 0, 'hold-test-02'
  )
on conflict (id) do update
  set status   = excluded.status,
      consumer = excluded.consumer,
      output   = null,
      log      = null,
      retry    = 0;

-- =====================================================================
-- 8. scriptTask 시나리오 (03, 04)
-- ---------------------------------------------------------------------
-- handle_workitem 의 LangChain 완료 판정 파이프라인을 거쳐 _execute_script_tasks
-- 가 scriptTask 를 inline 실행하도록, userTask 선행을 시드한다.
--   - act_setup_03 (userTask) -> act_script_03 (scriptTask, exit 0)
--   - act_setup_04 (userTask) -> act_script_04 (scriptTask, exit 1)
-- proc_inst.role_bindings 의 "everyone" 엔드포인트를 사용자 UUID 로 설정해
-- check_role_binding 의 LLM 폴백을 회피한다.
-- =====================================================================
do $seed03$
declare
  v_def_03 jsonb := jsonb_build_object(
    'processDefinitionId',   'ate_script_03_proc',
    'processDefinitionName', '스크립트 정상 실행 데모',
    'description',           'scriptTask 정상 종료 E2E 시나리오',
    'data',     '[]'::jsonb,
    'roles',    jsonb_build_array(jsonb_build_object('name','everyone','resolutionRule','직접 지정')),
    'gateways', jsonb_build_array(
       jsonb_build_object('id','start_03','name','start','type','startEvent'),
       jsonb_build_object('id','end_03','name','end','type','endEvent')
    ),
    'sequences', jsonb_build_array(
       jsonb_build_object('id','seq_03_a','source','start_03','target','act_setup_03'),
       jsonb_build_object('id','seq_03_b','source','act_setup_03','target','act_script_03'),
       jsonb_build_object('id','seq_03_c','source','act_script_03','target','end_03')
    ),
    'subProcesses','[]'::jsonb,
    'activities', jsonb_build_array(
       jsonb_build_object(
         'id','act_setup_03','name','스크립트 03 트리거','type','userTask',
         'description','스크립트 작업 03 을 시작하기 위한 선행 사용자 활동',
         'role','everyone','checkpoints', jsonb_build_array()
       ),
       jsonb_build_object(
         'id','act_script_03','name','스크립트 03 실행','type','scriptTask',
         'description','정상 종료되는 파이썬 스크립트',
         'role','everyone',
         'pythonCode',
         E'import os, sys, json, pathlib\n' ||
         E'order = os.environ.get("orderId", "unknown")\n' ||
         E'msg = "ate-script-03-result:" + order\n' ||
         E'pathlib.Path("/coverage/ate_script_03.out").write_text(msg)\n' ||
         E'print(msg)\n' ||
         E'sys.exit(0)\n'
       )
    )
  );
  v_def_04 jsonb := jsonb_build_object(
    'processDefinitionId',   'ate_script_04_proc',
    'processDefinitionName', '스크립트 비정상 종료 데모',
    'description',           'scriptTask 비정상 종료 E2E 시나리오',
    'data',     '[]'::jsonb,
    'roles',    jsonb_build_array(jsonb_build_object('name','everyone','resolutionRule','직접 지정')),
    'gateways', jsonb_build_array(
       jsonb_build_object('id','start_04','name','start','type','startEvent'),
       jsonb_build_object('id','end_04','name','end','type','endEvent')
    ),
    'sequences', jsonb_build_array(
       jsonb_build_object('id','seq_04_a','source','start_04','target','act_setup_04'),
       jsonb_build_object('id','seq_04_b','source','act_setup_04','target','act_script_04'),
       jsonb_build_object('id','seq_04_c','source','act_script_04','target','end_04')
    ),
    'subProcesses','[]'::jsonb,
    'activities', jsonb_build_array(
       jsonb_build_object(
         'id','act_setup_04','name','스크립트 04 트리거','type','userTask',
         'description','스크립트 작업 04 를 시작하기 위한 선행 사용자 활동',
         'role','everyone','checkpoints', jsonb_build_array()
       ),
       jsonb_build_object(
         'id','act_script_04','name','스크립트 04 실행','type','scriptTask',
         'description','비정상 종료되는 파이썬 스크립트',
         'role','everyone',
         'pythonCode',
         E'import os, sys, pathlib\n' ||
         E'pathlib.Path("/coverage/ate_script_04.err").write_text("ate-script-04-error:boom")\n' ||
         E'sys.stderr.write("ate-script-04-error:boom\\n")\n' ||
         E'sys.exit(1)\n'
       )
    )
  );
begin
  insert into public.proc_def (id, name, definition, tenant_id, isdeleted, type)
  values ('ate_script_03_proc','스크립트 정상 실행 데모', v_def_03, 'localhost', false, 'major')
  on conflict (id, tenant_id) do update set definition = excluded.definition, name = excluded.name;
  insert into public.proc_def (id, name, definition, tenant_id, isdeleted, type)
  values ('ate_script_04_proc','스크립트 비정상 종료 데모', v_def_04, 'localhost', false, 'major')
  on conflict (id, tenant_id) do update set definition = excluded.definition, name = excluded.name;

  if not exists (select 1 from public.proc_def_version where proc_def_id='ate_script_03_proc' and tenant_id='localhost' and version='1') then
    insert into public.proc_def_version (arcv_id, proc_def_id, version, version_tag, definition, tenant_id, message)
    values ('ate_script_03_arcv_1','ate_script_03_proc','1','major', v_def_03, 'localhost', 'E2E seed 03');
  else
    update public.proc_def_version set definition = v_def_03 where proc_def_id='ate_script_03_proc' and tenant_id='localhost' and version='1';
  end if;
  if not exists (select 1 from public.proc_def_version where proc_def_id='ate_script_04_proc' and tenant_id='localhost' and version='1') then
    insert into public.proc_def_version (arcv_id, proc_def_id, version, version_tag, definition, tenant_id, message)
    values ('ate_script_04_arcv_1','ate_script_04_proc','1','major', v_def_04, 'localhost', 'E2E seed 04');
  else
    update public.proc_def_version set definition = v_def_04 where proc_def_id='ate_script_04_proc' and tenant_id='localhost' and version='1';
  end if;
end $seed03$;

-- process instances with role_bindings binding 'everyone' to the human UUID
insert into public.bpm_proc_inst (
    proc_def_id, proc_inst_id, proc_inst_name,
    current_activity_ids, participants, role_bindings,
    variables_data, status, tenant_id,
    version_tag, version, start_date, updated_at
) values (
    'ate_script_03_proc', 'ate_script_03_proc.e2e-instance-0003','스크립트 정상 실행 인스턴스',
    ARRAY['act_setup_03'], ARRAY['22222222-2222-2222-2222-222222222222'],
    jsonb_build_array(jsonb_build_object('name','everyone','endpoint', jsonb_build_array('22222222-2222-2222-2222-222222222222'))),
    jsonb_build_array(jsonb_build_object('key','orderId','value','E2E-1001'))::jsonb,
    'RUNNING','localhost','major','1', now(), now()
), (
    'ate_script_04_proc', 'ate_script_04_proc.e2e-instance-0004','스크립트 비정상 종료 인스턴스',
    ARRAY['act_setup_04'], ARRAY['22222222-2222-2222-2222-222222222222'],
    jsonb_build_array(jsonb_build_object('name','everyone','endpoint', jsonb_build_array('22222222-2222-2222-2222-222222222222'))),
    '[]'::jsonb,
    'RUNNING','localhost','major','1', now(), now()
) on conflict (proc_inst_id) do update
  set status                = excluded.status,
      current_activity_ids  = excluded.current_activity_ids,
      role_bindings         = excluded.role_bindings,
      variables_data        = excluded.variables_data,
      updated_at            = excluded.updated_at;

-- userTask workitems (한국어 사용자 화면 노출용). consumer 로 reservation 해서
-- 폴링 워커가 시나리오 01/02 와 동시 처리하지 않도록 직렬화.
insert into public.todolist (
    id, user_id, username,
    proc_inst_id, root_proc_inst_id, execution_scope,
    proc_def_id, version_tag, version,
    activity_id, activity_name,
    start_date, end_date,
    status, description, tool, due_date,
    tenant_id, retry, consumer
) values
  (
    '33333333-aaaa-aaaa-aaaa-000000000003'::uuid,
    '22222222-2222-2222-2222-222222222222',
    'ATE 사용자',
    'ate_script_03_proc.e2e-instance-0003',
    'ate_script_03_proc.e2e-instance-0003',
    '0',
    'ate_script_03_proc', 'major', '1',
    'act_setup_03', '스크립트 03 트리거',
    now(), null,
    'SUBMITTED', '스크립트 정상 종료 시나리오 트리거', null, null,
    'localhost', 0, 'hold-test-03'
  ),
  (
    '44444444-aaaa-aaaa-aaaa-000000000004'::uuid,
    '22222222-2222-2222-2222-222222222222',
    'ATE 사용자',
    'ate_script_04_proc.e2e-instance-0004',
    'ate_script_04_proc.e2e-instance-0004',
    '0',
    'ate_script_04_proc', 'major', '1',
    'act_setup_04', '스크립트 04 트리거',
    now(), null,
    'SUBMITTED', '스크립트 비정상 종료 시나리오 트리거', null, null,
    'localhost', 0, 'hold-test-04'
  )
on conflict (id) do update
  set status   = excluded.status,
      consumer = excluded.consumer,
      output   = null,
      log      = null,
      retry    = 0;
