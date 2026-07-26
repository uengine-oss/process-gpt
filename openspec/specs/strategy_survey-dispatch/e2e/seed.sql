-- strategy_survey-dispatch E2E seed (원천 테이블 DDL; 러너가 INSERT + API 로 구성)
--
-- 설문 발행(watch_completions/dispatch_for_instance)은 완료 인스턴스(bpm_proc_inst)의
-- 참여자를 조회해 todolist 워크아이템(activity_id='kpi_survey')을 발행한다. 단위 테스트
-- (tests/test_measurement.py)의 platform_tables 픽스처와 동일한 컬럼 집합을 쓴다.

create table if not exists public.proc_def (
    id text primary key, name text, tenant_id text, isdeleted boolean default false
);
create table if not exists public.bpm_proc_inst (
    proc_inst_id text primary key, proc_inst_name text, proc_def_id text,
    root_proc_inst_id text, status text, tenant_id text, participants jsonb,
    start_date timestamptz, end_date timestamptz, is_deleted boolean default false,
    variables_data jsonb, updated_at timestamptz default now()
);
create table if not exists public.users (
    id uuid primary key default gen_random_uuid(),
    email text, username text, tenant_id text, is_agent boolean default false
);
create table if not exists public.todolist (
    id uuid primary key,
    user_id text,
    username text,
    proc_inst_id text,
    root_proc_inst_id text,
    proc_def_id text,
    activity_id text,
    activity_name text,
    status text,
    start_date timestamptz,
    end_date timestamptz,
    due_date timestamptz,
    description text,
    tool text,
    adhoc boolean,
    tenant_id text,
    updated_at timestamptz default now()
);
-- strategy_survey_requests / strategy_kpi_measurements / strategy_sync_state 는
-- 서비스가 기동 시 자동 생성한다.
