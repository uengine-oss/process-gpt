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
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- ==========================================
-- ENUM 타입 정의
-- ==========================================
-- 프로세스 인스턴스 상태 enum
DO $$ BEGIN
  CREATE TYPE process_status AS ENUM ('NEW', 'RUNNING', 'COMPLETED');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;
-- 할일 항목 상태 enum
DO $$ BEGIN
  CREATE TYPE todo_status AS ENUM ('NEW', 'TODO', 'IN_PROGRESS', 'SUBMITTED', 'PENDING', 'DONE', 'CANCELLED');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;
-- 에이전트 모드 enum
DO $$ BEGIN
  CREATE TYPE agent_mode AS ENUM ('DRAFT', 'COMPLETE');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;
-- 드래프트 상태 enum
DO $$ BEGIN
  CREATE TYPE draft_status AS ENUM ('STARTED', 'CANCELLED', 'COMPLETED', 'FB_REQUESTED', 'HUMAN_ASKED', 'FAILED');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;
-- 이벤트 타입 enum
DO $$ BEGIN
  CREATE TYPE event_type_enum AS ENUM (
  'task_started',
  'task_completed',
  'tool_usage_started',
  'tool_usage_finished',
  'crew_completed',
  'human_asked',
  'human_response',
  'human_checked',
  'task_working',
  'error',
  'waiting_for_user',
  'task_cancelled',
  'human_feedback_submitted',
  'gateway_decision',
  'gateway_decision_trace',
  'mcp_call_started',
  'mcp_call_finished',
  'mcp_call_failed',
  'mcp_tools_loaded',
  'mcp_server_health_changed',
  'llm_call_finished'
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;
-- 이벤트 상태 enum
DO $$ BEGIN
  CREATE TYPE event_status AS ENUM ('ASKED', 'APPROVED', 'REJECTED');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

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

-- If init.sql is re-run, avoid duplicate key errors
INSERT INTO public.tenants (id, owner)
VALUES ('process-gpt', null)
ON CONFLICT (id) DO NOTHING;

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
    tenant_id text not null default 'process-gpt',
    device_token text null,
    goal text null,
    persona text null,
    endpoint text null,
    description text null,
    tools text null,
    skills text null,
    is_agent boolean not null default false,
    agent_type text null,
    model text null,
    alias text null,
    last_used_at timestamp with time zone null default now(),
    tool_priority jsonb null,
    is_draft boolean not null default false,
    constraint users_pkey primary key (id, tenant_id),
    constraint users_tenant_id_fkey foreign key (tenant_id) references tenants (id) on update cascade on delete cascade
) tablespace pg_default;

CREATE INDEX IF NOT EXISTS idx_users_is_agent_true
  ON public.users (is_agent)
  WHERE is_agent = true;

-- 1) 트리거 함수: auth.users → public.users 동기화
create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  insert into public.users (
    id,
    username,
    email,
    tenant_id,
    is_admin,
    role
  )
  values (
    new.id,
    coalesce(
      (new.raw_user_meta_data ->> 'name'),
      new.email
    ),
    new.email,
    'process-gpt',   -- 고정 테넌트
    false,           -- 항상 일반 유저
    'user'           -- 기본 역할
  )
  on conflict (id, tenant_id) do nothing;  -- 이미 있으면 무시

  return new;
end;
$$;

-- 2) 트리거: auth.users INSERT 시 실행
-- Supabase Auth 스키마는 Supabase가 소유/관리합니다.
-- 일부 환경(권한 제한, managed DB 등)에서는 auth 스키마에 DDL이 실패할 수 있으므로
-- "가능하면 적용, 안 되면 스킵"으로 처리합니다.
DO $$
BEGIN
  -- 2) 트리거: auth.users INSERT 시 실행 (가능하면 생성)
  BEGIN
    EXECUTE 'DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users';
    EXECUTE 'CREATE TRIGGER on_auth_user_created
      AFTER INSERT ON auth.users
      FOR EACH ROW
      EXECUTE FUNCTION public.handle_new_auth_user()';
  EXCEPTION
    WHEN insufficient_privilege OR undefined_table OR invalid_schema_name THEN
      RAISE NOTICE 'Skipping auth.users trigger setup: %', SQLERRM;
  END;

  -- 3) Supabase Auth: identities 테이블은 여기서 미리 만들지 않는다.
  -- 예전엔 "신규 버전 signup 대비"로 최종 형태(uuid pk + provider_id)를
  -- 미리 만들어 뒀는데, 그러면 GoTrue가 자기 내장 마이그레이션 체인
  -- (20210909172000_create_identities_table 이후 수십 개, 예: id가 text였다가
  -- uuid로 바뀌는 중간 단계들)을 처음부터 재생하다가 "테이블이 이미 최종 형태"
  -- 라서 중간 단계 마이그레이션이 스키마 불일치로 깨진다
  -- (예: `id = user_id::text` 비교에서 uuid = text 타입 에러, 신선 설치 기준
  -- 재현 확인됨). auth.identities는 GoTrue 자신의 마이그레이션이 처음부터
  -- 끝까지 순서대로 만들게 그냥 둔다 — 그래야 스키마 진화 단계가 맞다.

  -- 4) 권한/검색경로 설정 (가능하면 적용)
  BEGIN
    IF EXISTS (select 1 from pg_roles where rolname = 'supabase_auth_admin') THEN
      EXECUTE 'GRANT USAGE ON SCHEMA auth TO supabase_auth_admin';
      EXECUTE 'ALTER ROLE supabase_auth_admin SET search_path = auth, public, extensions';
    END IF;
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE 'Skipping supabase_auth_admin grants: %', SQLERRM;
  END;
END $$;

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
    prod_version text null,
    uuid uuid not null default gen_random_uuid (),
    tenant_id text null default public.tenant_id(),
    isdeleted boolean not null default false,
    owner text null,
    agent_id text null,
    type text null,
    is_draft boolean not null default false,
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

create table if not exists public.proc_def_version (
    arcv_id text not null,
    proc_def_id text not null,
    version text not null,
    version_tag text null,
    snapshot text null,
    definition jsonb null,
    "timeStamp" timestamp without time zone null default current_timestamp,
    diff text null,
    message text null,
    uuid uuid not null default gen_random_uuid (),
    tenant_id text null default public.tenant_id(),
    parent_version text null,
    source_todolist_id uuid null,
    is_draft boolean not null default false,
    constraint proc_def_version_pkey primary key (uuid),
    constraint proc_def_version_tenant_id_fkey foreign key (tenant_id) references tenants (id) on update cascade on delete cascade
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
    constraint lock_tenant_id_fkey foreign key (tenant_id) references tenants (id) on update cascade on delete cascade,
    constraint lock_tenant_id_id_unique unique (tenant_id, id)
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
    status process_status null,
    tenant_id text null default public.tenant_id(),
     proc_def_version text null,
    version_tag text null,
    version text null,
    project_id uuid null,
    start_date timestamp without time zone null,
    end_date timestamp without time zone null,
    due_date timestamp without time zone null,
    updated_at timestamp with time zone default now(),
    is_deleted boolean not null default false,
    deleted_at timestamp with time zone null,
    is_clean_up boolean not null default false,
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
    version_tag text null,
    version text null,
    activity_id text null,
    activity_name text null,
    start_date timestamp without time zone null,
    end_date timestamp without time zone null,
    status todo_status null,
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
    agent_mode agent_mode null,
    agent_orch text null,
    feedback jsonb null,
    draft_status draft_status null,
    updated_at timestamp with time zone default now(),
    temp_feedback text null,
    output_url text null,
    rework_count integer null default 0,
    query text null,
    feedback_status text null,
    constraint todolist_pkey primary key (id),
    constraint todolist_tenant_id_fkey foreign key (tenant_id) references tenants (id) on update cascade on delete cascade
) tablespace pg_default;


DO $$ BEGIN
  CREATE TYPE delegation_status AS ENUM ('REQUESTED', 'ACCEPTED', 'REJECTED', 'COMPLETED');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

create table if not exists public.delegation_history (
    id uuid not null default uuid_generate_v4(),
    task_id uuid not null,
    from_user_id text not null,
    from_username text null,
    to_user_id text not null,
    to_username text null,
    reason text null,
    status delegation_status not null default 'COMPLETED',
    created_at timestamp with time zone not null default now(),
    responded_at timestamp with time zone null,
    tenant_id text null default public.tenant_id(),
    constraint delegation_history_pkey primary key (id),
    constraint delegation_history_task_id_fkey foreign key (task_id) references todolist (id) on update cascade on delete cascade,
    constraint delegation_history_tenant_id_fkey foreign key (tenant_id) references tenants (id) on update cascade on delete cascade
) tablespace pg_default;

create index if not exists idx_delegation_history_task_id on public.delegation_history (task_id);
create index if not exists idx_delegation_history_tenant_id on public.delegation_history (tenant_id);

create table if not exists public.chat_rooms (
    id text not null,
    participants jsonb not null,
    message jsonb null,
    name text null,
    primary_agent_id text null,
    tenant_id text null default public.tenant_id(),
    context jsonb null,
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
    deployable boolean not null default false,
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
    fields_json jsonb null,
    author_uid text null,
    constraint form_def_marketplace_pkey primary key (uuid)
) tablespace pg_default;

