-- ===============================================
-- INIT.SQL FILE WRITING GUIDE
-- ===============================================
-- 
-- 이 파일은 데이터베이스 초기화를 위한 SQL 스크립트입니다.
-- 새로운 데이터베이스 환경에서 처음 실행되는 파일입니다.
-- 다른 개발자들이 안전하게 수정할 수 있도록 다음 가이드를 따라주세요.
--
-- 파일 역할:
--    - init.sql: 새로운 테이블 생성 (CREATE TABLE)
--    - migration.sql: 기존 테이블 구조 변경 (ALTER TABLE)
--
-- 1. 확장 기능 (Extensions):
--    - 필요한 확장 기능을 최상단에 추가
--    - CREATE EXTENSION IF NOT EXISTS 사용
--    - vector, pgcrypto 등 필수 확장 기능 포함
--
-- 2. 함수 정의:
--    - 테이블 생성 전에 필요한 함수들을 먼저 정의
--    - 테넌트별 정보가 필요한 경우 public.tenant_id() 함수 사용
--    - CREATE OR REPLACE FUNCTION 사용
--
-- 3. 테이블 생성 규칙:
--    - CREATE TABLE IF NOT EXISTS 사용
--    - 모든 테이블에 적절한 제약조건 설정
--    - Primary Key, Foreign Key 명시적 정의
--    - 테넌트별 데이터는 tenant_id 컬럼 추가
--
-- 4. 인덱스 생성:
--    - 테이블 생성 후 관련 인덱스 추가
--    - CREATE INDEX IF NOT EXISTS 사용
--    - 유니크 인덱스는 테넌트별로 설정
--
-- 5. 뷰 생성:
--    - 복잡한 조인이나 자주 사용되는 쿼리는 뷰로 생성
--    - CREATE OR REPLACE VIEW 사용
--
-- 6. 함수 및 트리거:
--    - 비즈니스 로직 함수 정의
--    - 트리거 함수와 트리거 생성
--    - 보안 관련 함수 포함
--
-- 7. Row Level Security (RLS):
--    - 모든 테이블에 RLS 활성화
--    - 적절한 정책(Policy) 정의
--    - 인증된 사용자와 관리자 권한 구분
--
-- 8. 실시간 구독 설정:
--    - supabase_realtime publication에 테이블 추가
--    - 실시간 업데이트가 필요한 테이블만 포함
--
-- 9. ENUM 타입:
--     - 필요에 따라 상태값 등은 ENUM 타입으로 정의
--     - 기존 데이터 마이그레이션 로직 포함
--
-- ===============================================

-- Enable required extensions
create extension if not exists vector;
create extension if not exists pgcrypto;

-- Create tenant_id function
create or replace function public.tenant_id()
returns text
language sql stable
as $$
    select 
        nullif(
            ((current_setting('request.jwt.claims')::jsonb ->>  'app_metadata')::jsonb ->> 'tenant_id'),
            ''
        )::text
$$;

-- Create initial tables
create table if not exists public.tenants (
    id text not null,
    owner uuid null default auth.uid (),
    is_deleted boolean not null default false,
    deleted_at timestamp with time zone null,
    mcp jsonb null,
    constraint tenants_pkey primary key (id)
) tablespace pg_default;

INSERT INTO public.tenants (id, owner) VALUES ('process-gpt', null);

create table if not exists public.user_devices (
    user_email text not null,
    device_token text null,
    access_page text null,
    last_access_at timestamp with time zone null default now(),
    constraint user_devices_pkey primary key (user_email)
) tablespace pg_default;

create table if not exists public.users (
    id uuid not null,
    username text null,
    profile text null default '/images/defaultUser.png'::text,
    email text null,
    is_admin boolean not null default false,
    role text null,
    tenant_id text null,
    device_token text null,
    google_credentials jsonb,
    google_credentials_updated_at TIMESTAMP WITH TIME ZONE,
    goal text null,
    persona text null,
    url text null,
    description text null,
    tools text null,
    skills text null,
    is_agent boolean not null default false,
    model text null,
    constraint users_pkey primary key (id, tenant_id),
    constraint users_tenant_id_fkey foreign key (tenant_id) references tenants (id) on update cascade on delete cascade
) tablespace pg_default;

create table if not exists public.configuration (
    key text not null,
    value jsonb null,
    tenant_id text null default public.tenant_id(),
    uuid uuid not null default gen_random_uuid (),
    constraint configuration_pkey primary key (uuid),
    constraint configuration_tenant_id_fkey foreign key (tenant_id) references tenants (id) on update cascade on delete cascade
) tablespace pg_default;

create table if not exists public.proc_map_history (
    value jsonb not null,
    created_at timestamp with time zone not null default now(),
    tenant_id text null default public.tenant_id(),
    uuid uuid not null default gen_random_uuid (),
    constraint proc_map_history_pkey primary key (uuid),
    constraint proc_map_history_tenant_id_fkey foreign key (tenant_id) references tenants (id) on update cascade on delete cascade
) tablespace pg_default;

create table if not exists public.proc_def (
    id text not null,
    name text null,
    definition jsonb null,
    bpmn text null,
    uuid uuid not null default gen_random_uuid (),
    tenant_id text null default public.tenant_id(),
    isdeleted boolean not null default false,
    constraint proc_def_pkey primary key (uuid),
    constraint proc_def_tenant_id_fkey foreign key (tenant_id) references tenants (id) on update cascade on delete cascade
) tablespace pg_default;

create table if not exists public.proc_def_arcv (
    arcv_id text not null,
    proc_def_id text not null,
    version text not null,
    snapshot text null,
    "timeStamp" timestamp without time zone null default current_timestamp,
    diff text null,
    message text null,
    uuid uuid not null default gen_random_uuid (),
    tenant_id text null default public.tenant_id(),
    constraint proc_def_arcv_pkey primary key (uuid),
    constraint proc_def_arcv_tenant_id_fkey foreign key (tenant_id) references tenants (id) on update cascade on delete cascade
) tablespace pg_default;

create table if not exists public.form_def (
    uuid uuid not null default gen_random_uuid (),
    html text not null,
    proc_def_id text not null,
    activity_id text not null,
    tenant_id text null default public.tenant_id(),
    id text null default ''::text,
    fields_json jsonb null,
    constraint form_def_pkey primary key (uuid),
    constraint form_def_tenant_id_fkey foreign key (tenant_id) references tenants (id) on update cascade on delete cascade
) tablespace pg_default;

create table if not exists public.notifications (
    id uuid not null,
    title text null,
    type text null,
    description text null,
    is_checked boolean null default false,
    time_stamp timestamp with time zone null default now(),
    user_id text null,
    url text null,
    consumer text null,
    from_user_id text null,
    tenant_id text null default public.tenant_id(),
    constraint notifications_pkey primary key (id),
    constraint notifications_tenant_id_fkey foreign key (tenant_id) references tenants (id) on update cascade on delete cascade
) tablespace pg_default;

create table if not exists public.lock (
    id text not null,
    user_id text null,
    tenant_id text null default public.tenant_id(),
    uuid uuid not null default gen_random_uuid (),
    constraint lock_pkey primary key (uuid),
    constraint lock_tenant_id_fkey foreign key (tenant_id) references tenants (id) on update cascade on delete cascade
) tablespace pg_default;

create table if not exists public.bpm_proc_inst (
    proc_def_id text null,
    proc_inst_id text not null,
    proc_inst_name text null,
    root_proc_inst_id text null,
    parent_proc_inst_id text null,
    execution_scope text null,
    current_activity_ids text[] null,
    participants text[] null,
    role_bindings jsonb null,
    variables_data jsonb null,
    status text null,
    tenant_id text null default public.tenant_id(),
    proc_def_version text null,
    project_id uuid null,
    start_date timestamp without time zone null,
    end_date timestamp without time zone null,
    due_date timestamp without time zone null,
    updated_at timestamp with time zone default now(),
    is_deleted boolean not null default false,
    deleted_at timestamp with time zone null,
    constraint bpm_proc_inst_pkey primary key (proc_inst_id),
    constraint bpm_proc_inst_tenant_id_fkey foreign key (tenant_id) references tenants (id) on update cascade on delete cascade
) tablespace pg_default;

create table if not exists public.todolist (
    id uuid not null,
    user_id text null,
    username text null,
    proc_inst_id text null,
    root_proc_inst_id text null,
    execution_scope text null,
    proc_def_id text null,
    activity_id text null,
    activity_name text null,
    start_date timestamp without time zone null,
    end_date timestamp without time zone null,
    status text null,
    description text null,
    tool text null,
    due_date timestamp without time zone null,
    tenant_id text null default public.tenant_id(),
    reference_ids text[] null,
    adhoc boolean null default false,
    assignees jsonb null,
    duration integer null,
    output jsonb null,
    retry integer null default 0,
    consumer text null,
    log text null,
    project_id uuid null,
    draft jsonb null,
    agent_mode text null,
    agent_orch text null,
    feedback jsonb null,
    draft_status text null,
    updated_at timestamp with time zone default now(),
    temp_feedback text null,
    output_url text null,
    rework_count integer null default 0,
    constraint todolist_pkey primary key (id),
    constraint todolist_tenant_id_fkey foreign key (tenant_id) references tenants (id) on update cascade on delete cascade
) tablespace pg_default;

