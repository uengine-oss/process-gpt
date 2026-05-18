-- ===============================================
-- MIGRATION FILE WRITING GUIDE
-- ===============================================
-- 
-- 이 파일은 데이터베이스 스키마 마이그레이션을 위한 SQL 스크립트입니다.
-- 다른 개발자들이 안전하게 수정할 수 있도록 다음 가이드를 따라주세요.
--
-- ※ 중요: 이 파일은 마이그레이션용이지 초기화(INIT)용이 아닙니다.
--    - CREATE TABLE 문은 여기에 작성하지 마세요
--    - 새로운 테이블 및 함수는 init.sql 파일에 작성하세요
--    - 이 파일은 기존 테이블의 구조 변경만 처리합니다
--
-- 1. 컬럼 추가 시 주의사항:
--    - 항상 "ADD COLUMN IF NOT EXISTS" 사용
--    - 테넌트별 데이터인 경우 tenant_id 컬럼 추가
--
-- 2. 데이터 마이그레이션 시 주의사항:
--    - DO $$ BEGIN ... END $$ 블록 사용
--    - 기존 컬럼 존재 여부 확인 후 작업
--    - 데이터 백업 로직 포함
--    - RAISE NOTICE로 진행상황 로깅
--
-- 3. ENUM 타입 마이그레이션:
--    - 기존 ENUM 존재 여부 확인
--    - 임시 컬럼으로 데이터 변환
--    - 기존 컬럼 삭제 후 새 컬럼명 변경
--    - 기본값 설정 필수
--    - enum does not exist 오류: init.sql에서 해당 ENUM 타입 생성 쿼리 검색해서 실행
--
-- 4. 인덱스 및 제약조건:
--    - 유니크 인덱스는 테넌트별로 설정
--    - CHECK 제약조건은 명확한 값 범위 지정
--    - 제약조건 추가 시 DO 블록 사용하여 중복 오류 방지
--      예시: DO $$ BEGIN IF NOT EXISTS (...) THEN ALTER TABLE ... ADD CONSTRAINT ...; END IF; END $$;
--
-- 5. 함수 및 트리거:
--    - 기존 함수/트리거 삭제 후 재생성
--    - DROP IF EXISTS 사용
--
-- 6. 실시간 구독 설정:
--    - supabase_realtime publication에 테이블 추가
--    - 기존 구독 여부 확인 후 추가
--
-- 7. 테이블 삭제:
--    - DROP TABLE IF EXISTS 사용
--    - 의존성 있는 데이터 고려
--    - relation does not exist 오류: init.sql에서 해당 테이블 생성 쿼리 검색해서 실행
--
-- 8. 섹션 구분:
--    - 테이블별로 명확한 주석 구분
--    - 관련 기능끼리 그룹화
--    - 마이그레이션 순서 고려
--
-- 9. 검증 및 로깅:
--     - 마이그레이션 완료 후 상태 확인
--     - RAISE NOTICE로 결과 로깅
--     - 오류 발생 시 롤백 고려
--
-- ===============================================

-- Migration SQL for schema synchronization
create or replace function public.tenant_id()
returns text
language sql stable
as $$
    select 
        nullif(
            ((current_setting('request.jwt.claims', true)::jsonb ->>  'app_metadata')::jsonb ->> 'tenant_id'),
            ''
        )::text
$$;

-- tenants table
ALTER TABLE public.tenants ADD COLUMN IF NOT EXISTS id text;
ALTER TABLE public.tenants ADD COLUMN IF NOT EXISTS owner uuid DEFAULT auth.uid();
ALTER TABLE public.tenants ADD COLUMN IF NOT EXISTS is_deleted boolean DEFAULT false;
ALTER TABLE public.tenants ADD COLUMN IF NOT EXISTS deleted_at timestamp with time zone;
ALTER TABLE public.tenants ADD COLUMN IF NOT EXISTS mcp jsonb;
ALTER TABLE public.tenants ADD COLUMN IF NOT EXISTS skills text[];

-- user_devices table
ALTER TABLE public.user_devices ADD COLUMN IF NOT EXISTS user_email text;
ALTER TABLE public.user_devices ADD COLUMN IF NOT EXISTS device_token text;

-- users table
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS id uuid;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS username text;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS profile text DEFAULT '/images/defaultUser.png';
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS email text;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS is_admin boolean DEFAULT false;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS role text;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS tenant_id text;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS device_token text;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS goal text;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS persona text;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS endpoint text;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS description text;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS tools text;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS skills text;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS is_agent boolean DEFAULT false;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS model text;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS agent_type text;
ALTER TABLE public.users DROP COLUMN IF EXISTS google_credentials;
ALTER TABLE public.users DROP COLUMN IF EXISTS google_credentials_updated_at;
ALTER TABLE public.users DROP COLUMN IF EXISTS url;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS alias text;


-- configuration table
ALTER TABLE public.configuration ADD COLUMN IF NOT EXISTS key text;
ALTER TABLE public.configuration ADD COLUMN IF NOT EXISTS value jsonb;
ALTER TABLE public.configuration ADD COLUMN IF NOT EXISTS tenant_id text DEFAULT public.tenant_id();
ALTER TABLE public.configuration ADD COLUMN IF NOT EXISTS uuid uuid DEFAULT gen_random_uuid();

-- proc_map_history table
ALTER TABLE public.proc_map_history ADD COLUMN IF NOT EXISTS value jsonb;
ALTER TABLE public.proc_map_history ADD COLUMN IF NOT EXISTS created_at timestamp with time zone DEFAULT now();
ALTER TABLE public.proc_map_history ADD COLUMN IF NOT EXISTS tenant_id text DEFAULT public.tenant_id();
ALTER TABLE public.proc_map_history ADD COLUMN IF NOT EXISTS uuid uuid DEFAULT gen_random_uuid();

-- proc_def table
ALTER TABLE public.proc_def ADD COLUMN IF NOT EXISTS id text;
ALTER TABLE public.proc_def ADD COLUMN IF NOT EXISTS name text;
ALTER TABLE public.proc_def ADD COLUMN IF NOT EXISTS definition jsonb;
ALTER TABLE public.proc_def ADD COLUMN IF NOT EXISTS bpmn text;
ALTER TABLE public.proc_def ADD COLUMN IF NOT EXISTS prod_version text;
ALTER TABLE public.proc_def ADD COLUMN IF NOT EXISTS uuid uuid DEFAULT gen_random_uuid();
ALTER TABLE public.proc_def ADD COLUMN IF NOT EXISTS tenant_id text DEFAULT public.tenant_id();
ALTER TABLE public.proc_def ADD COLUMN IF NOT EXISTS isdeleted boolean DEFAULT false;
ALTER TABLE public.proc_def ADD COLUMN IF NOT EXISTS owner text;
ALTER TABLE public.proc_def ADD COLUMN IF NOT EXISTS type text;

-- proc_def_arcv table
ALTER TABLE public.proc_def_arcv ADD COLUMN IF NOT EXISTS arcv_id text;
ALTER TABLE public.proc_def_arcv ADD COLUMN IF NOT EXISTS proc_def_id text;
ALTER TABLE public.proc_def_arcv ADD COLUMN IF NOT EXISTS version text;
ALTER TABLE public.proc_def_arcv ADD COLUMN IF NOT EXISTS snapshot text;
ALTER TABLE public.proc_def_arcv ADD COLUMN IF NOT EXISTS "timeStamp" timestamp without time zone DEFAULT current_timestamp;
ALTER TABLE public.proc_def_arcv ADD COLUMN IF NOT EXISTS diff text;
ALTER TABLE public.proc_def_arcv ADD COLUMN IF NOT EXISTS message text;
ALTER TABLE public.proc_def_arcv ADD COLUMN IF NOT EXISTS uuid uuid DEFAULT gen_random_uuid();
ALTER TABLE public.proc_def_arcv ADD COLUMN IF NOT EXISTS tenant_id text DEFAULT public.tenant_id();

-- proc_def_version table
ALTER TABLE public.proc_def_version ADD COLUMN IF NOT EXISTS arcv_id text;
ALTER TABLE public.proc_def_version ADD COLUMN IF NOT EXISTS proc_def_id text;
ALTER TABLE public.proc_def_version ADD COLUMN IF NOT EXISTS version text;
ALTER TABLE public.proc_def_version ADD COLUMN IF NOT EXISTS version_tag text;
ALTER TABLE public.proc_def_version ADD COLUMN IF NOT EXISTS snapshot text;
ALTER TABLE public.proc_def_version ADD COLUMN IF NOT EXISTS definition jsonb;
ALTER TABLE public.proc_def_version ADD COLUMN IF NOT EXISTS "timeStamp" timestamp without time zone DEFAULT current_timestamp;
ALTER TABLE public.proc_def_version ADD COLUMN IF NOT EXISTS parent_version text null;
ALTER TABLE public.proc_def_version ADD COLUMN IF NOT EXISTS source_todolist_id uuid null;

-- form_def table
ALTER TABLE public.form_def ADD COLUMN IF NOT EXISTS uuid uuid DEFAULT gen_random_uuid();
ALTER TABLE public.form_def ADD COLUMN IF NOT EXISTS html text;
ALTER TABLE public.form_def ADD COLUMN IF NOT EXISTS proc_def_id text;
ALTER TABLE public.form_def ADD COLUMN IF NOT EXISTS activity_id text;
ALTER TABLE public.form_def ADD COLUMN IF NOT EXISTS tenant_id text DEFAULT public.tenant_id();
ALTER TABLE public.form_def ADD COLUMN IF NOT EXISTS id text DEFAULT '';
ALTER TABLE public.form_def ADD COLUMN IF NOT EXISTS fields_json jsonb;

-- notifications table
ALTER TABLE public.notifications ADD COLUMN IF NOT EXISTS id uuid;
ALTER TABLE public.notifications ADD COLUMN IF NOT EXISTS title text;
ALTER TABLE public.notifications ADD COLUMN IF NOT EXISTS type text;
ALTER TABLE public.notifications ADD COLUMN IF NOT EXISTS description text;
ALTER TABLE public.notifications ADD COLUMN IF NOT EXISTS is_checked boolean DEFAULT false;
ALTER TABLE public.notifications ADD COLUMN IF NOT EXISTS time_stamp timestamp with time zone DEFAULT now();
ALTER TABLE public.notifications ADD COLUMN IF NOT EXISTS user_id text;
ALTER TABLE public.notifications ADD COLUMN IF NOT EXISTS url text;
ALTER TABLE public.notifications ADD COLUMN IF NOT EXISTS from_user_id text;
ALTER TABLE public.notifications ADD COLUMN IF NOT EXISTS consumer text;
ALTER TABLE public.notifications ADD COLUMN IF NOT EXISTS tenant_id text DEFAULT public.tenant_id();

-- lock table
ALTER TABLE public.lock ADD COLUMN IF NOT EXISTS id text;
ALTER TABLE public.lock ADD COLUMN IF NOT EXISTS user_id text;
ALTER TABLE public.lock ADD COLUMN IF NOT EXISTS tenant_id text DEFAULT public.tenant_id();
ALTER TABLE public.lock ADD COLUMN IF NOT EXISTS uuid uuid DEFAULT gen_random_uuid();
DO $$ 
BEGIN
    -- tenant_id와 id 조합 유니크 제약조건
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints 
        WHERE constraint_name = 'lock_tenant_id_id_unique' 
        AND table_name = 'lock'
    ) THEN
        ALTER TABLE public.lock ADD CONSTRAINT lock_tenant_id_id_unique UNIQUE (tenant_id, id);
        RAISE NOTICE 'Added lock_tenant_id_id_unique constraint';
    ELSE
        RAISE NOTICE 'lock_tenant_id_id_unique constraint already exists';
    END IF;