create table if not exists public.tenant_oauth (
    tenant_id text not null,
    client_id text not null,
    client_secret text not null,
    redirect_uri text null,
    drive_folder_id text null,
    created_at timestamp with time zone null default now(),
    updated_at timestamp with time zone null default now(),
    google_credentials jsonb null,
    google_credentials_updated_at timestamp with time zone null,
    github_token text null,
    github_username text null,
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

-- 내부 지식공간 파일 메타/상태 (Drive 인덱싱 + 추후 직접 업로드 공통 관리)
create table if not exists public.knowledge_files (
    id uuid primary key default uuid_generate_v4(),
    tenant_id text not null,
    source_type text not null,           -- 'drive' | 'upload' | (future: 'sharepoint' 등)
    source_ref text not null,            -- drive: file_id, upload: storage path
    file_name text not null,
    folder_path text null,               -- 표시용 폴더 경로 (e.g. "회사정책/2026")
    drive_folder_id text null,           -- (옵션) Drive 부모 폴더 id
    mime_type text null,
    size_bytes bigint null,
    modified_time timestamptz null,      -- 원본의 최종 수정 시각
    owner text null,                     -- 원본 소유자 표시 (drive: 드라이브 소유자)
    uploaded_by_uid text null,           -- 직접 업로드한 사용자 uid (upload 소스)
    uploaded_by_name text null,          -- 직접 업로드한 사용자 표시명
    file_hash char(64) null,             -- SHA-256 (hex). 동일 테넌트 내 중복 업로드 감지용
    index_status text not null default 'pending',
    index_error text null,
    indexed_at timestamptz null,
    -- 자료 역할(doc_role) — 에이전트가 자료를 어떻게 활용할지 결정
    --   content   : 일반 검색·요약 대상 (기본값)
    --   glossary  : 용어 사전 — 답변 작성 시 컨텍스트로 자동 주입
    --   template  : 보고서·계약서 양식 — DOCX 생성 시 양식으로 활용
    --   reference : 법령·표준 등 참조 자료 — 인용 시 우선
    --   dataset   : 정량 분석 대상(엑셀/CSV) — data-analyst 서브에이전트가 코드 실행으로 처리
    doc_role text not null default 'content',
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint knowledge_files_unique_source unique (tenant_id, source_type, source_ref),
    constraint knowledge_files_tenant_fk foreign key (tenant_id)
        references public.tenants (id) on update cascade on delete cascade,
    constraint knowledge_files_status_check check (
        index_status in ('pending', 'processing', 'indexed', 'failed', 'excluded')
    ),
    constraint knowledge_files_role_check check (
        doc_role in ('content', 'glossary', 'template', 'reference', 'dataset')
    )
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
  event_type event_type_enum not null,
  status event_status null,
  crew_type text null,
  data jsonb not null,
  tenant_id text null default public.tenant_id(),
  timestamp timestamp with time zone null default now(),
  constraint events_pkey primary key (id)
) TABLESPACE pg_default;

-- 이벤트 조회(분기 판단 이력 포함)에 쓰이는 인덱스
create index if not exists idx_events_proc_inst_id on public.events (proc_inst_id);
create index if not exists idx_events_todo_id on public.events (todo_id);
create index if not exists idx_events_tenant_id on public.events (tenant_id);
create index if not exists idx_events_event_type on public.events (event_type);

create or replace function match_documents(
  query_embedding vector(1536),
  filter jsonb default '{}'::jsonb,
  match_count int default 5
)
returns table (
  id uuid,
  content text,
  metadata jsonb,
  similarity float
)
language sql
as $$
  select
    documents.id,
    documents.content,
    documents.metadata,
    1 - (documents.embedding <=> query_embedding) as similarity
  from documents
  where documents.metadata @> filter
  order by documents.embedding <=> query_embedding
  limit match_count;
$$;


------------------ 결제시스템 ---------------------------
-- payment(결제 이력)
CREATE TABLE IF NOT EXISTS public.payment (
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
CREATE TABLE IF NOT EXISTS public.service (
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
CREATE TABLE IF NOT EXISTS public.usage (
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
CREATE INDEX IF NOT EXISTS idx_usage_service_id      ON public.usage(service_id);
CREATE INDEX IF NOT EXISTS idx_usage_process_def_id  ON public.usage(process_def_id);
CREATE INDEX IF NOT EXISTS idx_usage_process_inst_id ON public.usage(process_inst_id);
CREATE INDEX IF NOT EXISTS idx_usage_tenant_master_date ON public.usage (tenant_id, service_id, usage_start_at);


-- credit(크레딧 정의)
CREATE TABLE IF NOT EXISTS public.credit (
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
CREATE TABLE IF NOT EXISTS public.credit_purchase (
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
CREATE TABLE IF NOT EXISTS public.credit_usage (
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

create index if not exists idx_knowledge_files_tenant on public.knowledge_files using btree (tenant_id) tablespace pg_default;
create index if not exists idx_knowledge_files_tenant_status on public.knowledge_files using btree (tenant_id, index_status) tablespace pg_default;
create index if not exists idx_knowledge_files_tenant_folder on public.knowledge_files using btree (tenant_id, folder_path) tablespace pg_default;
create index if not exists idx_knowledge_files_tenant_source on public.knowledge_files using btree (tenant_id, source_type) tablespace pg_default;
create index if not exists idx_knowledge_files_tenant_hash on public.knowledge_files using btree (tenant_id, file_hash) tablespace pg_default where file_hash is not null;

-- 빈 폴더 영속화 (업로드 트리 구조 유지)
create table if not exists public.knowledge_folders (
    id uuid primary key default uuid_generate_v4(),
    tenant_id text not null,
    folder_path text not null,
    doc_role text not null default 'content',  -- 폴더가 속한 자료 역할 (knowledge_files.doc_role 와 동일 의미)
    created_at timestamptz not null default now(),
    constraint knowledge_folders_unique unique (tenant_id, doc_role, folder_path),
    constraint knowledge_folders_tenant_fk foreign key (tenant_id)
        references public.tenants (id) on update cascade on delete cascade,
    constraint knowledge_folders_role_check check (
        doc_role in ('content', 'glossary', 'template', 'reference', 'dataset')
    )
) tablespace pg_default;

create index if not exists idx_knowledge_folders_tenant on public.knowledge_folders using btree (tenant_id) tablespace pg_default;
create index if not exists idx_knowledge_folders_tenant_role on public.knowledge_folders using btree (tenant_id, doc_role) tablespace pg_default;

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

CREATE OR REPLACE FUNCTION public.delegate_super_admin(
    p_new_super_admin_id uuid,
    p_tenant_id text default public.tenant_id()
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_current_user_id uuid;
    v_current_role text;
    v_target_exists boolean;
BEGIN
    v_current_user_id := auth.uid();
    IF v_current_user_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Unauthorized');
    END IF;

    SELECT role
      INTO v_current_role
      FROM public.users
     WHERE id = v_current_user_id
       AND tenant_id = p_tenant_id
     LIMIT 1;

    IF COALESCE(v_current_role, '') <> 'superAdmin' THEN
        RETURN jsonb_build_object('success', false, 'error', 'Only superAdmin can delegate');
    END IF;

    IF p_new_super_admin_id = v_current_user_id THEN
        RETURN jsonb_build_object('success', false, 'error', 'Cannot delegate to yourself');
    END IF;

    SELECT EXISTS (
        SELECT 1
          FROM public.users
         WHERE id = p_new_super_admin_id
           AND tenant_id = p_tenant_id
           AND is_agent = false
    ) INTO v_target_exists;

    IF NOT v_target_exists THEN
        RETURN jsonb_build_object('success', false, 'error', 'Target user not found');
    END IF;

    UPDATE public.users
       SET role = 'superAdmin',
           is_admin = true
     WHERE id = p_new_super_admin_id
       AND tenant_id = p_tenant_id;

    UPDATE public.users
       SET role = 'admin',
           is_admin = true
     WHERE id = v_current_user_id
       AND tenant_id = p_tenant_id;

    UPDATE public.tenants
       SET owner = p_new_super_admin_id
     WHERE id = p_tenant_id;

    RETURN jsonb_build_object(
        'success', true,
        'tenant_id', p_tenant_id,
        'new_super_admin_id', p_new_super_admin_id,
        'previous_super_admin_id', v_current_user_id
    );
EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION public.delegate_super_admin(uuid, text) TO authenticated;

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


DROP FUNCTION IF EXISTS public.duplicate_definition_from_marketplace(text, text, text, text);

CREATE OR REPLACE FUNCTION duplicate_definition_from_marketplace(
    p_definition_id   TEXT,
    p_definition_name TEXT,
    p_author_uid      TEXT,
    p_tenant_id       TEXT
)
RETURNS JSONB AS $$
DECLARE
    v_proc_def_record   RECORD;
    v_form_def_record   RECORD;
    v_result            JSONB := '{}';
    v_proc_def_uuid     UUID;
    v_form_def_uuid     UUID;
    v_new_definition_id TEXT;
    v_new_definition    JSONB;
    v_activities        JSONB;
    v_activity          JSONB;
    v_tool              TEXT;
    v_form_id           TEXT;
BEGIN
    -- 프로세스 정의 조회
    SELECT *
      INTO v_proc_def_record
      FROM proc_def_marketplace
     WHERE id = p_definition_id
       AND name = p_definition_name;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('error', 'Process definition not found in marketplace');
    END IF;

    -- 새로운 정의 ID 생성 (기존 ID + UUID)
    v_new_definition_id := p_definition_id || '_' || gen_random_uuid()::TEXT;

    -- definition JSON에서 processDefinitionId 업데이트
    v_new_definition := v_proc_def_record.definition;
    v_new_definition := jsonb_set(
        v_new_definition,
        '{processDefinitionId}',
        to_jsonb(v_new_definition_id)
    );

    -- activities 배열 캐싱
    v_activities := COALESCE(v_new_definition->'activities', '[]'::jsonb);

    -- proc_def 에 복사
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
        name       = EXCLUDED.name,
        definition = EXCLUDED.definition,
        bpmn       = EXCLUDED.bpmn
    RETURNING uuid INTO v_proc_def_uuid;

    -- form_def_marketplace → form_def 복사
    FOR v_form_def_record IN
        SELECT *
          FROM form_def_marketplace
         WHERE proc_def_id = p_definition_id
           AND author_uid  = p_author_uid
    LOOP
        -- definition JSON 에서 해당 activity 를 찾아 tool 기반으로 formId 계산
        SELECT elem
          INTO v_activity
          FROM jsonb_array_elements(v_activities) AS elem
         WHERE elem->>'id' = v_form_def_record.activity_id
         LIMIT 1;

        IF v_activity IS NOT NULL
           AND v_activity ? 'tool'
           AND v_activity->>'tool' LIKE 'formHandler:%' THEN
            v_tool    := v_activity->>'tool';
            v_form_id := split_part(v_tool, 'formHandler:', 2);
        ELSE
            -- tool 정보가 없으면 기존 id 사용 (fallback)
            v_form_id := v_form_def_record.id;
        END IF;

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
            v_form_id,
            NULL
        )
        ON CONFLICT (id, tenant_id) DO UPDATE SET
            html        = EXCLUDED.html,
            proc_def_id = EXCLUDED.proc_def_id,
            activity_id = EXCLUDED.activity_id
        RETURNING uuid INTO v_form_def_uuid;
    END LOOP;

    -- import_count 증가
    UPDATE proc_def_marketplace
       SET import_count = import_count + 1
     WHERE id   = p_definition_id
       AND name = p_definition_name;

    v_result := jsonb_build_object(
        'success',          true,
        'proc_def_uuid',    v_proc_def_uuid,
        'new_definition_id', v_new_definition_id,
        'message',          'Definition duplicated successfully'
    );

    RETURN v_result;

EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'error',   SQLERRM,
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
-- (DROP TRIGGER IF EXISTS 선행: init.sql은 CREATE OR REPLACE FUNCTION/
--  IF NOT EXISTS 위주로 이미 재실행 안전하게 작성되어 있으나 트리거만
--  예외였음 — 이미 초기화된 DB에 스키마 변경분을 재적용할 때
--  "trigger already exists"로 실패하지 않도록 통일)
DROP TRIGGER IF EXISTS trigger_update_project_updated_at ON public.bpm_proc_inst;
CREATE TRIGGER trigger_update_project_updated_at
    AFTER UPDATE OF updated_at ON public.bpm_proc_inst
    FOR EACH ROW
    EXECUTE FUNCTION update_project_updated_at();

DROP TRIGGER IF EXISTS trigger_update_bpm_proc_inst_updated_at ON public.todolist;
CREATE TRIGGER trigger_update_bpm_proc_inst_updated_at
    AFTER UPDATE ON public.todolist
    FOR EACH ROW
    EXECUTE FUNCTION update_bpm_proc_inst_updated_at();

DROP TRIGGER IF EXISTS set_updated_at ON public.todolist;
CREATE TRIGGER set_updated_at
    BEFORE UPDATE ON public.todolist
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS set_updated_at ON public.knowledge_files;
CREATE TRIGGER set_updated_at
    BEFORE UPDATE ON public.knowledge_files
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS before_insert_user_permissions ON public.user_permissions;
CREATE TRIGGER before_insert_user_permissions
    BEFORE INSERT ON public.user_permissions
    FOR EACH ROW
    EXECUTE FUNCTION set_user_permissions_id();

DROP TRIGGER IF EXISTS on_first_tenant_inserted ON public.tenants;
CREATE TRIGGER on_first_tenant_inserted
    AFTER INSERT ON public.tenants
    FOR EACH ROW
    EXECUTE PROCEDURE public.update_tenant_id_for_first_tenant();

DROP TRIGGER IF EXISTS todolist_change_trigger ON todolist;
CREATE TRIGGER todolist_change_trigger
    AFTER INSERT OR UPDATE ON todolist
    FOR EACH ROW
    EXECUTE FUNCTION handle_todolist_change();

DROP TRIGGER IF EXISTS update_user_id_trigger ON todolist;
CREATE TRIGGER update_user_id_trigger
    AFTER UPDATE ON todolist
    FOR EACH ROW
    WHEN (OLD.user_id IS DISTINCT FROM NEW.user_id)
    EXECUTE FUNCTION update_notification_user_id();

DROP TRIGGER IF EXISTS delete_notification_trigger ON todolist;
CREATE TRIGGER delete_notification_trigger
    AFTER DELETE ON todolist
    FOR EACH ROW
    EXECUTE FUNCTION delete_notification_on_todolist_delete();

DROP TRIGGER IF EXISTS chat_insert_trigger ON public.chats;
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
ALTER TABLE proc_def_version ENABLE ROW LEVEL SECURITY;
ALTER TABLE form_def ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE lock ENABLE ROW LEVEL SECURITY;
ALTER TABLE bpm_proc_inst ENABLE ROW LEVEL SECURITY;
ALTER TABLE todolist ENABLE ROW LEVEL SECURITY;
ALTER TABLE delegation_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE chat_rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE chats ENABLE ROW LEVEL SECURITY;
ALTER TABLE calendar ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE proc_def_marketplace ENABLE ROW LEVEL SECURITY;
ALTER TABLE form_def_marketplace ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenant_oauth ENABLE ROW LEVEL SECURITY;
ALTER TABLE knowledge_files ENABLE ROW LEVEL SECURITY;
ALTER TABLE knowledge_folders ENABLE ROW LEVEL SECURITY;

-- Create RLS policies
-- Tenants policies
DROP POLICY IF EXISTS tenants_insert_policy ON tenants;
CREATE POLICY tenants_insert_policy ON tenants FOR INSERT TO authenticated WITH CHECK (true);
DROP POLICY IF EXISTS tenants_select_policy ON tenants;
CREATE POLICY tenants_select_policy ON tenants FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS tenants_update_policy ON tenants;
CREATE POLICY tenants_update_policy ON tenants FOR UPDATE TO authenticated USING (auth.uid() = owner);
DROP POLICY IF EXISTS tenants_delete_policy ON tenants;
CREATE POLICY tenants_delete_policy ON tenants FOR DELETE TO authenticated USING (auth.uid() = owner);

-- Users policies
DROP POLICY IF EXISTS users_insert_policy ON users;
CREATE POLICY users_insert_policy ON users FOR INSERT TO authenticated WITH CHECK (true);
DROP POLICY IF EXISTS users_select_policy ON users;
CREATE POLICY users_select_policy ON users FOR SELECT TO public USING (true);
DROP POLICY IF EXISTS users_update_policy ON users;
CREATE POLICY users_update_policy ON users FOR UPDATE TO public USING (EXISTS (SELECT 1 FROM users WHERE users.id = auth.uid() AND users.is_admin = true) OR auth.uid() = id) WITH CHECK (true);
DROP POLICY IF EXISTS users_delete_policy ON users;
CREATE POLICY users_delete_policy ON users FOR DELETE TO authenticated USING (public.tenant_id() = tenant_id);

-- Configuration policies
DROP POLICY IF EXISTS configuration_insert_policy ON configuration;
CREATE POLICY configuration_insert_policy ON configuration FOR INSERT TO authenticated WITH CHECK (tenant_id = public.tenant_id());
DROP POLICY IF EXISTS configuration_select_policy ON configuration;
CREATE POLICY configuration_select_policy ON configuration FOR SELECT TO authenticated USING (tenant_id = public.tenant_id());
DROP POLICY IF EXISTS configuration_update_policy ON configuration;
CREATE POLICY configuration_update_policy ON configuration FOR UPDATE TO authenticated USING (tenant_id = public.tenant_id());
DROP POLICY IF EXISTS configuration_delete_policy ON configuration;
CREATE POLICY configuration_delete_policy ON configuration FOR DELETE TO authenticated USING ((tenant_id = public.tenant_id()) AND (EXISTS (SELECT 1 FROM users WHERE users.id = auth.uid() AND users.is_admin = true)));

-- Proc map history policies
DROP POLICY IF EXISTS proc_map_history_insert_policy ON proc_map_history;
CREATE POLICY proc_map_history_insert_policy ON proc_map_history FOR INSERT TO authenticated WITH CHECK (tenant_id = public.tenant_id());
DROP POLICY IF EXISTS proc_map_history_select_policy ON proc_map_history;
CREATE POLICY proc_map_history_select_policy ON proc_map_history FOR SELECT TO authenticated USING (tenant_id = public.tenant_id());
DROP POLICY IF EXISTS proc_map_history_update_policy ON proc_map_history;
CREATE POLICY proc_map_history_update_policy ON proc_map_history FOR UPDATE TO authenticated USING (tenant_id = public.tenant_id());
DROP POLICY IF EXISTS proc_map_history_delete_policy ON proc_map_history;
CREATE POLICY proc_map_history_delete_policy ON proc_map_history FOR DELETE TO authenticated USING (tenant_id = public.tenant_id());

-- Proc def policies
DROP POLICY IF EXISTS proc_def_insert_policy ON proc_def;
CREATE POLICY proc_def_insert_policy ON proc_def FOR INSERT TO authenticated WITH CHECK ((tenant_id = public.tenant_id()) AND (EXISTS (SELECT 1 FROM users WHERE users.id = auth.uid() AND users.is_admin = true)));
DROP POLICY IF EXISTS proc_def_select_policy ON proc_def;
CREATE POLICY proc_def_select_policy ON proc_def FOR SELECT TO authenticated USING (tenant_id = public.tenant_id());
DROP POLICY IF EXISTS proc_def_update_policy ON proc_def;
CREATE POLICY proc_def_update_policy ON proc_def FOR UPDATE TO authenticated USING ((tenant_id = public.tenant_id()) AND (EXISTS (SELECT 1 FROM users WHERE users.id = auth.uid() AND users.is_admin = true)));
DROP POLICY IF EXISTS proc_def_delete_policy ON proc_def;
CREATE POLICY proc_def_delete_policy ON proc_def FOR DELETE TO authenticated USING ((tenant_id = public.tenant_id()) AND (EXISTS (SELECT 1 FROM users WHERE users.id = auth.uid() AND users.is_admin = true)));

DROP POLICY IF EXISTS proc_def_arcv_insert_policy ON proc_def_arcv;
CREATE POLICY proc_def_arcv_insert_policy ON proc_def_arcv FOR INSERT TO authenticated WITH CHECK (tenant_id = public.tenant_id());
DROP POLICY IF EXISTS proc_def_arcv_select_policy ON proc_def_arcv;
CREATE POLICY proc_def_arcv_select_policy ON proc_def_arcv FOR SELECT TO authenticated USING (tenant_id = public.tenant_id());
DROP POLICY IF EXISTS proc_def_arcv_update_policy ON proc_def_arcv;
CREATE POLICY proc_def_arcv_update_policy ON proc_def_arcv FOR UPDATE TO authenticated USING (tenant_id = public.tenant_id());
DROP POLICY IF EXISTS proc_def_arcv_delete_policy ON proc_def_arcv;
CREATE POLICY proc_def_arcv_delete_policy ON proc_def_arcv FOR DELETE TO authenticated USING (tenant_id = public.tenant_id());

-- Proc def version policies
DROP POLICY IF EXISTS proc_def_version_insert_policy ON proc_def_version;
CREATE POLICY proc_def_version_insert_policy ON proc_def_version FOR INSERT TO authenticated WITH CHECK (tenant_id = public.tenant_id());
DROP POLICY IF EXISTS proc_def_version_select_policy ON proc_def_version;
CREATE POLICY proc_def_version_select_policy ON proc_def_version FOR SELECT TO authenticated USING (tenant_id = public.tenant_id());
DROP POLICY IF EXISTS proc_def_version_update_policy ON proc_def_version;
CREATE POLICY proc_def_version_update_policy ON proc_def_version FOR UPDATE TO authenticated USING (tenant_id = public.tenant_id());
DROP POLICY IF EXISTS proc_def_version_delete_policy ON proc_def_version;
CREATE POLICY proc_def_version_delete_policy ON proc_def_version FOR DELETE TO authenticated USING (tenant_id = public.tenant_id());

-- Form def policies
DROP POLICY IF EXISTS form_def_insert_policy ON form_def;
CREATE POLICY form_def_insert_policy ON form_def FOR INSERT TO authenticated WITH CHECK (EXISTS (SELECT 1 FROM users WHERE users.id = auth.uid() AND users.is_admin = true));
DROP POLICY IF EXISTS form_def_select_policy ON form_def;
CREATE POLICY form_def_select_policy ON form_def FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS form_def_update_policy ON form_def;
CREATE POLICY form_def_update_policy ON form_def FOR UPDATE TO authenticated USING (EXISTS (SELECT 1 FROM users WHERE users.id = auth.uid() AND users.is_admin = true));
DROP POLICY IF EXISTS form_def_delete_policy ON form_def;
CREATE POLICY form_def_delete_policy ON form_def FOR DELETE TO authenticated USING (EXISTS (SELECT 1 FROM users WHERE users.id = auth.uid() AND users.is_admin = true));

-- Notifications policies
DROP POLICY IF EXISTS notifications_insert_policy ON notifications;
CREATE POLICY notifications_insert_policy ON notifications FOR INSERT TO authenticated WITH CHECK (tenant_id = public.tenant_id());
DROP POLICY IF EXISTS notifications_select_policy ON notifications;
CREATE POLICY notifications_select_policy ON notifications FOR SELECT TO authenticated USING (tenant_id = public.tenant_id());
DROP POLICY IF EXISTS notifications_update_policy ON notifications;
CREATE POLICY notifications_update_policy ON notifications FOR UPDATE TO authenticated USING (tenant_id = public.tenant_id());
DROP POLICY IF EXISTS notifications_delete_policy ON notifications;
CREATE POLICY notifications_delete_policy ON notifications FOR DELETE TO authenticated USING (tenant_id = public.tenant_id());

-- Lock policies
DROP POLICY IF EXISTS lock_insert_policy ON lock;
CREATE POLICY lock_insert_policy ON lock FOR INSERT TO authenticated WITH CHECK (EXISTS (SELECT 1 FROM users WHERE users.id = auth.uid() AND users.is_admin = true));
DROP POLICY IF EXISTS lock_select_policy ON lock;
CREATE POLICY lock_select_policy ON lock FOR SELECT TO authenticated USING (tenant_id = public.tenant_id());
DROP POLICY IF EXISTS lock_update_policy ON lock;
CREATE POLICY lock_update_policy ON lock FOR UPDATE TO authenticated USING (EXISTS (SELECT 1 FROM users WHERE users.id = auth.uid() AND users.is_admin = true));
DROP POLICY IF EXISTS lock_delete_policy ON lock;
CREATE POLICY lock_delete_policy ON lock FOR DELETE TO authenticated USING (EXISTS (SELECT 1 FROM users WHERE users.id = auth.uid() AND users.is_admin = true));

-- BPM proc inst policies
DROP POLICY IF EXISTS bpm_proc_inst_insert_policy ON bpm_proc_inst;
CREATE POLICY bpm_proc_inst_insert_policy ON bpm_proc_inst FOR INSERT TO authenticated WITH CHECK ((tenant_id = public.tenant_id()) AND (EXISTS (SELECT 1 FROM users WHERE users.id = auth.uid() AND users.is_admin = true)));
DROP POLICY IF EXISTS bpm_proc_inst_select_policy ON bpm_proc_inst;
CREATE POLICY bpm_proc_inst_select_policy ON bpm_proc_inst FOR SELECT TO authenticated USING (tenant_id = public.tenant_id());
DROP POLICY IF EXISTS bpm_proc_inst_update_policy ON bpm_proc_inst;
CREATE POLICY bpm_proc_inst_update_policy ON bpm_proc_inst FOR UPDATE TO authenticated USING ((tenant_id = public.tenant_id()) AND (EXISTS (SELECT 1 FROM users WHERE users.id = auth.uid() AND users.is_admin = true)));
DROP POLICY IF EXISTS bpm_proc_inst_delete_policy ON bpm_proc_inst;
CREATE POLICY bpm_proc_inst_delete_policy ON bpm_proc_inst FOR DELETE TO authenticated USING ((tenant_id = public.tenant_id()) AND (EXISTS (SELECT 1 FROM users WHERE users.id = auth.uid() AND users.is_admin = true)));

-- Todolist policies
DROP POLICY IF EXISTS todolist_insert_policy ON todolist;
CREATE POLICY todolist_insert_policy ON todolist FOR INSERT TO authenticated WITH CHECK (tenant_id = public.tenant_id());
DROP POLICY IF EXISTS todolist_select_policy ON todolist;
CREATE POLICY todolist_select_policy ON todolist FOR SELECT TO authenticated USING (tenant_id = public.tenant_id());
DROP POLICY IF EXISTS todolist_update_policy ON todolist;
CREATE POLICY todolist_update_policy ON todolist FOR UPDATE TO authenticated USING (tenant_id = public.tenant_id());
DROP POLICY IF EXISTS todolist_delete_policy ON todolist;
CREATE POLICY todolist_delete_policy ON todolist FOR DELETE TO authenticated USING (tenant_id = public.tenant_id());

-- Delegation history policies
DROP POLICY IF EXISTS delegation_history_insert_policy ON delegation_history;
CREATE POLICY delegation_history_insert_policy ON delegation_history FOR INSERT TO authenticated WITH CHECK (tenant_id = public.tenant_id());
DROP POLICY IF EXISTS delegation_history_select_policy ON delegation_history;
CREATE POLICY delegation_history_select_policy ON delegation_history FOR SELECT TO authenticated USING (tenant_id = public.tenant_id());
DROP POLICY IF EXISTS delegation_history_update_policy ON delegation_history;
CREATE POLICY delegation_history_update_policy ON delegation_history FOR UPDATE TO authenticated USING (tenant_id = public.tenant_id());
DROP POLICY IF EXISTS delegation_history_delete_policy ON delegation_history;
CREATE POLICY delegation_history_delete_policy ON delegation_history FOR DELETE TO authenticated USING (tenant_id = public.tenant_id());

-- Chat rooms policies
DROP POLICY IF EXISTS chat_rooms_insert_policy ON chat_rooms;
CREATE POLICY chat_rooms_insert_policy ON chat_rooms FOR INSERT TO authenticated WITH CHECK (tenant_id = public.tenant_id());
DROP POLICY IF EXISTS chat_rooms_select_policy ON chat_rooms;
CREATE POLICY chat_rooms_select_policy ON chat_rooms FOR SELECT TO authenticated USING (tenant_id = public.tenant_id());
DROP POLICY IF EXISTS chat_rooms_update_policy ON chat_rooms;
CREATE POLICY chat_rooms_update_policy ON chat_rooms FOR UPDATE TO authenticated USING (tenant_id = public.tenant_id());
DROP POLICY IF EXISTS chat_rooms_delete_policy ON chat_rooms;
CREATE POLICY chat_rooms_delete_policy ON chat_rooms FOR DELETE TO authenticated USING (tenant_id = public.tenant_id());

-- Chats policies
DROP POLICY IF EXISTS chats_insert_policy ON chats;
CREATE POLICY chats_insert_policy ON chats FOR INSERT TO authenticated WITH CHECK (tenant_id = public.tenant_id());
DROP POLICY IF EXISTS chats_select_policy ON chats;
CREATE POLICY chats_select_policy ON chats FOR SELECT TO authenticated USING (tenant_id = public.tenant_id());
DROP POLICY IF EXISTS chats_update_policy ON chats;
CREATE POLICY chats_update_policy ON chats FOR UPDATE TO authenticated USING (tenant_id = public.tenant_id());
DROP POLICY IF EXISTS chats_delete_policy ON chats;
CREATE POLICY chats_delete_policy ON chats FOR DELETE TO authenticated USING (tenant_id = public.tenant_id());

-- Calendar policies
DROP POLICY IF EXISTS calendar_insert_policy ON calendar;
CREATE POLICY calendar_insert_policy ON calendar FOR INSERT TO authenticated WITH CHECK (tenant_id = public.tenant_id());
DROP POLICY IF EXISTS calendar_select_policy ON calendar;
CREATE POLICY calendar_select_policy ON calendar FOR SELECT TO authenticated USING (tenant_id = public.tenant_id());
DROP POLICY IF EXISTS calendar_update_policy ON calendar;
CREATE POLICY calendar_update_policy ON calendar FOR UPDATE TO authenticated USING (tenant_id = public.tenant_id());
DROP POLICY IF EXISTS calendar_delete_policy ON calendar;
CREATE POLICY calendar_delete_policy ON calendar FOR DELETE TO authenticated USING (tenant_id = public.tenant_id());

-- User permissions policies
DROP POLICY IF EXISTS user_permissions_insert_policy ON user_permissions;
CREATE POLICY user_permissions_insert_policy ON user_permissions FOR INSERT TO authenticated WITH CHECK (tenant_id = public.tenant_id());
DROP POLICY IF EXISTS user_permissions_select_policy ON user_permissions;
CREATE POLICY user_permissions_select_policy ON user_permissions FOR SELECT TO authenticated USING (tenant_id = public.tenant_id());
DROP POLICY IF EXISTS user_permissions_update_policy ON user_permissions;
CREATE POLICY user_permissions_update_policy ON user_permissions FOR UPDATE TO authenticated USING (tenant_id = public.tenant_id());
DROP POLICY IF EXISTS user_permissions_delete_policy ON user_permissions;
CREATE POLICY user_permissions_delete_policy ON user_permissions FOR DELETE TO authenticated USING (tenant_id = public.tenant_id());

-- Proc def marketplace policies
DROP POLICY IF EXISTS proc_def_marketplace_insert_policy ON proc_def_marketplace;
CREATE POLICY proc_def_marketplace_insert_policy ON proc_def_marketplace FOR INSERT TO authenticated WITH CHECK (true);
DROP POLICY IF EXISTS proc_def_marketplace_select_policy ON proc_def_marketplace;
CREATE POLICY proc_def_marketplace_select_policy ON proc_def_marketplace FOR SELECT TO public USING (true);
DROP POLICY IF EXISTS proc_def_marketplace_update_policy ON proc_def_marketplace;
CREATE POLICY proc_def_marketplace_update_policy ON proc_def_marketplace FOR UPDATE TO authenticated USING (true);
DROP POLICY IF EXISTS proc_def_marketplace_delete_policy ON proc_def_marketplace;
CREATE POLICY proc_def_marketplace_delete_policy ON proc_def_marketplace FOR DELETE TO authenticated USING (true);

-- Form def marketplace policies
DROP POLICY IF EXISTS form_def_marketplace_insert_policy ON form_def_marketplace;
CREATE POLICY form_def_marketplace_insert_policy ON form_def_marketplace FOR INSERT TO authenticated WITH CHECK (true);
DROP POLICY IF EXISTS form_def_marketplace_select_policy ON form_def_marketplace;
CREATE POLICY form_def_marketplace_select_policy ON form_def_marketplace FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS form_def_marketplace_update_policy ON form_def_marketplace;
CREATE POLICY form_def_marketplace_update_policy ON form_def_marketplace FOR UPDATE TO authenticated USING (true);
DROP POLICY IF EXISTS form_def_marketplace_delete_policy ON form_def_marketplace;
CREATE POLICY form_def_marketplace_delete_policy ON form_def_marketplace FOR DELETE TO authenticated USING (true);

-- Tenant oauth policies
DROP POLICY IF EXISTS tenant_oauth_insert_policy ON tenant_oauth;
CREATE POLICY tenant_oauth_insert_policy ON tenant_oauth FOR INSERT TO authenticated WITH CHECK (EXISTS (SELECT 1 FROM users WHERE users.id = auth.uid() AND users.is_admin = true));
DROP POLICY IF EXISTS tenant_oauth_select_policy ON tenant_oauth;
CREATE POLICY tenant_oauth_select_policy ON tenant_oauth FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM users WHERE users.id = auth.uid() AND users.is_admin = true));
DROP POLICY IF EXISTS tenant_oauth_update_policy ON tenant_oauth;
CREATE POLICY tenant_oauth_update_policy ON tenant_oauth FOR UPDATE TO authenticated USING (EXISTS (SELECT 1 FROM users WHERE users.id = auth.uid() AND users.is_admin = true));
DROP POLICY IF EXISTS tenant_oauth_delete_policy ON tenant_oauth;
CREATE POLICY tenant_oauth_delete_policy ON tenant_oauth FOR DELETE TO authenticated USING (EXISTS (SELECT 1 FROM users WHERE users.id = auth.uid() AND users.is_admin = true));

-- Knowledge files policies (테넌트 단위 격리)
DROP POLICY IF EXISTS knowledge_files_select_policy ON knowledge_files;
CREATE POLICY knowledge_files_select_policy ON knowledge_files FOR SELECT TO authenticated USING (tenant_id = public.tenant_id());
DROP POLICY IF EXISTS knowledge_files_insert_policy ON knowledge_files;
CREATE POLICY knowledge_files_insert_policy ON knowledge_files FOR INSERT TO authenticated WITH CHECK (tenant_id = public.tenant_id());
DROP POLICY IF EXISTS knowledge_files_update_policy ON knowledge_files;
CREATE POLICY knowledge_files_update_policy ON knowledge_files FOR UPDATE TO authenticated USING (tenant_id = public.tenant_id());
DROP POLICY IF EXISTS knowledge_files_delete_policy ON knowledge_files;
CREATE POLICY knowledge_files_delete_policy ON knowledge_files FOR DELETE TO authenticated USING (tenant_id = public.tenant_id());

-- Knowledge folders policies
DROP POLICY IF EXISTS knowledge_folders_select_policy ON knowledge_folders;
CREATE POLICY knowledge_folders_select_policy ON knowledge_folders FOR SELECT TO authenticated USING (tenant_id = public.tenant_id());
DROP POLICY IF EXISTS knowledge_folders_insert_policy ON knowledge_folders;
CREATE POLICY knowledge_folders_insert_policy ON knowledge_folders FOR INSERT TO authenticated WITH CHECK (tenant_id = public.tenant_id());
DROP POLICY IF EXISTS knowledge_folders_update_policy ON knowledge_folders;
CREATE POLICY knowledge_folders_update_policy ON knowledge_folders FOR UPDATE TO authenticated USING (tenant_id = public.tenant_id());
DROP POLICY IF EXISTS knowledge_folders_delete_policy ON knowledge_folders;
CREATE POLICY knowledge_folders_delete_policy ON knowledge_folders FOR DELETE TO authenticated USING (tenant_id = public.tenant_id());

-- Storage policies
DROP POLICY IF EXISTS "Allow authenticated users to upload" ON storage.objects;
CREATE POLICY "Allow authenticated users to upload" ON storage.objects FOR INSERT WITH CHECK (auth.role() = 'authenticated');

-- Project policies
DROP POLICY IF EXISTS project_insert_policy ON project;
CREATE POLICY project_insert_policy ON project FOR INSERT TO authenticated WITH CHECK ((tenant_id = public.tenant_id()) AND (EXISTS (SELECT 1 FROM users WHERE users.id = auth.uid() AND users.is_admin = true)));
DROP POLICY IF EXISTS project_select_policy ON project;
CREATE POLICY project_select_policy ON project FOR SELECT TO authenticated USING (tenant_id = public.tenant_id());
DROP POLICY IF EXISTS project_update_policy ON project;
CREATE POLICY project_update_policy ON project FOR UPDATE TO authenticated USING ((tenant_id = public.tenant_id()) AND (EXISTS (SELECT 1 FROM users WHERE users.id = auth.uid() AND users.is_admin = true)));
DROP POLICY IF EXISTS project_delete_policy ON project;
CREATE POLICY project_delete_policy ON project FOR DELETE TO authenticated USING ((tenant_id = public.tenant_id()) AND (EXISTS (SELECT 1 FROM users WHERE users.id = auth.uid() AND users.is_admin = true)));

-- Enable Realtime for specific tables
DO $$ BEGIN
  alter publication supabase_realtime add table chats;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;
DO $$ BEGIN
  alter publication supabase_realtime add table notifications;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;
DO $$ BEGIN
  alter publication supabase_realtime add table todolist;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;
DO $$ BEGIN
  alter publication supabase_realtime add table bpm_proc_inst;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;
DO $$ BEGIN
  alter publication supabase_realtime add table proc_def;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;
DO $$ BEGIN
  alter publication supabase_realtime add table project;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;
DO $$ BEGIN
  alter publication supabase_realtime add table events;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;


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
drop trigger if exists cleanup_bpm_proc_inst_related_data_trigger on public.bpm_proc_inst;
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


create or replace function public.normalize_cron_expr_for_pg_cron(
  p_cron_expr text
)
returns table(normalized_expr text, target_year int)
language plpgsql
as $$
declare
  v_tokens text[];
  v_count int;
  v_dom text;
  v_dow text;
begin
  v_tokens := regexp_split_to_array(
    trim(regexp_replace(coalesce(p_cron_expr, ''), '\s+', ' ', 'g')),
    ' '
  );
  v_count := coalesce(array_length(v_tokens, 1), 0);

  if v_count = 5 then
    v_dom := replace(v_tokens[3], '?', '*');
    v_dow := replace(v_tokens[5], '?', '*');
    normalized_expr := format('%s %s %s %s %s', v_tokens[1], v_tokens[2], v_dom, v_tokens[4], v_dow);
    target_year := null;
    return next;
    return;
  end if;

  if v_count = 6 then
    v_dom := replace(v_tokens[4], '?', '*');
    v_dow := replace(v_tokens[6], '?', '*');
    normalized_expr := format('%s %s %s %s %s', v_tokens[2], v_tokens[3], v_dom, v_tokens[5], v_dow);
    target_year := null;
    return next;
    return;
  end if;

  if v_count = 7 then
    v_dom := replace(v_tokens[4], '?', '*');
    v_dow := replace(v_tokens[6], '?', '*');
    normalized_expr := format('%s %s %s %s %s', v_tokens[2], v_tokens[3], v_dom, v_tokens[5], v_dow);

    if v_tokens[7] ~ '^\d{4}$' then
      target_year := v_tokens[7]::int;
    elsif v_tokens[7] in ('*', '?') then
      target_year := null;
    else
      raise exception 'Unsupported 7th cron token(year): %', v_tokens[7];
    end if;

    return next;
    return;
  end if;

  raise exception 'Unsupported cron field count: %, expr=%', v_count, p_cron_expr;
end;
$$;


create or replace function public.update_todolist_status_with_year(
  p_proc_inst_id text,
  p_activity_id text,
  p_target_year int default null
)
returns void
language plpgsql
security definer
as $$
declare
  v_current_year int := extract(year from now())::int;
  v_job_name text := p_proc_inst_id || '_' || p_activity_id;
begin
  if p_target_year is not null then
    if v_current_year > p_target_year then
      -- 이미 지나간 연도인 경우 불필요 반복 실행 방지를 위해 잡 정리
      perform cron.unschedule(v_job_name);
      return;
    end if;

    if v_current_year < p_target_year then
      -- 대상 연도가 아니면 대기
      return;
    end if;
  end if;

  perform public.update_todolist_status(p_proc_inst_id, p_activity_id);
end;
$$;


create or replace function register_cron_intermidiated(
  p_job_name text,
  p_cron_expr text,
  p_input jsonb
)
returns void
language plpgsql
security definer
as $$
declare
  v_job_name text;
  v_normalized_cron_expr text;
  v_target_year int;
begin
  select normalized_expr, target_year
    into v_normalized_cron_expr, v_target_year
  from public.normalize_cron_expr_for_pg_cron(p_cron_expr);

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
    v_normalized_cron_expr,
    format(
      E'select public.update_todolist_status_with_year(''%s'', ''%s'', %s);',
      p_input->>'proc_inst_id',
      p_input->>'activity_id',
      coalesce(v_target_year::text, 'null')
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
security definer
as $$
declare
  v_job_name text := p_proc_inst_id || '_' || p_activity_id;
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




-- ==========================================
-- ENUM 타입 마이그레이션 쿼리
-- ==========================================
-- ※ 주의: 아래 마이그레이션 쿼리들은 해당 컬럼이 text 타입인 경우에만 실행하세요
-- 이미 enum 타입으로 변경된 경우에는 실행하지 마세요
--
-- ENUM 마이그레이션(재실행 안전)
-- - 이미 enum 타입이면 스킵 (뷰/트리거 등 의존성 때문에 DROP COLUMN이 터질 수 있음)
-- - 타입이 다르면 ALTER COLUMN TYPE ... USING 으로 변환
--
DO $$
DECLARE
  v_udt text;
BEGIN
  -- events.event_type -> event_type_enum
  SELECT udt_name INTO v_udt
  FROM information_schema.columns
  WHERE table_schema = 'public' AND table_name = 'events' AND column_name = 'event_type';

  IF v_udt IS NOT NULL AND v_udt <> 'event_type_enum' THEN
    EXECUTE $sql$
      ALTER TABLE public.events
        ALTER COLUMN event_type TYPE event_type_enum
        USING (
          CASE (event_type::text)
            WHEN 'task_started' THEN 'task_started'::event_type_enum
            WHEN 'task_completed' THEN 'task_completed'::event_type_enum
            WHEN 'tool_usage_started' THEN 'tool_usage_started'::event_type_enum
            WHEN 'tool_usage_finished' THEN 'tool_usage_finished'::event_type_enum
            WHEN 'crew_completed' THEN 'crew_completed'::event_type_enum
            WHEN 'human_asked' THEN 'human_asked'::event_type_enum
            WHEN 'human_response' THEN 'human_response'::event_type_enum
            ELSE NULL
          END
        )
    $sql$;
  END IF;

  -- events.status -> event_status
  SELECT udt_name INTO v_udt
  FROM information_schema.columns
  WHERE table_schema = 'public' AND table_name = 'events' AND column_name = 'status';

  IF v_udt IS NOT NULL AND v_udt <> 'event_status' THEN
    EXECUTE $sql$
      ALTER TABLE public.events
        ALTER COLUMN status TYPE event_status
        USING (
          CASE (status::text)
            WHEN 'ASKED' THEN 'ASKED'::event_status
            WHEN 'APPROVED' THEN 'APPROVED'::event_status
            WHEN 'REJECTED' THEN 'REJECTED'::event_status
            ELSE NULL
          END
        )
    $sql$;
  END IF;

  -- bpm_proc_inst.status -> process_status
  SELECT udt_name INTO v_udt
  FROM information_schema.columns
  WHERE table_schema = 'public' AND table_name = 'bpm_proc_inst' AND column_name = 'status';

  IF v_udt IS NOT NULL AND v_udt <> 'process_status' THEN
    EXECUTE $sql$
      ALTER TABLE public.bpm_proc_inst
        ALTER COLUMN status TYPE process_status
        USING (
          CASE (status::text)
            WHEN 'NEW' THEN 'NEW'::process_status
            WHEN 'RUNNING' THEN 'RUNNING'::process_status
            WHEN 'COMPLETED' THEN 'COMPLETED'::process_status
            ELSE 'NEW'::process_status
          END
        )
    $sql$;
  END IF;

  -- todolist.status -> todo_status
  SELECT udt_name INTO v_udt
  FROM information_schema.columns
  WHERE table_schema = 'public' AND table_name = 'todolist' AND column_name = 'status';

  IF v_udt IS NOT NULL AND v_udt <> 'todo_status' THEN
    EXECUTE $sql$
      ALTER TABLE public.todolist
        ALTER COLUMN status TYPE todo_status
        USING (
          CASE (status::text)
            WHEN 'NEW' THEN 'NEW'::todo_status
            WHEN 'TODO' THEN 'TODO'::todo_status
            WHEN 'IN_PROGRESS' THEN 'IN_PROGRESS'::todo_status
            WHEN 'DONE' THEN 'DONE'::todo_status
            WHEN 'SUBMITTED' THEN 'SUBMITTED'::todo_status
            WHEN 'PENDING' THEN 'PENDING'::todo_status
            WHEN 'CANCELLED' THEN 'CANCELLED'::todo_status
            ELSE 'TODO'::todo_status
          END
        )
    $sql$;
  END IF;

  -- todolist.agent_mode -> agent_mode
  SELECT udt_name INTO v_udt
  FROM information_schema.columns
  WHERE table_schema = 'public' AND table_name = 'todolist' AND column_name = 'agent_mode';

  IF v_udt IS NOT NULL AND v_udt <> 'agent_mode' THEN
    EXECUTE $sql$
      ALTER TABLE public.todolist
        ALTER COLUMN agent_mode TYPE agent_mode
        USING (
          CASE (agent_mode::text)
            WHEN 'DRAFT' THEN 'DRAFT'::agent_mode
            WHEN 'COMPLETE' THEN 'COMPLETE'::agent_mode
            ELSE NULL
          END
        )
    $sql$;
  END IF;

  -- todolist.draft_status -> draft_status
  SELECT udt_name INTO v_udt
  FROM information_schema.columns
  WHERE table_schema = 'public' AND table_name = 'todolist' AND column_name = 'draft_status';

  IF v_udt IS NOT NULL AND v_udt <> 'draft_status' THEN
    EXECUTE $sql$
      ALTER TABLE public.todolist
        ALTER COLUMN draft_status TYPE draft_status
        USING (
          CASE (draft_status::text)
            WHEN 'STARTED' THEN 'STARTED'::draft_status
            WHEN 'CANCELLED' THEN 'CANCELLED'::draft_status
            WHEN 'COMPLETED' THEN 'COMPLETED'::draft_status
            WHEN 'FB_REQUESTED' THEN 'FB_REQUESTED'::draft_status
            WHEN 'HUMAN_ASKED' THEN 'HUMAN_ASKED'::draft_status
            WHEN 'FAILED' THEN 'FAILED'::draft_status
            ELSE NULL
          END
        )
    $sql$;
  END IF;
END $$;



create table if not exists public.proc_inst_source (
    id uuid not null default gen_random_uuid (),
    proc_inst_id text null,
    file_name text null,
    created_at timestamp with time zone not null default now(),
    is_process boolean not null default false,
    file_path text null,
    file_id text null,
    constraint proc_inst_source_pkey primary key (id)
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





DROP FUNCTION IF EXISTS public.fetch_done_data(text);

CREATE OR REPLACE FUNCTION public.fetch_done_data(
  p_proc_inst_id text
)
RETURNS TABLE (
  output jsonb
)
LANGUAGE SQL
AS $$
  SELECT t.output
    FROM public.todolist AS t
   WHERE (t.root_proc_inst_id = p_proc_inst_id OR t.proc_inst_id = p_proc_inst_id)
     AND t.status = 'DONE'
     AND t.output IS NOT NULL
   ORDER BY t.start_date;
$$;

-- 3) 결과 저장 (중간/최종)
CREATE OR REPLACE FUNCTION public.save_task_result(
  p_todo_id uuid,
  p_payload jsonb,
  p_final   boolean
)
RETURNS void AS $$
DECLARE
  v_mode text;
BEGIN
  SELECT agent_mode
    INTO v_mode
    FROM todolist
   WHERE id = p_todo_id;

  IF p_final THEN
    IF v_mode = 'COMPLETE' THEN
      UPDATE todolist
         SET output       = p_payload,
             status       = 'SUBMITTED',
             draft_status = 'COMPLETED',
             consumer     = NULL
       WHERE id = p_todo_id;
    ELSE
      UPDATE todolist
         SET draft        = p_payload,
             draft_status = 'COMPLETED',
             consumer     = NULL
       WHERE id = p_todo_id;
    END IF;
  ELSE
    UPDATE todolist
       SET draft = p_payload
     WHERE id = p_todo_id;
  END IF;
END;
$$ LANGUAGE plpgsql VOLATILE;

-- 익명(anon) 역할에 실행 권한 부여
GRANT EXECUTE ON FUNCTION public.fetch_done_data(text) TO anon;
GRANT EXECUTE ON FUNCTION public.save_task_result(uuid, jsonb, boolean) TO anon;


DROP FUNCTION IF EXISTS public.openai_deep_fetch_pending_task(integer, text);

CREATE OR REPLACE FUNCTION public.openai_deep_fetch_pending_task(
  p_limit    integer,
  p_consumer text
)
RETURNS TABLE (
  id uuid,
  user_id text,
  proc_inst_id text,
  proc_def_id text,
  activity_id text,
  activity_name text,
  start_date timestamp without time zone,
  end_date timestamp without time zone,
  description text,
  tool text,
  due_date timestamp without time zone,
  tenant_id text,
  reference_ids text[],
  adhoc boolean,
  assignees jsonb,
  duration integer,
  output jsonb,
  retry integer,
  consumer text,
  log text,
  draft jsonb,
  project_id uuid,
  feedback jsonb,
  updated_at timestamp with time zone,
  username text,
  status public.todo_status,
  agent_mode public.agent_mode,
  agent_orch text,
  temp_feedback text,
  draft_status public.draft_status,
  -- 가상 컬럼(업데이트 전 값)
  task_type public.draft_status
) AS $$
BEGIN
  RETURN QUERY
    WITH cte AS (
      SELECT
        t.*,
        t.draft_status AS task_type   -- 원본 보관
      FROM todolist AS t
      WHERE t.status = 'IN_PROGRESS'
        AND t.agent_orch = 'openai-deep-research'
        AND (
          (t.agent_mode IN ('DRAFT','COMPLETE') AND t.draft IS NULL AND t.draft_status IS NULL)
          OR t.draft_status = 'FB_REQUESTED'
        )
      ORDER BY t.start_date
      LIMIT p_limit
      FOR UPDATE SKIP LOCKED
    ),
    upd AS (
      UPDATE todolist AS t
         SET draft_status = 'STARTED',
             consumer     = p_consumer
        FROM cte
       WHERE t.id = cte.id
       RETURNING
         t.id,
         t.user_id,
         t.proc_inst_id,
         t.proc_def_id,
         t.activity_id,
         t.activity_name,
         t.start_date,
         t.end_date,
         t.description,
         t.tool,
         t.due_date,
         t.tenant_id,
         t.reference_ids,
         t.adhoc,
         t.assignees,
         t.duration,
         t.output,
         t.retry,
         t.consumer,
         t.log,
         t.draft,
         t.project_id,
         t.feedback,
         t.updated_at,
         t.username,
         t.status,
         t.agent_mode,
         t.agent_orch,
         t.temp_feedback,
         t.draft_status,              -- 변경 후 값 (STARTED)
         cte.task_type      -- 변경 전 값
    )
    SELECT * FROM upd;
END;
$$ LANGUAGE plpgsql VOLATILE;

-- 익명(anon) 역할에 실행 권한 부여
GRANT EXECUTE ON FUNCTION public.openai_deep_fetch_pending_task(integer, text) TO anon;


-- ============================================================================
-- Deep Research Custom: RPC functions for polling
-- ============================================================================
DROP FUNCTION IF EXISTS public.deep_research_fetch_pending_task(text, text, integer);

CREATE OR REPLACE FUNCTION public.deep_research_fetch_pending_task(
  p_agent_orch text,
  p_consumer   text,
  p_limit      integer
)
RETURNS TABLE(
  id uuid,
  user_id text,
  proc_inst_id text,
  proc_def_id text,
  activity_id text,
  activity_name text,
  start_date timestamp without time zone,
  end_date timestamp without time zone,
  description text,
  tool text,
  due_date timestamp without time zone,
  tenant_id text,
  reference_ids text[],
  adhoc boolean,
  assignees jsonb,
  duration integer,
  output jsonb,
  retry integer,
  consumer text,
  log text,
  draft jsonb,
  project_id uuid,
  feedback jsonb,
  updated_at timestamp with time zone,
  username text,
  status public.todo_status,
  agent_mode public.agent_mode,
  agent_orch text,
  temp_feedback text,
  draft_status public.draft_status,
  query text,
  task_type public.draft_status
)
LANGUAGE plpgsql
AS $function$
BEGIN
  RETURN QUERY
    WITH cte AS (
      SELECT
        t.*,
        t.draft_status AS task_type
      FROM todolist AS t
      WHERE t.status = 'IN_PROGRESS'
        AND (p_agent_orch IS NULL OR p_agent_orch = '' OR t.agent_orch::text = p_agent_orch)
        AND (
          (t.agent_mode IN ('DRAFT','COMPLETE') AND t.draft IS NULL AND t.draft_status IS NULL)
          OR t.draft_status = 'FB_REQUESTED'
        )
      ORDER BY t.start_date
      LIMIT p_limit
      FOR UPDATE SKIP LOCKED
    ),
    upd AS (
      UPDATE todolist AS t
         SET draft_status = 'STARTED',
             consumer     = p_consumer
        FROM cte
       WHERE t.id = cte.id
       RETURNING
         t.id,
         t.user_id,
         t.proc_inst_id,
         t.proc_def_id,
         t.activity_id,
         t.activity_name,
         t.start_date,
         t.end_date,
         t.description,
         t.tool,
         t.due_date,
         t.tenant_id,
         t.reference_ids,
         t.adhoc,
         t.assignees,
         t.duration,
         t.output,
         t.retry,
         t.consumer,
         t.log,
         t.draft,
         t.project_id,
         t.feedback,
         t.updated_at,
         t.username,
         t.status,
         t.agent_mode::public.agent_mode,
         t.agent_orch,
         t.temp_feedback,
         t.draft_status,
         t.query,
         cte.task_type
    )
    SELECT * FROM upd;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.deep_research_fetch_pending_task(text, text, integer) TO anon;


DROP FUNCTION IF EXISTS public.fetch_pending_task(text, text, integer, text);

CREATE OR REPLACE FUNCTION public.fetch_pending_task(
  p_agent_orch text,
  p_consumer   text,
  p_limit      integer,
  p_env        text
)
RETURNS SETOF todolist
LANGUAGE plpgsql
VOLATILE
AS $$
BEGIN
  RETURN QUERY
    WITH cte AS (
      SELECT t.id
      FROM todolist AS t
      WHERE t.status = 'IN_PROGRESS'
        -- env 분기 제거됨
        -- agent_orch 필터(옵션)
        AND (p_agent_orch IS NULL OR p_agent_orch = '' OR t.agent_orch::text = p_agent_orch)
        -- 처리 대상 선택 로직
        AND (
          (t.agent_mode IN ('DRAFT','COMPLETE') AND t.draft IS NULL AND t.draft_status IS NULL)
          OR t.draft_status = 'FB_REQUESTED'
        )
      ORDER BY t.start_date
      LIMIT p_limit
      FOR UPDATE SKIP LOCKED
    ),
    upd AS (
      UPDATE todolist AS t
         SET draft_status = 'STARTED',
             consumer     = p_consumer
        FROM cte
       WHERE t.id = cte.id
       RETURNING t.*
    )
    SELECT * FROM upd;
END;
$$;


-- 익명(anon) 역할에 실행 권한 부여
GRANT EXECUTE ON FUNCTION public.fetch_pending_task(text, text, integer, text) TO anon;


CREATE TABLE IF NOT EXISTS env (
    key VARCHAR(255) NOT NULL,        -- 'browser_use'
    value TEXT,                       -- 시크릿 데이터 (JSON)
    tenant_id VARCHAR(255) PRIMARY KEY  -- 테넌트 ID
);


-- =============================================================================
-- Work Assistant MCP용 RLS 정책
-- MCP 도구에서 필요한 SELECT 권한만 부여
-- =============================================================================

-- proc_def (프로세스 정의) - SELECT
ALTER TABLE proc_def ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "work-assistant-proc_def_select_policy" ON proc_def;
CREATE POLICY "work-assistant-proc_def_select_policy" ON proc_def 
    FOR SELECT TO authenticated 
    USING (tenant_id = public.tenant_id());

-- form_def (폼 정의) - SELECT
ALTER TABLE form_def ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "work-assistant-form_def_select_policy" ON form_def;
CREATE POLICY "work-assistant-form_def_select_policy" ON form_def 
    FOR SELECT TO authenticated 
    USING (tenant_id = public.tenant_id());

-- bpm_proc_inst (프로세스 인스턴스) - SELECT
ALTER TABLE bpm_proc_inst ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "work-assistant-bpm_proc_inst_select_policy" ON bpm_proc_inst;
CREATE POLICY "work-assistant-bpm_proc_inst_select_policy" ON bpm_proc_inst 
    FOR SELECT TO authenticated 
    USING (tenant_id = public.tenant_id());

-- todolist (할 일 목록) - SELECT
ALTER TABLE todolist ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "work-assistant-todolist_select_policy" ON todolist;
CREATE POLICY "work-assistant-todolist_select_policy" ON todolist 
    FOR SELECT TO authenticated 
    USING (tenant_id = public.tenant_id());

-- configuration (설정/조직도) - SELECT
ALTER TABLE configuration ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "work-assistant-configuration_select_policy" ON configuration;
CREATE POLICY "work-assistant-configuration_select_policy" ON configuration 
    FOR SELECT TO authenticated 
    USING (tenant_id = public.tenant_id());



-- =============================================================================
-- Agent Memory 테이블 (에이전틱 메모리)
-- 벡터 검색을 통한 컨텍스트 관리
-- =============================================================================

-- 메모리 타입 enum
DO $$ BEGIN
    CREATE TYPE memory_type AS ENUM ('conversation', 'tool_result', 'fact', 'preference');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- =============================================================================
-- chat_vector_memory 테이블 (채팅방 단위 에이전틱 메모리: 다자간/다에이전트 공용)
-- - room_id(=conversation_id=프론트 roomId) 스코프로 벡터 검색
-- - 모든 에이전트(메인/일반/라우터)가 동일 테이블을 사용하도록 확장용
-- =============================================================================

CREATE TABLE IF NOT EXISTS chat_vector_memory (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id TEXT NOT NULL,
    user_uid UUID NOT NULL,
    room_id TEXT NOT NULL,
    agent_id TEXT,
    source_role TEXT, -- user | assistant | tool
    memory_type memory_type NOT NULL DEFAULT 'conversation', -- conversation | tool_result | fact | preference
    content TEXT NOT NULL,
    embedding vector(1536),
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    expires_at TIMESTAMPTZ
);

-- auth 스키마 권한이 없는 환경에서는 FK 생성이 실패할 수 있어 선택적으로 적용
DO $$
BEGIN
  BEGIN
    ALTER TABLE chat_vector_memory
      ADD CONSTRAINT fk_chat_vector_memory_user
      FOREIGN KEY (user_uid) REFERENCES auth.users(id) ON DELETE CASCADE;
  EXCEPTION
    WHEN duplicate_object THEN NULL;
    WHEN insufficient_privilege OR undefined_table OR invalid_schema_name THEN
      RAISE NOTICE 'Skipping fk_chat_vector_memory_user: %', SQLERRM;
  END;
END $$;

-- 인덱스
CREATE INDEX IF NOT EXISTS idx_chat_vector_memory_tenant_user_room ON chat_vector_memory(tenant_id, user_uid, room_id);
CREATE INDEX IF NOT EXISTS idx_chat_vector_memory_room_created ON chat_vector_memory(room_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_chat_vector_memory_type ON chat_vector_memory(memory_type);
CREATE INDEX IF NOT EXISTS idx_chat_vector_memory_agent ON chat_vector_memory(agent_id);
CREATE INDEX IF NOT EXISTS idx_chat_vector_memory_created ON chat_vector_memory(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_chat_vector_memory_expires ON chat_vector_memory(expires_at) WHERE expires_at IS NOT NULL;

-- 벡터 검색 인덱스 (IVFFlat)
CREATE INDEX IF NOT EXISTS idx_chat_vector_memory_embedding ON chat_vector_memory
USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);

-- RLS 활성화
ALTER TABLE chat_vector_memory ENABLE ROW LEVEL SECURITY;

-- RLS 정책: 사용자는 자신의 테넌트/사용자 스코프만 접근 가능
DROP POLICY IF EXISTS "chat_vector_memory_user_policy" ON chat_vector_memory;
CREATE POLICY "chat_vector_memory_user_policy" ON chat_vector_memory
    FOR ALL TO authenticated
    USING (user_uid = auth.uid() AND tenant_id = public.tenant_id());

-- 만료된 메모리 자동 삭제 함수
CREATE OR REPLACE FUNCTION delete_expired_chat_vector_memory()
RETURNS void AS $$
BEGIN
    DELETE FROM chat_vector_memory WHERE expires_at IS NOT NULL AND expires_at < NOW();
END;
$$ LANGUAGE plpgsql;

-- 벡터 유사도 검색 함수 (채팅방 room_id 스코프)
CREATE OR REPLACE FUNCTION search_chat_vector_memory(
    p_tenant_id TEXT,
    p_user_uid UUID,
    p_room_id TEXT,
    p_embedding vector(1536),
    p_limit INT DEFAULT 8,
    p_memory_types memory_type[] DEFAULT NULL,
    p_agent_id TEXT DEFAULT NULL,
    p_min_similarity FLOAT DEFAULT NULL
)
RETURNS TABLE (
    id UUID,
    room_id TEXT,
    agent_id TEXT,
    source_role TEXT,
    memory_type memory_type,
    content TEXT,
    metadata JSONB,
    similarity FLOAT,
    created_at TIMESTAMPTZ
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        m.id,
        m.room_id,
        m.agent_id,
        m.source_role,
        m.memory_type,
        m.content,
        m.metadata,
        1 - (m.embedding <=> p_embedding) AS similarity,
        m.created_at
    FROM chat_vector_memory m
    WHERE m.tenant_id = p_tenant_id
      AND m.user_uid = p_user_uid
      AND m.room_id = p_room_id
      AND (m.expires_at IS NULL OR m.expires_at > NOW())
      AND (p_memory_types IS NULL OR m.memory_type = ANY(p_memory_types))
      AND (p_agent_id IS NULL OR m.agent_id = p_agent_id)
      AND m.embedding IS NOT NULL
      AND (p_min_similarity IS NULL OR (1 - (m.embedding <=> p_embedding)) >= p_min_similarity)
    ORDER BY m.embedding <=> p_embedding
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql STABLE;

-- ==========================================
-- ProcessGPT SDK 이벤트 벌크 저장 함수
-- ==========================================
-- record_events_bulk: 여러 이벤트를 한 번에 저장하는 함수
-- ProcessGPT Agent SDK에서 이벤트 버퍼 플러시 시 사용
CREATE OR REPLACE FUNCTION public.record_events_bulk(p_events jsonb)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  INSERT INTO events (id, job_id, todo_id, proc_inst_id, crew_type, event_type, data, status)
  SELECT COALESCE((e->>'id')::uuid, gen_random_uuid()),
         e->>'job_id',
         e->>'todo_id',
         e->>'proc_inst_id',
         e->>'crew_type',
         (e->>'event_type')::public.event_type_enum,
         (e->'data')::jsonb,
         NULLIF(e->>'status','')::public.event_status
    FROM jsonb_array_elements(COALESCE(p_events, '[]'::jsonb)) AS e;
END;
$$;


-- Tenant Skills 테이블 생성 (스킬 정의 + 소유자)
create table if not exists public.tenant_skills (
  tenant_id   text not null,
  skill_name  text not null,
  owner_id    uuid not null,
  created_at  timestamptz null default now(),
  constraint  tenant_skills_pkey primary key (tenant_id, skill_name),
  constraint  tenant_skills_owner_fkey foreign key (owner_id, tenant_id)
              references public.users (id, tenant_id) on update cascade on delete cascade
) tablespace pg_default;

create index if not exists idx_tenant_skills_tenant
  on public.tenant_skills (tenant_id);

alter table public.tenant_skills enable row level security;

DROP POLICY IF EXISTS tenant_skills_insert_policy ON public.tenant_skills;
create policy tenant_skills_insert_policy on public.tenant_skills for insert to authenticated with check (tenant_id = public.tenant_id());
DROP POLICY IF EXISTS tenant_skills_select_policy ON public.tenant_skills;
create policy tenant_skills_select_policy on public.tenant_skills for select to authenticated using (tenant_id = public.tenant_id());
DROP POLICY IF EXISTS tenant_skills_update_policy ON public.tenant_skills;
create policy tenant_skills_update_policy on public.tenant_skills for update to authenticated using (tenant_id = public.tenant_id());
DROP POLICY IF EXISTS tenant_skills_delete_policy ON public.tenant_skills;
create policy tenant_skills_delete_policy on public.tenant_skills for delete to authenticated using (tenant_id = public.tenant_id());


-- Agent Skills 테이블 생성 (에이전트-스킬 할당)
create table if not exists public.agent_skills (
  user_id uuid not null,
  tenant_id text not null,
  skill_name text not null,
  created_at timestamptz null default now(),
  constraint agent_skills_pkey primary key (user_id, tenant_id, skill_name),
  constraint agent_skills_user_fkey foreign key (user_id, tenant_id)
    references public.users (id, tenant_id) on update cascade on delete cascade,
  constraint agent_skills_skill_fkey foreign key (tenant_id, skill_name)
    references public.tenant_skills (tenant_id, skill_name) on update cascade on delete cascade
) tablespace pg_default;

create index if not exists idx_agent_skills_tenant_skill
  on public.agent_skills (tenant_id, skill_name);


-- ==========================================
-- 범용 리소스 PR 워크플로우 (skill / proc_def / dmn)
-- ==========================================

-- PR 상태 ENUM
DO $$ BEGIN
  CREATE TYPE resource_pr_status AS ENUM (
    'OPEN',               -- 요청됨, 검토 대기
    'CHANGES_REQUESTED',  -- 관리자 변경 요청
    'APPROVED',           -- 승인됨 (병합 가능)
    'MERGED',             -- 기준 브랜치 병합 완료
    'CLOSED'              -- 취소/거절
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

-- PR 요청 테이블 (리소스 종류에 무관한 범용 구조)
create table if not exists public.resource_pull_requests (
  id             uuid                not null default gen_random_uuid(),
  tenant_id      text                not null,
  resource_type  text                not null,
  resource_id    text                not null,
  branch_name    text                not null,
  base_branch    text                not null default 'main',
  title          text                not null,
  description    text                null,
  status         resource_pr_status  not null default 'OPEN',
  requester_id   uuid[]              not null default '{}'::uuid[],
  reviewer_id    uuid                null,
  git_pr_number  integer             null,
  git_pr_url     text                null,
  git_repo_url   text                null,
  created_at     timestamptz         not null default now(),
  updated_at     timestamptz         not null default now(),
  merged_at      timestamptz         null,
  constraint resource_pull_requests_pkey primary key (id),
  constraint resource_pull_requests_resource_type_check check (
    resource_type in ('skill', 'bpmn', 'dmn')
  ),
  constraint resource_pull_requests_reviewer_fkey foreign key (reviewer_id, tenant_id)
    references public.users (id, tenant_id) on update cascade on delete cascade
) tablespace pg_default;

create index if not exists idx_resource_pull_requests_tenant_resource
  on public.resource_pull_requests (tenant_id, resource_type, resource_id);

create index if not exists idx_resource_pull_requests_status
  on public.resource_pull_requests (tenant_id, status);

-- PR 리뷰 이력 테이블 (APPROVED / CHANGES_REQUESTED 이벤트 누적)
create table if not exists public.resource_pr_reviews (
  id           uuid        not null default gen_random_uuid(),
  pr_id        uuid        not null,
  tenant_id    text        not null,
  reviewer_id  uuid        not null,
  action       text        not null,
  comment      text        null,
  created_at   timestamptz not null default now(),
  constraint resource_pr_reviews_pkey primary key (id),
  constraint resource_pr_reviews_pr_fkey foreign key (pr_id)
    references public.resource_pull_requests (id) on update cascade on delete cascade,
  constraint resource_pr_reviews_reviewer_fkey foreign key (reviewer_id, tenant_id)
    references public.users (id, tenant_id) on update cascade on delete cascade
) tablespace pg_default;

create index if not exists idx_resource_pr_reviews_pr_id
  on public.resource_pr_reviews (pr_id);

-- updated_at 자동 갱신
drop trigger if exists resource_pull_requests_updated_at on public.resource_pull_requests;
create trigger resource_pull_requests_updated_at
  before update on public.resource_pull_requests
  for each row execute function update_updated_at_column();

-- RLS
alter table public.resource_pull_requests enable row level security;
alter table public.resource_pr_reviews enable row level security;

DROP POLICY IF EXISTS resource_pull_requests_insert_policy ON public.resource_pull_requests;
create policy resource_pull_requests_insert_policy on public.resource_pull_requests for insert to authenticated with check (tenant_id = public.tenant_id());
DROP POLICY IF EXISTS resource_pull_requests_select_policy ON public.resource_pull_requests;
create policy resource_pull_requests_select_policy on public.resource_pull_requests for select to authenticated using (tenant_id = public.tenant_id());
DROP POLICY IF EXISTS resource_pull_requests_update_policy ON public.resource_pull_requests;
create policy resource_pull_requests_update_policy on public.resource_pull_requests for update to authenticated using (tenant_id = public.tenant_id());
DROP POLICY IF EXISTS resource_pull_requests_delete_policy ON public.resource_pull_requests;
create policy resource_pull_requests_delete_policy on public.resource_pull_requests for delete to authenticated using (tenant_id = public.tenant_id());

DROP POLICY IF EXISTS resource_pr_reviews_insert_policy ON public.resource_pr_reviews;
create policy resource_pr_reviews_insert_policy on public.resource_pr_reviews for insert to authenticated with check (tenant_id = public.tenant_id());
DROP POLICY IF EXISTS resource_pr_reviews_select_policy ON public.resource_pr_reviews;
create policy resource_pr_reviews_select_policy on public.resource_pr_reviews for select to authenticated using (tenant_id = public.tenant_id());
DROP POLICY IF EXISTS resource_pr_reviews_update_policy ON public.resource_pr_reviews;
create policy resource_pr_reviews_update_policy on public.resource_pr_reviews for update to authenticated using (tenant_id = public.tenant_id());
DROP POLICY IF EXISTS resource_pr_reviews_delete_policy ON public.resource_pr_reviews;
create policy resource_pr_reviews_delete_policy on public.resource_pr_reviews for delete to authenticated using (tenant_id = public.tenant_id());


create table if not exists
  public.agent_knowledge_history (
    id uuid not null default gen_random_uuid (),
    knowledge_type text not null,
    knowledge_id text not null,
    knowledge_name text null,
    agent_id uuid not null,
    tenant_id text null,
    operation text not null,
    previous_content text null,
    new_content text null,
    moved_from_storage text null,
    moved_to_storage text null,
    feedback_content text null,
    batch_job_id text null,
    created_at timestamp with time zone not null default now(),
    constraint agent_knowledge_history_pkey primary key (id),
    constraint agent_knowledge_history_agent_id_fkey foreign key (agent_id, tenant_id) references users (id, tenant_id) on update cascade on delete cascade,
    constraint agent_knowledge_history_knowledge_type_check check (
      (
        knowledge_type = any (
          array['MEMORY'::text, 'DMN_RULE'::text, 'SKILL'::text]
        )
      )
    ),
    constraint agent_knowledge_history_operation_check check (
      (
        operation = any (
          array[
            'CREATE'::text,
            'UPDATE'::text,
            'DELETE'::text,
            'MOVE'::text
          ]
        )
      )
    ),
    constraint agent_knowledge_history_moved_from_storage_check check (
      (
        moved_from_storage = any (
          array['MEMORY'::text, 'DMN_RULE'::text, 'SKILL'::text]
        )
      )
    ),
    constraint agent_knowledge_history_moved_to_storage_check check (
      (
        moved_to_storage = any (
          array['MEMORY'::text, 'DMN_RULE'::text, 'SKILL'::text]
        )
      )
    )
  ) tablespace pg_default;

create index if not exists idx_agent_knowledge_history_agent_id on public.agent_knowledge_history using btree (agent_id) tablespace pg_default;

create index if not exists idx_agent_knowledge_history_tenant_id on public.agent_knowledge_history using btree (tenant_id) tablespace pg_default;

create index if not exists idx_agent_knowledge_history_operation on public.agent_knowledge_history using btree (operation) tablespace pg_default;

create index if not exists idx_agent_knowledge_history_created_at on public.agent_knowledge_history using btree (created_at desc) tablespace pg_default;

create index if not exists idx_agent_knowledge_history_batch_job_id on public.agent_knowledge_history using btree (batch_job_id) tablespace pg_default;

create index if not exists idx_agent_knowledge_history_knowledge_type on public.agent_knowledge_history using btree (knowledge_type) tablespace pg_default;

create index if not exists idx_agent_knowledge_history_knowledge_id on public.agent_knowledge_history using btree (knowledge_id) tablespace pg_default;


-- create table
--   public.agent_knowledge_history (
--     id uuid not null default gen_random_uuid (),
--     knowledge_type text not null,
--     knowledge_id text not null,
--     knowledge_name text null,
--     agent_id uuid not null,
--     tenant_id text null,
--     operation text not null,
--     previous_content text null,
--     new_content text null,
--     moved_from_storage text null,
--     moved_to_storage text null,
--     feedback_content text null,
--     batch_job_id text null,
--     created_at timestamp with time zone not null default now(),
--     constraint agent_knowledge_history_pkey primary key (id),
--     constraint agent_knowledge_history_agent_id_fkey foreign key (agent_id, tenant_id) references users (id, tenant_id) on update cascade on delete cascade,
--     constraint agent_knowledge_history_knowledge_type_check check (
--       (
--         knowledge_type = any (
--           array['MEMORY'::text, 'DMN_RULE'::text, 'SKILL'::text]
--         )
--       )
--     ),
--     constraint agent_knowledge_history_operation_check check (
--       (
--         operation = any (
--           array[
--             'CREATE'::text,
--             'UPDATE'::text,
--             'DELETE'::text,
--             'MOVE'::text
--           ]
--         )
--       )
--     ),
--     constraint agent_knowledge_history_moved_from_storage_check check (
--       (
--         moved_from_storage = any (
--           array['MEMORY'::text, 'DMN_RULE'::text, 'SKILL'::text]
--         )
--       )
--     ),
--     constraint agent_knowledge_history_moved_to_storage_check check (
--       (
--         moved_to_storage = any (
--           array['MEMORY'::text, 'DMN_RULE'::text, 'SKILL'::text]
--         )
--       )
--     )
--   ) tablespace pg_default;

-- create index if not exists idx_agent_knowledge_history_agent_id on public.agent_knowledge_history using btree (agent_id) tablespace pg_default;

-- create index if not exists idx_agent_knowledge_history_tenant_id on public.agent_knowledge_history using btree (tenant_id) tablespace pg_default;

-- create index if not exists idx_agent_knowledge_history_operation on public.agent_knowledge_history using btree (operation) tablespace pg_default;

-- create index if not exists idx_agent_knowledge_history_created_at on public.agent_knowledge_history using btree (created_at desc) tablespace pg_default;

-- create index if not exists idx_agent_knowledge_history_batch_job_id on public.agent_knowledge_history using btree (batch_job_id) tablespace pg_default;

-- create index if not exists idx_agent_knowledge_history_knowledge_type on public.agent_knowledge_history using btree (knowledge_type) tablespace pg_default;

-- create index if not exists idx_agent_knowledge_history_knowledge_id on public.agent_knowledge_history using btree (knowledge_id) tablespace pg_default;



-- ============================================================================
-- 에이전트 초기 지식 셋팅 로그 테이블
-- 셋팅 완료 여부 추적 (users 테이블 확장 없이 별도 관리)
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.agent_knowledge_setup_log (
  agent_id UUID NOT NULL,
  tenant_id TEXT,
  status TEXT NOT NULL DEFAULT 'DONE',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (agent_id),
  CONSTRAINT agent_knowledge_setup_log_user_fkey
    FOREIGN KEY (agent_id, tenant_id) REFERENCES public.users (id, tenant_id) ON DELETE CASCADE
);

GRANT SELECT, INSERT ON public.agent_knowledge_setup_log TO anon;
CREATE INDEX IF NOT EXISTS idx_agent_knowledge_setup_log_agent_id ON public.agent_knowledge_setup_log(agent_id);


-- 에이전트 초기 지식 셋팅 대상 조회 (agent_knowledge_setup_log에 없는 에이전트)
CREATE OR REPLACE FUNCTION public.agent_needing_knowledge_setup(p_limit integer DEFAULT 1)
RETURNS SETOF users AS $$
BEGIN
  RETURN QUERY
  SELECT u.*
  FROM public.users u
  LEFT JOIN public.agent_knowledge_setup_log s ON u.id = s.agent_id
  WHERE u.is_agent = true
    AND u.agent_type = 'agent'
    AND u.goal IS NOT NULL
    AND u.goal != ''
    AND s.agent_id IS NULL
  ORDER BY u.id ASC
  LIMIT p_limit;
END;
$$ LANGUAGE plpgsql STABLE;

GRANT EXECUTE ON FUNCTION public.agent_needing_knowledge_setup(integer) TO anon;


-- =====================================================
-- document_pages + knowledge_files.doc_card
-- agent navigation (catalog + grep + page-read) 인프라.
-- 기존 청크 RAG (documents 테이블 + Chroma) 는 건드리지 않는 add-only.
-- =====================================================

-- knowledge_files 에 doc_card JSONB 컬럼 추가
-- 스키마(현행 최소):
--   { "abstract": "...", "n_pages": int, "generated_at": "ISO8601Z",
--     "generation_model": "..." }
ALTER TABLE public.knowledge_files
    ADD COLUMN IF NOT EXISTS doc_card jsonb;

-- 페이지 단위 본문 저장. agent 의 read_document_page / grep_in_document 가 읽음.
-- file_id 는 knowledge_files.source_ref 와 동일 값
-- (drive: 파일ID / upload: storage path). documents 테이블의 metadata.file_id 와도 동일.
create table if not exists public.document_pages (
    id            uuid primary key default uuid_generate_v4(),
    tenant_id     text not null,
    file_id       text not null,
    page_number   int  not null,
    content       text not null,
    page_meta     jsonb not null default '{}'::jsonb,
    created_at    timestamptz not null default now(),
    constraint document_pages_unique_page unique (tenant_id, file_id, page_number),
    constraint document_pages_tenant_fk foreign key (tenant_id)
        references public.tenants(id) on update cascade on delete cascade
);

create index if not exists idx_document_pages_tenant_file
    on public.document_pages using btree (tenant_id, file_id) tablespace pg_default;

ALTER TABLE public.document_pages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS document_pages_select_policy ON public.document_pages;
CREATE POLICY document_pages_select_policy ON public.document_pages FOR SELECT TO authenticated USING (tenant_id = public.tenant_id());
DROP POLICY IF EXISTS document_pages_insert_policy ON public.document_pages;
CREATE POLICY document_pages_insert_policy ON public.document_pages FOR INSERT TO authenticated WITH CHECK (tenant_id = public.tenant_id());
DROP POLICY IF EXISTS document_pages_update_policy ON public.document_pages;
CREATE POLICY document_pages_update_policy ON public.document_pages FOR UPDATE TO authenticated USING (tenant_id = public.tenant_id());
DROP POLICY IF EXISTS document_pages_delete_policy ON public.document_pages;
CREATE POLICY document_pages_delete_policy ON public.document_pages FOR DELETE TO authenticated USING (tenant_id = public.tenant_id());


-- =====================================================
-- knowledge_files.doc_summary — summary-pipeline mini-summary 캐시.
-- memento /summarize 가 batch 별 LLM 콜 결과를 통째로 컬럼에 캐싱해 재요약 비용 절감.
-- 스키마: { batch_size, n_pages, n_batches, abstract, batches:[...], model, generated_at }
-- 같은 file_id (= source_ref) 면 cache hit. 파일 재인덱싱 시
-- document_pages._delete_existing_pages 와 같은 시점에 NULL 로 무효화.
-- =====================================================
ALTER TABLE public.knowledge_files
    ADD COLUMN IF NOT EXISTS doc_summary jsonb;


-- =====================================================
-- knowledge_files.doc_role — 자료 역할 분류 (에이전트 활용 패턴 분기용)
--   content   : 일반 검색·요약 대상 본문 (기본값)
--   glossary  : 용어 사전 — 답변 작성 시 컨텍스트로 자동 주입
--   template  : 보고서·계약서 양식 — DOCX 생성 시 양식으로 활용
--   reference : 법령·표준 등 참조 자료 — 인용 시 우선
-- =====================================================
ALTER TABLE public.knowledge_files
    ADD COLUMN IF NOT EXISTS doc_role text NOT NULL DEFAULT 'content';

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'knowledge_files_role_check'
    ) THEN
        ALTER TABLE public.knowledge_files
            ADD CONSTRAINT knowledge_files_role_check
            CHECK (doc_role IN ('content', 'glossary', 'template', 'reference', 'dataset'));
    END IF;
END $$;

create index if not exists idx_knowledge_files_tenant_role
    on public.knowledge_files using btree (tenant_id, doc_role) tablespace pg_default;


-- =====================================================
-- knowledge_folders.doc_role — 폴더에도 역할 부여
-- 빈 폴더가 어느 role 탭에 속하는지 결정. unique key 가
-- (tenant_id, folder_path) → (tenant_id, doc_role, folder_path) 로 변경됨.
-- =====================================================
ALTER TABLE public.knowledge_folders
    ADD COLUMN IF NOT EXISTS doc_role text NOT NULL DEFAULT 'content';

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'knowledge_folders_role_check'
    ) THEN
        ALTER TABLE public.knowledge_folders
            ADD CONSTRAINT knowledge_folders_role_check
            CHECK (doc_role IN ('content', 'glossary', 'template', 'reference', 'dataset'));
    END IF;

    -- (tenant_id, folder_path) unique 제약을 (tenant_id, doc_role, folder_path) 로 교체.
    IF EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'knowledge_folders_unique' AND conrelid = 'public.knowledge_folders'::regclass
    ) THEN
        ALTER TABLE public.knowledge_folders DROP CONSTRAINT knowledge_folders_unique;
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'knowledge_folders_unique_role' AND conrelid = 'public.knowledge_folders'::regclass
    ) THEN
        ALTER TABLE public.knowledge_folders
            ADD CONSTRAINT knowledge_folders_unique_role UNIQUE (tenant_id, doc_role, folder_path);
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_knowledge_folders_tenant_role
    ON public.knowledge_folders USING btree (tenant_id, doc_role) TABLESPACE pg_default;


-- =====================================================
-- knowledge_files.glossary_compact — 용어 사전 정제 본문
-- doc_role='glossary' 자료를 ingest 시 LLM 이 page batch 단위로 추출·압축한 텍스트.
-- 형식 자유 (한 줄 = 한 용어). 채팅 진입 시 /glossary/inline 이 우선 활용.
-- =====================================================
ALTER TABLE public.knowledge_files
    ADD COLUMN IF NOT EXISTS glossary_compact text;




-- ================================================================
-- tenant_git_config: 테넌트별 Git 서비스 연결 정보
-- provider당 하나의 레코드, is_default=true가 기본 provider
-- ================================================================

CREATE TABLE IF NOT EXISTS tenant_git_config (
    id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id    TEXT        NOT NULL,
    provider     TEXT        NOT NULL CHECK (provider IN ('github', 'gitlab', 'gitea')),
    base_url     TEXT,                        -- GitHub: NULL, GitLab/Gitea: 'https://gitlab.mycompany.com'
    username     TEXT        NOT NULL,
    token        TEXT        NOT NULL,        -- Personal Access Token (암호화 권장)
    is_default   BOOLEAN     NOT NULL DEFAULT false,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),

    UNIQUE (tenant_id, provider)             -- 테넌트당 provider 하나
);

-- updated_at 자동 갱신 트리거
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS tenant_git_config_updated_at ON tenant_git_config;
CREATE TRIGGER tenant_git_config_updated_at
    BEFORE UPDATE ON tenant_git_config
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ================================================================
-- is_default 무결성: 테넌트당 is_default=true가 최대 1개여야 함
-- ================================================================
CREATE UNIQUE INDEX IF NOT EXISTS tenant_git_config_one_default
    ON tenant_git_config (tenant_id)
    WHERE is_default = true;

-- ================================================================
-- RLS (Row Level Security)
-- ================================================================
ALTER TABLE tenant_git_config ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS tenant_git_config_insert_policy ON tenant_git_config;
CREATE POLICY tenant_git_config_insert_policy ON tenant_git_config FOR INSERT TO authenticated WITH CHECK (tenant_id = public.tenant_id());
DROP POLICY IF EXISTS tenant_git_config_select_policy ON tenant_git_config;
CREATE POLICY tenant_git_config_select_policy ON tenant_git_config FOR SELECT TO authenticated USING (tenant_id = public.tenant_id());
DROP POLICY IF EXISTS tenant_git_config_update_policy ON tenant_git_config;
CREATE POLICY tenant_git_config_update_policy ON tenant_git_config FOR UPDATE TO authenticated USING (tenant_id = public.tenant_id());
DROP POLICY IF EXISTS tenant_git_config_delete_policy ON tenant_git_config;
CREATE POLICY tenant_git_config_delete_policy ON tenant_git_config FOR DELETE TO authenticated USING (tenant_id = public.tenant_id());



create table public.feedback_proposals (
  id uuid not null default gen_random_uuid (),
  tenant_id text not null,
  proc_def_id text not null,
  activity_id text not null,
  status text not null default 'COLLECTING'::text,
  collected_items jsonb not null default '[]'::jsonb,
  first_collected_at timestamp with time zone not null default now(),
  extracted_rule text null,
  proposed_at timestamp with time zone null,
  decided_by uuid null,
  decided_by_name text null,
  decided_by_email text null,
  decided_at timestamp with time zone null,
  decision_note text null,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  candidate_skill_names text[] not null default '{}'::text[],
  targets jsonb not null default '[]'::jsonb,
  constraint feedback_proposals_pkey primary key (id),
  constraint feedback_proposals_status_check check (
    (
      status = any (
        array[
          'COLLECTING'::text,
          'PROPOSED'::text,
          'APPROVED'::text,
          'REJECTED'::text,
          'DISCARDED'::text,
          'RESOLVED'::text
        ]
      )
    )
  )
) TABLESPACE pg_default;

create unique INDEX IF not exists feedback_proposals_collecting_key on public.feedback_proposals using btree (tenant_id, proc_def_id, activity_id) TABLESPACE pg_default
where
  (status = 'COLLECTING'::text);

create index IF not exists feedback_proposals_status_idx on public.feedback_proposals using btree (status) TABLESPACE pg_default;

create trigger feedback_proposals_updated_at BEFORE
update on feedback_proposals for EACH row
execute FUNCTION update_updated_at_column ();

CREATE OR REPLACE FUNCTION public.decide_feedback_proposal_target(
    p_batch_id          uuid,
    p_target_type       text,
    p_status            text,
    p_decided_by        uuid,
    p_decided_by_name   text,
    p_decided_by_email  text,
    p_decision_note     text
) RETURNS public.feedback_proposals
LANGUAGE plpgsql
AS $$
DECLARE
    v_row         public.feedback_proposals;
    v_targets     jsonb;
    v_elem        jsonb;
    v_found       boolean := false;
    v_all_decided boolean := true;
    i             int;
BEGIN
    SELECT * INTO v_row
    FROM public.feedback_proposals
    WHERE id = p_batch_id AND status = 'PROPOSED'
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN NULL;
    END IF;

    v_targets := v_row.targets;

    FOR i IN 0 .. jsonb_array_length(v_targets) - 1 LOOP
        v_elem := v_targets -> i;
        IF (v_elem ->> 'type') = p_target_type AND (v_elem ->> 'status') = 'PENDING' THEN
            v_elem := v_elem || jsonb_build_object(
                'status', p_status,
                'decided_by', p_decided_by,
                'decided_by_name', p_decided_by_name,
                'decided_by_email', p_decided_by_email,
                'decision_note', p_decision_note,
                'decided_at', to_jsonb(now())
            );
            v_targets := jsonb_set(v_targets, ARRAY[i::text], v_elem);
            v_found := true;
        END IF;
    END LOOP;

    IF NOT v_found THEN
        RETURN NULL;
    END IF;

    FOR i IN 0 .. jsonb_array_length(v_targets) - 1 LOOP
        IF (v_targets -> i ->> 'status') = 'PENDING' THEN
            v_all_decided := false;
        END IF;
    END LOOP;

    UPDATE public.feedback_proposals
    SET targets = v_targets,
        status = CASE WHEN v_all_decided THEN 'RESOLVED' ELSE status END
    WHERE id = p_batch_id
    RETURNING * INTO v_row;

    RETURN v_row;
END;
$$;


-- ============================================================================
-- 핸드오버 이벤트 로그
--
-- 채팅방(/chat)과 워크아이템에서 발생하는 "업무 이관" 을 구조화된 이벤트로
-- 축적한다. process-miner 서비스가 이 로그로부터 핸드오버 네트워크(조직 마이닝)와
-- 프로세스 정의(제어 흐름 마이닝)를 도출한다.
--
-- 사람과 AI 에이전트는 모두 public.users 한 테이블에 있으므로(is_agent 플래그로만
-- 구분) 이 로그도 둘을 구분하지 않는다. from_is_agent / to_is_agent 는 분석 편의를
-- 위한 비정규화 스냅샷일 뿐이며, 네트워크는 하나로 계산된다.
--
-- source
--   chat_handover    : 사용자가 채팅방에서 '인계하기' 버튼을 눌러 명시적으로 넘김
--   agent_delegation : 채팅방에서 에이전트에게 암묵적으로 위임됨(초대/라우팅)
--   todolist         : 기존 BPMN 인스턴스 실행 이력에서 역산된 이관
-- ============================================================================

create table if not exists public.handover_events (
    id                    uuid        not null default gen_random_uuid(),
    tenant_id             text        not null default public.tenant_id(),

    -- 핸드오버 체인 = 하나의 업무 케이스(프로세스 마이닝의 Case ID)
    case_id               text        not null,
    source                text        not null,
    is_explicit           boolean     not null default true,

    -- 이관 전/후 컨텍스트
    from_room_id          text        null,
    to_room_id            text        null,
    from_task_id          uuid        null,
    to_task_id            uuid        null,

    -- 리소스(사람 또는 에이전트)
    from_user_id          text        null,
    from_user_name        text        null,
    from_role             text        null,
    from_is_agent         boolean     not null default false,
    to_user_id            text        not null,
    to_user_name          text        null,
    to_role               text        null,
    to_is_agent           boolean     not null default false,
    agent_orch            text        null,

    -- 활동 라벨
    activity_label        text        null,  -- 넘기는 사람이 적은 "지금까지 한 일"
    next_activity_label   text        null,  -- 넘기는 사람이 적은 "다음에 할 일"
    norm_activity_label   text        null,  -- process-miner 가 채우는 정규화 라벨
    instruction           text        null,
    reason                text        null,

    -- 산출물 / 참여 에이전트
    artifact_refs         jsonb       not null default '[]'::jsonb,
    participant_agents    jsonb       not null default '[]'::jsonb,
    trigger_message_uuid  text        null,

    proc_def_id           text        null,

    -- 타이밍
    occurred_at           timestamptz not null default now(),
    returned_at           timestamptz null,   -- 에이전트가 결과를 돌려준 시각
    handover_latency_sec  integer     null,   -- 직전 이벤트로부터의 이관 지연

    created_at            timestamptz not null default now(),
    updated_at            timestamptz not null default now(),

    constraint handover_events_pkey primary key (id),
    constraint handover_events_source_check check (
        source in ('chat_handover', 'agent_delegation', 'todolist')
    ),
    constraint handover_events_tenant_id_fkey foreign key (tenant_id)
        references public.tenants (id) on update cascade on delete cascade
) tablespace pg_default;

create index if not exists idx_handover_events_case
    on public.handover_events (tenant_id, case_id, occurred_at);
create index if not exists idx_handover_events_from_user
    on public.handover_events (tenant_id, from_user_id);
create index if not exists idx_handover_events_to_user
    on public.handover_events (tenant_id, to_user_id);
create index if not exists idx_handover_events_from_room
    on public.handover_events (tenant_id, from_room_id);
create index if not exists idx_handover_events_to_room
    on public.handover_events (tenant_id, to_room_id);
-- process-miner 의 미처리 행 스캔용
create index if not exists idx_handover_events_unlabeled
    on public.handover_events (tenant_id, occurred_at)
    where norm_activity_label is null;

-- todolist 실행 이력 역산 시 같은 워크아이템이 두 번 들어오지 않도록
create unique index if not exists uq_handover_events_todolist
    on public.handover_events (source, to_task_id)
    where to_task_id is not null;

-- 암묵 위임 중복 방지: 같은 방·같은 에이전트·같은 트리거 메시지는 1건
-- (새로고침 후 스트림 재접속 시 중복 삽입 차단)
--
-- WHERE 절 없는 전체 인덱스여야 한다. 부분 인덱스로 만들면 PostgREST 의
-- upsert(onConflict=...) 가 술어를 지정할 수 없어 "no unique or exclusion
-- constraint matching the ON CONFLICT specification" 로 실패한다.
-- trigger_message_uuid 는 암묵 위임에만 채워지고 나머지 source 는 NULL 인데,
-- Postgres 기본값(NULLS DISTINCT)에서 NULL 은 서로 충돌하지 않으므로
-- chat_handover / todolist 행에는 아무 제약도 걸리지 않는다.
create unique index if not exists uq_handover_events_agent_delegation
    on public.handover_events (from_room_id, to_user_id, trigger_message_uuid);

drop trigger if exists handover_events_updated_at on public.handover_events;
create trigger handover_events_updated_at
    before update on public.handover_events
    for each row execute function public.update_updated_at_column();

-- RLS (resource_pull_requests 패턴과 동일)
alter table public.handover_events enable row level security;

DROP POLICY IF EXISTS handover_events_insert_policy ON public.handover_events;
create policy handover_events_insert_policy on public.handover_events
    for insert to authenticated with check (tenant_id = public.tenant_id());
DROP POLICY IF EXISTS handover_events_select_policy ON public.handover_events;
create policy handover_events_select_policy on public.handover_events
    for select to authenticated using (tenant_id = public.tenant_id());
DROP POLICY IF EXISTS handover_events_update_policy ON public.handover_events;
create policy handover_events_update_policy on public.handover_events
    for update to authenticated using (tenant_id = public.tenant_id());
DROP POLICY IF EXISTS handover_events_delete_policy ON public.handover_events;
create policy handover_events_delete_policy on public.handover_events
    for delete to authenticated using (tenant_id = public.tenant_id());


-- ============================================================================
-- 핸드오버 스레드 상관키(origin_room_id)
--
-- 이메일 스레드가 References/In-Reply-To 로 루트 Message-ID 를 앞으로 끌고 가듯,
-- 인계도 "이 업무가 최초로 시작된 방" 을 인계받는 방으로 계속 전파한다.
-- 그래야 A→B→C→D 로 이어진 인계가 Gmail 의 forward 묶음처럼 한 스레드로 모인다.
--
-- case_id 와의 관계:
--   origin_room_id — 구조적 상관키. 항상 채워지며 스레드 묶음의 기준.
--   case_id        — 분석용 케이스 키. 지금은 origin_room_id 와 같은 값이지만,
--                    나중에 업무 키(견적번호 등)나 케이스 분할이 도입되면 갈라진다.
-- 둘을 분리해 두어야 나중에 case 를 쪼개도 스레드 표시는 깨지지 않는다.
-- ============================================================================

alter table public.handover_events
    add column if not exists origin_room_id text;

-- 기존 행 백필: 지금까지는 case_id 가 곧 루트 방 id 였다.
update public.handover_events
set origin_room_id = case_id
where origin_room_id is null;

create index if not exists idx_handover_events_origin_room
    on public.handover_events (tenant_id, origin_room_id, occurred_at);

comment on column public.handover_events.origin_room_id is
    '이 업무가 최초로 시작된 채팅방 id. 인계받는 방으로 계속 전파되어 스레드 묶음의 기준이 된다.';
comment on column public.handover_events.case_id is
    '프로세스 마이닝의 Case ID. 기본값은 origin_room_id 이며 업무 키 도입 시 분리될 수 있다.';


-- ============================================================================
-- 역량(capability) 기반 조직 모델
--
-- 지금까지 조직도에는 "누가 어느 팀인가"만 있었고, "이 일을 하려면 어떤 역량이
-- 필요한가 / 누가 그 일을 맡을 자격이 있는가" 를 표현할 방법이 없었다.
-- 그래서 프로세스의 다음 단계 담당자를 사람 이름으로만 지정할 수밖에 없었고,
-- 인계 기록에서 조직 구조를 도출해도 붙일 자리가 없었다.
--
-- 세 층으로 나눈다:
--   org_capabilities        역량 사전 (예: 견적 산출, 계약 검토, 승인 권한)
--   user_capabilities       누가 어떤 역량을 가졌나 (관측 근거와 함께)
--   activity_eligibility    어떤 활동을 하려면 어떤 역량/역할/부서여야 하나
--
-- user_capabilities 는 사람이 직접 등록할 수도 있고(source='declared'),
-- 인계 기록에서 도출할 수도 있다(source='observed'). 도출된 것은 근거 건수를
-- 함께 남겨 "왜 이 사람이 후보인가" 를 설명할 수 있게 한다.
-- ============================================================================

create table if not exists public.org_capabilities (
    id           uuid        not null default gen_random_uuid(),
    tenant_id    text        not null default public.tenant_id(),
    name         text        not null,
    description  text        null,
    -- 이 역량이 처음 어떻게 생겼는지: 사람이 정의 / 인계 기록에서 도출
    origin       text        not null default 'declared',
    created_at   timestamptz not null default now(),
    constraint org_capabilities_pkey primary key (id),
    constraint org_capabilities_origin_check check (origin in ('declared', 'observed')),
    constraint org_capabilities_tenant_fkey foreign key (tenant_id)
        references public.tenants (id) on update cascade on delete cascade
);
create unique index if not exists uq_org_capabilities_name
    on public.org_capabilities (tenant_id, name);

create table if not exists public.user_capabilities (
    id             uuid        not null default gen_random_uuid(),
    tenant_id      text        not null default public.tenant_id(),
    user_id        text        not null,          -- users.id (사람 또는 에이전트)
    capability_id  uuid        not null,
    -- declared: 관리자가 등록 / observed: 인계 기록에서 도출
    source         text        not null default 'declared',
    -- 도출 근거 건수. 왜 후보로 떴는지 설명하는 데 쓴다.
    evidence_count integer     not null default 0,
    proficiency    text        null,              -- 예: primary / backup
    created_at     timestamptz not null default now(),
    updated_at     timestamptz not null default now(),
    constraint user_capabilities_pkey primary key (id),
    constraint user_capabilities_source_check check (source in ('declared', 'observed')),
    constraint user_capabilities_capability_fkey foreign key (capability_id)
        references public.org_capabilities (id) on update cascade on delete cascade,
    constraint user_capabilities_tenant_fkey foreign key (tenant_id)
        references public.tenants (id) on update cascade on delete cascade
);
create unique index if not exists uq_user_capabilities
    on public.user_capabilities (tenant_id, user_id, capability_id);

-- 활동 → 자격 요건. 담당자를 사람 이름으로 못 박지 않고
-- "이 역량을 가진 사람 / 이 역할 / 이 부서" 로 풀 수 있게 한다.
create table if not exists public.activity_eligibility (
    id                   uuid        not null default gen_random_uuid(),
    tenant_id            text        not null default public.tenant_id(),
    proc_def_id          text        null,        -- 아직 제안 단계면 비어 있을 수 있다
    activity_name        text        not null,
    required_capability  uuid        null,
    required_role        text        null,
    required_department  text        null,
    -- 이 요건이 어떻게 정해졌는지
    origin               text        not null default 'observed',
    evidence_count       integer     not null default 0,
    created_at           timestamptz not null default now(),
    constraint activity_eligibility_pkey primary key (id),
    constraint activity_eligibility_origin_check check (origin in ('declared', 'observed')),
    constraint activity_eligibility_capability_fkey foreign key (required_capability)
        references public.org_capabilities (id) on update cascade on delete set null,
    constraint activity_eligibility_tenant_fkey foreign key (tenant_id)
        references public.tenants (id) on update cascade on delete cascade
);
create index if not exists idx_activity_eligibility_lookup
    on public.activity_eligibility (tenant_id, activity_name);

drop trigger if exists user_capabilities_updated_at on public.user_capabilities;
create trigger user_capabilities_updated_at
    before update on public.user_capabilities
    for each row execute function public.update_updated_at_column();

-- RLS (resource_pull_requests 패턴과 동일)
alter table public.org_capabilities enable row level security;
alter table public.user_capabilities enable row level security;
alter table public.activity_eligibility enable row level security;

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['org_capabilities','user_capabilities','activity_eligibility'] LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I_insert_policy ON public.%I', t, t);
    EXECUTE format('CREATE POLICY %I_insert_policy ON public.%I FOR INSERT TO authenticated WITH CHECK (tenant_id = public.tenant_id())', t, t);
    EXECUTE format('DROP POLICY IF EXISTS %I_select_policy ON public.%I', t, t);
    EXECUTE format('CREATE POLICY %I_select_policy ON public.%I FOR SELECT TO authenticated USING (tenant_id = public.tenant_id())', t, t);
    EXECUTE format('DROP POLICY IF EXISTS %I_update_policy ON public.%I', t, t);
    EXECUTE format('CREATE POLICY %I_update_policy ON public.%I FOR UPDATE TO authenticated USING (tenant_id = public.tenant_id())', t, t);
    EXECUTE format('DROP POLICY IF EXISTS %I_delete_policy ON public.%I', t, t);
    EXECUTE format('CREATE POLICY %I_delete_policy ON public.%I FOR DELETE TO authenticated USING (tenant_id = public.tenant_id())', t, t);
  END LOOP;
END $$;

comment on table public.org_capabilities is '역량 사전. 프로세스 단계가 요구하는 능력을 이름으로 다룬다.';
comment on table public.user_capabilities is '누가 어떤 역량을 가졌나. observed 는 인계 기록에서 도출된 것이며 evidence_count 가 근거 건수다.';
comment on table public.activity_eligibility is '활동 수행 자격. 담당자를 이름이 아니라 역량/역할/부서로 풀 수 있게 한다.';


-- ============================================================
-- MCP Hub : 서버 등록 / 버전 / 툴 카탈로그 / 권한 / 헬스 / 관측
-- ------------------------------------------------------------
-- 정본은 아래 테이블이고, 레거시 public.tenants.mcp jsonb 는
-- public.sync_tenants_mcp() 트리거가 재생성하는 파생 미러로 강등된다.
-- 덕분에 기존 소비자(deepagents/core/llm/mcp.py, completion 의
-- mcp_processor.py, cli-agent/core/bridge.py, AgentField.vue)는
-- 코드 수정 없이 계속 동작한다.
-- ============================================================

-- ---------- enum ----------
DO $$ BEGIN
  CREATE TYPE mcp_transport_enum AS ENUM ('stdio','http','sse','streamable-http');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE mcp_server_status_enum AS ENUM ('draft','active','deprecated','disabled');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE mcp_health_state_enum AS ENUM ('unknown','healthy','degraded','unhealthy');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE mcp_source_enum AS ENUM ('manual','gallery','registry','imported-jsonb');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE mcp_principal_enum AS ENUM ('tenant','department','role','user','agent');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE mcp_permission_enum AS ENUM ('none','use','manage');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ---------- 공용 트리거 함수 ----------
create or replace function public.mcp_touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

-- ---------- 1) 서버 ----------
create table if not exists public.mcp_server (
    id uuid not null default gen_random_uuid(),
    tenant_id text not null default public.tenant_id(),
    name text not null,
    display_name text null,
    description text null,
    category text null,
    tags text[] null default '{}',
    department_id text null,
    owner_email text null,
    doc_url text null,
    status mcp_server_status_enum not null default 'draft',
    is_default boolean not null default false,
    enabled boolean not null default true,
    current_version_id uuid null,
    source mcp_source_enum not null default 'manual',
    source_ref text null,
    created_at timestamp with time zone not null default now(),
    created_by text null,
    updated_at timestamp with time zone not null default now(),
    updated_by text null,
    is_deleted boolean not null default false,
    deleted_at timestamp with time zone null,
    constraint mcp_server_pkey primary key (id),
    constraint mcp_server_uk unique (tenant_id, name),
    constraint mcp_server_tenant_fkey foreign key (tenant_id)
        references public.tenants (id) on update cascade on delete cascade
) tablespace pg_default;

create index if not exists idx_mcp_server_tenant on public.mcp_server (tenant_id) where is_deleted = false;
create index if not exists idx_mcp_server_department on public.mcp_server (tenant_id, department_id);

drop trigger if exists mcp_server_updated_at on public.mcp_server;
create trigger mcp_server_updated_at
    before update on public.mcp_server
    for each row execute function public.mcp_touch_updated_at();

-- ---------- 2) 버전 (연결정보 불변 스냅샷) ----------
create table if not exists public.mcp_server_version (
    id uuid not null default gen_random_uuid(),
    server_id uuid not null references public.mcp_server (id) on delete cascade,
    tenant_id text not null default public.tenant_id(),
    version integer not null,
    semver text null,
    transport mcp_transport_enum not null,
    command text null,
    args jsonb null default '[]'::jsonb,
    url text null,
    headers jsonb null default '{}'::jsonb,
    env jsonb null default '{}'::jsonb,
    timeout_ms integer not null default 30000,
    config_hash text not null,
    change_note text null,
    validated_at timestamp with time zone null,
    validation_result jsonb null,
    created_at timestamp with time zone not null default now(),
    created_by text null,
    constraint mcp_server_version_pkey primary key (id),
    constraint mcp_server_version_uk unique (server_id, version)
) tablespace pg_default;

create index if not exists idx_mcp_server_version_server on public.mcp_server_version (server_id, version desc);

DO $$ BEGIN
  ALTER TABLE public.mcp_server
    ADD CONSTRAINT mcp_server_current_version_fkey
    FOREIGN KEY (current_version_id) REFERENCES public.mcp_server_version (id)
    ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ---------- 3) 툴 카탈로그 캐시 ----------
create table if not exists public.mcp_tool (
    id uuid not null default gen_random_uuid(),
    server_id uuid not null references public.mcp_server (id) on delete cascade,
    version_id uuid null references public.mcp_server_version (id) on delete set null,
    tenant_id text not null default public.tenant_id(),
    tool_name text not null,
    sanitized_name text not null,
    description text null,
    input_schema jsonb null,
    output_schema jsonb null,
    annotations jsonb null,
    is_available boolean not null default true,
    first_seen_at timestamp with time zone not null default now(),
    last_seen_at timestamp with time zone not null default now(),
    constraint mcp_tool_pkey primary key (id),
    constraint mcp_tool_uk unique (server_id, tool_name)
) tablespace pg_default;

create index if not exists idx_mcp_tool_tenant on public.mcp_tool (tenant_id) where is_available = true;
create index if not exists idx_mcp_tool_name on public.mcp_tool (tenant_id, tool_name);

-- ---------- 4) 접근 권한 ----------
create table if not exists public.mcp_server_permission (
    id uuid not null default gen_random_uuid(),
    server_id uuid not null references public.mcp_server (id) on delete cascade,
    tenant_id text not null default public.tenant_id(),
    principal_type mcp_principal_enum not null,
    principal_id text null,
    permission mcp_permission_enum not null default 'use',
    allowed_tools text[] null,
    denied_tools text[] null default '{}',
    created_at timestamp with time zone not null default now(),
    created_by text null,
    constraint mcp_server_permission_pkey primary key (id)
) tablespace pg_default;