create table if not exists public.chat_rooms (
    id text not null,
    participants jsonb not null,
    message jsonb null,
    name text null,
    tenant_id text null default public.tenant_id(),
    constraint chat_rooms_pkey primary key (id),
    constraint chat_rooms_tenant_id_fkey foreign key (tenant_id) references tenants (id) on update cascade on delete cascade
) tablespace pg_default;

create table if not exists public.chats (
    uuid text not null,
    id text not null,
    messages jsonb null,
    tenant_id text null default public.tenant_id(),
    thread_id text null,
    constraint chats_pkey primary key (uuid),
    constraint chats_tenant_id_fkey foreign key (tenant_id) references tenants (id) on update cascade on delete cascade
) tablespace pg_default;

create table if not exists public.chat_attachments (
    id text not null,
    file_name text null,
    file_path text null,
    chat_room_id text null,
    user_name text null,
    created_at timestamp with time zone not null default now(),
    tenant_id text null,
    constraint chat_attachments_pkey primary key (id),
    constraint chat_attachments_chat_room_id_fkey foreign KEY (chat_room_id) references chat_rooms (id) on update CASCADE on delete CASCADE,
    constraint chat_attachments_tenant_id_fkey foreign KEY (tenant_id) references tenants (id)
) TABLESPACE pg_default;

create table if not exists public.calendar (
    uid text not null,
    data jsonb null,
    tenant_id text null default public.tenant_id(),
    constraint calendar_pkey primary key (uid)
) tablespace pg_default;

create table if not exists public.user_permissions (
    id text not null,
    user_id uuid not null,
    tenant_id text not null default public.tenant_id(),
    proc_def_id text not null,
    proc_def_ids jsonb not null,
    readable boolean not null default false,
    writable boolean not null default false,
    constraint user_permissions_pkey primary key (id)
) tablespace pg_default;

create table if not exists public.proc_def_marketplace (
    uuid uuid not null default gen_random_uuid (),
    id text not null,
    name text null,
    definition jsonb null,
    bpmn text null,
    description text null,
    category text null,
    tags text null,
    author_name text null,
    author_uid text null,
    image text null,
    import_count integer not null default 0,
    constraint proc_def_marketplace_pkey primary key (uuid)
) tablespace pg_default;

create table if not exists public.form_def_marketplace (
    uuid uuid not null default gen_random_uuid (),
    id text null default ''::text,
    proc_def_id text not null,
    activity_id text not null,
    html text not null,
    author_uid text null,
    constraint form_def_marketplace_pkey primary key (uuid)
) tablespace pg_default;

create table public.tenant_oauth (
    tenant_id text not null,
    client_id text not null,
    client_secret text not null,
    redirect_uri text null,
    drive_folder_id text null,
    created_at timestamp with time zone null default now(),
    updated_at timestamp with time zone null default now(),
    google_credentials jsonb null,
    google_credentials_updated_at timestamp with time zone null,
    constraint tenant_oauth_pkey primary key (tenant_id),
    constraint tenant_oauth_tenant_id_fkey foreign key (tenant_id) references tenants (id) on update cascade on delete cascade
) tablespace pg_default;

create table if not exists public.project (
    name character varying null,
    start_date date null,
    end_date date null,
    created_date date null,
    status character varying not null,
    project_id uuid not null default gen_random_uuid (),
    due_date date null,
    user_id text null,
    updated_at timestamp with time zone default now(),
    tenant_id text null default public.tenant_id(),
    constraint project_pkey primary key (project_id),
    constraint project_tenant_id_fkey foreign key (tenant_id) references tenants (id) on update cascade on delete cascade
) tablespace pg_default;

-- create table if not exists public.milestone (
--     id bigserial,
--     impact_type character varying null,
--     impact_desc text null,
--     created_date date null,
--     task_id uuid null,
--     impact_id uuid null,
--     constraint milestone_pkey primary key (id),
--     constraint fk_milestone_task foreign key (task_id) references worklist (task_id),
--     constraint fk_milestone_impact_id foreign key (impact_id) references worklist (task_id),
--     constraint fk_milestone_impact foreign key (impact_id) references worklist (task_id)
-- ) tablespace pg_default;

create table if not exists public.task_dependency (
    id bigserial,
    lag_time integer null,
    lead_time integer null,
    type character varying null,
    created_date date null,
    task_id uuid null,
    depends_id uuid null,
    constraint worklist_dependency_pkey primary key (id)
) tablespace pg_default;

create table if not exists public.processed_files (
    id uuid not null default uuid_generate_v4 (),
    file_id text not null,
    tenant_id text not null,
    processed_at timestamp with time zone null default now(),
    file_name text null,
    constraint processed_files_pkey primary key (id),
    constraint processed_files_file_id_tenant_id_key unique (file_id, tenant_id)
) tablespace pg_default;

create table if not exists public.documents (
    id uuid primary key,
    content text,
    metadata jsonb,
    embedding vector(1536)
);

create table if not exists public.events (
  id text not null,
  job_id text not null,
  todo_id text null,
  proc_inst_id text null,
  event_type text not null,
  status text null,
  crew_type text null,
  data jsonb not null,
  timestamp timestamp with time zone null default now(),
  constraint events_pkey primary key (id)
) TABLESPACE pg_default;



------------------ 결제시스템 ---------------------------
-- payment(결제 이력)
CREATE TABLE public.payment (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(), -- 고유ID
    payment_key TEXT,                              -- 결제 KEY(PG 관리)
    order_id TEXT UNIQUE,                          -- 주문 ID(난수)
    order_name TEXT,                               -- 사용자 표시용 상품명
    status TEXT DEFAULT 'READY' CHECK (
      status IN (
        'READY',               -- 생성 직후
        'IN_PROGRESS',         -- 인증 완료 (승인 전)
        'AUTH_FAILED',         -- 인증 실패
        'DONE',                -- 결제 승인 완료
        'CANCELED',            -- 전체 취소
        'PARTIAL_CANCELED',    -- 부분 취소
        'ABORTED',             -- 승인 실패
        'EXPIRED',             -- 유효시간 만료
        'WAITING_FOR_DEPOSIT'  -- 가상계좌 대기
      )
    ),
    receipt_url TEXT,                           	-- PG 영수증 링크               
    amount DECIMAL(10,2) NOT NULL,              	-- 결제 금액
    approved_at TIMESTAMPTZ,                      	-- 결제 완료 시간
    method TEXT,                                	-- 카드, 가상계좌 등
    user_id TEXT,                               	-- 결제자
    created_at TIMESTAMPTZ DEFAULT now(),        	 	-- 생성 날짜
    ref_type TEXT,                              	-- 상품 타입(subscription, credit)                             
    ref_id TEXT,                                	-- 상품 ID(subscription.id, credit.id)
    tenant_id TEXT REFERENCES public.tenants(id)  	-- 테넌트
);


-- service(개별 서비스 식별)
CREATE TABLE public.service (
    id          TEXT NOT NULL, 								 -- 서비스 ID
    name        TEXT,                                        -- 서비스 이름
    created_at  TIMESTAMPTZ DEFAULT NOW(),      			 -- 생성일
    tenant_id   TEXT       REFERENCES public.tenants(id),    -- 테넌트

    CONSTRAINT service_pkey PRIMARY KEY (id, tenant_id)
);

