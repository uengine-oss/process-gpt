-- strategy_impact-analysis E2E seed (원천 테이블 DDL; 러너가 API + INSERT 로 구성)
--
-- 영향도 분석이 의미를 가지려면 실행 지표(PERFORMS.avg_duration_hours)가 필요하다.
-- 러너는 목표 미달 KPI(개발 소요 시간)와, 서로 다른 처리시간의 todolist 완료 이력을
-- seed 한 뒤 sync 하여 병목 태스크/리소스/스킬이 랭킹되게 한다.

create table if not exists public.proc_def (
    id text primary key, name text, tenant_id text, isdeleted boolean default false
);
alter table public.proc_def add column if not exists definition jsonb;
create table if not exists public.users (
    id uuid primary key, username text, email text, tenant_id text,
    is_agent boolean default false, skills text, role text
);
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
