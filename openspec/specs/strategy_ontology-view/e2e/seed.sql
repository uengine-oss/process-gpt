-- strategy_ontology-view E2E seed (원천 테이블 DDL; 러너가 API + INSERT 로 4레이어 구성)
--
-- 전략층(Strategy/KPI/Initiative)은 전략 API 로, 프로세스·리소스·스킬층은 원천 seed +
-- POST /api/ontology/sync 로 채운다. proc_def_id 공유로 두 경로가 같은 Process 노드에서
-- 만난다(IMPACTS_KPI/EXECUTED_BY = API, CONTAINS_TASK/PERFORMS = sync).

create table if not exists public.proc_def (
    id text primary key, name text, tenant_id text, isdeleted boolean default false
);
alter table public.proc_def add column if not exists definition jsonb;
create table if not exists public.users (
    id uuid primary key, username text, email text, tenant_id text,
    is_agent boolean default false, skills text, role text
);
create table if not exists public.configuration (key text, value jsonb, tenant_id text);
create table if not exists public.todolist (
    id uuid primary key, user_id text, proc_def_id text, activity_id text,
    status text, start_date timestamptz, end_date timestamptz,
    duration integer, tenant_id text
);
create table if not exists public.agent_skills (user_id text, tenant_id text, skill_name text);
create table if not exists public.skills (
    id uuid primary key default gen_random_uuid(), tenant_id text,
    name text, description text, updated_at timestamptz default now()
);
