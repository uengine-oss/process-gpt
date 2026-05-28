-- =====================================================================
-- completion_process-definition-feedback E2E seed
-- ---------------------------------------------------------------------
-- Seeds the minimum deterministic data the suite needs:
--   1. tenants.localhost (idempotent)
--   2. public.proc_def + public.proc_def_version: a process definition
--      'pdf_demo_proc' with two activities (act_one, act_two) connected
--      by a single sequence, so process_definition.find_next_item and
--      find_sequences return a sensible structure for the diff prompt.
--   3. public.bpm_proc_inst pointing to act_one with
--      proc_def_version = 'pdf_demo_proc_arcv_1' so the handler's
--      arcv_id resolution branch is exercised.
--   4. public.todolist row with temp_feedback + log filled, used as
--      the taskId for /get-feedback and /get-feedback-diff success
--      scenarios.
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
-- 2. Process definition (act_one -> seq_one_to_two -> act_two)
-- ---------------------------------------------------------------------
do $seed$
declare
  v_def_json jsonb := jsonb_build_object(
    'processDefinitionId',   'pdf_demo_proc',
    'processDefinitionName', '프로세스 정의 피드백 데모',
    'description',           '프로세스 정의 피드백/차이 비교 시나리오 검증용',
    'data',     '[]'::jsonb,
    'roles',    '[]'::jsonb,
    'gateways', '[]'::jsonb,
    'subProcesses','[]'::jsonb,
    'sequences', jsonb_build_array(
       jsonb_build_object(
         'id',     'seq_one_to_two',
         'source', 'act_one',
         'target', 'act_two',
         'name',   '다음 단계'
       )
    ),
    'activities', jsonb_build_array(
       jsonb_build_object(
         'id',          'act_one',
         'name',        '초안 작성',
         'type',        'userTask',
         'description', '기본 설명',
         'instruction', '기본 지시',
         'role',        'user',
         'tool',        'formHandler:pdf_form',
         'checkpoints', jsonb_build_array('기본 점검'),
         'inputData',   '[]'::jsonb
       ),
       jsonb_build_object(
         'id',          'act_two',
         'name',        '검토',
         'type',        'userTask',
         'description', '초안 검토 단계',
         'role',        'user',
         'tool',        'formHandler:pdf_form_review',
         'inputData',   '[]'::jsonb
       )
    )
  );
begin
  insert into public.proc_def (id, name, definition, tenant_id, isdeleted, type)
  values ('pdf_demo_proc', '프로세스 정의 피드백 데모', v_def_json, 'localhost', false, 'major')
  on conflict (id, tenant_id) do update
    set definition = excluded.definition,
        name       = excluded.name;

  if not exists (
    select 1 from public.proc_def_version
     where proc_def_id = 'pdf_demo_proc' and tenant_id = 'localhost' and version = '1'
  ) then
    insert into public.proc_def_version (
      arcv_id, proc_def_id, version, version_tag, definition, tenant_id, message
    ) values (
      'pdf_demo_proc_arcv_1', 'pdf_demo_proc', '1', 'major', v_def_json, 'localhost',
      'E2E seed'
    );
  else
    update public.proc_def_version
       set definition = v_def_json
     where proc_def_id = 'pdf_demo_proc' and tenant_id = 'localhost' and version = '1';
  end if;
end $seed$;

-- ---------------------------------------------------------------------
-- 3. Process instance pointing at proc_def_version arcv_id
-- ---------------------------------------------------------------------
insert into public.bpm_proc_inst (
    proc_def_id, proc_inst_id, proc_inst_name,
    current_activity_ids, participants, role_bindings,
    variables_data, status, tenant_id,
    version_tag, version, proc_def_version,
    start_date, updated_at
) values (
    'pdf_demo_proc',
    'pdf_demo_proc.e2e-instance-0001',
    '프로세스 정의 피드백 인스턴스',
    ARRAY['act_one'],
    ARRAY['11111111-1111-1111-1111-111111111111'],
    '[]'::jsonb,
    '[]'::jsonb,
    'RUNNING',
    'localhost',
    'major', '1', 'pdf_demo_proc_arcv_1',
    now(), now()
) on conflict (proc_inst_id) do update
  set status                = excluded.status,
      current_activity_ids  = excluded.current_activity_ids,
      proc_def_version      = excluded.proc_def_version,
      updated_at            = excluded.updated_at;

-- ---------------------------------------------------------------------
-- 4. Todolist row (DONE, with temp_feedback and log)
-- ---------------------------------------------------------------------
insert into public.todolist (
    id, user_id, username,
    proc_inst_id, root_proc_inst_id, execution_scope,
    proc_def_id, version_tag, version,
    activity_id, activity_name,
    start_date, end_date,
    status, description, tool, due_date,
    tenant_id, retry, consumer, output,
    log, temp_feedback
) values (
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1'::uuid,
    '11111111-1111-1111-1111-111111111111',
    'E2E 사용자',
    'pdf_demo_proc.e2e-instance-0001',
    'pdf_demo_proc.e2e-instance-0001',
    '0',
    'pdf_demo_proc', 'major', '1',
    'act_one', '초안 작성',
    now(), now(),
    'DONE', '초안 작성 결과', 'formHandler:pdf_form', null,
    'localhost', 0, null,
    jsonb_build_object('pdf_form', jsonb_build_object('field_a', '초안 값')),
    '초안 결과 로그',
    '설명이 너무 추상적입니다. 더 구체적으로 보강해 주세요.'
) on conflict (id) do update
  set status        = excluded.status,
      output        = excluded.output,
      log           = excluded.log,
      temp_feedback = excluded.temp_feedback,
      activity_id   = excluded.activity_id,
      activity_name = excluded.activity_name;