-- service_rate(각 서비스별 과금 단위·크레딧 정의)
CREATE TABLE IF NOT EXISTS public.service_rate (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(), 	-- 고유 ID
    service_id      text NOT NULL,								-- 서비스 ID 
    tenant_id       text NOT NULL,								-- 테넌트
    model           text NOT NULL,								-- 모델명
    available_from  TIMESTAMPTZ NOT NULL DEFAULT now(), 			-- 적용 시점
    created_at      TIMESTAMPTZ DEFAULT now(), 					-- 생성일
    dimension       jsonb NOT NULL DEFAULT '{}'::jsonb, 			-- 가격 및 unit 정보

    CONSTRAINT unique_service_dimension
    UNIQUE (service_id, tenant_id, model, available_from),

    CONSTRAINT service_rate_tenant_id_fkey
    FOREIGN KEY (tenant_id) REFERENCES public.tenants (id),

    -- 핵심: service(id, tenant_id) 복합키 참조 + 서비스 삭제 시 함께 삭제
    CONSTRAINT service_rate_service_tenant_fk
    FOREIGN KEY (service_id, tenant_id)
    REFERENCES public.service (id, tenant_id)
    ON UPDATE CASCADE
    ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_service_rate_service_tenant ON public.service_rate (service_id, tenant_id);


-- usage(사용량)
CREATE TABLE public.usage (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,        	 -- 사용량 ID
    tenant_id TEXT NOT NULL REFERENCES public.tenants(id),   -- 테넌트

    quantity DECIMAL(12,4) NOT NULL,                      	 -- 사용 양(토큰 및 호출수..)  
    amount DECIMAL(12,7),                                 	 -- 트리거: 크레딧 합계
    metadata JSONB,                                       	 -- 계산용 데이터
    service_rate_id UUID REFERENCES public.service_rate(id), -- 트리거: 해당 시점의 가격
    group_id UUID, 									      	 -- 연결된 사용량 ID

    model TEXT,                                           	 -- 사용 모델
    service_id TEXT,	                                  	 -- 서비스 ID (LLM, RAG 등)
    user_id TEXT,                                         	 -- 사용자
    agent_id TEXT,                                        	 -- agent ID
    process_def_id  TEXT,                                 	 -- 프로세스 정의 ID
    process_inst_id TEXT,                                 	 -- 프로세스 인스턴스 ID
	
	usage_start_at TIMESTAMPTZ NOT NULL,     			  	 -- 사용 시작
    usage_end_at TIMESTAMPTZ DEFAULT NOW(),    			  	 -- 사용 종료(자동 생성)

    CONSTRAINT usage_service_fk
	    FOREIGN KEY (service_id, tenant_id)
	    REFERENCES public.service (id, tenant_id)
	    ON UPDATE CASCADE
	    ON DELETE RESTRICT
);
CREATE INDEX idx_usage_service_id      ON public.usage(service_id);
CREATE INDEX idx_usage_process_def_id  ON public.usage(process_def_id);
CREATE INDEX idx_usage_process_inst_id ON public.usage(process_inst_id);
CREATE INDEX idx_usage_tenant_master_date ON public.usage (tenant_id, service_id, usage_start_at);


-- credit(크레딧 정의)
CREATE TABLE public.credit (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),      -- 크레딧 ID
    name TEXT NOT NULL,                                 -- 크레딧 명
    description TEXT,                                   -- 크레딧 설명
    type TEXT NOT NULL,                                 -- 크레딧 타입
    price DECIMAL(10,2) NOT NULL DEFAULT 0,             -- 결제 금액
    credit DECIMAL(12,3) NOT NULL DEFAULT 0,            -- 제공 크레딧
    badge JSONB NOT NULL DEFAULT '{}'::jsonb,           -- 크레딧 특징
    status TEXT NOT NULL DEFAULT 'active'               -- 크레딧 상태
        CHECK (status IN ('active', 'inactive', 'hidden')),
    created_at TIMESTAMPTZ DEFAULT NOW(),               -- 생성 날짜
    validity_months INT DEFAULT 12,                     -- 크레딧 만료 개월(기본 12개월)
    tenant_id TEXT REFERENCES public.tenants(id)        -- 테넌트
);

-- credit_purchase(테넌트의 '충전 크래딧' 구매이력)
CREATE TABLE public.credit_purchase (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,    		-- 크레딧 구매ID
    tenant_id TEXT NOT NULL REFERENCES public.tenants(id),  -- 테넌트
    added_credit DECIMAL(12,7) NOT NULL,              	   	-- 추가된 크레딧 
    source_type TEXT NOT NULL                         		-- 충전 방식 구분
        CHECK (source_type IN ('purchase'))
        DEFAULT 'purchase',
    source_id   TEXT NOT NULL,                        -- 충전 ID (credit.id 또는 promo code)
    payment_id UUID REFERENCES public.payment(id),    -- 결제 ID 정보(구매자 추적용)
    expires_at TIMESTAMPTZ ,              			  -- 만료일(생성일 기준 + validity_months)
    created_at TIMESTAMPTZ DEFAULT NOW(), 			  -- 생성일(자동생성)

    CONSTRAINT added_credit_ch CHECK (added_credit >= 0)
);
 

-- credit_usage(크레딧 차감 이력 테이블)
CREATE TABLE public.credit_usage (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,                    -- 크레딧 이력 ID
    tenant_id TEXT NOT NULL REFERENCES public.tenants(id),            -- 테넌트ID
    usage_id UUID NOT NULL REFERENCES public.usage(id),               -- 사용량 ID
    credit_purchase_id UUID REFERENCES public.credit_purchase(id),    -- 연결된 구매 크레딧 ID
    used_credit DECIMAL(12,7) NOT NULL, 								-- 실제로 이만큼 소진
    created_at TIMESTAMPTZ DEFAULT NOW(),                				-- 생성 날짜

    CONSTRAINT used_credit_ch CHECK (used_credit >= 0)
);

-- Create indexes
create index if not exists idx_processed_files_tenant_id on public.processed_files using btree (tenant_id) tablespace pg_default;
create index if not exists idx_processed_files_file_id on public.processed_files using btree (file_id) tablespace pg_default;

