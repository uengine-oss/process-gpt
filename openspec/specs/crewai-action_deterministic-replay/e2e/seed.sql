-- =====================================================================
-- Deterministic Replay E2E seed  (crewai-action_deterministic-replay)
--
-- Prepares a local self-hosted Supabase (supabase-db) for the
-- "실행 경로 고착화 → LLM 없는 결정론적 재실행" demo:
--   1. mcp_python_code  : table used by DeterministicCodeTool
--                         (forward `code`/`parameters` columns included —
--                          the checkout's rework seed only had
--                          `compensation`)
--   2. inventory        : demo business table the Supabase MCP server
--                         (postgres-mcp, execute_sql tool) reads/writes
--   3. inventory_log    : demo audit table (2nd step of the tool path)
--   4. proc_def         : demo process definition (order_fulfillment_demo)
--   5. todolist         : two workitems for the same activity —
--                         det-demo-first  (1차: LLM 실행 + 이력 기록)
--                         det-demo-replay (2차: 고착화 코드 재실행, 다른 입력)
--   6. events           : cleared for the demo workitems
--
-- tenants.mcp (Supabase MCP server config) is set by run_e2e.py because
-- it contains a DATABASE_URI with a password read from docker-infra/.env.
--
-- Idempotent: safe to re-run.
-- =====================================================================
set search_path to public, extensions;
create extension if not exists pgcrypto;

-- 1. mcp_python_code --------------------------------------------------
create table if not exists public.mcp_python_code (
    id           uuid primary key default gen_random_uuid(),
    proc_def_id  text not null,
    activity_id  text not null,
    tenant_id    text not null,
    compensation text,
    created_at   timestamp with time zone default now(),
    updated_at   timestamp with time zone default now()
);
alter table public.mcp_python_code add column if not exists code text;
alter table public.mcp_python_code add column if not exists parameters jsonb;
grant all on public.mcp_python_code to anon, authenticated, service_role, supabase_admin;

delete from public.mcp_python_code
 where proc_def_id = 'order_fulfillment_demo' and tenant_id = 'localhost';

-- 2/3. demo business tables ------------------------------------------
create table if not exists public.inventory (
    product_name text primary key,
    stock        integer not null default 0,
    updated_at   timestamp with time zone default now()
);
create table if not exists public.inventory_log (
    id           uuid primary key default gen_random_uuid(),
    product_name text not null,
    new_stock    integer not null,
    reason       text,
    created_at   timestamp with time zone default now()
);
grant all on public.inventory, public.inventory_log
  to anon, authenticated, service_role, supabase_admin;

delete from public.inventory_log;
insert into public.inventory (product_name, stock) values
    ('iPhone', 20), ('Galaxy', 35)
on conflict (product_name) do update set stock = excluded.stock, updated_at = now();

-- 4. proc_def ---------------------------------------------------------
insert into public.proc_def (id, uuid, name, tenant_id, type, isdeleted, is_draft)
select 'order_fulfillment_demo', gen_random_uuid(), '발주 입고 처리 (데모)',
       'localhost', 'bpmn', false, false
 where not exists (select 1 from public.proc_def
                    where id = 'order_fulfillment_demo' and tenant_id = 'localhost');

-- 5. todolist workitems ----------------------------------------------
--    fixed UUIDs so run_e2e.py / demo assets can reference them.
--    user_id는 auth uuid여야 업무 목록 UI에 표시된다 (demo@localhost 계정).
insert into public.todolist
    (id, user_id, username, proc_inst_id, root_proc_inst_id,
     proc_def_id, activity_id, activity_name, status, tenant_id,
     agent_orch, rework_count, query, description, start_date, end_date)
select v.id::uuid, u.id::text, 'demo',
       v.inst, v.inst, 'order_fulfillment_demo', 'update_inventory', '재고 반영',
       'DONE'::todo_status, 'localhost', 'crewai-action', 0, v.q, v.d,
       now() - interval '1 hour', now()
  from (values
    ('11111111-2222-3333-4444-555555550001', 'order_fulfillment_demo.det-demo-1',
     'iPhone 상품의 발주 입고를 반영하라. 입고 수량(재고에 더할 값)은 60, 반영 후 재고는 80, 변경 사유는 발주 입고. 재고 UPDATE는 stock = stock + 60 형태로 실행하고, inventory_log에는 반영 후 재고와 사유를 남겨라.',
     '1차 실행: LLM 에이전트가 Supabase MCP(execute_sql)로 직접 수행'),
    ('11111111-2222-3333-4444-555555550002', 'order_fulfillment_demo.det-demo-2',
     'Galaxy 상품의 발주 입고를 반영하라. 입고 수량(재고에 더할 값)은 215, 반영 후 재고는 250, 변경 사유는 발주 입고.',
     '2차 실행: 고착화된 코드로 LLM 추론 없이 결정론적 재실행')
  ) as v(id, inst, q, d)
  cross join (select id from auth.users where email = 'demo@localhost' limit 1) u
on conflict (id) do update
   set status = 'DONE', query = excluded.query, user_id = excluded.user_id,
       username = excluded.username, rework_count = 0,
       description = excluded.description,
       start_date = excluded.start_date, end_date = excluded.end_date;

-- 6. events -----------------------------------------------------------
delete from public.events
 where todo_id in ('11111111-2222-3333-4444-555555550001',
                   '11111111-2222-3333-4444-555555550002');

notify pgrst, 'reload schema';
