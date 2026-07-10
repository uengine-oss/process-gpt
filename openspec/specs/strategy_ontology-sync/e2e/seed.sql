-- strategy_ontology-sync E2E seed (원천 테이블 DDL; 러너가 INSERT 수행)
--
-- 실제 플랫폼(Supabase) 컬럼을 반영한다. 단위 테스트(tests/test_ontology_sync.py)의
-- base_tables 픽스처와 동일한 컬럼 집합.

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