-- principal_id 가 null 인 tenant 스코프도 유일해야 하므로 표현식 인덱스로 대체
create unique index if not exists mcp_server_permission_uk
    on public.mcp_server_permission (server_id, principal_type, coalesce(principal_id, '*'));

-- ---------- 5) 에이전트 바인딩 ----------
create table if not exists public.mcp_agent_binding (
    id uuid not null default gen_random_uuid(),
    tenant_id text not null default public.tenant_id(),
    agent_id text not null,
    server_id uuid not null references public.mcp_server (id) on delete cascade,
    allowed_tools text[] null,
    enabled boolean not null default true,
    created_at timestamp with time zone not null default now(),
    constraint mcp_agent_binding_pkey primary key (id),
    constraint mcp_agent_binding_uk unique (agent_id, server_id)
) tablespace pg_default;

create index if not exists idx_mcp_agent_binding_agent on public.mcp_agent_binding (tenant_id, agent_id);

-- ---------- 6) 헬스 ----------
create table if not exists public.mcp_server_health (
    id bigserial primary key,
    server_id uuid not null references public.mcp_server (id) on delete cascade,
    tenant_id text not null default public.tenant_id(),
    checked_at timestamp with time zone not null default now(),
    state mcp_health_state_enum not null default 'unknown',
    latency_ms integer null,
    tool_count integer null,
    protocol_version text null,
    server_info jsonb null,
    error_code text null,
    error_message text null,
    checker text null default 'mcp-hub'
) tablespace pg_default;