END $$;

-- bpm_proc_inst table
ALTER TABLE public.bpm_proc_inst ADD COLUMN IF NOT EXISTS proc_def_id text;
ALTER TABLE public.bpm_proc_inst ADD COLUMN IF NOT EXISTS proc_inst_id text;
ALTER TABLE public.bpm_proc_inst ADD COLUMN IF NOT EXISTS proc_inst_name text;
ALTER TABLE public.bpm_proc_inst ADD COLUMN IF NOT EXISTS current_activity_ids text[];
ALTER TABLE public.bpm_proc_inst ADD COLUMN IF NOT EXISTS participants text[];
ALTER TABLE public.bpm_proc_inst ADD COLUMN IF NOT EXISTS role_bindings jsonb;
ALTER TABLE public.bpm_proc_inst ADD COLUMN IF NOT EXISTS variables_data jsonb;
ALTER TABLE public.bpm_proc_inst ADD COLUMN IF NOT EXISTS status process_status;
ALTER TABLE public.bpm_proc_inst ADD COLUMN IF NOT EXISTS tenant_id text DEFAULT public.tenant_id();
ALTER TABLE public.bpm_proc_inst ADD COLUMN IF NOT EXISTS proc_def_version text;
ALTER TABLE public.bpm_proc_inst ADD COLUMN IF NOT EXISTS version_tag text;
ALTER TABLE public.bpm_proc_inst ADD COLUMN IF NOT EXISTS version text;
ALTER TABLE public.bpm_proc_inst ADD COLUMN IF NOT EXISTS project_id uuid;
ALTER TABLE public.bpm_proc_inst ADD COLUMN IF NOT EXISTS start_date timestamp without time zone;
ALTER TABLE public.bpm_proc_inst ADD COLUMN IF NOT EXISTS end_date timestamp without time zone;
ALTER TABLE public.bpm_proc_inst ADD COLUMN IF NOT EXISTS due_date timestamp without time zone;
ALTER TABLE public.bpm_proc_inst ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW();
ALTER TABLE public.bpm_proc_inst ADD COLUMN IF NOT EXISTS is_deleted boolean DEFAULT false;
ALTER TABLE public.bpm_proc_inst ADD COLUMN IF NOT EXISTS deleted_at timestamp with time zone;
ALTER TABLE public.bpm_proc_inst ADD COLUMN IF NOT EXISTS parent_proc_inst_id text;
ALTER TABLE public.bpm_proc_inst ADD COLUMN IF NOT EXISTS root_proc_inst_id text;
ALTER TABLE public.bpm_proc_inst ADD COLUMN IF NOT EXISTS execution_scope text;
ALTER TABLE public.bpm_proc_inst ADD COLUMN IF NOT EXISTS is_clean_up boolean DEFAULT false;

-- Properly migrate current_user_ids to participants
DO $$
BEGIN
    -- Check if current_user_ids column exists
    IF EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'bpm_proc_inst' 
        AND column_name = 'current_user_ids'
    ) THEN
        -- Copy data from current_user_ids to participants for all rows
        UPDATE public.bpm_proc_inst 
        SET participants = current_user_ids 
        WHERE current_user_ids IS NOT NULL;
        
        -- Drop the old column
        ALTER TABLE public.bpm_proc_inst DROP COLUMN current_user_ids;
        
        RAISE NOTICE 'Successfully migrated current_user_ids to participants and dropped old column';
    ELSE
        RAISE NOTICE 'current_user_ids column does not exist, migration not needed';
    END IF;
END $$;

-- todolist table
ALTER TABLE public.todolist ADD COLUMN IF NOT EXISTS id uuid;
ALTER TABLE public.todolist ADD COLUMN IF NOT EXISTS user_id text;
ALTER TABLE public.todolist ADD COLUMN IF NOT EXISTS username text;
ALTER TABLE public.todolist ADD COLUMN IF NOT EXISTS proc_inst_id text;
ALTER TABLE public.todolist ADD COLUMN IF NOT EXISTS root_proc_inst_id text;
ALTER TABLE public.todolist ADD COLUMN IF NOT EXISTS proc_def_id text;
ALTER TABLE public.todolist ADD COLUMN IF NOT EXISTS version_tag text;
ALTER TABLE public.todolist ADD COLUMN IF NOT EXISTS version text;
ALTER TABLE public.todolist ADD COLUMN IF NOT EXISTS activity_id text;
ALTER TABLE public.todolist ADD COLUMN IF NOT EXISTS activity_name text;
ALTER TABLE public.todolist ADD COLUMN IF NOT EXISTS start_date timestamp without time zone;
ALTER TABLE public.todolist ADD COLUMN IF NOT EXISTS end_date timestamp without time zone;
ALTER TABLE public.todolist ADD COLUMN IF NOT EXISTS status todo_status;
ALTER TABLE public.todolist ADD COLUMN IF NOT EXISTS description text;
ALTER TABLE public.todolist ADD COLUMN IF NOT EXISTS tool text;
ALTER TABLE public.todolist ADD COLUMN IF NOT EXISTS due_date timestamp without time zone;
ALTER TABLE public.todolist ADD COLUMN IF NOT EXISTS tenant_id text DEFAULT public.tenant_id();
ALTER TABLE public.todolist ADD COLUMN IF NOT EXISTS reference_ids text[];
ALTER TABLE public.todolist ADD COLUMN IF NOT EXISTS adhoc boolean DEFAULT false;
ALTER TABLE public.todolist ADD COLUMN IF NOT EXISTS assignees jsonb;
ALTER TABLE public.todolist ADD COLUMN IF NOT EXISTS duration integer;
ALTER TABLE public.todolist ADD COLUMN IF NOT EXISTS output jsonb;
ALTER TABLE public.todolist ADD COLUMN IF NOT EXISTS retry integer DEFAULT 0;
ALTER TABLE public.todolist ADD COLUMN IF NOT EXISTS consumer text;
ALTER TABLE public.todolist ADD COLUMN IF NOT EXISTS log text;
ALTER TABLE public.todolist ADD COLUMN IF NOT EXISTS project_id uuid;
ALTER TABLE public.todolist ADD COLUMN IF NOT EXISTS draft jsonb;
ALTER TABLE public.todolist ADD COLUMN IF NOT EXISTS agent_mode agent_mode;
ALTER TABLE public.todolist ADD COLUMN IF NOT EXISTS agent_orch text;
ALTER TABLE public.todolist ADD COLUMN IF NOT EXISTS feedback jsonb;
ALTER TABLE public.todolist ADD COLUMN IF NOT EXISTS draft_status draft_status;
ALTER TABLE public.todolist ADD COLUMN IF NOT EXISTS updated_at timestamp with time zone default now();
ALTER TABLE public.todolist ADD COLUMN IF NOT EXISTS temp_feedback text;
ALTER TABLE public.todolist ADD COLUMN IF NOT EXISTS execution_scope text;
ALTER TABLE public.todolist ADD COLUMN IF NOT EXISTS output_url text;
ALTER TABLE public.todolist ADD COLUMN IF NOT EXISTS rework_count integer DEFAULT 0;
ALTER TABLE public.todolist ADD COLUMN IF NOT EXISTS query text;
ALTER TABLE public.todolist ADD COLUMN IF NOT EXISTS feedback_status text;
-- 기존 description 컬럼을 query 컬럼으로 변경
-- UPDATE public.todolist 
-- SET query = COALESCE(query, description) 
-- WHERE description IS NOT NULL;

-- chat_rooms table
ALTER TABLE public.chat_rooms ADD COLUMN IF NOT EXISTS id text;
ALTER TABLE public.chat_rooms ADD COLUMN IF NOT EXISTS participants jsonb;
ALTER TABLE public.chat_rooms ADD COLUMN IF NOT EXISTS message jsonb;
ALTER TABLE public.chat_rooms ADD COLUMN IF NOT EXISTS name text;
ALTER TABLE public.chat_rooms ADD COLUMN IF NOT EXISTS tenant_id text DEFAULT public.tenant_id();

-- chats table
ALTER TABLE public.chats ADD COLUMN IF NOT EXISTS uuid text;
ALTER TABLE public.chats ADD COLUMN IF NOT EXISTS id text;
ALTER TABLE public.chats ADD COLUMN IF NOT EXISTS messages jsonb;
ALTER TABLE public.chats ADD COLUMN IF NOT EXISTS tenant_id text DEFAULT public.tenant_id();
ALTER TABLE public.chats ADD COLUMN IF NOT EXISTS thread_id text;

-- chat_attachments table
ALTER TABLE public.chat_attachments ADD COLUMN IF NOT EXISTS id text;
ALTER TABLE public.chat_attachments ADD COLUMN IF NOT EXISTS file_name text;
ALTER TABLE public.chat_attachments ADD COLUMN IF NOT EXISTS file_path text;
ALTER TABLE public.chat_attachments ADD COLUMN IF NOT EXISTS chat_room_id text;
ALTER TABLE public.chat_attachments ADD COLUMN IF NOT EXISTS user_name text;
ALTER TABLE public.chat_attachments ADD COLUMN IF NOT EXISTS created_at timestamp with time zone DEFAULT now();
ALTER TABLE public.chat_attachments ADD COLUMN IF NOT EXISTS tenant_id text;

-- calendar table
ALTER TABLE public.calendar ADD COLUMN IF NOT EXISTS uid text;
ALTER TABLE public.calendar ADD COLUMN IF NOT EXISTS data jsonb;
ALTER TABLE public.calendar ADD COLUMN IF NOT EXISTS tenant_id text DEFAULT public.tenant_id();

-- user_permissions table
ALTER TABLE public.user_permissions ADD COLUMN IF NOT EXISTS id text;
ALTER TABLE public.user_permissions ADD COLUMN IF NOT EXISTS user_id uuid;
ALTER TABLE public.user_permissions ADD COLUMN IF NOT EXISTS tenant_id text DEFAULT public.tenant_id();
ALTER TABLE public.user_permissions ADD COLUMN IF NOT EXISTS proc_def_id text;
ALTER TABLE public.user_permissions ADD COLUMN IF NOT EXISTS proc_def_ids jsonb;
ALTER TABLE public.user_permissions ADD COLUMN IF NOT EXISTS readable boolean DEFAULT false;
ALTER TABLE public.user_permissions ADD COLUMN IF NOT EXISTS writable boolean DEFAULT false;
ALTER TABLE public.user_permissions ADD COLUMN IF NOT EXISTS deployable boolean DEFAULT false;

