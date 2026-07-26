-- =====================================================================
-- Deterministic Undo E2E seed  (crewai-action_deterministic-undo)
--
-- 전제: crewai-action_deterministic-replay/e2e/run_e2e.py 가 먼저 실행되어
--   - inventory: iPhone=80(1차 LLM 실행), Galaxy=250(고착화 재실행)
--   - inventory_log: iPhone/Galaxy 각 1행
--   - mcp_python_code: 순방향 code + parameters
--   - events: 1차 실행(todo ...0001)의 tool_usage_finished 이력
-- 이 시드는 undo(재작업) 워크아이템 하나만 추가한다.
--
-- Idempotent: safe to re-run.
-- =====================================================================
set search_path to public, extensions;

insert into public.todolist
    (id, user_id, username, proc_inst_id, root_proc_inst_id,
     proc_def_id, activity_id, activity_name, status, tenant_id,
     agent_orch, rework_count, query, description, start_date, end_date)
select '11111111-2222-3333-4444-555555550003'::uuid, u.id::text, 'demo',
       'order_fulfillment_demo.det-demo-1', 'order_fulfillment_demo.det-demo-1',
       'order_fulfillment_demo', 'update_inventory', '재고 반영',
       'DONE'::todo_status, 'localhost', 'crewai-action', 1,
       '재작업 재실행: iPhone 상품의 정정 입고를 반영하라. 입고 수량(재고에 더할 값)은 40, 반영 후 재고는 60, 변경 사유는 재작업 반영.',
       'Undo: 고착화된 undo 코드로 이전 실행을 되돌린 후 새 값으로 재실행',
       now() - interval '30 minutes', now()
  from (select id from auth.users where email = 'demo@localhost' limit 1) u
on conflict (id) do update
   set status = 'DONE', rework_count = 1, query = excluded.query,
       user_id = excluded.user_id, username = excluded.username,
       description = excluded.description,
       start_date = excluded.start_date, end_date = excluded.end_date;

delete from public.events
 where todo_id = '11111111-2222-3333-4444-555555550003';

-- 이전 undo e2e 실행이 남긴 compensation 코드 제거 (재생성 검증 위해)
update public.mcp_python_code set compensation = null
 where proc_def_id = 'order_fulfillment_demo' and tenant_id = 'localhost';

notify pgrst, 'reload schema';