create index if not exists idx_mcp_server_health_server on public.mcp_server_health (server_id, checked_at desc);

create table if not exists public.mcp_server_health_current (
    server_id uuid not null references public.mcp_server (id) on delete cascade,
    tenant_id text not null default public.tenant_id(),
    state mcp_health_state_enum not null default 'unknown',
    checked_at timestamp with time zone not null default now(),
    latency_ms integer null,
    tool_count integer null,
    consecutive_failures integer not null default 0,
    availability_24h numeric(5,2) null,
    error_message text null,
    constraint mcp_server_health_current_pkey primary key (server_id)
) tablespace pg_default;

create index if not exists idx_mcp_health_current_tenant on public.mcp_server_health_current (tenant_id, state);

-- ---------- 7) MCP 호출 로그 (관측 정본) ----------
create table if not exists public.mcp_call_log (
    id uuid not null default gen_random_uuid(),
    tenant_id text not null default public.tenant_id(),
    server_id uuid null references public.mcp_server (id) on delete set null,
    server_name text not null,
    tool_name text not null,
    trace_id text null,
    span_id text null,
    parent_span_id text null,
    proc_inst_id text null,
    todo_id text null,
    job_id text null,
    agent_id text null,
    user_id text null,
    engine text null,
    started_at timestamp with time zone not null default now(),
    finished_at timestamp with time zone null,
    duration_ms integer null,
    status text not null default 'running',
    error_type text null,
    error_message text null,
    input_bytes integer null,
    output_bytes integer null,
    input_preview jsonb null,
    output_preview jsonb null,
    constraint mcp_call_log_pkey primary key (id)
) tablespace pg_default;