-- proc_def_marketplace table
ALTER TABLE public.proc_def_marketplace ADD COLUMN IF NOT EXISTS uuid uuid DEFAULT gen_random_uuid();
ALTER TABLE public.proc_def_marketplace ADD COLUMN IF NOT EXISTS id text;
ALTER TABLE public.proc_def_marketplace ADD COLUMN IF NOT EXISTS name text;
ALTER TABLE public.proc_def_marketplace ADD COLUMN IF NOT EXISTS definition jsonb;
ALTER TABLE public.proc_def_marketplace ADD COLUMN IF NOT EXISTS bpmn text;
ALTER TABLE public.proc_def_marketplace ADD COLUMN IF NOT EXISTS description text;
ALTER TABLE public.proc_def_marketplace ADD COLUMN IF NOT EXISTS category text;
ALTER TABLE public.proc_def_marketplace ADD COLUMN IF NOT EXISTS tags text;
ALTER TABLE public.proc_def_marketplace ADD COLUMN IF NOT EXISTS author_name text;
ALTER TABLE public.proc_def_marketplace ADD COLUMN IF NOT EXISTS author_uid text;
ALTER TABLE public.proc_def_marketplace ADD COLUMN IF NOT EXISTS image text;
ALTER TABLE public.proc_def_marketplace ADD COLUMN IF NOT EXISTS import_count integer DEFAULT 0;

-- form_def_marketplace table
ALTER TABLE public.form_def_marketplace ADD COLUMN IF NOT EXISTS uuid uuid DEFAULT gen_random_uuid();
ALTER TABLE public.form_def_marketplace ADD COLUMN IF NOT EXISTS id text DEFAULT '';
ALTER TABLE public.form_def_marketplace ADD COLUMN IF NOT EXISTS proc_def_id text;
ALTER TABLE public.form_def_marketplace ADD COLUMN IF NOT EXISTS activity_id text;
ALTER TABLE public.form_def_marketplace ADD COLUMN IF NOT EXISTS html text;
ALTER TABLE public.form_def_marketplace ADD COLUMN IF NOT EXISTS author_uid text;
ALTER TABLE public.form_def_marketplace ADD COLUMN IF NOT EXISTS fields_json jsonb;

-- tenant_oauth table
ALTER TABLE public.tenant_oauth ADD COLUMN IF NOT EXISTS tenant_id text;
ALTER TABLE public.tenant_oauth ADD COLUMN IF NOT EXISTS client_id text;
ALTER TABLE public.tenant_oauth ADD COLUMN IF NOT EXISTS client_secret text;
ALTER TABLE public.tenant_oauth ADD COLUMN IF NOT EXISTS redirect_uri text;
ALTER TABLE public.tenant_oauth ADD COLUMN IF NOT EXISTS drive_folder_id TEXT;
ALTER TABLE public.tenant_oauth ADD COLUMN IF NOT EXISTS google_credentials jsonb;
ALTER TABLE public.tenant_oauth ADD COLUMN IF NOT EXISTS google_credentials_updated_at TIMESTAMP WITH TIME ZONE;
ALTER TABLE public.tenant_oauth ADD COLUMN IF NOT EXISTS created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW();
ALTER TABLE public.tenant_oauth ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW();

-- project table
ALTER TABLE public.project ADD COLUMN IF NOT EXISTS name character varying;
ALTER TABLE public.project ADD COLUMN IF NOT EXISTS start_date date;
ALTER TABLE public.project ADD COLUMN IF NOT EXISTS end_date date;
ALTER TABLE public.project ADD COLUMN IF NOT EXISTS created_date date;
ALTER TABLE public.project ADD COLUMN IF NOT EXISTS status character varying;
ALTER TABLE public.project ADD COLUMN IF NOT EXISTS project_id uuid DEFAULT gen_random_uuid();
ALTER TABLE public.project ADD COLUMN IF NOT EXISTS user_id TEXT;
ALTER TABLE public.project ADD COLUMN IF NOT EXISTS due_date date;
ALTER TABLE public.project ADD COLUMN IF NOT EXISTS tenant_id text DEFAULT public.tenant_id();
ALTER TABLE public.project ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW();

-- milestone table
-- ALTER TABLE public.milestone ADD COLUMN IF NOT EXISTS id bigserial;
-- ALTER TABLE public.milestone ADD COLUMN IF NOT EXISTS impact_type character varying;
-- ALTER TABLE public.milestone ADD COLUMN IF NOT EXISTS impact_desc text;
-- ALTER TABLE public.milestone ADD COLUMN IF NOT EXISTS created_date date;
-- ALTER TABLE public.milestone ADD COLUMN IF NOT EXISTS task_id uuid;
-- ALTER TABLE public.milestone ADD COLUMN IF NOT EXISTS impact_id uuid;

-- task_dependency table
ALTER TABLE public.task_dependency ADD COLUMN IF NOT EXISTS id bigserial;
ALTER TABLE public.task_dependency ADD COLUMN IF NOT EXISTS lag_time integer;
ALTER TABLE public.task_dependency ADD COLUMN IF NOT EXISTS lead_time integer;
ALTER TABLE public.task_dependency ADD COLUMN IF NOT EXISTS type character varying;
ALTER TABLE public.task_dependency ADD COLUMN IF NOT EXISTS created_date date;
ALTER TABLE public.task_dependency ADD COLUMN IF NOT EXISTS task_id uuid;
ALTER TABLE public.task_dependency ADD COLUMN IF NOT EXISTS depends_id uuid;

DROP TRIGGER IF EXISTS encrypt_credentials_trigger ON public.users;

DROP FUNCTION IF EXISTS encrypt_credentials(TEXT);
DROP FUNCTION IF EXISTS decrypt_credentials(TEXT);
DROP FUNCTION IF EXISTS encrypt_credentials_trigger();


-- Add tables to supabase_realtime publication if not already added
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' AND tablename = 'chats'
    ) THEN
        alter publication supabase_realtime add table chats;
    END IF;
    
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' AND tablename = 'notifications'
    ) THEN
        alter publication supabase_realtime add table notifications;
    END IF;
    
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' AND tablename = 'todolist'
    ) THEN
        alter publication supabase_realtime add table todolist;
    END IF;
    
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' AND tablename = 'bpm_proc_inst'
    ) THEN
        alter publication supabase_realtime add table bpm_proc_inst;
    END IF;
    
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' AND tablename = 'proc_def'
    ) THEN
        alter publication supabase_realtime add table proc_def;
    END IF;
END $$;

DROP TABLE IF EXISTS public.agents;

--events table
ALTER TABLE public.events ADD COLUMN IF NOT EXISTS id text;
ALTER TABLE public.events ADD COLUMN IF NOT EXISTS job_id text;
ALTER TABLE public.events ADD COLUMN IF NOT EXISTS todo_id text;
ALTER TABLE public.events ADD COLUMN IF NOT EXISTS proc_inst_id text;
ALTER TABLE public.events ADD COLUMN IF NOT EXISTS event_type event_type_enum;
ALTER TABLE public.events ADD COLUMN IF NOT EXISTS crew_type text;
ALTER TABLE public.events ADD COLUMN IF NOT EXISTS data jsonb;
ALTER TABLE public.events ADD COLUMN IF NOT EXISTS status event_status;


-- ==========================================
-- 데이터소스 테이블
-- ==========================================
ALTER TABLE IF EXISTS public.data_source ADD COLUMN IF NOT EXISTS uuid uuid DEFAULT gen_random_uuid();
ALTER TABLE IF EXISTS public.data_source ADD COLUMN IF NOT EXISTS key text;
ALTER TABLE IF EXISTS public.data_source ADD COLUMN IF NOT EXISTS value jsonb;
ALTER TABLE IF EXISTS public.data_source ADD COLUMN IF NOT EXISTS version integer DEFAULT 1;
ALTER TABLE IF EXISTS public.data_source ADD COLUMN IF NOT EXISTS description text;
ALTER TABLE IF EXISTS public.data_source ADD COLUMN IF NOT EXISTS tenant_id text DEFAULT public.tenant_id();
ALTER TABLE IF EXISTS public.data_source ADD COLUMN IF NOT EXISTS created_at timestamp with time zone DEFAULT now();
ALTER TABLE IF EXISTS public.data_source ADD COLUMN IF NOT EXISTS updated_at timestamp with time zone DEFAULT now();

-- 유니크 인덱스 (테넌트별 key + version)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'data_source' AND table_schema = 'public') THEN
        CREATE UNIQUE INDEX IF NOT EXISTS unique_data_source_key_version_per_tenant
          ON data_source (key, version, tenant_id);
    END IF;
END $$;

-- ===============================================
-- Enum 타입 마이그레이션
-- ===============================================

-- 1. Enum 타입 생성 (이미 존재하지 않는 경우에만)
DO $$
BEGIN
    -- 프로세스 인스턴스 상태 enum
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'process_status') THEN
        CREATE TYPE process_status AS ENUM ('NEW', 'RUNNING', 'COMPLETED');
        RAISE NOTICE 'Created process_status enum type';
    ELSE
        RAISE NOTICE 'process_status enum type already exists';
    END IF;

    -- 할일 항목 상태 enum
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'todo_status') THEN
        CREATE TYPE todo_status AS ENUM ('NEW', 'TODO', 'IN_PROGRESS', 'SUBMITTED', 'PENDING', 'DONE', 'CANCELLED');
        RAISE NOTICE 'Created todo_status enum type';
    ELSE
        IF NOT EXISTS (
            SELECT 1 FROM pg_enum 
            WHERE enumtypid = (SELECT oid FROM pg_type WHERE typname = 'todo_status')
            AND enumlabel = 'NEW'
        ) THEN
            ALTER TYPE todo_status ADD VALUE 'NEW';
            RAISE NOTICE 'Added NEW value to todo_status enum type';
        ELSE
            RAISE NOTICE 'NEW value already exists in todo_status enum type';
        END IF;
    END IF;

    -- 에이전트 모드 enum
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'agent_mode') THEN
        CREATE TYPE agent_mode AS ENUM ('DRAFT', 'COMPLETE');
        RAISE NOTICE 'Created agent_mode enum type';
    ELSE
        RAISE NOTICE 'agent_mode enum type already exists';
    END IF;

    -- 이벤트 타입 enum
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'event_type_enum') THEN
        CREATE TYPE event_type_enum AS ENUM (
            'task_started','task_completed','tool_usage_started',
            'tool_usage_finished','crew_completed','human_asked', 'human_response', 'human_checked', 'task_working', 'error'
        );
        RAISE NOTICE 'Created event_type_enum enum type';
    ELSE
        -- 기존 enum에 error 값 추가
        IF NOT EXISTS (
            SELECT 1 FROM pg_enum 
            WHERE enumtypid = (SELECT oid FROM pg_type WHERE typname = 'event_type_enum')
            AND enumlabel = 'error'
        ) THEN
            ALTER TYPE event_type_enum ADD VALUE 'error';
            RAISE NOTICE 'Added error value to event_type_enum enum type';
        ELSE
            RAISE NOTICE 'error value already exists in event_type_enum enum type';
        END IF;
        
        -- 기존 enum에 human_checked 값 추가
        IF NOT EXISTS (
            SELECT 1 FROM pg_enum 
            WHERE enumtypid = (SELECT oid FROM pg_type WHERE typname = 'event_type_enum')
            AND enumlabel = 'human_checked'
        ) THEN
            ALTER TYPE event_type_enum ADD VALUE 'human_checked';
            RAISE NOTICE 'Added human_checked value to event_type_enum enum type';
        ELSE
            RAISE NOTICE 'human_checked value already exists in event_type_enum enum type';
        END IF;
        
        -- 기존 enum에 task_working 값 추가
        IF NOT EXISTS (
            SELECT 1 FROM pg_enum 
            WHERE enumtypid = (SELECT oid FROM pg_type WHERE typname = 'event_type_enum')
            AND enumlabel = 'task_working'
        ) THEN
            ALTER TYPE event_type_enum ADD VALUE 'task_working';
            RAISE NOTICE 'Added task_working value to event_type_enum enum type';
        ELSE
            RAISE NOTICE 'task_working value already exists in event_type_enum enum type';
        END IF;
    END IF;

    -- 드래프트 상태 enum
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'draft_status') THEN
        CREATE TYPE draft_status AS ENUM ('STARTED', 'CANCELLED', 'COMPLETED', 'FB_REQUESTED', 'HUMAN_ASKED', 'FAILED');
        RAISE NOTICE 'Created draft_status enum type';
    ELSE
        RAISE NOTICE 'draft_status enum type already exists';
    END IF;

    -- 이벤트 상태 enum
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'event_status') THEN
        CREATE TYPE event_status AS ENUM ('ASKED', 'APPROVED', 'REJECTED');
        RAISE NOTICE 'Created event_status enum type';
    ELSE
        RAISE NOTICE 'event_status enum type already exists';
    END IF;
