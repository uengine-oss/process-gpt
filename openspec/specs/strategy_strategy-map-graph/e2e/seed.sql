-- strategy_strategy-map-graph E2E seed
--
-- CRUD/관계/삭제 시나리오는 API(POST /api/objectives ...)로 그래프에 직접 쓰므로
-- 원천 seed 가 필요 없다. 이관(migrate-graph)·BSCard(import-bscard) 시나리오만
-- 아래 관계형 원천 테이블에 행이 필요하다. 러너가 CREATE + INSERT 를 모두 수행한다.

-- proc_def: KPI/이니셔티브의 proc_def_id 미러 Process 노드 이름 조회에 사용.
create table if not exists public.proc_def (
    id text primary key, name text, tenant_id text,
    isdeleted boolean default false, definition jsonb
);

-- 관계형 전략맵 원천(이관 대상) — 서비스가 기동 시 자동 생성하지만 멱등 보강.
create table if not exists public.strategy_objectives (
    id uuid primary key default gen_random_uuid(),
    tenant_id text not null, name text not null, description text,
    perspective text not null default 'financial',
    parents jsonb not null default '[]'::jsonb,
    sort_order integer not null default 0,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);
create table if not exists public.strategy_kpis (
    id uuid primary key default gen_random_uuid(),
    tenant_id text not null, objective_id uuid not null,
    name text not null, description text, unit text,
    measure_type text not null default 'manual', proc_def_id text,
    direction text not null default 'increase',
    baseline_value numeric, target_value numeric, current_value numeric,
    period_start date, period_end date,
    survey_questions jsonb not null default '[]'::jsonb,
    last_measured_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);
create table if not exists public.strategy_initiatives (
    id uuid primary key default gen_random_uuid(),
    tenant_id text not null, objective_id uuid not null,
    name text not null, description text, owner_email text,
    status text not null default 'planned', progress integer not null default 0,
    proc_def_id text, start_date date, due_date date,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

-- 레거시 BSCard 원천(configuration key='strategy').
create table if not exists public.configuration (key text, value jsonb, tenant_id text);