create index if not exists idx_mcp_call_log_tenant_time on public.mcp_call_log (tenant_id, started_at desc);
create index if not exists idx_mcp_call_log_server_time on public.mcp_call_log (server_id, started_at desc);
create index if not exists idx_mcp_call_log_proc on public.mcp_call_log (proc_inst_id);
create index if not exists idx_mcp_call_log_todo on public.mcp_call_log (todo_id);
create index if not exists idx_mcp_call_log_trace on public.mcp_call_log (trace_id);

-- ---------- 8) LLM 호출 로그 (LiteLLM 콜백 수신) ----------
create table if not exists public.llm_call_log (
    id uuid not null default gen_random_uuid(),
    tenant_id text null default public.tenant_id(),
    trace_id text null,
    span_id text null,
    parent_span_id text null,
    proc_inst_id text null,
    todo_id text null,
    job_id text null,
    agent_id text null,
    engine text null,
    call_type text null,
    model text null,
    provider text null,
    litellm_call_id text null,
    started_at timestamp with time zone null,
    finished_at timestamp with time zone null,
    duration_ms integer null,
    status text not null default 'success',
    prompt_tokens integer null,
    completion_tokens integer null,
    total_tokens integer null,
    cache_read_tokens integer null,
    cost_usd numeric(14,8) null,
    error_type text null,
    error_message text null,
    tool_calls_count integer null,
    raw jsonb null,
    constraint llm_call_log_pkey primary key (id)
) tablespace pg_default;