END $$;

-- 2. bpm_proc_inst 테이블 status 컬럼 마이그레이션
DO $$
BEGIN
    -- status 컬럼이 text 타입인지 확인
    IF EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'bpm_proc_inst' 
        AND column_name = 'status' 
        AND data_type = 'text'
    ) THEN
        -- 임시 컬럼 추가
        ALTER TABLE public.bpm_proc_inst ADD COLUMN IF NOT EXISTS status_new process_status;
        
        -- 기존 데이터를 새 enum 타입으로 변환
        UPDATE public.bpm_proc_inst 
        SET status_new = CASE 
            WHEN status = 'NEW' THEN 'NEW'::process_status
            WHEN status = 'RUNNING' THEN 'RUNNING'::process_status
            WHEN status = 'COMPLETED' THEN 'COMPLETED'::process_status
            ELSE 'NEW'::process_status  -- 기본값 설정
        END;
        
        -- 기존 컬럼 삭제 후 새 컬럼명 변경
        ALTER TABLE public.bpm_proc_inst DROP COLUMN status;
        ALTER TABLE public.bpm_proc_inst RENAME COLUMN status_new TO status;
        
        RAISE NOTICE 'Successfully migrated bpm_proc_inst.status to process_status enum';
    ELSE
        RAISE NOTICE 'bpm_proc_inst.status is already process_status enum or column does not exist';
    END IF;
END $$;

-- 3. todolist 테이블 status 컬럼 마이그레이션
DO $$
BEGIN
    -- status 컬럼이 text 타입인지 확인
    IF EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'todolist' 
        AND column_name = 'status' 
        AND data_type = 'text'
    ) THEN
        -- 임시 컬럼 추가
        ALTER TABLE public.todolist ADD COLUMN IF NOT EXISTS status_new todo_status;
        
        -- 기존 데이터를 새 enum 타입으로 변환
        UPDATE public.todolist 
        SET status_new = CASE 
            WHEN status = 'NEW' THEN 'NEW'::todo_status
            WHEN status = 'TODO' THEN 'TODO'::todo_status
            WHEN status = 'IN_PROGRESS' THEN 'IN_PROGRESS'::todo_status
            WHEN status = 'DONE' THEN 'DONE'::todo_status
            WHEN status = 'SUBMITTED' THEN 'SUBMITTED'::todo_status
            WHEN status = 'PENDING' THEN 'PENDING'::todo_status
            WHEN status = 'CANCELLED' THEN 'CANCELLED'::todo_status
            ELSE 'TODO'::todo_status  -- 기본값 설정
        END;
        
        -- 기존 컬럼 삭제 후 새 컬럼명 변경
        ALTER TABLE public.todolist DROP COLUMN status;
        ALTER TABLE public.todolist RENAME COLUMN status_new TO status;
        
        RAISE NOTICE 'Successfully migrated todolist.status to todo_status enum';
    ELSE
        RAISE NOTICE 'todolist.status is already todo_status enum or column does not exist';
    END IF;
END $$;

-- 4. todolist 테이블 agent_mode 컬럼 마이그레이션
DO $$
BEGIN
    -- agent_mode 컬럼이 text 타입인지 확인
    IF EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'todolist' 
        AND column_name = 'agent_mode' 
        AND data_type = 'text'
    ) THEN
        -- 임시 컬럼 추가
        ALTER TABLE public.todolist ADD COLUMN IF NOT EXISTS agent_mode_new agent_mode;
        
        -- 기존 데이터를 새 enum 타입으로 변환
        UPDATE public.todolist 
        SET agent_mode_new = CASE 
            WHEN agent_mode = 'NONE' THEN 'NONE'::agent_mode
            WHEN agent_mode = 'A2A' THEN 'A2A'::agent_mode
            WHEN agent_mode = 'DRAFT' THEN 'DRAFT'::agent_mode
            WHEN agent_mode = 'COMPLETE' THEN 'COMPLETE'::agent_mode
            ELSE 'NONE'::agent_mode  -- 기본값 설정
        END;
        
        -- 기존 컬럼 삭제 후 새 컬럼명 변경
        ALTER TABLE public.todolist DROP COLUMN agent_mode;
        ALTER TABLE public.todolist RENAME COLUMN agent_mode_new TO agent_mode;
        
        RAISE NOTICE 'Successfully migrated todolist.agent_mode to agent_mode enum';
    ELSE
        RAISE NOTICE 'todolist.agent_mode is already agent_mode enum or column does not exist';
    END IF;
END $$;

-- 4. todolist 테이블 draft_status 컬럼 마이그레이션
DO $$
BEGIN
    -- draft_status 컬럼이 text 타입인지 확인
    IF EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'todolist' 
        AND column_name = 'draft_status' 
        AND data_type = 'text'
    ) THEN
        -- 임시 컬럼 추가
        ALTER TABLE public.todolist ADD COLUMN IF NOT EXISTS draft_status_new draft_status;
        
        -- 기존 데이터를 새 enum 타입으로 변환 (정확 스펠링 기준, 최소 매핑)
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
        
        -- 기존 컬럼 삭제 후 새 컬럼명 변경
        ALTER TABLE public.todolist DROP COLUMN draft_status;
        ALTER TABLE public.todolist RENAME COLUMN draft_status_new TO draft_status;
        
        RAISE NOTICE 'Successfully migrated todolist.draft_status to draft_status enum';
    ELSE
        RAISE NOTICE 'todolist.draft_status is already draft_status enum or column does not exist';
    END IF;
END $$;


-- 2) events.event_type 컬럼 마이그레이션 (임시 컬럼 → 이관 → 드롭 → 리네임)
DO $$
BEGIN
IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'events'
    AND column_name = 'event_type' AND data_type = 'text'
) THEN
    ALTER TABLE public.events ADD COLUMN IF NOT EXISTS event_type_new event_type_enum;
    
    UPDATE public.events
    SET event_type_new = CASE
    WHEN event_type = 'task_started' THEN 'task_started'::event_type_enum
    WHEN event_type = 'task_completed' THEN 'task_completed'::event_type_enum
    WHEN event_type = 'tool_usage_started' THEN 'tool_usage_started'::event_type_enum
    WHEN event_type = 'tool_usage_finished' THEN 'tool_usage_finished'::event_type_enum
    WHEN event_type = 'crew_completed' THEN 'crew_completed'::event_type_enum
    WHEN event_type = 'human_asked' THEN 'human_asked'::event_type_enum
    WHEN event_type = 'human_response' THEN 'human_response'::event_type_enum
    WHEN event_type = 'error' THEN 'error'::event_type_enum
    ELSE NULL  -- 기본값을 NULL로 설정
    END;
    
    ALTER TYPE event_type_enum ADD VALUE IF NOT EXISTS 'human_response';
    ALTER TYPE event_type_enum ADD VALUE IF NOT EXISTS 'error';
    ALTER TABLE public.events DROP COLUMN event_type;
    ALTER TABLE public.events RENAME COLUMN event_type_new TO event_type;
    
    RAISE NOTICE 'Successfully migrated events.event_type to event_type_enum';
ELSE
    RAISE NOTICE 'events.event_type is already event_type_enum or column does not exist';
END IF;
END $$;

-- 3) events.status 컬럼 마이그레이션 (임시 컬럼 → 이관 → 드롭 → 리네임)
DO $$
BEGIN
IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'events'
    AND column_name = 'status' AND data_type = 'text'
) THEN
    ALTER TABLE public.events ADD COLUMN IF NOT EXISTS status_new event_status;
    
    UPDATE public.events
    SET status_new = CASE
    WHEN status = 'ASKED' THEN 'ASKED'::event_status
    WHEN status = 'APPROVED' THEN 'APPROVED'::event_status
    WHEN status = 'REJECTED' THEN 'REJECTED'::event_status
    ELSE NULL  -- 기본값을 NULL로 설정
    END;
    
    ALTER TABLE public.events DROP COLUMN status;
    ALTER TABLE public.events RENAME COLUMN status_new TO status;
    
    RAISE NOTICE 'Successfully migrated events.status to event_status enum';
ELSE
    RAISE NOTICE 'events.status is already event_status enum or column does not exist';
END IF;
END $$;

-- 6. 마이그레이션 완료 확인
DO $$
BEGIN
    RAISE NOTICE '=== Enum Migration Summary ===';
    
    -- bpm_proc_inst status 확인
    IF EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'bpm_proc_inst' 
        AND column_name = 'status' 
        AND udt_name = 'process_status'
    ) THEN
        RAISE NOTICE 'bpm_proc_inst.status: process_status enum';
    ELSE
        RAISE NOTICE 'bpm_proc_inst.status: not migrated';
    END IF;
    
    -- todolist status 확인
    IF EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'todolist' 
        AND column_name = 'status' 
        AND udt_name = 'todo_status'
    ) THEN
        RAISE NOTICE 'todolist.status: todo_status enum';
    ELSE
        RAISE NOTICE 'todolist.status: not migrated';
    END IF;
    
    -- todolist agent_mode 확인
    IF EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'todolist' 
        AND column_name = 'agent_mode' 
        AND udt_name = 'agent_mode'
    ) THEN
        RAISE NOTICE 'todolist.agent_mode: agent_mode enum';
    ELSE
        RAISE NOTICE 'todolist.agent_mode: not migrated';
    END IF;
    
    -- todolist draft_status 확인
    IF EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'todolist' 
        AND column_name = 'draft_status' 
        AND udt_name = 'draft_status'
    ) THEN
        RAISE NOTICE 'todolist.draft_status: draft_status enum';
    ELSE
        RAISE NOTICE 'todolist.draft_status: not migrated';
    END IF;
    
    -- events status 확인
    IF EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'events' 
        AND column_name = 'status' 
        AND udt_name = 'event_status'
    ) THEN
        RAISE NOTICE 'events.status: event_status enum';
    ELSE
        RAISE NOTICE 'events.status: not migrated';
    END IF;
    
    -- events event_type 확인
    IF EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'events' 
        AND column_name = 'event_type' 
        AND udt_name = 'event_type_enum'
    ) THEN
        RAISE NOTICE 'events.event_type: event_type_enum';
    ELSE
        RAISE NOTICE 'events.event_type: not migrated';
    END IF;
    
    RAISE NOTICE '=== Migration Complete ===';