CREATE UNIQUE INDEX IF NOT EXISTS unique_proc_def_id_per_tenant ON proc_def (id, tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS unique_form_def_id_per_tenant ON form_def (id, tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS unique_config_key_per_tenant ON configuration (key, tenant_id);

-- Create views
CREATE OR REPLACE VIEW public.chat_room_chats AS
SELECT
    cr.id,
    cr.name,
    cr.participants,
    c.uuid,
    c.messages
FROM
    chat_rooms cr
    JOIN chats c ON cr.id = c.id;

CREATE OR REPLACE VIEW public.v_task_dependency AS
SELECT
    d.id,
    d.lag_time,
    d.lead_time,
    d.type,
    d.created_date,
    d.task_id,
    d.depends_id,
    t.proc_inst_id,
    t.project_id
FROM
    task_dependency d
    JOIN todolist t ON d.task_id = t.id;

-- Create functions
CREATE OR REPLACE FUNCTION set_user_permissions_id()
RETURNS TRIGGER AS $$
BEGIN
    NEW.id := NEW.proc_def_id || '_' || NEW.user_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION check_process_permission(p_proc_def_id TEXT, p_user_id UUID DEFAULT NULL)
RETURNS SETOF user_permissions AS $$
BEGIN
    RETURN QUERY
    SELECT up.*
    FROM user_permissions up,
         jsonb_array_elements(up.proc_def_ids->'major_proc_list') AS major_proc,
         jsonb_array_elements(major_proc->'sub_proc_list') AS sub_proc
    WHERE (p_user_id IS NULL OR up.user_id = p_user_id)
    AND (
        up.proc_def_ids->>'id' = p_proc_def_id OR
        major_proc->>'id' = p_proc_def_id OR
        sub_proc->>'id' = p_proc_def_id
    );
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION search_bpm_proc_inst(keyword TEXT, user_email TEXT)
RETURNS SETOF bpm_proc_inst AS $$
BEGIN
    RETURN QUERY
    SELECT *
    FROM bpm_proc_inst
    WHERE (proc_def_id ILIKE '%' || keyword || '%'
       OR proc_inst_id ILIKE '%' || keyword || '%'
       OR proc_inst_name ILIKE '%' || keyword || '%'
       OR variables_data::text ILIKE '%' || keyword || '%')
      AND user_email = ANY(participants);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION search_chat_room_chats(keyword TEXT)
RETURNS SETOF chat_room_chats AS $$
BEGIN
    RETURN QUERY
    SELECT *
    FROM chat_room_chats
    WHERE messages->>'content' ILIKE '%' || keyword || '%'
       OR messages->>'name' ILIKE '%' || keyword || '%'
       OR messages->>'email' ILIKE '%' || keyword || '%';
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.update_tenant_id_for_first_tenant()
RETURNS TRIGGER AS $$
DECLARE
    tenant_count INT;
BEGIN
    SELECT COUNT(*) INTO tenant_count FROM public.tenants;
    IF tenant_count = 1 THEN
        UPDATE public.proc_def
        SET tenant_id = NEW.id
        WHERE id = 'leave_request_process';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION handle_todolist_change()
RETURNS TRIGGER AS $$
DECLARE
    v_proc_inst_name text;
    should_notify boolean := false;
BEGIN
    -- INSERT: 새로운 todolist가 추가되고 상태가 'IN_PROGRESS'인 경우
    IF (TG_OP = 'INSERT' AND NEW.status = 'IN_PROGRESS') THEN
        should_notify := true;
    END IF;
    
    -- UPDATE: 기존 todolist가 업데이트되고 상태가 'IN_PROGRESS'로 변경된 경우
    IF (TG_OP = 'UPDATE' AND NEW.status = 'IN_PROGRESS' AND (OLD.status IS NULL OR OLD.status != 'IN_PROGRESS')) THEN
        should_notify := true;
    END IF;
    
    IF should_notify THEN
        SELECT proc_inst_name, tenant_id INTO v_proc_inst_name 
        FROM bpm_proc_inst 
        WHERE proc_inst_id = NEW.proc_inst_id;
        
        INSERT INTO notifications (id, user_id, title, type, description, is_checked, time_stamp, tenant_id, url)
        VALUES (
            gen_random_uuid(),
            NEW.user_id,
            NEW.activity_name,
            CASE 
                WHEN NEW.proc_inst_id IS NOT NULL AND NEW.proc_inst_id <> '' THEN 'workitem_bpm'
                ELSE 'workitem'
            END,
            COALESCE(v_proc_inst_name, NEW.activity_name),
            false, -- in_progress 상태이므로 항상 미체크
            now(),
            NEW.tenant_id,
            '/todolist/' || NEW.id
        )
        ON CONFLICT (id) DO UPDATE
        SET
            user_id = EXCLUDED.user_id,
            title = EXCLUDED.title,
            type = EXCLUDED.type,
            description = EXCLUDED.description,
            is_checked = EXCLUDED.is_checked,
            time_stamp = EXCLUDED.time_stamp,
            tenant_id = EXCLUDED.tenant_id,
            url = EXCLUDED.url;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION update_notification_user_id()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE notifications
    SET user_id = NEW.user_id,
        time_stamp = now()
    WHERE url = '/todolist/' || NEW.id;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION delete_notification_on_todolist_delete()
RETURNS TRIGGER AS $$
BEGIN
    DELETE FROM notifications
    WHERE url = '/todolist/' || OLD.id;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION handle_chat_insert()
RETURNS TRIGGER AS $$
DECLARE
    chat_room_participant jsonb;
    participant_email text;
    participant_record record;
    chat_room_name text;
    user_is_in_chat_room boolean;
BEGIN
    SELECT name INTO chat_room_name FROM public.chat_rooms WHERE id = NEW.id;

    FOR participant_record IN
        SELECT jsonb_array_elements(participants) as p
        FROM public.chat_rooms
        WHERE id = NEW.id
    LOOP
        chat_room_participant := participant_record.p;
        
        IF chat_room_participant->>'username' != 'System' AND chat_room_participant->>'email' != NEW.messages->>'email' THEN
            participant_email := chat_room_participant->>'email';
            
            -- 사용자가 현재 해당 채팅방에 있는지 확인
            SELECT EXISTS(
                SELECT 1 FROM user_devices 
                WHERE user_email = participant_email 
                AND access_page = 'chat:' || NEW.id
                AND last_access_at > now() - interval '5 minutes'
            ) INTO user_is_in_chat_room;
            
            -- 사용자가 채팅방에 없을 때만 알림 생성
            IF NOT user_is_in_chat_room THEN
                INSERT INTO notifications (id, user_id, title, type, description, is_checked, time_stamp, url, from_user_id)
                VALUES (
                    gen_random_uuid(),
                    participant_email,
                    NEW.messages->>'content',
                    'chat',
                    chat_room_name,
                    false,
                    now(),
                    '/chats?id=' || NEW.id,
                    NEW.messages->>'name'
                )
                ON CONFLICT (id) DO UPDATE
                SET
                    user_id = EXCLUDED.user_id,
                    title = EXCLUDED.title,
                    time_stamp = EXCLUDED.time_stamp,
                    is_checked = EXCLUDED.is_checked,
                    url = EXCLUDED.url,
                    from_user_id = EXCLUDED.from_user_id;
            END IF;
        END IF;
    END LOOP;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION duplicate_definition_from_marketplace(
    p_definition_id TEXT,
    p_definition_name TEXT,
    p_author_uid TEXT,
    p_tenant_id TEXT
)
RETURNS JSONB AS $$
DECLARE
    v_proc_def_record RECORD;
    v_form_def_record RECORD;
    v_result JSONB := '{}';
    v_proc_def_uuid UUID;
    v_form_def_uuid UUID;
    v_new_definition_id TEXT;
    v_new_definition JSONB;
BEGIN
    -- 프로세스 정의를 marketplace에서 복사
    SELECT * INTO v_proc_def_record
    FROM proc_def_marketplace
    WHERE id = p_definition_id AND name = p_definition_name;
    
    IF NOT FOUND THEN
        RETURN jsonb_build_object('error', 'Process definition not found in marketplace');
    END IF;
    
    -- 새로운 정의 ID 생성 (기존 ID + UUID)
    v_new_definition_id := p_definition_id || '_' || gen_random_uuid()::TEXT;
    
    -- definition JSON에서 processDefinitionId 업데이트
    v_new_definition := v_proc_def_record.definition;
    v_new_definition := jsonb_set(v_new_definition, '{processDefinitionId}', to_jsonb(v_new_definition_id));
    
    -- proc_def에 복사
    INSERT INTO proc_def (
        id,
        name,
        definition,
        bpmn,
        tenant_id
    ) VALUES (
        v_new_definition_id,
        v_proc_def_record.name,
        v_new_definition,
        v_proc_def_record.bpmn,
        p_tenant_id
    )
    ON CONFLICT (id, tenant_id) DO UPDATE SET
        name = EXCLUDED.name,
        definition = EXCLUDED.definition,
        bpmn = EXCLUDED.bpmn
    RETURNING uuid INTO v_proc_def_uuid;
    
    -- form_def_marketplace에서 관련 폼들을 찾아서 form_def로 복사
    FOR v_form_def_record IN
        SELECT *
        FROM form_def_marketplace
        WHERE proc_def_id = p_definition_id AND author_uid = p_author_uid
    LOOP
        INSERT INTO form_def (
            html,
            proc_def_id,
            activity_id,
            tenant_id,
            id,
            fields_json
        ) VALUES (
            v_form_def_record.html,
            v_new_definition_id,
            v_form_def_record.activity_id,
            p_tenant_id,
            v_form_def_record.id,
            NULL
        )
        ON CONFLICT (id, tenant_id) DO UPDATE SET
            html = EXCLUDED.html,
            proc_def_id = EXCLUDED.proc_def_id,
            activity_id = EXCLUDED.activity_id
        RETURNING uuid INTO v_form_def_uuid;
    END LOOP;
    
    -- import_count 증가
    UPDATE proc_def_marketplace
    SET import_count = import_count + 1
    WHERE id = p_definition_id AND name = p_definition_name;
    
    v_result := jsonb_build_object(
        'success', true,
        'proc_def_uuid', v_proc_def_uuid,
        'new_definition_id', v_new_definition_id,
        'message', 'Definition duplicated successfully'
    );
    
    RETURN v_result;
    
EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'error', SQLERRM,
            'success', false
        );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- project updated_at 업데이트 
CREATE OR REPLACE FUNCTION update_project_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.project_id IS NOT NULL THEN
    UPDATE public.project
    SET updated_at = now()
    WHERE project_id = NEW.project_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- bpm_proc_inst updated_at 자동 업데이트
CREATE OR REPLACE FUNCTION update_bpm_proc_inst_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.proc_inst_id IS NOT NULL THEN
    UPDATE public.bpm_proc_inst
    SET updated_at = now()
    WHERE proc_inst_id = NEW.proc_inst_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- todolist updated_at 자동 업데이트
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create triggers
CREATE TRIGGER trigger_update_project_updated_at
    AFTER UPDATE OF updated_at ON public.bpm_proc_inst
    FOR EACH ROW
    EXECUTE FUNCTION update_project_updated_at();

CREATE TRIGGER trigger_update_bpm_proc_inst_updated_at
    AFTER UPDATE ON public.todolist
    FOR EACH ROW
    EXECUTE FUNCTION update_bpm_proc_inst_updated_at();

CREATE TRIGGER set_updated_at
    BEFORE UPDATE ON public.todolist
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER before_insert_user_permissions
    BEFORE INSERT ON public.user_permissions
    FOR EACH ROW
    EXECUTE FUNCTION set_user_permissions_id();

CREATE TRIGGER on_first_tenant_inserted
    AFTER INSERT ON public.tenants
    FOR EACH ROW
    EXECUTE PROCEDURE public.update_tenant_id_for_first_tenant();

CREATE TRIGGER todolist_change_trigger
    AFTER INSERT OR UPDATE ON todolist
    FOR EACH ROW
    EXECUTE FUNCTION handle_todolist_change();

CREATE TRIGGER update_user_id_trigger
    AFTER UPDATE ON todolist
    FOR EACH ROW
    WHEN (OLD.user_id IS DISTINCT FROM NEW.user_id)
    EXECUTE FUNCTION update_notification_user_id();

CREATE TRIGGER delete_notification_trigger
    AFTER DELETE ON todolist
    FOR EACH ROW
    EXECUTE FUNCTION delete_notification_on_todolist_delete();

CREATE TRIGGER chat_insert_trigger
    AFTER INSERT ON public.chats
    FOR EACH ROW
    EXECUTE FUNCTION handle_chat_insert();

-- Enable Row Level Security
ALTER TABLE tenants ENABLE ROW LEVEL SECURITY;
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE configuration ENABLE ROW LEVEL SECURITY;
ALTER TABLE proc_map_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE proc_def ENABLE ROW LEVEL SECURITY;
ALTER TABLE proc_def_arcv ENABLE ROW LEVEL SECURITY;
ALTER TABLE form_def ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE lock ENABLE ROW LEVEL SECURITY;
ALTER TABLE bpm_proc_inst ENABLE ROW LEVEL SECURITY;
ALTER TABLE todolist ENABLE ROW LEVEL SECURITY;
ALTER TABLE chat_rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE chats ENABLE ROW LEVEL SECURITY;
ALTER TABLE calendar ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE proc_def_marketplace ENABLE ROW LEVEL SECURITY;
ALTER TABLE form_def_marketplace ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenant_oauth ENABLE ROW LEVEL SECURITY;

-- Create RLS policies
-- Tenants policies
CREATE POLICY tenants_insert_policy ON tenants FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY tenants_select_policy ON tenants FOR SELECT TO authenticated USING (true);
CREATE POLICY tenants_update_policy ON tenants FOR UPDATE TO authenticated USING (auth.uid() = owner);
CREATE POLICY tenants_delete_policy ON tenants FOR DELETE TO authenticated USING (auth.uid() = owner);

-- Users policies
CREATE POLICY users_insert_policy ON users FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY users_select_policy ON users FOR SELECT TO public USING (true);
CREATE POLICY users_update_policy ON users FOR UPDATE TO public USING (EXISTS (SELECT 1 FROM users WHERE users.id = auth.uid() AND users.is_admin = true) OR auth.uid() = id) WITH CHECK (true);
CREATE POLICY users_delete_policy ON users FOR DELETE TO authenticated USING (public.tenant_id() = tenant_id);

-- Configuration policies
CREATE POLICY configuration_insert_policy ON configuration FOR INSERT TO authenticated WITH CHECK (tenant_id = public.tenant_id());
CREATE POLICY configuration_select_policy ON configuration FOR SELECT TO authenticated USING (tenant_id = public.tenant_id());
CREATE POLICY configuration_update_policy ON configuration FOR UPDATE TO authenticated USING (tenant_id = public.tenant_id());
CREATE POLICY configuration_delete_policy ON configuration FOR DELETE TO authenticated USING ((tenant_id = public.tenant_id()) AND (EXISTS (SELECT 1 FROM users WHERE users.id = auth.uid() AND users.is_admin = true)));

-- Proc map history policies
CREATE POLICY proc_map_history_insert_policy ON proc_map_history FOR INSERT TO authenticated WITH CHECK (tenant_id = public.tenant_id());
CREATE POLICY proc_map_history_select_policy ON proc_map_history FOR SELECT TO authenticated USING (tenant_id = public.tenant_id());
CREATE POLICY proc_map_history_update_policy ON proc_map_history FOR UPDATE TO authenticated USING (tenant_id = public.tenant_id());
CREATE POLICY proc_map_history_delete_policy ON proc_map_history FOR DELETE TO authenticated USING (tenant_id = public.tenant_id());

-- Proc def policies
CREATE POLICY proc_def_insert_policy ON proc_def FOR INSERT TO authenticated WITH CHECK ((tenant_id = public.tenant_id()) AND (EXISTS (SELECT 1 FROM users WHERE users.id = auth.uid() AND users.is_admin = true)));
CREATE POLICY proc_def_select_policy ON proc_def FOR SELECT TO authenticated USING (tenant_id = public.tenant_id());
CREATE POLICY proc_def_update_policy ON proc_def FOR UPDATE TO authenticated USING ((tenant_id = public.tenant_id()) AND (EXISTS (SELECT 1 FROM users WHERE users.id = auth.uid() AND users.is_admin = true)));
CREATE POLICY proc_def_delete_policy ON proc_def FOR DELETE TO authenticated USING ((tenant_id = public.tenant_id()) AND (EXISTS (SELECT 1 FROM users WHERE users.id = auth.uid() AND users.is_admin = true)));

-- Proc def arcv policies
CREATE POLICY proc_def_arcv_insert_policy ON proc_def_arcv FOR INSERT TO authenticated WITH CHECK (tenant_id = public.tenant_id());
CREATE POLICY proc_def_arcv_select_policy ON proc_def_arcv FOR SELECT TO authenticated USING (tenant_id = public.tenant_id());
CREATE POLICY proc_def_arcv_update_policy ON proc_def_arcv FOR UPDATE TO authenticated USING (tenant_id = public.tenant_id());
CREATE POLICY proc_def_arcv_delete_policy ON proc_def_arcv FOR DELETE TO authenticated USING (tenant_id = public.tenant_id());

-- Form def policies
CREATE POLICY form_def_insert_policy ON form_def FOR INSERT TO authenticated WITH CHECK (EXISTS (SELECT 1 FROM users WHERE users.id = auth.uid() AND users.is_admin = true));
CREATE POLICY form_def_select_policy ON form_def FOR SELECT TO authenticated USING (true);
CREATE POLICY form_def_update_policy ON form_def FOR UPDATE TO authenticated USING (EXISTS (SELECT 1 FROM users WHERE users.id = auth.uid() AND users.is_admin = true));
CREATE POLICY form_def_delete_policy ON form_def FOR DELETE TO authenticated USING (EXISTS (SELECT 1 FROM users WHERE users.id = auth.uid() AND users.is_admin = true));

-- Notifications policies
CREATE POLICY notifications_insert_policy ON notifications FOR INSERT TO authenticated WITH CHECK (tenant_id = public.tenant_id());
CREATE POLICY notifications_select_policy ON notifications FOR SELECT TO authenticated USING (tenant_id = public.tenant_id());
CREATE POLICY notifications_update_policy ON notifications FOR UPDATE TO authenticated USING (tenant_id = public.tenant_id());
CREATE POLICY notifications_delete_policy ON notifications FOR DELETE TO authenticated USING (tenant_id = public.tenant_id());

-- Lock policies
CREATE POLICY lock_insert_policy ON lock FOR INSERT TO authenticated WITH CHECK (EXISTS (SELECT 1 FROM users WHERE users.id = auth.uid() AND users.is_admin = true));
CREATE POLICY lock_select_policy ON lock FOR SELECT TO authenticated USING (tenant_id = public.tenant_id());
CREATE POLICY lock_update_policy ON lock FOR UPDATE TO authenticated USING (EXISTS (SELECT 1 FROM users WHERE users.id = auth.uid() AND users.is_admin = true));
CREATE POLICY lock_delete_policy ON lock FOR DELETE TO authenticated USING (EXISTS (SELECT 1 FROM users WHERE users.id = auth.uid() AND users.is_admin = true));

-- BPM proc inst policies
CREATE POLICY bpm_proc_inst_insert_policy ON bpm_proc_inst FOR INSERT TO authenticated WITH CHECK ((tenant_id = public.tenant_id()) AND (EXISTS (SELECT 1 FROM users WHERE users.id = auth.uid() AND users.is_admin = true)));
CREATE POLICY bpm_proc_inst_select_policy ON bpm_proc_inst FOR SELECT TO authenticated USING (tenant_id = public.tenant_id());
CREATE POLICY bpm_proc_inst_update_policy ON bpm_proc_inst FOR UPDATE TO authenticated USING ((tenant_id = public.tenant_id()) AND (EXISTS (SELECT 1 FROM users WHERE users.id = auth.uid() AND users.is_admin = true)));
CREATE POLICY bpm_proc_inst_delete_policy ON bpm_proc_inst FOR DELETE TO authenticated USING ((tenant_id = public.tenant_id()) AND (EXISTS (SELECT 1 FROM users WHERE users.id = auth.uid() AND users.is_admin = true)));

-- Todolist policies
CREATE POLICY todolist_insert_policy ON todolist FOR INSERT TO authenticated WITH CHECK (tenant_id = public.tenant_id());
CREATE POLICY todolist_select_policy ON todolist FOR SELECT TO authenticated USING (tenant_id = public.tenant_id());
CREATE POLICY todolist_update_policy ON todolist FOR UPDATE TO authenticated USING (tenant_id = public.tenant_id());
CREATE POLICY todolist_delete_policy ON todolist FOR DELETE TO authenticated USING (tenant_id = public.tenant_id());

-- Chat rooms policies
CREATE POLICY chat_rooms_insert_policy ON chat_rooms FOR INSERT TO authenticated WITH CHECK (tenant_id = public.tenant_id());
CREATE POLICY chat_rooms_select_policy ON chat_rooms FOR SELECT TO authenticated USING (tenant_id = public.tenant_id());
CREATE POLICY chat_rooms_update_policy ON chat_rooms FOR UPDATE TO authenticated USING (tenant_id = public.tenant_id());
CREATE POLICY chat_rooms_delete_policy ON chat_rooms FOR DELETE TO authenticated USING (tenant_id = public.tenant_id());

-- Chats policies
CREATE POLICY chats_insert_policy ON chats FOR INSERT TO authenticated WITH CHECK (tenant_id = public.tenant_id());
CREATE POLICY chats_select_policy ON chats FOR SELECT TO authenticated USING (tenant_id = public.tenant_id());
CREATE POLICY chats_update_policy ON chats FOR UPDATE TO authenticated USING (tenant_id = public.tenant_id());
CREATE POLICY chats_delete_policy ON chats FOR DELETE TO authenticated USING (tenant_id = public.tenant_id());

-- Calendar policies
CREATE POLICY calendar_insert_policy ON calendar FOR INSERT TO authenticated WITH CHECK (tenant_id = public.tenant_id());
CREATE POLICY calendar_select_policy ON calendar FOR SELECT TO authenticated USING (tenant_id = public.tenant_id());
CREATE POLICY calendar_update_policy ON calendar FOR UPDATE TO authenticated USING (tenant_id = public.tenant_id());
CREATE POLICY calendar_delete_policy ON calendar FOR DELETE TO authenticated USING (tenant_id = public.tenant_id());

-- User permissions policies
CREATE POLICY user_permissions_insert_policy ON user_permissions FOR INSERT TO authenticated WITH CHECK (tenant_id = public.tenant_id());
CREATE POLICY user_permissions_select_policy ON user_permissions FOR SELECT TO authenticated USING (tenant_id = public.tenant_id());
CREATE POLICY user_permissions_update_policy ON user_permissions FOR UPDATE TO authenticated USING (tenant_id = public.tenant_id());
CREATE POLICY user_permissions_delete_policy ON user_permissions FOR DELETE TO authenticated USING (tenant_id = public.tenant_id());

-- Proc def marketplace policies
CREATE POLICY proc_def_marketplace_insert_policy ON proc_def_marketplace FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY proc_def_marketplace_select_policy ON proc_def_marketplace FOR SELECT TO public USING (true);
CREATE POLICY proc_def_marketplace_update_policy ON proc_def_marketplace FOR UPDATE TO authenticated USING (true);
CREATE POLICY proc_def_marketplace_delete_policy ON proc_def_marketplace FOR DELETE TO authenticated USING (true);

-- Form def marketplace policies
CREATE POLICY form_def_marketplace_insert_policy ON form_def_marketplace FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY form_def_marketplace_select_policy ON form_def_marketplace FOR SELECT TO authenticated USING (true);
CREATE POLICY form_def_marketplace_update_policy ON form_def_marketplace FOR UPDATE TO authenticated USING (true);
CREATE POLICY form_def_marketplace_delete_policy ON form_def_marketplace FOR DELETE TO authenticated USING (true);

-- Tenant oauth policies
CREATE POLICY tenant_oauth_insert_policy ON tenant_oauth FOR INSERT TO authenticated WITH CHECK (EXISTS (SELECT 1 FROM users WHERE users.id = auth.uid() AND users.is_admin = true));
CREATE POLICY tenant_oauth_select_policy ON tenant_oauth FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM users WHERE users.id = auth.uid() AND users.is_admin = true));
CREATE POLICY tenant_oauth_update_policy ON tenant_oauth FOR UPDATE TO authenticated USING (EXISTS (SELECT 1 FROM users WHERE users.id = auth.uid() AND users.is_admin = true));
CREATE POLICY tenant_oauth_delete_policy ON tenant_oauth FOR DELETE TO authenticated USING (EXISTS (SELECT 1 FROM users WHERE users.id = auth.uid() AND users.is_admin = true));