create index if not exists idx_llm_call_log_tenant_time on public.llm_call_log (tenant_id, started_at desc);
create index if not exists idx_llm_call_log_proc on public.llm_call_log (proc_inst_id);
create index if not exists idx_llm_call_log_trace on public.llm_call_log (trace_id);

-- ---------- 9) 갤러리 / 레지스트리 카탈로그 ----------
create table if not exists public.mcp_catalog_entry (
    id uuid not null default gen_random_uuid(),
    source mcp_source_enum not null,
    slug text not null,
    name text not null,
    description text null,
    category text null,
    tags text[] null default '{}',
    publisher text null,
    homepage_url text null,
    icon_url text null,
    install_template jsonb not null,
    required_env jsonb null default '[]'::jsonb,
    registry_payload jsonb null,
    updated_at timestamp with time zone not null default now(),
    constraint mcp_catalog_entry_pkey primary key (id),
    constraint mcp_catalog_entry_uk unique (source, slug)
) tablespace pg_default;

-- ============================================================
-- 권한 판정
-- department_id / role 은 users 스키마에 부서 컬럼이 없으므로
-- 호출자(mcp-hub)가 알고 있는 값을 인자로 넘긴다.
-- ============================================================
create or replace function public.mcp_can_use(
    p_server_id uuid,
    p_agent_id text,
    p_department_id text default null
) returns boolean language sql stable as $$
  select case
    -- 권한 행이 하나도 없으면 테넌트 전체 허용(기존 동작 유지)
    when not exists (select 1 from public.mcp_server_permission p where p.server_id = p_server_id)
      then true
    else coalesce(bool_or(p.permission in ('use','manage')), false)
  end
  from public.mcp_server_permission p
  where p.server_id = p_server_id
    and (
         p.principal_type = 'tenant'
      or (p.principal_type = 'agent' and p.principal_id = p_agent_id)
      or (p.principal_type = 'user'  and p.principal_id = p_agent_id)
      or (p.principal_type = 'department' and p_department_id is not null
          and p.principal_id = p_department_id)
      or (p.principal_type = 'role' and p.principal_id in
            (select u.role from public.users u where u.id::text = p_agent_id))
    );