END $$;



-- ===============================================
-- todolist.user_id 이메일을 users.id로 마이그레이션
-- ===============================================

-- 1. 마이그레이션 전 데이터 상태 확인
DO $$
DECLARE
    email_count integer;
    uuid_count integer;
    mixed_count integer;
    total_count integer;
BEGIN
    -- 전체 todolist 개수
    SELECT COUNT(*) INTO total_count FROM public.todolist WHERE user_id IS NOT NULL;
    
    -- 이메일 형식만 있는 개수 (UUID가 아닌 경우)
    SELECT COUNT(*) INTO email_count 
    FROM public.todolist 
    WHERE user_id IS NOT NULL 
    AND user_id NOT SIMILAR TO '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}';
    
    -- UUID 형식만 있는 개수
    SELECT COUNT(*) INTO uuid_count 
    FROM public.todolist 
    WHERE user_id IS NOT NULL 
    AND user_id SIMILAR TO '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}';
    
    -- 쉼표로 구분된 혼합 데이터 개수
    SELECT COUNT(*) INTO mixed_count 
    FROM public.todolist 
    WHERE user_id IS NOT NULL 
    AND user_id LIKE '%,%';
    
    RAISE NOTICE '=== Migration Status Check ===';
    RAISE NOTICE 'Total todolist with user_id: %', total_count;
    RAISE NOTICE 'Email format count: %', email_count;
    RAISE NOTICE 'UUID format count: %', uuid_count;
    RAISE NOTICE 'Mixed format (comma separated) count: %', mixed_count;
END $$;

-- 2. 이메일을 UUID로 변환하는 함수 생성
CREATE OR REPLACE FUNCTION migrate_email_to_uuid(input_text text)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
    email_part text;
    uuid_part text;
    result_part text;
    final_result text[] := '{}';
    input_array text[];
    i integer;
    user_uuid uuid;
BEGIN
    -- 입력이 null이면 null 반환
    IF input_text IS NULL THEN
        RETURN NULL;
    END IF;
    
    -- 쉼표로 분리
    input_array := string_to_array(input_text, ',');
    
    -- 각 부분을 처리
    FOR i IN 1..array_length(input_array, 1) LOOP
        result_part := trim(input_array[i]);
        
        -- 이미 UUID 형식인지 확인
        IF result_part SIMILAR TO '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' THEN
            -- 이미 UUID이므로 그대로 사용
            final_result := array_append(final_result, result_part);
        ELSE
            -- 이메일인 경우 users 테이블에서 UUID 찾기
            BEGIN
                SELECT id::text INTO user_uuid
                FROM public.users
                WHERE email = result_part
                LIMIT 1;
                
                IF user_uuid IS NOT NULL THEN
                    final_result := array_append(final_result, user_uuid::text);
                ELSE
                    -- 매칭되는 사용자가 없으면 원본 값 유지 (로그용)
                    RAISE NOTICE 'No user found for email: %', result_part;
                    final_result := array_append(final_result, result_part);
                END IF;
            EXCEPTION
                WHEN OTHERS THEN
                    -- 에러 발생 시 원본 값 유지
                    RAISE NOTICE 'Error processing: %, keeping original value', result_part;
                    final_result := array_append(final_result, result_part);
            END;
        END IF;
    END LOOP;
    
    -- 결과를 쉼표로 연결하여 반환
    RETURN array_to_string(final_result, ',');
END;
$$;

-- 3. 실제 마이그레이션 실행 (수정된 버전)
DO $$
DECLARE
    migration_count integer := 0;
    error_count integer := 0;
    todolist_id uuid;
    todolist_user_id text;
BEGIN
    RAISE NOTICE 'Starting todolist.user_id migration...';
    
    -- 이메일 형식이 있는 todolist만 처리
    FOR todolist_id, todolist_user_id IN 
        SELECT id, user_id 
        FROM public.todolist 
        WHERE user_id IS NOT NULL 
        AND user_id NOT SIMILAR TO '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
    LOOP
        BEGIN
            -- 마이그레이션 함수를 사용하여 업데이트
            UPDATE public.todolist 
            SET user_id = migrate_email_to_uuid(todolist_user_id),
                updated_at = now()
            WHERE id = todolist_id;
            
            migration_count := migration_count + 1;
            
            -- 진행 상황 로그 (100개마다)
            IF migration_count % 100 = 0 THEN
                RAISE NOTICE 'Processed % records', migration_count;
            END IF;
            
        EXCEPTION
            WHEN OTHERS THEN
                error_count := error_count + 1;
                RAISE NOTICE 'Error migrating todolist ID %: %', todolist_id, SQLERRM;
        END;
    END LOOP;
    
    RAISE NOTICE '=== Migration Complete ===';
    RAISE NOTICE 'Successfully migrated: % records', migration_count;
    RAISE NOTICE 'Errors encountered: % records', error_count;
END $$;

-- 4. 마이그레이션 후 결과 확인
DO $$
DECLARE
    email_count_after integer;
    uuid_count_after integer;
    mixed_count_after integer;
    total_count_after integer;
    unmapped_count integer;
    unmapped_email text;
BEGIN
    -- 마이그레이션 후 상태 확인
    SELECT COUNT(*) INTO total_count_after FROM public.todolist WHERE user_id IS NOT NULL;
    
    SELECT COUNT(*) INTO email_count_after 
    FROM public.todolist 
    WHERE user_id IS NOT NULL 
    AND user_id NOT SIMILAR TO '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}';
    
    SELECT COUNT(*) INTO uuid_count_after 
    FROM public.todolist 
    WHERE user_id IS NOT NULL 
    AND user_id SIMILAR TO '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}';
    
    SELECT COUNT(*) INTO mixed_count_after 
    FROM public.todolist 
    WHERE user_id IS NOT NULL 
    AND user_id LIKE '%,%';
    
    -- 매핑되지 않은 이메일 개수 (users 테이블에 없는 이메일)
    SELECT COUNT(*) INTO unmapped_count 
    FROM public.todolist 
    WHERE user_id IS NOT NULL 
    AND user_id NOT SIMILAR TO '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
    AND user_id NOT LIKE '%,%';
    
    RAISE NOTICE '=== Post-Migration Status ===';
    RAISE NOTICE 'Total todolist with user_id: %', total_count_after;
    RAISE NOTICE 'Email format count (should be 0): %', email_count_after;
    RAISE NOTICE 'UUID format count: %', uuid_count_after;
    RAISE NOTICE 'Mixed format (comma separated) count: %', mixed_count_after;
    RAISE NOTICE 'Unmapped emails (not in users table): %', unmapped_count;
    
    -- 매핑되지 않은 이메일이 있다면 로그 출력
    IF unmapped_count > 0 THEN
        RAISE NOTICE '=== Unmapped Emails ===';
        FOR unmapped_email IN 
            SELECT DISTINCT user_id 
            FROM public.todolist 
            WHERE user_id IS NOT NULL 
            AND user_id NOT SIMILAR TO '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
            AND user_id NOT LIKE '%,%'
        LOOP
            RAISE NOTICE 'Unmapped email: %', unmapped_email;
        END LOOP;
    END IF;
END $$;

-- 5. 마이그레이션 함수 정리
DROP FUNCTION IF EXISTS migrate_email_to_uuid(text);



-- ===============================================
-- todolist.user_id를 기준으로 users.username을 todolist.username에 마이그레이션
-- ===============================================

-- 1. 마이그레이션 전 상태 확인
DO $$
DECLARE
    total_count integer;
    with_username_count integer;
    without_username_count integer;
    user_id_count integer;
BEGIN
    -- 전체 todolist 개수
    SELECT COUNT(*) INTO total_count FROM public.todolist;
    
    -- username이 있는 todolist 개수
    SELECT COUNT(*) INTO with_username_count 
    FROM public.todolist 
    WHERE username IS NOT NULL AND username != '';
    
    -- username이 없는 todolist 개수
    SELECT COUNT(*) INTO without_username_count 
    FROM public.todolist 
    WHERE username IS NULL OR username = '';
    
    -- user_id가 있는 todolist 개수
    SELECT COUNT(*) INTO user_id_count 
    FROM public.todolist 
    WHERE user_id IS NOT NULL AND user_id != '';
    
    RAISE NOTICE '=== Username Migration Status Check ===';
    RAISE NOTICE 'Total todolist: %', total_count;
    RAISE NOTICE 'Todolist with username: %', with_username_count;
    RAISE NOTICE 'Todolist without username: %', without_username_count;
    RAISE NOTICE 'Todolist with user_id: %', user_id_count;
END $$;

-- 2. user_id를 기준으로 username을 가져오는 함수 생성
CREATE OR REPLACE FUNCTION get_usernames_from_user_ids(user_ids text)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
    user_id_part text;
    username_part text;
    result_part text;
    final_result text[] := '{}';
    user_ids_array text[];
    i integer;
    user_username text;
BEGIN
    -- 입력이 null이면 null 반환
    IF user_ids IS NULL OR user_ids = '' THEN
        RETURN NULL;
    END IF;
    
    -- 쉼표로 분리
    user_ids_array := string_to_array(user_ids, ',');
    
    -- 각 부분을 처리
    FOR i IN 1..array_length(user_ids_array, 1) LOOP
        user_id_part := trim(user_ids_array[i]);
        
        -- UUID 형식인지 확인
        IF user_id_part SIMILAR TO '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' THEN
            -- UUID인 경우 users 테이블에서 username 찾기
            BEGIN
                SELECT username INTO user_username
                FROM public.users
                WHERE id::text = user_id_part
                LIMIT 1;
                
                IF user_username IS NOT NULL AND user_username != '' THEN
                    final_result := array_append(final_result, user_username);
                ELSE
                    -- username이 없으면 user_id 그대로 사용
                    RAISE NOTICE 'No username found for user_id: %', user_id_part;
                    final_result := array_append(final_result, user_id_part);
                END IF;
            EXCEPTION
                WHEN OTHERS THEN
                    -- 에러 발생 시 user_id 그대로 사용
                    RAISE NOTICE 'Error processing user_id: %, keeping original value', user_id_part;
                    final_result := array_append(final_result, user_id_part);
            END;
        ELSE
            -- UUID가 아닌 경우 (이메일 등) 그대로 사용
            final_result := array_append(final_result, user_id_part);
        END IF;
    END LOOP;
    
    -- 결과를 쉼표로 연결하여 반환
    RETURN array_to_string(final_result, ',');
END;
$$;

-- 3. 실제 마이그레이션 실행
DO $$
DECLARE
    migration_count integer := 0;
    error_count integer := 0;
    todolist_id uuid;
    todolist_user_id text;
    todolist_username text;
