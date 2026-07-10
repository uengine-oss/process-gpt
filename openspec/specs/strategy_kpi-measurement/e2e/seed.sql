-- strategy_kpi-measurement E2E seed (원천 테이블 DDL; 러너가 INSERT + API 로 구성)
--
-- 측정은 완료 인스턴스(bpm_proc_inst)와 설문 응답(strategy_survey_requests)을 실적으로
-- 환산한다. 단위 테스트(tests/test_measurement.py)의 platform_tables 픽스처 컬럼 집합과 동일.

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
-- strategy_survey_requests / strategy_kpi_measurements 는 서비스가 기동 시 자동 생성한다.