-- Storage policies
CREATE POLICY "Allow authenticated users to upload" ON storage.objects FOR INSERT WITH CHECK (auth.role() = 'authenticated');

-- Project policies
CREATE POLICY project_insert_policy ON project FOR INSERT TO authenticated WITH CHECK ((tenant_id = public.tenant_id()) AND (EXISTS (SELECT 1 FROM users WHERE users.id = auth.uid() AND users.is_admin = true)));
CREATE POLICY project_select_policy ON project FOR SELECT TO authenticated USING (tenant_id = public.tenant_id());
CREATE POLICY project_update_policy ON project FOR UPDATE TO authenticated USING ((tenant_id = public.tenant_id()) AND (EXISTS (SELECT 1 FROM users WHERE users.id = auth.uid() AND users.is_admin = true)));
CREATE POLICY project_delete_policy ON project FOR DELETE TO authenticated USING ((tenant_id = public.tenant_id()) AND (EXISTS (SELECT 1 FROM users WHERE users.id = auth.uid() AND users.is_admin = true)));

-- Enable Realtime for specific tables
alter publication supabase_realtime add table chats;
alter publication supabase_realtime add table notifications;
alter publication supabase_realtime add table todolist;
alter publication supabase_realtime add table bpm_proc_inst;
alter publication supabase_realtime add table proc_def; 
alter publication supabase_realtime add table project;