BEGIN
    RAISE NOTICE 'Starting todolist.username migration from user_id...';
    
    -- user_id가 있는 todolist만 처리
    FOR todolist_id, todolist_user_id, todolist_username IN 
        SELECT id, user_id, username 
        FROM public.todolist 
        WHERE user_id IS NOT NULL 
        AND user_id != ''
    LOOP
        BEGIN
            -- username이 비어있거나 null인 경우에만 업데이트
            IF todolist_username IS NULL OR todolist_username = '' THEN
                -- 마이그레이션 함수를 사용하여 username 업데이트
                UPDATE public.todolist 
                SET username = get_usernames_from_user_ids(todolist_user_id),
                    updated_at = now()
                WHERE id = todolist_id;
                
                migration_count := migration_count + 1;
                
                -- 진행 상황 로그 (100개마다)
                IF migration_count % 100 = 0 THEN
                    RAISE NOTICE 'Processed % records', migration_count;
                END IF;
            END IF;
            
        EXCEPTION
            WHEN OTHERS THEN
                error_count := error_count + 1;
                RAISE NOTICE 'Error migrating todolist ID %: %', todolist_id, SQLERRM;
        END;
    END LOOP;
    
    RAISE NOTICE '=== Username Migration Complete ===';
    RAISE NOTICE 'Successfully migrated: % records', migration_count;
    RAISE NOTICE 'Errors encountered: % records', error_count;
END $$;

-- 4. 마이그레이션 후 결과 확인
DO $$
DECLARE
    total_count_after integer;
    with_username_count_after integer;
    without_username_count_after integer;
    user_id_count_after integer;
    unmapped_count integer;
    unmapped_user_id text;
BEGIN
    -- 마이그레이션 후 상태 확인
    SELECT COUNT(*) INTO total_count_after FROM public.todolist;
    
    SELECT COUNT(*) INTO with_username_count_after 
    FROM public.todolist 
    WHERE username IS NOT NULL AND username != '';
    
    SELECT COUNT(*) INTO without_username_count_after 
    FROM public.todolist 
    WHERE username IS NULL OR username = '';
    
    SELECT COUNT(*) INTO user_id_count_after 
    FROM public.todolist 
    WHERE user_id IS NOT NULL AND user_id != '';
    
    -- 매핑되지 않은 user_id 개수 (users 테이블에 없는 UUID)
    SELECT COUNT(*) INTO unmapped_count 
    FROM public.todolist 
    WHERE user_id IS NOT NULL 
    AND user_id SIMILAR TO '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
    AND username = user_id; -- username이 user_id와 같은 경우 (매핑 실패)
    
    RAISE NOTICE '=== Post-Username Migration Status ===';
    RAISE NOTICE 'Total todolist: %', total_count_after;
    RAISE NOTICE 'Todolist with username: %', with_username_count_after;
    RAISE NOTICE 'Todolist without username: %', without_username_count_after;
    RAISE NOTICE 'Todolist with user_id: %', user_id_count_after;
    RAISE NOTICE 'Unmapped user_ids (not in users table): %', unmapped_count;
    
    -- 매핑되지 않은 user_id가 있다면 로그 출력
    IF unmapped_count > 0 THEN
        RAISE NOTICE '=== Unmapped User IDs ===';
        FOR unmapped_user_id IN 
            SELECT DISTINCT user_id 
            FROM public.todolist 
            WHERE user_id IS NOT NULL 
            AND user_id SIMILAR TO '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
            AND username = user_id
        LOOP
            RAISE NOTICE 'Unmapped user_id: %', unmapped_user_id;
        END LOOP;
    END IF;
END $$;

-- 5. 마이그레이션 함수 정리
DROP FUNCTION IF EXISTS get_usernames_from_user_ids(text);


-- ===============================================
-- bpm_proc_inst.participants 이메일을 users.id로 마이그레이션
-- ===============================================

-- 1. 마이그레이션 전 데이터 상태 확인
DO $$
DECLARE
    total_count integer;
    with_participants_count integer;
    email_count integer;
    uuid_count integer;
    mixed_count integer;
BEGIN
    -- 전체 bpm_proc_inst 개수
    SELECT COUNT(*) INTO total_count FROM public.bpm_proc_inst;
    
    -- participants가 있는 개수
    SELECT COUNT(*) INTO with_participants_count 
    FROM public.bpm_proc_inst 
    WHERE participants IS NOT NULL AND array_length(participants, 1) > 0;
    
    -- 이메일 형식만 있는 개수 (UUID가 아닌 경우)
    SELECT COUNT(*) INTO email_count 
    FROM public.bpm_proc_inst 
    WHERE participants IS NOT NULL 
    AND EXISTS (
        SELECT 1 FROM unnest(participants) AS p 
        WHERE p NOT SIMILAR TO '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
    );
    
    -- UUID 형식만 있는 개수
    SELECT COUNT(*) INTO uuid_count 
    FROM public.bpm_proc_inst 
    WHERE participants IS NOT NULL 
    AND NOT EXISTS (
        SELECT 1 FROM unnest(participants) AS p 
        WHERE p NOT SIMILAR TO '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
    );
    
    -- 혼합 데이터 개수 (이메일과 UUID가 섞여있는 경우)
    SELECT COUNT(*) INTO mixed_count 
    FROM public.bpm_proc_inst 
    WHERE participants IS NOT NULL 
    AND EXISTS (
        SELECT 1 FROM unnest(participants) AS p 
        WHERE p NOT SIMILAR TO '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
    )
    AND EXISTS (
        SELECT 1 FROM unnest(participants) AS p 
        WHERE p SIMILAR TO '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
    );
    
    RAISE NOTICE '=== BPM Proc Inst Participants Migration Status Check ===';
    RAISE NOTICE 'Total bpm_proc_inst: %', total_count;
    RAISE NOTICE 'With participants: %', with_participants_count;
    RAISE NOTICE 'Email format count: %', email_count;
    RAISE NOTICE 'UUID format count: %', uuid_count;
    RAISE NOTICE 'Mixed format count: %', mixed_count;
END $$;

-- 2. 이메일 배열을 UUID 배열로 변환하는 함수 생성
CREATE OR REPLACE FUNCTION migrate_participants_emails_to_uuids(participants_array text[])
RETURNS text[]
LANGUAGE plpgsql
AS $$
DECLARE
    result_array text[] := '{}';
    participant text;
    user_uuid uuid;
    i integer;
BEGIN
    -- 입력이 null이면 null 반환
    IF participants_array IS NULL OR array_length(participants_array, 1) IS NULL THEN
        RETURN NULL;
    END IF;
    
    -- 각 참가자를 처리
    FOREACH participant IN ARRAY participants_array
    LOOP
        -- 이미 UUID 형식인지 확인
        IF participant SIMILAR TO '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' THEN
            -- 이미 UUID이므로 그대로 사용
            result_array := array_append(result_array, participant);
        ELSE
            -- 이메일인 경우 users 테이블에서 UUID 찾기
            BEGIN
                SELECT id::text INTO user_uuid
                FROM public.users
                WHERE email = participant
                LIMIT 1;
                
                IF user_uuid IS NOT NULL THEN
                    result_array := array_append(result_array, user_uuid::text);
                ELSE
                    -- 매칭되는 사용자가 없으면 원본 값 유지 (로그용)
                    RAISE NOTICE 'No user found for email: %', participant;
                    result_array := array_append(result_array, participant);
                END IF;
            EXCEPTION
                WHEN OTHERS THEN
                    -- 에러 발생 시 원본 값 유지
                    RAISE NOTICE 'Error processing participant: %, keeping original value', participant;
                    result_array := array_append(result_array, participant);
            END;
        END IF;
    END LOOP;
    
    RETURN result_array;
END;
$$;

-- 3. 실제 마이그레이션 실행
DO $$
DECLARE
    migration_count integer := 0;
    error_count integer := 0;
    proc_inst_record record;
BEGIN
    RAISE NOTICE 'Starting bpm_proc_inst.participants migration...';
    
    -- participants가 있고 이메일이 포함된 bpm_proc_inst만 처리
    FOR proc_inst_record IN 
        SELECT proc_inst_id, participants 
        FROM public.bpm_proc_inst 
        WHERE participants IS NOT NULL 
        AND array_length(participants, 1) > 0
        AND EXISTS (
            SELECT 1 FROM unnest(participants) AS p 
            WHERE p NOT SIMILAR TO '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
        )
    LOOP
        BEGIN
            -- 마이그레이션 함수를 사용하여 업데이트
            UPDATE public.bpm_proc_inst 
            SET participants = migrate_participants_emails_to_uuids(proc_inst_record.participants),
                updated_at = now()
            WHERE proc_inst_id = proc_inst_record.proc_inst_id;
            
            migration_count := migration_count + 1;
            
            -- 진행 상황 로그 (50개마다)
            IF migration_count % 50 = 0 THEN
                RAISE NOTICE 'Processed % records', migration_count;
            END IF;
            
        EXCEPTION
            WHEN OTHERS THEN
                error_count := error_count + 1;
                RAISE NOTICE 'Error migrating proc_inst_id %: %', proc_inst_record.proc_inst_id, SQLERRM;
        END;
    END LOOP;
    
    RAISE NOTICE '=== Participants Migration Complete ===';
    RAISE NOTICE 'Successfully migrated: % records', migration_count;
    RAISE NOTICE 'Errors encountered: % records', error_count;
END $$;

-- 4. 마이그레이션 후 결과 확인
DO $$
DECLARE
    total_count_after integer;
    with_participants_count_after integer;
    email_count_after integer;
    uuid_count_after integer;
    mixed_count_after integer;
    unmapped_count integer;
    unmapped_email text;
BEGIN
    -- 마이그레이션 후 상태 확인
    SELECT COUNT(*) INTO total_count_after FROM public.bpm_proc_inst;
    
    SELECT COUNT(*) INTO with_participants_count_after 
    FROM public.bpm_proc_inst 
    WHERE participants IS NOT NULL AND array_length(participants, 1) > 0;
    
    SELECT COUNT(*) INTO email_count_after 
    FROM public.bpm_proc_inst 
    WHERE participants IS NOT NULL 
    AND EXISTS (
        SELECT 1 FROM unnest(participants) AS p 
        WHERE p NOT SIMILAR TO '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
    );
    
    SELECT COUNT(*) INTO uuid_count_after 
    FROM public.bpm_proc_inst 
    WHERE participants IS NOT NULL 
    AND NOT EXISTS (
        SELECT 1 FROM unnest(participants) AS p 
        WHERE p NOT SIMILAR TO '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
    );
    
    SELECT COUNT(*) INTO mixed_count_after 
    FROM public.bpm_proc_inst 
    WHERE participants IS NOT NULL 
    AND EXISTS (
        SELECT 1 FROM unnest(participants) AS p 
        WHERE p NOT SIMILAR TO '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
    )
    AND EXISTS (
        SELECT 1 FROM unnest(participants) AS p 
        WHERE p SIMILAR TO '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
    );
    
    -- 매핑되지 않은 이메일 개수 (users 테이블에 없는 이메일)
    SELECT COUNT(*) INTO unmapped_count 
    FROM public.bpm_proc_inst 
    WHERE participants IS NOT NULL 
    AND EXISTS (
        SELECT 1 FROM unnest(participants) AS p 
        WHERE p NOT SIMILAR TO '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
        AND p NOT LIKE '%,%'
    );
    
    RAISE NOTICE '=== Post-Participants Migration Status ===';
    RAISE NOTICE 'Total bpm_proc_inst: %', total_count_after;
    RAISE NOTICE 'With participants: %', with_participants_count_after;
    RAISE NOTICE 'Email format count (should be 0): %', email_count_after;
    RAISE NOTICE 'UUID format count: %', uuid_count_after;
    RAISE NOTICE 'Mixed format count: %', mixed_count_after;
    RAISE NOTICE 'Unmapped emails (not in users table): %', unmapped_count;
    
    -- 매핑되지 않은 이메일이 있다면 로그 출력
    IF unmapped_count > 0 THEN
        RAISE NOTICE '=== Unmapped Emails in Participants ===';
        FOR unmapped_email IN 
            SELECT DISTINCT p
            FROM public.bpm_proc_inst,
                 unnest(participants) AS p
            WHERE participants IS NOT NULL 
            AND p NOT SIMILAR TO '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
            AND p NOT LIKE '%,%'
        LOOP
            RAISE NOTICE 'Unmapped email: %', unmapped_email;
        END LOOP;
    END IF;