$$;

-- ============================================================
-- 레거시 호환: 정본 테이블 -> tenants.mcp jsonb 투영
-- ============================================================
create or replace function public.mcp_servers_jsonb(p_tenant text)
returns jsonb language sql stable as $$
  select jsonb_build_object(
    'mcpServers',
    coalesce(jsonb_object_agg(s.name, c.cfg), '{}'::jsonb)
  )
  from public.mcp_server s
  join public.mcp_server_version v on v.id = s.current_version_id
  cross join lateral (
    select jsonb_strip_nulls(
      case when v.transport = 'stdio' then
        jsonb_build_object(
          'command', v.command,
          'args',    nullif(v.args, '[]'::jsonb),
          'env',     nullif(v.env, '{}'::jsonb)
        )
      else
        jsonb_build_object(
          'type',    v.transport::text,
          'url',     v.url,
          'headers', nullif(v.headers, '{}'::jsonb)
        )
      end
      || jsonb_build_object('enabled', s.enabled, 'is_default', s.is_default)
    ) as cfg
  ) c
  where s.tenant_id = p_tenant
    and s.is_deleted = false;
$$;

create or replace function public.sync_tenants_mcp()
returns trigger language plpgsql security definer as $$
declare
  t text;
begin
  t := coalesce(new.tenant_id, old.tenant_id);
  if t is null then
    return null;
  end if;
  update public.tenants
     set mcp = public.mcp_servers_jsonb(t)
   where id = t;
  return null;
end $$;

drop trigger if exists trg_mcp_server_sync on public.mcp_server;
create trigger trg_mcp_server_sync
    after insert or update or delete on public.mcp_server
    for each row execute function public.sync_tenants_mcp();

drop trigger if exists trg_mcp_server_version_sync on public.mcp_server_version;
create trigger trg_mcp_server_version_sync
    after insert or update on public.mcp_server_version
    for each row execute function public.sync_tenants_mcp();