-- schedule 관련
create table if not exists public.cron_job_run_log (
  id serial primary key,
  job_name text,
  executed_at timestamptz default now(),
  status text,
  http_status int,
  response_body jsonb,
  error_message text
);

create or replace function public.start_process_scheduled(
  p_job_name text,
  p_input jsonb
)
returns void
language plpgsql
as $$
declare
  response text;
  status_code int; 
begin
  response := net.http_post(
    'http://host.docker.internal:8000/initiate',
    p_input,
    '{"Content-Type":"application/json"}'
  )::text;

  status_code := 200;

  insert into public.cron_job_run_log (
    job_name, status, http_status, response_body
  )
  values (
    p_job_name,
    'SUCCESS',
    status_code,
    to_jsonb(response)
  );

  raise notice '✅ HTTP status: %, response: %', status_code, response;

exception
  when others then
    insert into public.cron_job_run_log (
      job_name, status, http_status, error_message
    )
    values (
      p_job_name,
      'ERROR',
      500,
      SQLERRM
    );
    raise notice '❌ exception: %', SQLERRM;
    raise;
end;
$$;


create or replace function public.register_cron_job(
  p_job_name text,
  p_cron_expr text,
  p_input jsonb
)
returns void
language plpgsql
security definer
as $$
DECLARE
  v_job_name text;