END $$;

-- 5. 마이그레이션 함수 정리
DROP FUNCTION IF EXISTS migrate_participants_emails_to_uuids(text[]);



-- ===============================================
-- draft_status enum에 FAILED 값 추가
-- ===============================================
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_enum 
        WHERE enumtypid = (SELECT oid FROM pg_type WHERE typname = 'draft_status')
        AND enumlabel = 'FAILED'
    ) THEN
        ALTER TYPE draft_status ADD VALUE 'FAILED';
        RAISE NOTICE 'Added FAILED value to draft_status enum type';
    ELSE
        RAISE NOTICE 'FAILED value already exists in draft_status enum type';
    END IF;
END $$;


-- Billing
-- credit 테이블 컬럼 추가 (IF NOT EXISTS 사용)
ALTER TABLE public.credit ADD COLUMN IF NOT EXISTS id UUID PRIMARY KEY DEFAULT gen_random_uuid();
ALTER TABLE public.credit ADD COLUMN IF NOT EXISTS name TEXT NOT NULL;
ALTER TABLE public.credit ADD COLUMN IF NOT EXISTS description TEXT;
ALTER TABLE public.credit ADD COLUMN IF NOT EXISTS type TEXT NOT NULL;
ALTER TABLE public.credit ADD COLUMN IF NOT EXISTS price DECIMAL(10,2) NOT NULL DEFAULT 0;
ALTER TABLE public.credit ADD COLUMN IF NOT EXISTS credit DECIMAL(12,3) NOT NULL DEFAULT 0;
ALTER TABLE public.credit ADD COLUMN IF NOT EXISTS badge JSONB NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE public.credit ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'inactive', 'hidden'));
ALTER TABLE public.credit ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT NOW();
ALTER TABLE public.credit ADD COLUMN IF NOT EXISTS validity_months INT DEFAULT 12;
ALTER TABLE public.credit ADD COLUMN IF NOT EXISTS tenant_id TEXT;
-- credit 테이블 제약조건 추가 (DO 블록 사용)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints 
        WHERE constraint_name = 'credit_tenant_fk' 
        AND table_name = 'credit'
    ) THEN
        ALTER TABLE public.credit ADD CONSTRAINT credit_tenant_fk 
            FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);
        RAISE NOTICE 'Added credit_tenant_fk foreign key constraint';
    ELSE
        RAISE NOTICE 'credit_tenant_fk foreign key constraint already exists';
    END IF;
END $$;


-- 크레딧 구매 테이블 컬럼 추가 (IF NOT EXISTS 사용)
ALTER TABLE public.credit_purchase ADD COLUMN IF NOT EXISTS id UUID PRIMARY KEY DEFAULT gen_random_uuid();
ALTER TABLE public.credit_purchase ADD COLUMN IF NOT EXISTS tenant_id TEXT NOT NULL;
ALTER TABLE public.credit_purchase ADD COLUMN IF NOT EXISTS added_credit DECIMAL(12,7) NOT NULL;
ALTER TABLE public.credit_purchase ADD COLUMN IF NOT EXISTS source_type TEXT NOT NULL DEFAULT 'purchase' CHECK (source_type IN ('purchase'));
ALTER TABLE public.credit_purchase ADD COLUMN IF NOT EXISTS source_id TEXT NOT NULL;
ALTER TABLE public.credit_purchase ADD COLUMN IF NOT EXISTS payment_id UUID;
ALTER TABLE public.credit_purchase ADD COLUMN IF NOT EXISTS expires_at TIMESTAMPTZ;
ALTER TABLE public.credit_purchase ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT NOW();
-- credit_purchase 테이블 제약조건 추가 (DO 블록 사용)
DO $$
BEGIN
    -- Foreign Key 제약조건들
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints 
        WHERE constraint_name = 'credit_purchase_tenant_fk' 
        AND table_name = 'credit_purchase'
    ) THEN
        ALTER TABLE public.credit_purchase ADD CONSTRAINT credit_purchase_tenant_fk 
            FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);
        RAISE NOTICE 'Added credit_purchase_tenant_fk foreign key constraint';
    ELSE
        RAISE NOTICE 'credit_purchase_tenant_fk foreign key constraint already exists';
    END IF;
    
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints 
        WHERE constraint_name = 'credit_purchase_payment_fk' 
        AND table_name = 'credit_purchase'
    ) THEN
        ALTER TABLE public.credit_purchase ADD CONSTRAINT credit_purchase_payment_fk 
            FOREIGN KEY (payment_id) REFERENCES public.payment(id);
        RAISE NOTICE 'Added credit_purchase_payment_fk foreign key constraint';
    ELSE
        RAISE NOTICE 'credit_purchase_payment_fk foreign key constraint already exists';
    END IF;
    
    -- CHECK 제약조건
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints 
        WHERE constraint_name = 'added_credit_ch' 
        AND table_name = 'credit_purchase'
    ) THEN
        ALTER TABLE public.credit_purchase ADD CONSTRAINT added_credit_ch 
            CHECK (added_credit >= 0);
        RAISE NOTICE 'Added added_credit_ch check constraint';
    ELSE
        RAISE NOTICE 'added_credit_ch check constraint already exists';
    END IF;
END $$;


-- public.credit_usage 컬럼 추가 (존재하지 않을 경우만)
ALTER TABLE public.credit_usage ADD COLUMN IF NOT EXISTS id UUID DEFAULT gen_random_uuid() PRIMARY KEY;
ALTER TABLE public.credit_usage ADD COLUMN IF NOT EXISTS tenant_id TEXT NOT NULL;
ALTER TABLE public.credit_usage ADD COLUMN IF NOT EXISTS usage_id UUID NOT NULL;
ALTER TABLE public.credit_usage ADD COLUMN IF NOT EXISTS credit_purchase_id UUID;
ALTER TABLE public.credit_usage ADD COLUMN IF NOT EXISTS used_credit DECIMAL(12,7) NOT NULL;
ALTER TABLE public.credit_usage ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT NOW();
-- credit_usage 테이블 제약조건 추가 (DO 블록 사용)
DO $$
BEGIN
    -- Foreign Key 제약조건들
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints 
        WHERE constraint_name = 'credit_usage_tenant_fk' 
        AND table_name = 'credit_usage'
    ) THEN
        ALTER TABLE public.credit_usage ADD CONSTRAINT credit_usage_tenant_fk 
            FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);
        RAISE NOTICE 'Added credit_usage_tenant_fk foreign key constraint';
    ELSE
        RAISE NOTICE 'credit_usage_tenant_fk foreign key constraint already exists';
    END IF;
    
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints 
        WHERE constraint_name = 'credit_usage_usage_fk' 
        AND table_name = 'credit_usage'
    ) THEN
        ALTER TABLE public.credit_usage ADD CONSTRAINT credit_usage_usage_fk 
            FOREIGN KEY (usage_id) REFERENCES public.usage(id);
        RAISE NOTICE 'Added credit_usage_usage_fk foreign key constraint';
    ELSE
        RAISE NOTICE 'credit_usage_usage_fk foreign key constraint already exists';
    END IF;
    
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints 
        WHERE constraint_name = 'credit_usage_purchase_fk' 
        AND table_name = 'credit_usage'
    ) THEN
        ALTER TABLE public.credit_usage ADD CONSTRAINT credit_usage_purchase_fk 
            FOREIGN KEY (credit_purchase_id) REFERENCES public.credit_purchase(id);
        RAISE NOTICE 'Added credit_usage_purchase_fk foreign key constraint';
    ELSE
        RAISE NOTICE 'credit_usage_purchase_fk foreign key constraint already exists';
    END IF;
    
    -- CHECK 제약조건
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints 
        WHERE constraint_name = 'used_credit_ch' 
        AND table_name = 'credit_usage'
    ) THEN
        ALTER TABLE public.credit_usage ADD CONSTRAINT used_credit_ch 
            CHECK (used_credit >= 0);
        RAISE NOTICE 'Added used_credit_ch check constraint';
    ELSE
        RAISE NOTICE 'used_credit_ch check constraint already exists';
    END IF;
END $$;


-- service 테이블 추가
ALTER TABLE public.service ADD COLUMN IF NOT EXISTS id         TEXT NOT NULL;
ALTER TABLE public.service ADD COLUMN IF NOT EXISTS name       TEXT;
ALTER TABLE public.service ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT NOW();
ALTER TABLE public.service ADD COLUMN IF NOT EXISTS tenant_id  TEXT;
-- service 테이블 제약조건 추가 (DO 블록 사용)
DO $$
BEGIN
    -- Primary Key 제약조건
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints 
        WHERE constraint_name = 'service_pkey' 
        AND table_name = 'service'
    ) THEN
        ALTER TABLE public.service ADD CONSTRAINT service_pkey PRIMARY KEY (id, tenant_id);
        RAISE NOTICE 'Added service_pkey primary key constraint';
    ELSE
        RAISE NOTICE 'service_pkey primary key constraint already exists';
    END IF;
    
    -- Foreign Key 제약조건
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints 
        WHERE constraint_name = 'service_tenant_fk' 
        AND table_name = 'service'
    ) THEN
        ALTER TABLE public.service ADD CONSTRAINT service_tenant_fk 
            FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);
        RAISE NOTICE 'Added service_tenant_fk foreign key constraint';
    ELSE
        RAISE NOTICE 'service_tenant_fk foreign key constraint already exists';
    END IF;
END $$;