-- ============================================================
-- RLS
-- ============================================================
alter table public.mcp_server              enable row level security;
alter table public.mcp_server_version      enable row level security;
alter table public.mcp_tool                enable row level security;
alter table public.mcp_server_permission   enable row level security;
alter table public.mcp_agent_binding       enable row level security;
alter table public.mcp_server_health       enable row level security;
alter table public.mcp_server_health_current enable row level security;
alter table public.mcp_call_log            enable row level security;
alter table public.llm_call_log            enable row level security;
alter table public.mcp_catalog_entry       enable row level security;

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'mcp_server','mcp_server_version','mcp_tool','mcp_server_permission',
    'mcp_agent_binding','mcp_server_health','mcp_server_health_current',
    'mcp_call_log','llm_call_log'
  ] LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I_select_policy ON public.%I', t, t);
    EXECUTE format('CREATE POLICY %I_select_policy ON public.%I FOR SELECT TO authenticated USING (tenant_id = public.tenant_id())', t, t);
    EXECUTE format('DROP POLICY IF EXISTS %I_insert_policy ON public.%I', t, t);
    EXECUTE format('CREATE POLICY %I_insert_policy ON public.%I FOR INSERT TO authenticated WITH CHECK (tenant_id = public.tenant_id())', t, t);
    EXECUTE format('DROP POLICY IF EXISTS %I_update_policy ON public.%I', t, t);
    EXECUTE format('CREATE POLICY %I_update_policy ON public.%I FOR UPDATE TO authenticated USING (tenant_id = public.tenant_id())', t, t);
    EXECUTE format('DROP POLICY IF EXISTS %I_delete_policy ON public.%I', t, t);
    EXECUTE format('CREATE POLICY %I_delete_policy ON public.%I FOR DELETE TO authenticated USING (tenant_id = public.tenant_id())', t, t);
  END LOOP;
END $$;

-- 카탈로그는 테넌트 무관 전역 읽기, 쓰기는 service_role 만
DROP POLICY IF EXISTS mcp_catalog_entry_select_policy ON public.mcp_catalog_entry;
CREATE POLICY mcp_catalog_entry_select_policy ON public.mcp_catalog_entry
    FOR SELECT TO authenticated USING (true);

-- ============================================================
-- 백필 : tenants.mcp jsonb -> mcp_server + mcp_server_version(v1)
-- 여러 번 실행해도 안전하다 (이미 있는 name 은 건너뛴다).
-- ============================================================
create or replace function public.mcp_backfill_from_tenants()
returns integer language plpgsql security definer as $$
declare
  r          record;
  v_srv_id   uuid;
  v_ver_id   uuid;
  v_transport mcp_transport_enum;
  v_count    integer := 0;
begin
  for r in
    select t.id as tenant_id, e.key as name, e.value as cfg
      from public.tenants t
      cross join lateral jsonb_each(coalesce(t.mcp -> 'mcpServers', '{}'::jsonb)) e
  loop
    -- 이미 등록된 서버는 건너뛴다
    if exists (select 1 from public.mcp_server s
                where s.tenant_id = r.tenant_id and s.name = r.name) then
      continue;
    end if;

    v_transport := case
      when coalesce(r.cfg ->> 'command', '') <> '' then 'stdio'
      when coalesce(r.cfg ->> 'type', '') in ('http','streamable_http','streamable-http') then 'streamable-http'
      when coalesce(r.cfg ->> 'type', '') = 'sse' then 'sse'
      when coalesce(r.cfg ->> 'url', '') <> '' then 'streamable-http'
      else 'stdio'
    end;

    insert into public.mcp_server (
      tenant_id, name, description, status, enabled, is_default, source
    ) values (
      r.tenant_id,
      r.name,
      r.cfg ->> 'description',
      'active',
      coalesce((r.cfg ->> 'enabled')::boolean, true),
      coalesce((r.cfg ->> 'is_default')::boolean, false),
      'imported-jsonb'
    ) returning id into v_srv_id;

    insert into public.mcp_server_version (
      server_id, tenant_id, version, transport,
      command, args, url, headers, env, config_hash, change_note
    ) values (
      v_srv_id, r.tenant_id, 1, v_transport,
      r.cfg ->> 'command',
      coalesce(r.cfg -> 'args',    '[]'::jsonb),
      r.cfg ->> 'url',
      coalesce(r.cfg -> 'headers', '{}'::jsonb),
      coalesce(r.cfg -> 'env',     '{}'::jsonb),
      encode(sha256((r.cfg #- '{enabled}' #- '{is_default}')::text::bytea), 'hex'),
      'tenants.mcp 에서 자동 이관'
    ) returning id into v_ver_id;

    update public.mcp_server set current_version_id = v_ver_id where id = v_srv_id;
    v_count := v_count + 1;
  end loop;

  -- users.tools CSV -> mcp_agent_binding
  insert into public.mcp_agent_binding (tenant_id, agent_id, server_id)
  select u.tenant_id, u.id::text, s.id
    from public.users u
    cross join lateral unnest(string_to_array(coalesce(u.tools, ''), ',')) tool_name
    join public.mcp_server s
      on s.tenant_id = u.tenant_id and s.name = btrim(tool_name)
   where u.is_agent = true
     and btrim(tool_name) <> ''
  on conflict (agent_id, server_id) do nothing;

  return v_count;
end $$;

select public.mcp_backfill_from_tenants();

comment on table public.mcp_server is 'MCP 서버 정본. tenants.mcp jsonb 는 sync_tenants_mcp() 트리거가 만드는 파생 미러다.';
comment on table public.mcp_server_version is '연결정보 불변 스냅샷. 수정은 새 버전 생성으로만 이뤄진다.';
comment on table public.mcp_call_log is 'MCP 툴 호출 관측 정본. events 는 UI 스트림용 요약만 담는다.';
comment on table public.llm_call_log is 'LiteLLM 프록시 콜백이 적재하는 LLM 호출 로그. trace_id 로 mcp_call_log 와 조인된다.';
comment on function public.mcp_servers_jsonb(text) is '정본 테이블을 레거시 {"mcpServers":{...}} 형태로 투영한다.';


-- ============================================================
-- 실행 프로파일링용 페이로드 사이드카
-- ------------------------------------------------------------
-- llm_call_log / mcp_call_log 는 관측 대시보드가 풀스캔 집계하는
-- 핫 테이블이라 큰 텍스트를 넣으면 안 된다. 프롬프트·응답·툴 인자
-- 원문은 여기에 따로 두고 보존기간을 짧게 가져간다.
-- ============================================================

create table if not exists public.trace_payload (
    id bigserial primary key,
    tenant_id text not null default public.tenant_id(),
    trace_id text null,
    span_id text not null,
    span_kind text not null,            -- 'llm' | 'mcp'
    proc_inst_id text null,
    todo_id text null,
    job_id text null,
    created_at timestamp with time zone not null default now(),
    -- LLM
    messages jsonb null,                -- 마스킹된 프롬프트 배열
    completion jsonb null,              -- {content, tool_calls, finish_reason}
    model_params jsonb null,            -- temperature/max_tokens/tool_choice/tools(이름만)
    -- MCP / tool
    tool_input jsonb null,
    tool_output jsonb null,
    -- 공통
    truncated boolean not null default false,
    orig_bytes integer null
) tablespace pg_default;

-- 같은 스팬이 재전송돼도 한 행만 남게 한다 (업서트 키)
create unique index if not exists trace_payload_span_uk
    on public.trace_payload (span_id, span_kind);
create index if not exists idx_trace_payload_tenant_time
    on public.trace_payload (tenant_id, created_at desc);
create index if not exists idx_trace_payload_todo on public.trace_payload (todo_id);
create index if not exists idx_trace_payload_job on public.trace_payload (job_id);
create index if not exists idx_trace_payload_trace on public.trace_payload (trace_id);

alter table public.trace_payload enable row level security;

DO $$
BEGIN
  EXECUTE 'DROP POLICY IF EXISTS trace_payload_select_policy ON public.trace_payload';
  EXECUTE 'CREATE POLICY trace_payload_select_policy ON public.trace_payload
             FOR SELECT TO authenticated USING (tenant_id = public.tenant_id())';
  EXECUTE 'DROP POLICY IF EXISTS trace_payload_insert_policy ON public.trace_payload';
  EXECUTE 'CREATE POLICY trace_payload_insert_policy ON public.trace_payload
             FOR INSERT TO authenticated WITH CHECK (tenant_id = public.tenant_id())';
  EXECUTE 'DROP POLICY IF EXISTS trace_payload_delete_policy ON public.trace_payload';
  EXECUTE 'CREATE POLICY trace_payload_delete_policy ON public.trace_payload
             FOR DELETE TO authenticated USING (tenant_id = public.tenant_id())';
END $$;

-- ------------------------------------------------------------
-- llm_call_log: 집계·필터에 쓰이는 스칼라만 본 테이블에 추가.
-- 프롬프트·응답 본문은 위 사이드카로 간다.
-- ------------------------------------------------------------
alter table public.llm_call_log add column if not exists finish_reason text;
alter table public.llm_call_log add column if not exists model_actual text;
alter table public.llm_call_log add column if not exists user_id text;
alter table public.llm_call_log add column if not exists cache_creation_tokens integer;
alter table public.llm_call_log add column if not exists request_id text;
alter table public.llm_call_log add column if not exists api_base text;

comment on table public.trace_payload is
  '실행 프로파일링용 원문(프롬프트·응답·툴 인자). 마스킹 후 짧은 보존기간으로 유지한다.';


-- ============================================================
-- todolist 상태전이 이력 — 리드타임 분해용
--
-- 왜 필요한가:
--   완료된 사람 태스크 124건 중 task_started 이벤트는 6건뿐이다.
--   task_started/task_completed 는 에이전트 executor 만 방출하므로
--   사람이 언제 착수해서 언제 제출했는지가 어디에도 남지 않는다.
--   그 결과 정작 병목인 HITL 태스크가 워터폴에서 0초로 찍힌다.
--
--   todolist 는 현재 상태만 들고 있고 updated_at 은 이후 쓰기에 계속
--   덮인다(사람 행 중앙값 29일). task_execution_properties 는 행을
--   덮어쓰며 비종료 상태를 전부 'STARTED' 로 뭉갠다. 그래서 전이를
--   append-only 로 쌓는 테이블이 따로 필요하다.
-- ============================================================

-- 실제 착수 시각 (20260128 마이그레이션). 아래 백필 질의가 쓴다 — 새 볼륨에는 이 열이 없다
alter table public.todolist add column if not exists actual_start_date timestamptz;

create table if not exists public.todolist_status_history (
    id              bigserial primary key,
    tenant_id       text not null default public.tenant_id(),

    todo_id         uuid not null,
    proc_inst_id    text,
    activity_id     text,

    from_status     todo_status,          -- INSERT 시 null (=배정)
    to_status       todo_status not null,
    changed_at      timestamptz not null default now(),

    changed_by      text,                 -- todolist.user_id
    changed_by_is_agent boolean not null default false,

    -- 같은 todo_id 에서 IN_PROGRESS 재진입 횟수. 0 = 최초 수행, 1+ = 재작업.
    -- 같은 todo_id 가 여러 번 실행되므로(로컬 데이터의 전 태스크가 2세션)
    -- 이 값 없이 min/max 로 묶으면 태스크 길이가 며칠로 부푼다.
    rework_seq      int not null default 0,

    draft_status    draft_status,
    feedback_status text,

    -- 트리거가 남긴 실측이 아니라 과거 데이터에서 역산한 추정치인지.
    -- actual_start_date 는 COALESCE(start_date, updated_at) 로 백필된
    -- 행이 있어 대기가 0 으로 나온다. 구분하지 않으면 "대기 없음" 이라는
    -- 거짓 결론이 나온다.
    is_estimated    boolean not null default false
);

create index if not exists idx_tsh_todo      on public.todolist_status_history (todo_id, changed_at);
create index if not exists idx_tsh_inst      on public.todolist_status_history (proc_inst_id, changed_at);
create index if not exists idx_tsh_tenant    on public.todolist_status_history (tenant_id, changed_at desc);

comment on table  public.todolist_status_history is '워크아이템 상태전이 append-only 이력. 리드타임을 큐대기/사람판단/에이전트수행으로 분해하는 근거.';
comment on column public.todolist_status_history.is_estimated is '과거 데이터 백필로 역산한 추정치(실측 아님)';
comment on column public.todolist_status_history.rework_seq is 'IN_PROGRESS 재진입 횟수. 0=최초, 1+=재작업 세션';

-- ------------------------------------------------------------
-- 전이 적재 트리거
-- ------------------------------------------------------------
create or replace function public.record_todolist_status_change()
returns trigger as $$
declare
    v_from  todo_status;
    v_seq   int;
begin
    if TG_OP = 'UPDATE' then
        -- status 가 실제로 바뀐 경우만. UPDATE OF status 는 값이 같아도 발화한다.
        if NEW.status is not distinct from OLD.status then
            return NEW;
        end if;
        v_from := OLD.status;
    else
        v_from := null;   -- 배정
    end if;

    -- IN_PROGRESS 로 들어갈 때마다 세션 번호를 올린다.
    if NEW.status = 'IN_PROGRESS' then
        select count(*) into v_seq
          from public.todolist_status_history
         where todo_id = NEW.id and to_status = 'IN_PROGRESS';
    else
        select coalesce(max(rework_seq), 0) into v_seq
          from public.todolist_status_history
         where todo_id = NEW.id;
    end if;

    insert into public.todolist_status_history (
        tenant_id, todo_id, proc_inst_id, activity_id,
        from_status, to_status, changed_at,
        changed_by, changed_by_is_agent, rework_seq,
        draft_status, feedback_status, is_estimated
    ) values (
        coalesce(NEW.tenant_id, public.tenant_id()),
        NEW.id, NEW.proc_inst_id, NEW.activity_id,
        v_from, NEW.status, now(),
        NEW.user_id, (NEW.agent_mode is not null), v_seq,
        NEW.draft_status, NEW.feedback_status, false
    );

    return NEW;
end;
$$ language plpgsql;

drop trigger if exists trg_record_todolist_status_change on public.todolist;
create trigger trg_record_todolist_status_change
    after insert or update of status on public.todolist
    for each row
    execute function public.record_todolist_status_change();

-- ------------------------------------------------------------
-- 과거 데이터 백필 (1회)
--
-- 트리거는 소급되지 않는다. 기존 행에서 배정/착수/완료를 역산하되
-- 전부 is_estimated=true 로 표시한다. 근거:
--   * start_date 는 naive 이고 계획일이 들어간 행이 있다
--     (실행 09-01 인데 값이 09-13).
--   * actual_start_date 는 20260128 마이그레이션이
--     COALESCE(start_date, updated_at) 로 백필해 둔 행이 섞여 있어
--     그런 행의 대기시간은 0 이 되는데 이는 실측이 아니다.
--   * end_date 는 규칙이 깨져 있다. KST-naive 로 봐도 182건 중 140건,
--     UTC-naive 로 봐도 90건이 착수시각보다 이르다. 완료시각으로 쓰지 않는다.
-- 완료시각은 events 의 마지막 타임스탬프만 인정한다. updated_at 은 이후
-- 쓰기에 계속 덮이므로(사람 행 중앙값 29일) 완료시각으로 쓰면 사람 작업시간이
-- 29일로 찍힌다. 근거가 없으면 완료 행을 만들지 않아 "모름" 으로 남긴다 —
-- 없는 값을 지어내는 것보다 낫다. 앞으로는 트리거가 실측을 남긴다.
-- ------------------------------------------------------------
insert into public.todolist_status_history (
    tenant_id, todo_id, proc_inst_id, activity_id,
    from_status, to_status, changed_at,
    changed_by, changed_by_is_agent, rework_seq,
    draft_status, feedback_status, is_estimated
)
select * from (
    with last_evt as (
        select todo_id, max(timestamp) as ts
          from public.events
         where todo_id is not null
         group by todo_id
    ),
    base as (
        select t.*,
               -- 배정시각: naive start_date 를 UTC 로 보되, 계획일이라
               -- 착수보다 늦으면 착수시각으로 눌러 음수 대기를 만들지 않는다.
               least(
                   coalesce(t.start_date at time zone 'UTC', t.actual_start_date, t.updated_at),
                   coalesce(t.actual_start_date, t.updated_at)
               ) as assigned_at,
               t.actual_start_date as started_at,
               e.ts as finished_at   -- 이벤트 근거가 없으면 null → 완료 행 생략
          from public.todolist t
          left join last_evt e on e.todo_id = t.id::text
    )
    -- 배정
    select b.tenant_id, b.id, b.proc_inst_id, b.activity_id,
           null::todo_status, 'TODO'::todo_status, b.assigned_at,
           b.user_id, (b.agent_mode is not null), 0,
           b.draft_status, b.feedback_status, true
      from base b
     where b.assigned_at is not null

    union all
    -- 착수
    select b.tenant_id, b.id, b.proc_inst_id, b.activity_id,
           'TODO'::todo_status, 'IN_PROGRESS'::todo_status, b.started_at,
           b.user_id, (b.agent_mode is not null), 0,
           b.draft_status, b.feedback_status, true
      from base b
     where b.started_at is not null

    union all
    -- 완료 (종료 상태인 행만)
    select b.tenant_id, b.id, b.proc_inst_id, b.activity_id,
           'IN_PROGRESS'::todo_status, b.status, b.finished_at,
           b.user_id, (b.agent_mode is not null), 0,
           b.draft_status, b.feedback_status, true
      from base b
     where b.status in ('DONE','CANCELLED')
       and b.finished_at is not null
       and b.finished_at >= coalesce(b.started_at, b.assigned_at)
) s
where not exists (select 1 from public.todolist_status_history);

-- ------------------------------------------------------------
-- RLS (mcp_hub 마이그레이션과 동일 패턴)
-- ------------------------------------------------------------
alter table public.todolist_status_history enable row level security;

drop policy if exists todolist_status_history_select_policy on public.todolist_status_history;
create policy todolist_status_history_select_policy on public.todolist_status_history
    for select to authenticated using (tenant_id = public.tenant_id());

drop policy if exists todolist_status_history_insert_policy on public.todolist_status_history;
create policy todolist_status_history_insert_policy on public.todolist_status_history
    for insert to authenticated with check (tenant_id = public.tenant_id());