BEGIN
  SELECT jobname INTO v_job_name
  FROM cron.job
  WHERE jobname = p_job_name;

  IF v_job_name IS NOT NULL THEN
    PERFORM cron.unschedule(v_job_name);
  END IF;

  -- ✅ 새로 schedule
  PERFORM cron.schedule(
    p_job_name,
    p_cron_expr,
    format(
      E'select public.start_process_scheduled(''%s'', ''%s''::jsonb);',
      replace(p_job_name, '''', ''''''),
      replace(p_input::text, '''', '''''')
    )
  );
END;
$$;


grant execute on function public.register_cron_job(text, text, jsonb) to authenticated;


create or replace function public.get_cron_jobs()
returns setof cron.job
language sql
security definer
as $$
  select * from cron.job;
$$;

grant execute on function public.get_cron_jobs() to authenticated;

create or replace function public.delete_cron_job(
  p_job_name text
)
returns void
language plpgsql
security definer
as $$
begin
  perform cron.unschedule(p_job_name);
end;
$$;

grant execute on function public.delete_cron_job(text) to authenticated;



GRANT USAGE ON SCHEMA cron TO authenticated;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA cron TO authenticated;

-- ===============================================
-- 테넌트 자동 삭제 기능 (deleted_at 기준 7일 후)
-- ===============================================

-- pg_cron 확장 추가 (이미 있을 수 있지만 안전하게)
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- 테넌트 정리 함수 (기존 start_process_scheduled 패턴과 동일)
create or replace function public.cleanup_deleted_tenants_job(
  p_job_name text,
  p_input jsonb
)
returns void
language plpgsql
as $$
declare
  deleted_count int;
  response text;
  status_code int; 
begin
  -- deleted_at이 일주일(7일) 지난 테넌트들을 실제로 삭제
  delete from public.tenants
  where deleted_at is not null
    and deleted_at < now() - interval '7 days';
  
  get diagnostics deleted_count = row_count;
  
  response := format('Successfully deleted %s expired tenants', deleted_count);
  status_code := 200;

  insert into public.cron_job_run_log (
    job_name, status, http_status, response_body
  )
  values (
    p_job_name,
    'SUCCESS',
    status_code,
    jsonb_build_object(
      'deleted_count', deleted_count,
      'message', response
    )
  );

  raise notice '✅ Tenant cleanup completed: % tenants deleted', deleted_count;

exception
  when others then
    insert into public.cron_job_run_log (
      job_name, status, http_status, error_message
    )
    values (
      p_job_name,
      'ERROR',
      500,
      SQLERRM
    );
    raise notice '❌ Tenant cleanup failed: %', SQLERRM;
    raise;
end;
$$;

grant execute on function public.cleanup_deleted_tenants_job(text, jsonb) to authenticated;

-- 테넌트 정리 cron job 등록 함수
create or replace function public.register_tenant_cleanup()
returns void
language plpgsql
security definer
as $$
begin
  -- 기존 job이 있다면 삭제
  perform cron.unschedule('tenant_cleanup_daily') where exists (
    select 1 from cron.job where jobname = 'tenant_cleanup_daily'
  );

  -- 새로 등록 (매일 새벽 2시에 실행 - 한국시간 기준, UTC로는 17시)
  perform cron.schedule(
    'tenant_cleanup_daily',
    '0 17 * * *',
    'select public.cleanup_deleted_tenants_job(''tenant_cleanup_daily'', ''{}''::jsonb);'
  );
  
  raise notice '✅ Tenant cleanup job registered successfully (runs daily at 2:00 AM KST / 17:00 UTC)';
end;
$$;

grant execute on function public.register_tenant_cleanup() to authenticated;

-- 테넌트 정리 cron job 등록 실행 (한 번 실행하면 매일 자동 실행)
SELECT public.register_tenant_cleanup();

-- ===============================================
-- bpm_proc_inst 자동 삭제 기능 (deleted_at 기준 7일 후)
-- ===============================================

-- bpm_proc_inst 삭제 시 관련 데이터를 삭제하는 트리거 함수
create or replace function public.cleanup_bpm_proc_inst_related_data()
returns trigger as $$
begin
    -- proc_inst_id와 관련된 todolist 삭제
    delete from public.todolist
    where proc_inst_id = old.proc_inst_id;
    
    -- proc_inst_id와 관련된 chats 삭제 (id 컬럼이 proc_inst_id와 매칭)
    delete from public.chats
    where id = old.proc_inst_id;
    
    -- proc_inst_id와 관련된 chat_rooms 삭제 (id 컬럼이 proc_inst_id와 매칭)
    delete from public.chat_rooms
    where id = old.proc_inst_id;
    
    return old;
end;
$$ language plpgsql;

-- bpm_proc_inst 삭제 시 관련 데이터를 삭제하는 트리거 생성
create trigger cleanup_bpm_proc_inst_related_data_trigger
    before delete on public.bpm_proc_inst
    for each row
    execute function public.cleanup_bpm_proc_inst_related_data();

-- bpm_proc_inst 정리 함수 (기존 start_process_scheduled 패턴과 동일)
create or replace function public.cleanup_deleted_bpm_proc_inst_job(
  p_job_name text,
  p_input jsonb
)
returns void
language plpgsql
as $$
declare
  deleted_count int;
  response text;
  status_code int; 
begin
  -- deleted_at이 일주일(7일) 지난 bpm_proc_inst들을 실제로 삭제
  delete from public.bpm_proc_inst
  where deleted_at is not null
    and deleted_at < now() - interval '7 days';
  
  get diagnostics deleted_count = row_count;
  
  response := format('Successfully deleted %s expired bpm_proc_inst records', deleted_count);
  status_code := 200;

  insert into public.cron_job_run_log (
    job_name, status, http_status, response_body
  )
  values (
    p_job_name,
    'SUCCESS',
    status_code,
    jsonb_build_object(
      'deleted_count', deleted_count,
      'message', response
    )
  );

  raise notice '✅ BPM Process Instance cleanup completed: % records deleted', deleted_count;

exception
  when others then
    insert into public.cron_job_run_log (
      job_name, status, http_status, error_message
    )
    values (
      p_job_name,
      'ERROR',
      500,
      SQLERRM
    );
    raise notice '❌ BPM Process Instance cleanup failed: %', SQLERRM;
    raise;
end;
$$;

grant execute on function public.cleanup_deleted_bpm_proc_inst_job(text, jsonb) to authenticated;

-- bpm_proc_inst 정리 cron job 등록 함수
create or replace function public.register_bpm_proc_inst_cleanup()
returns void
language plpgsql
security definer
as $$
begin
  -- 기존 job이 있다면 삭제
  perform cron.unschedule('bpm_proc_inst_cleanup_daily') where exists (
    select 1 from cron.job where jobname = 'bpm_proc_inst_cleanup_daily'
  );

  -- 새로 등록 (매일 새벽 3시에 실행 - 한국시간 기준, UTC로는 18시)
  perform cron.schedule(
    'bpm_proc_inst_cleanup_daily',
    '0 18 * * *',
    'select public.cleanup_deleted_bpm_proc_inst_job(''bpm_proc_inst_cleanup_daily'', ''{}''::jsonb);'
  );
  
  raise notice '✅ BPM Process Instance cleanup job registered successfully (runs daily at 3:00 AM KST / 18:00 UTC)';
end;
$$;

grant execute on function public.register_bpm_proc_inst_cleanup() to authenticated;

-- bpm_proc_inst 정리 cron job 등록 실행 (한 번 실행하면 매일 자동 실행)
SELECT public.register_bpm_proc_inst_cleanup();



-- ==========================================
-- 📌 데이터소스 테이블
-- ==========================================
CREATE TABLE IF NOT EXISTS public.data_source (
    uuid uuid NOT NULL DEFAULT gen_random_uuid(),
    key text NOT NULL,
    value jsonb NULL,
    version integer NOT NULL DEFAULT 1,
    description text NULL,
    tenant_id text NULL DEFAULT public.tenant_id(),
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone NOT NULL DEFAULT now(),
    CONSTRAINT data_source_pkey PRIMARY KEY (uuid),
    CONSTRAINT data_source_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants (id) ON UPDATE CASCADE ON DELETE CASCADE
) TABLESPACE pg_default;

-- ✅ 유니크 인덱스 (테넌트별 key + version)
CREATE UNIQUE INDEX IF NOT EXISTS unique_data_source_key_version_per_tenant
  ON data_source (key, version, tenant_id);


  -- RLS 켜기
ALTER TABLE data_source ENABLE ROW LEVEL SECURITY;


create or replace function register_cron_intermidiated(
  p_job_name text,
  p_cron_expr text,
  p_input jsonb
)
returns void
language plpgsql
as $$
declare
  v_job_name text;
begin
  -- 기존 job이 있으면 unschedule
  select jobname into v_job_name
  from cron.job
  where jobname = p_job_name;

  if v_job_name is not null then
    perform cron.unschedule(v_job_name);
  end if;

  -- 새로 schedule
  perform cron.schedule(
    p_job_name,
    p_cron_expr,
    format(
      E'select public.update_todolist_status(''%s'', ''%s'');',
      p_input->>'proc_inst_id',
      p_input->>'activity_id'
    )
  );
end;
$$;

create or replace function update_todolist_status(
  p_proc_inst_id text,
  p_activity_id text
)
returns void
language plpgsql
as $$
declare
  v_job_name text := p_proc_inst_id || '__' || p_activity_id;
begin
  -- 상태를 SUBMITTED로 업데이트
  update todolist
  set status = 'SUBMITTED',
      updated_at = now()
  where proc_inst_id = p_proc_inst_id
    and activity_id = p_activity_id;

  -- 스케줄에서 job 제거
  perform cron.unschedule(v_job_name);
end;
$$;


create or replace function exec_sql(query text)
returns json
language plpgsql
as $$
declare
  result json;
begin
  execute query into result;
  return result;
end;
$$;


grant usage on schema cron to service_role;
grant execute on all functions in schema cron to service_role;



-- enum 타입 추가
-- 프로세스 인스턴스 상태 enum
CREATE TYPE process_status AS ENUM ('NEW', 'RUNNING', 'COMPLETED');
-- 할일 항목 상태 enum
CREATE TYPE todo_status AS ENUM ('TODO', 'IN_PROGRESS', 'SUBMITTED', 'PENDING', 'DONE', 'CANCELLED');
-- 에이전트 모드 enum
CREATE TYPE agent_mode AS ENUM ('NONE', 'A2A', 'DRAFT', 'COMPLETE');
-- 오케스트레이션 방식 enum
CREATE TYPE agent_orch AS ENUM ('crewai-action', 'openai-deep-research', 'crewai-deep-research', 'langchain-react');
-- 드래프트 상태 enum
CREATE TYPE draft_status AS ENUM ('STARTED', 'CANCELLED', 'COMPLETED', 'FB_REQUESTED', 'HUMAN_ASKED', 'FAILED');
-- 이벤트 타입 enum
CREATE TYPE event_type_enum AS ENUM (
  'task_started',
  'task_completed',
  'tool_usage_started',
  'tool_usage_finished',
  'crew_completed',
  'human_asked',
  'human_response'
);
-- 이벤트 상태 enum
CREATE TYPE event_status AS ENUM ('ASKED', 'APPROVED', 'REJECTED');

-- events 테이블 마이그레이션 (event_type)
-- 1. 임시 컬럼 추가
ALTER TABLE public.events ADD COLUMN event_type_new event_type_enum;
-- 2. 기존 데이터를 새 enum 타입으로 변환
UPDATE public.events
SET event_type_new = CASE
  WHEN event_type = 'task_started' THEN 'task_started'::event_type_enum
  WHEN event_type = 'task_completed' THEN 'task_completed'::event_type_enum
  WHEN event_type = 'tool_usage_started' THEN 'tool_usage_started'::event_type_enum
  WHEN event_type = 'tool_usage_finished' THEN 'tool_usage_finished'::event_type_enum
  WHEN event_type = 'crew_completed' THEN 'crew_completed'::event_type_enum
  WHEN event_type = 'human_asked' THEN 'human_asked'::event_type_enum
  WHEN event_type = 'human_response' THEN 'human_response'::event_type_enum
  ELSE NULL  -- 기본값을 NULL로 설정
END;
-- 3. 기존 컬럼 삭제 후 새 컬럼명 변경
ALTER TABLE public.events DROP COLUMN event_type;
ALTER TABLE public.events RENAME COLUMN event_type_new TO event_type;

-- events 테이블 마이그레이션 (status)
-- 1. 임시 컬럼 추가
ALTER TABLE public.events ADD COLUMN status_new event_status;
-- 2. 기존 데이터를 새 enum 타입으로 변환
UPDATE public.events
SET status_new = CASE
  WHEN status = 'ASKED' THEN 'ASKED'::event_status
  WHEN status = 'APPROVED' THEN 'APPROVED'::event_status
  WHEN status = 'REJECTED' THEN 'REJECTED'::event_status
  ELSE NULL  -- 기본값을 NULL로 설정
END;
-- 3. 기존 컬럼 삭제 후 새 컬럼명 변경
ALTER TABLE public.events DROP COLUMN status;
ALTER TABLE public.events RENAME COLUMN status_new TO status;

-- bpm_proc_inst 테이블 마이그레이션 (status)
-- 1. 임시 컬럼 추가
ALTER TABLE public.bpm_proc_inst ADD COLUMN status_new process_status;
-- 2. 기존 데이터를 새 enum 타입으로 변환
UPDATE public.bpm_proc_inst 
SET status_new = CASE 
    WHEN status = 'NEW' THEN 'NEW'::process_status
    WHEN status = 'RUNNING' THEN 'RUNNING'::process_status
    WHEN status = 'COMPLETED' THEN 'COMPLETED'::process_status
    ELSE 'NEW'::process_status  -- 기본값 설정
END;
-- 3. 기존 컬럼 삭제 후 새 컬럼명 변경
ALTER TABLE public.bpm_proc_inst DROP COLUMN status;
ALTER TABLE public.bpm_proc_inst RENAME COLUMN status_new TO status;

-- todolist 테이블 마이그레이션 (status)
-- 1. 임시 컬럼 추가
ALTER TABLE public.todolist ADD COLUMN status_new todo_status;
-- 2. 기존 데이터를 새 enum 타입으로 변환
UPDATE public.todolist 
SET status_new = CASE 
    WHEN status = 'TODO' THEN 'TODO'::todo_status
    WHEN status = 'IN_PROGRESS' THEN 'IN_PROGRESS'::todo_status
    WHEN status = 'DONE' THEN 'DONE'::todo_status
    WHEN status = 'SUBMITTED' THEN 'SUBMITTED'::todo_status
    WHEN status = 'PENDING' THEN 'PENDING'::todo_status
    WHEN status = 'CANCELLED' THEN 'CANCELLED'::todo_status
    ELSE 'TODO'::todo_status  -- 기본값 설정
END;
-- 3. 기존 컬럼 삭제 후 새 컬럼명 변경
ALTER TABLE public.todolist DROP COLUMN status;
ALTER TABLE public.todolist RENAME COLUMN status_new TO status;

-- todolist 테이블 마이그레이션 (agent_mode)
-- 1. 임시 컬럼 추가
ALTER TABLE public.todolist ADD COLUMN agent_mode_new agent_mode;
-- 2. 기존 데이터를 새 enum 타입으로 변환
UPDATE public.todolist 
SET agent_mode_new = CASE 
    WHEN agent_mode = 'NONE' THEN 'NONE'::agent_mode
    WHEN agent_mode = 'A2A' THEN 'A2A'::agent_mode
    WHEN agent_mode = 'DRAFT' THEN 'DRAFT'::agent_mode
    WHEN agent_mode = 'COMPLETE' THEN 'COMPLETE'::agent_mode
    ELSE 'NONE'::agent_mode  -- 기본값 설정
END;
-- 3. 기존 컬럼 삭제 후 새 컬럼명 변경
ALTER TABLE public.todolist DROP COLUMN agent_mode;
ALTER TABLE public.todolist RENAME COLUMN agent_mode_new TO agent_mode;


-- todolist 테이블 마이그레이션 (agent_orch)
-- 1. 임시 컬럼 추가
ALTER TABLE public.todolist ADD COLUMN agent_orch_new agent_orch;
-- 2. 기존 데이터를 새 enum 타입으로 변환
UPDATE public.todolist 
SET agent_orch_new = CASE 
    WHEN agent_orch = 'crewai-deep-research' THEN 'crewai-deep-research'::agent_orch
    WHEN agent_orch = 'openai-deep-research' THEN 'openai-deep-research'::agent_orch
    WHEN agent_orch = 'crewai-action' THEN 'crewai-action'::agent_orch
    WHEN agent_orch = 'langchain-react' THEN 'langchain-react'::agent_orch
    ELSE NULL  -- 기본값을 NULL로 설정
END;
-- 3. 기존 컬럼 삭제 후 새 컬럼명 변경
ALTER TABLE public.todolist DROP COLUMN agent_orch;
ALTER TABLE public.todolist RENAME COLUMN agent_orch_new TO agent_orch;


-- todolist 테이블 마이그레이션 (draft_status)
-- 1. 임시 컬럼 추가
ALTER TABLE public.todolist ADD COLUMN draft_status_new draft_status;
-- 2. 기존 데이터를 새 enum 타입으로 변환 (정확 스펠링 기준)
UPDATE public.todolist 
SET draft_status_new = CASE 
    WHEN draft_status = 'STARTED' THEN 'STARTED'::draft_status
    WHEN draft_status = 'CANCELLED' THEN 'CANCELLED'::draft_status
    WHEN draft_status = 'COMPLETED' THEN 'COMPLETED'::draft_status
    WHEN draft_status = 'FB_REQUESTED' THEN 'FB_REQUESTED'::draft_status
    WHEN draft_status = 'HUMAN_ASKED' THEN 'HUMAN_ASKED'::draft_status
    WHEN draft_status = 'FAILED' THEN 'FAILED'::draft_status
    ELSE NULL  -- 기본값을 NULL로 설정
END;
-- 3. 기존 컬럼 삭제 후 새 컬럼명 변경
ALTER TABLE public.todolist DROP COLUMN draft_status;
ALTER TABLE public.todolist RENAME COLUMN draft_status_new TO draft_status;



create table if not exists public.proc_inst_source (
    id uuid not null default gen_random_uuid (),
    proc_inst_id text null,
    file_name text null,
    created_at timestamp with time zone not null default now(),
    is_process boolean not null default false,
    file_path text null,
    constraint proc_inst_source_pkey primary key (id),
    constraint proc_inst_source_proc_inst_id_fkey foreign key (proc_inst_id) references bpm_proc_inst (proc_inst_id) on update cascade on delete cascade
) tablespace pg_default;


-- 문서 이미지 테이블
CREATE TABLE IF NOT EXISTS public.document_images (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    document_id UUID REFERENCES documents(id),
    tenant_id TEXT NOT NULL,
    image_id TEXT NULL,
    image_url TEXT NULL,
    metadata JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 인덱스 생성
CREATE INDEX IF NOT EXISTS idx_document_images_document_id ON document_images(document_id);
CREATE INDEX IF NOT EXISTS idx_document_images_tenant_id ON document_images(tenant_id);


-- ==========================================
-- Mem0 vector store 함수 (vecs 스키마)
-- ==========================================
-- 조회 (agent_id 필터링 + limit)
create or replace function public.get_memories(agent text, lim int default 100)
returns setof vecs.memories
language sql stable
security definer
as $$
  select *
  from vecs.memories
  where (agent is null or metadata->>'agent_id' = agent)
  order by id
  limit lim;
$$;

-- 단일 행 삭제
create or replace function public.delete_memory(mem_id text)
returns void
language sql volatile
security definer
as $$
  delete from vecs.memories where id = mem_id;
$$;

-- 특정 agent_id의 모든 메모리 삭제
create or replace function public.delete_memories_by_agent(agent text)
returns void
language sql volatile
security definer
as $$
  delete from vecs.memories where metadata->>'agent_id' = agent;
$$;