-- service_rate 테이블 추가
ALTER TABLE public.service_rate ADD COLUMN IF NOT EXISTS id UUID PRIMARY KEY DEFAULT gen_random_uuid();
ALTER TABLE public.service_rate ADD COLUMN IF NOT EXISTS service_id TEXT NOT NULL;
ALTER TABLE public.service_rate ADD COLUMN IF NOT EXISTS tenant_id TEXT NOT NULL;
ALTER TABLE public.service_rate ADD COLUMN IF NOT EXISTS model TEXT NOT NULL;
ALTER TABLE public.service_rate ADD COLUMN IF NOT EXISTS available_from TIMESTAMPTZ NOT NULL DEFAULT now();
ALTER TABLE public.service_rate ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT now();
ALTER TABLE public.service_rate ADD COLUMN IF NOT EXISTS dimension JSONB NOT NULL DEFAULT '{}'::jsonb;
-- service_rate 테이블 제약조건 추가 (DO 블록 사용)
DO $$
BEGIN
    -- Unique 제약조건
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints 
        WHERE constraint_name = 'unique_service_dimension' 
        AND table_name = 'service_rate'
    ) THEN
        ALTER TABLE public.service_rate ADD CONSTRAINT unique_service_dimension 
            UNIQUE (service_id, tenant_id, model, available_from);
        RAISE NOTICE 'Added unique_service_dimension unique constraint';
    ELSE
        RAISE NOTICE 'unique_service_dimension unique constraint already exists';
    END IF;
    
    -- Foreign Key 제약조건들
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints 
        WHERE constraint_name = 'service_rate_tenant_id_fkey' 
        AND table_name = 'service_rate'
    ) THEN
        ALTER TABLE public.service_rate ADD CONSTRAINT service_rate_tenant_id_fkey 
            FOREIGN KEY (tenant_id) REFERENCES public.tenants (id);
        RAISE NOTICE 'Added service_rate_tenant_id_fkey foreign key constraint';
    ELSE
        RAISE NOTICE 'service_rate_tenant_id_fkey foreign key constraint already exists';
    END IF;
    
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints 
        WHERE constraint_name = 'service_rate_service_tenant_fk' 
        AND table_name = 'service_rate'
    ) THEN
        ALTER TABLE public.service_rate ADD CONSTRAINT service_rate_service_tenant_fk
            FOREIGN KEY (service_id, tenant_id)
            REFERENCES public.service (id, tenant_id)
            ON UPDATE CASCADE
            ON DELETE CASCADE;
        RAISE NOTICE 'Added service_rate_service_tenant_fk foreign key constraint';
    ELSE
        RAISE NOTICE 'service_rate_service_tenant_fk foreign key constraint already exists';
    END IF;
END $$;
CREATE INDEX IF NOT EXISTS idx_service_rate_service_tenant 
    ON public.service_rate (service_id, tenant_id);


-- usage 테이블 추가
ALTER TABLE public.usage ADD COLUMN IF NOT EXISTS id UUID DEFAULT gen_random_uuid();
ALTER TABLE public.usage ADD COLUMN IF NOT EXISTS tenant_id TEXT;
ALTER TABLE public.usage ADD COLUMN IF NOT EXISTS quantity DECIMAL(12,4) NOT NULL;
ALTER TABLE public.usage ADD COLUMN IF NOT EXISTS amount DECIMAL(12,7);
ALTER TABLE public.usage ADD COLUMN IF NOT EXISTS metadata JSONB;
ALTER TABLE public.usage ADD COLUMN IF NOT EXISTS service_rate_id UUID;
ALTER TABLE public.usage ADD COLUMN IF NOT EXISTS group_id UUID;
ALTER TABLE public.usage ADD COLUMN IF NOT EXISTS model TEXT;
ALTER TABLE public.usage ADD COLUMN IF NOT EXISTS service_id TEXT;
ALTER TABLE public.usage ADD COLUMN IF NOT EXISTS user_id TEXT;
ALTER TABLE public.usage ADD COLUMN IF NOT EXISTS agent_id TEXT;
ALTER TABLE public.usage ADD COLUMN IF NOT EXISTS process_def_id TEXT;
ALTER TABLE public.usage ADD COLUMN IF NOT EXISTS process_inst_id TEXT;
ALTER TABLE public.usage ADD COLUMN IF NOT EXISTS usage_start_at TIMESTAMPTZ NOT NULL;
ALTER TABLE public.usage ADD COLUMN IF NOT EXISTS usage_end_at TIMESTAMPTZ DEFAULT NOW();
-- usage 테이블 제약조건 추가 (DO 블록 사용)
DO $$
BEGIN
    -- Primary Key 제약조건
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints 
        WHERE constraint_name = 'usage_pkey' 
        AND table_name = 'usage'
    ) THEN
        ALTER TABLE public.usage ADD CONSTRAINT usage_pkey PRIMARY KEY (id);
        RAISE NOTICE 'Added usage_pkey primary key constraint';
    ELSE
        RAISE NOTICE 'usage_pkey primary key constraint already exists';
    END IF;
    
    -- Foreign Key 제약조건들
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints 
        WHERE constraint_name = 'usage_tenant_fk' 
        AND table_name = 'usage'
    ) THEN
        ALTER TABLE public.usage ADD CONSTRAINT usage_tenant_fk 
            FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);
        RAISE NOTICE 'Added usage_tenant_fk foreign key constraint';
    ELSE
        RAISE NOTICE 'usage_tenant_fk foreign key constraint already exists';
    END IF;
    
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints 
        WHERE constraint_name = 'usage_service_rate_fk' 
        AND table_name = 'usage'
    ) THEN
        ALTER TABLE public.usage ADD CONSTRAINT usage_service_rate_fk 
            FOREIGN KEY (service_rate_id) REFERENCES public.service_rate(id);
        RAISE NOTICE 'Added usage_service_rate_fk foreign key constraint';
    ELSE
        RAISE NOTICE 'usage_service_rate_fk foreign key constraint already exists';
    END IF;
    
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints 
        WHERE constraint_name = 'usage_service_fk' 
        AND table_name = 'usage'
    ) THEN
        ALTER TABLE public.usage ADD CONSTRAINT usage_service_fk 
            FOREIGN KEY (service_id, tenant_id) REFERENCES public.service (id, tenant_id) 
            ON UPDATE CASCADE ON DELETE RESTRICT;
        RAISE NOTICE 'Added usage_service_fk foreign key constraint';
    ELSE
        RAISE NOTICE 'usage_service_fk foreign key constraint already exists';
    END IF;
END $$;
CREATE INDEX IF NOT EXISTS idx_usage_service_id       ON public.usage(service_id);
CREATE INDEX IF NOT EXISTS idx_usage_process_def_id   ON public.usage(process_def_id);
CREATE INDEX IF NOT EXISTS idx_usage_process_inst_id  ON public.usage(process_inst_id);
CREATE INDEX IF NOT EXISTS idx_usage_tenant_master_date ON public.usage (tenant_id, service_id, usage_start_at);


-- payment 테이블 추가
-- 컬럼 추가
ALTER TABLE public.payment ADD COLUMN IF NOT EXISTS id UUID DEFAULT gen_random_uuid();
ALTER TABLE public.payment ADD COLUMN IF NOT EXISTS payment_key TEXT;
ALTER TABLE public.payment ADD COLUMN IF NOT EXISTS order_id TEXT UNIQUE;
ALTER TABLE public.payment ADD COLUMN IF NOT EXISTS order_name TEXT;
ALTER TABLE public.payment ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'READY'
    CHECK (
        status IN (
            'READY',
            'IN_PROGRESS',
            'AUTH_FAILED',
            'DONE',
            'CANCELED',
            'PARTIAL_CANCELED',
            'ABORTED',
            'EXPIRED',
            'WAITING_FOR_DEPOSIT'
        )
    );
ALTER TABLE public.payment ADD COLUMN IF NOT EXISTS receipt_url TEXT;
ALTER TABLE public.payment ADD COLUMN IF NOT EXISTS amount DECIMAL(10,2) NOT NULL;
ALTER TABLE public.payment ADD COLUMN IF NOT EXISTS approved_at TIMESTAMPTZ;
ALTER TABLE public.payment ADD COLUMN IF NOT EXISTS method TEXT;
ALTER TABLE public.payment ADD COLUMN IF NOT EXISTS user_id TEXT;
ALTER TABLE public.payment ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT now();
ALTER TABLE public.payment ADD COLUMN IF NOT EXISTS ref_type TEXT;
ALTER TABLE public.payment ADD COLUMN IF NOT EXISTS ref_id TEXT;
ALTER TABLE public.payment ADD COLUMN IF NOT EXISTS tenant_id TEXT;
-- 제약조건 추가 (DO 블록 사용)
DO $$
BEGIN
    -- Primary Key 제약조건
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints 
        WHERE constraint_name = 'payment_pkey' 
        AND table_name = 'payment'
    ) THEN
        ALTER TABLE public.payment ADD CONSTRAINT payment_pkey PRIMARY KEY (id);
        RAISE NOTICE 'Added payment_pkey primary key constraint';
    ELSE
        RAISE NOTICE 'payment_pkey primary key constraint already exists';
    END IF;
    
    -- order_id 유니크 제약조건 (테넌트별로 설정)
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints 
        WHERE constraint_name = 'payment_order_id_key' 
        AND table_name = 'payment'
    ) THEN
        -- 기존 유니크 제약조건 삭제 후 테넌트별로 재생성
        ALTER TABLE public.payment DROP CONSTRAINT IF EXISTS payment_order_id_key;
        CREATE UNIQUE INDEX IF NOT EXISTS payment_order_id_tenant_key 
            ON public.payment (order_id, tenant_id);
        RAISE NOTICE 'Added payment_order_id_tenant_key unique index';
    ELSE
        RAISE NOTICE 'payment_order_id_key constraint already exists';
    END IF;
    
    -- Foreign Key 제약조건
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints 
        WHERE constraint_name = 'payment_tenant_fk' 
        AND table_name = 'payment'
    ) THEN
        ALTER TABLE public.payment ADD CONSTRAINT payment_tenant_fk 
            FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);
        RAISE NOTICE 'Added payment_tenant_fk foreign key constraint';
    ELSE
        RAISE NOTICE 'payment_tenant_fk foreign key constraint already exists';
    END IF;
END $$;



-- proc_inst_source 테이블 추가
ALTER TABLE public.proc_inst_source ADD COLUMN IF NOT EXISTS id UUID DEFAULT gen_random_uuid();
ALTER TABLE public.proc_inst_source ADD COLUMN IF NOT EXISTS proc_inst_id TEXT;
ALTER TABLE public.proc_inst_source ADD COLUMN IF NOT EXISTS file_name TEXT;
ALTER TABLE public.proc_inst_source ADD COLUMN IF NOT EXISTS created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW();
ALTER TABLE public.proc_inst_source ADD COLUMN IF NOT EXISTS is_process BOOLEAN DEFAULT FALSE;
ALTER TABLE public.proc_inst_source ADD COLUMN IF NOT EXISTS file_path TEXT;


-- users 테이블 agent_type 컬럼 마이그레이션
UPDATE public.users SET agent_type = 'agent' WHERE is_agent = true AND agent_type IS NULL;


-- todolist 테이블 agent_orch 컬럼을 다시 text로 마이그레이션
DO $$
BEGIN
    -- agent_orch 컬럼이 enum 타입(agent_orch)인지 확인
    IF EXISTS (
        SELECT 1 
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'todolist'
          AND column_name = 'agent_orch'
          AND udt_name = 'agent_orch'
    ) THEN
        -- 임시 text 컬럼 추가
        ALTER TABLE public.todolist ADD COLUMN IF NOT EXISTS agent_orch_text text;

        -- enum 값을 text로 복사
        UPDATE public.todolist
        SET agent_orch_text = agent_orch::text;

        -- 기존 enum 컬럼 삭제 후 새 컬럼명을 agent_orch로 변경
        ALTER TABLE public.todolist DROP COLUMN agent_orch;
        ALTER TABLE public.todolist RENAME COLUMN agent_orch_text TO agent_orch;

        RAISE NOTICE 'Successfully migrated todolist.agent_orch back to text';
    ELSE
        RAISE NOTICE 'todolist.agent_orch is already text or column does not exist';
    END IF;
END $$;
