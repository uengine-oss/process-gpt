-- Enable required extensions
create extension if not exists vector;
create extension if not exists pgcrypto;

-- ==========================================
-- ENUM 타입 정의
-- ==========================================
-- 프로세스 인스턴스 상태 enum
CREATE TYPE process_status AS ENUM ('NEW', 'RUNNING', 'COMPLETED');
-- 할일 항목 상태 enum
CREATE TYPE todo_status AS ENUM ('NEW', 'TODO', 'IN_PROGRESS', 'SUBMITTED', 'PENDING', 'DONE', 'CANCELLED');
-- 에이전트 모드 enum
CREATE TYPE agent_mode AS ENUM ('DRAFT', 'COMPLETE');
-- 오케스트레이션 방식 enum
CREATE TYPE agent_orch AS ENUM ('crewai-action', 'openai-deep-research', 'crewai-deep-research', 'langchain-react', 'browser-automation-agent', 'a2a', 'visionparse');
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
  'human_response',
  'human_checked',
  'task_working',
  'error'
);
-- 이벤트 상태 enum
CREATE TYPE event_status AS ENUM ('ASKED', 'APPROVED', 'REJECTED');

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

INSERT INTO public.tenants (id, owner) VALUES ('process-gpt', null) ON CONFLICT (id) DO NOTHING;

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
    constraint users_pkey primary key (id, tenant_id),
    constraint users_tenant_id_fkey foreign key (tenant_id) references tenants (id) on update cascade on delete cascade
) tablespace pg_default;

CREATE INDEX IF NOT EXISTS idx_users_is_agent_true
  ON public.users (is_agent)
  WHERE is_agent = true;


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
    type text null,
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
    agent_orch agent_orch null,
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
    id uuid not null default gen_random_uuid (),
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
  event_type event_type_enum not null,
  status event_status null,
  crew_type text null,
  data jsonb not null,
  timestamp timestamp with time zone null default now(),
  constraint events_pkey primary key (id)
) TABLESPACE pg_default;

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
ALTER TABLE proc_def_version ENABLE ROW LEVEL SECURITY;
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
CREATE POLICY tenants_insert_policy ON tenants FOR INSERT TO authenticated, anon WITH CHECK (true);
CREATE POLICY tenants_select_policy ON tenants FOR SELECT TO authenticated, anon USING (true);
CREATE POLICY tenants_update_policy ON tenants FOR UPDATE TO authenticated, anon USING (auth.uid() = owner);
CREATE POLICY tenants_delete_policy ON tenants FOR DELETE TO authenticated USING (auth.uid() = owner);

-- Users policies
CREATE POLICY users_insert_policy ON users FOR INSERT TO authenticated, anon WITH CHECK (true);
CREATE POLICY users_select_policy ON users FOR SELECT TO authenticated, anon USING (true);
CREATE POLICY users_update_policy ON users FOR UPDATE TO authenticated USING (EXISTS (SELECT 1 FROM users WHERE users.id = auth.uid() AND users.is_admin = true) OR auth.uid() = id) WITH CHECK (true);
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

CREATE POLICY proc_def_arcv_insert_policy ON proc_def_arcv FOR INSERT TO authenticated WITH CHECK (tenant_id = public.tenant_id());
CREATE POLICY proc_def_arcv_select_policy ON proc_def_arcv FOR SELECT TO authenticated USING (tenant_id = public.tenant_id());
CREATE POLICY proc_def_arcv_update_policy ON proc_def_arcv FOR UPDATE TO authenticated USING (tenant_id = public.tenant_id());
CREATE POLICY proc_def_arcv_delete_policy ON proc_def_arcv FOR DELETE TO authenticated USING (tenant_id = public.tenant_id());

-- Proc def version policies
CREATE POLICY proc_def_version_insert_policy ON proc_def_version FOR INSERT TO authenticated WITH CHECK (tenant_id = public.tenant_id());
CREATE POLICY proc_def_version_select_policy ON proc_def_version FOR SELECT TO authenticated USING (tenant_id = public.tenant_id());
CREATE POLICY proc_def_version_update_policy ON proc_def_version FOR UPDATE TO authenticated USING (tenant_id = public.tenant_id());
CREATE POLICY proc_def_version_delete_policy ON proc_def_version FOR DELETE TO authenticated USING (tenant_id = public.tenant_id());

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
alter publication supabase_realtime add table events;



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




create table if not exists public.proc_inst_source (
    id uuid not null default gen_random_uuid (),
    proc_inst_id text null,
    file_name text null,
    created_at timestamp with time zone not null default now(),
    is_process boolean not null default false,
    file_path text null,
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




-- 1) 대기중인 작업 조회 및 상태 변경
DROP FUNCTION IF EXISTS public.crewai_deep_fetch_pending_task(integer, text);

CREATE OR REPLACE FUNCTION public.crewai_deep_fetch_pending_task(
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
  agent_orch public.agent_orch,
  temp_feedback text,
  draft_status public.draft_status,
  -- 가상 컬럼(업데이트 전 값)
  task_type public.draft_status,
  root_proc_inst_id text
) AS $$
BEGIN
  RETURN QUERY
    WITH cte AS (
      SELECT
        t.*,
        t.draft_status AS task_type   -- 원본 보관
      FROM todolist AS t
      WHERE t.status = 'IN_PROGRESS'
        AND t.agent_orch = 'crewai-deep-research'
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
         cte.task_type,
         t.root_proc_inst_id
    )
    SELECT * FROM upd;
END;
$$ LANGUAGE plpgsql VOLATILE;



-- 2) 완료된 데이터(output/feedback) 조회
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



CREATE TABLE env (
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

-- main_chat_memory 테이블 (에이전트 메모리)
CREATE TABLE IF NOT EXISTS main_chat_memory (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id TEXT NOT NULL,
    user_uid UUID NOT NULL,
    session_id TEXT,
    memory_type memory_type NOT NULL DEFAULT 'conversation',
    content TEXT NOT NULL,
    embedding vector(1536),
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    expires_at TIMESTAMPTZ,
    
    CONSTRAINT fk_main_chat_memory_user FOREIGN KEY (user_uid) REFERENCES auth.users(id) ON DELETE CASCADE
);

-- 인덱스
CREATE INDEX IF NOT EXISTS idx_main_chat_memory_tenant_user ON main_chat_memory(tenant_id, user_uid);
CREATE INDEX IF NOT EXISTS idx_main_chat_memory_session ON main_chat_memory(session_id);
CREATE INDEX IF NOT EXISTS idx_main_chat_memory_type ON main_chat_memory(memory_type);
CREATE INDEX IF NOT EXISTS idx_main_chat_memory_created ON main_chat_memory(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_main_chat_memory_expires ON main_chat_memory(expires_at) WHERE expires_at IS NOT NULL;

-- 벡터 검색 인덱스 (IVFFlat)
CREATE INDEX IF NOT EXISTS idx_main_chat_memory_embedding ON main_chat_memory 
USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);

-- RLS 활성화
ALTER TABLE main_chat_memory ENABLE ROW LEVEL SECURITY;

-- RLS 정책: 사용자는 자신의 메모리만 접근 가능
DROP POLICY IF EXISTS "main_chat_memory_user_policy" ON main_chat_memory;
CREATE POLICY "main_chat_memory_user_policy" ON main_chat_memory
    FOR ALL TO authenticated
    USING (user_uid = auth.uid() AND tenant_id = public.tenant_id());

-- 만료된 메모리 자동 삭제 함수
CREATE OR REPLACE FUNCTION delete_expired_main_chat_memory()
RETURNS void AS $$
BEGIN
    DELETE FROM main_chat_memory WHERE expires_at IS NOT NULL AND expires_at < NOW();
END;
$$ LANGUAGE plpgsql;

-- 벡터 유사도 검색 함수
CREATE OR REPLACE FUNCTION search_main_chat_memory(
    p_tenant_id TEXT,
    p_user_uid UUID,
    p_embedding vector(1536),
    p_limit INT DEFAULT 5,
    p_memory_types memory_type[] DEFAULT NULL,
    p_session_id TEXT DEFAULT NULL
)
RETURNS TABLE (
    id UUID,
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
        m.memory_type,
        m.content,
        m.metadata,
        1 - (m.embedding <=> p_embedding) AS similarity,
        m.created_at
    FROM main_chat_memory m
    WHERE m.tenant_id = p_tenant_id
      AND m.user_uid = p_user_uid
      AND (m.expires_at IS NULL OR m.expires_at > NOW())
      AND (p_memory_types IS NULL OR m.memory_type = ANY(p_memory_types))
      AND (p_session_id IS NULL OR m.session_id = p_session_id)
      AND m.embedding IS NOT NULL
    ORDER BY m.embedding <=> p_embedding
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql STABLE;




-- =============================================================================
-- Auth login/logout audit logging
-- - Records *all* login attempts (success/failure) and logout timestamps
-- - Designed to be callable even before authentication (anon role)
-- =============================================================================

-- 1) Audit table
CREATE TABLE IF NOT EXISTS public.auth_login_audit (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    created_at timestamptz NOT NULL DEFAULT now(),

    -- Can be NULL for pre-auth attempts or unknown tenant
    tenant_id text NULL,

    -- What user tried (may be NULL for OAuth-only flows)
    email text NULL,

    -- login/logout/login_oauth
    action text NOT NULL,

    -- Whether the attempt succeeded (for oauth-start we still record as true/false based on caller intent)
    success boolean NOT NULL,

    -- Optional error message on failures
    error_message text NULL,

    -- auth.users id (available only when request is authenticated)
    user_id uuid NULL,

    -- Optional client info
    ip_address text NULL,
    user_agent text NULL,

    -- Extra context (provider, headers, etc.)
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,

    CONSTRAINT auth_login_audit_tenant_fkey
        FOREIGN KEY (tenant_id) REFERENCES public.tenants(id)
        ON UPDATE CASCADE ON DELETE SET NULL,

    CONSTRAINT auth_login_audit_action_check
        CHECK (action IN ('login', 'logout', 'login_oauth'))
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_auth_login_audit_created_at ON public.auth_login_audit (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_auth_login_audit_tenant_created_at ON public.auth_login_audit (tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_auth_login_audit_email_created_at ON public.auth_login_audit (email, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_auth_login_audit_user_created_at ON public.auth_login_audit (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_auth_login_audit_action_created_at ON public.auth_login_audit (action, created_at DESC);

COMMENT ON TABLE public.auth_login_audit IS 'Login/logout audit trail (includes failed login attempts).';

-- 2) RLS
ALTER TABLE public.auth_login_audit ENABLE ROW LEVEL SECURITY;

-- Insert allowed for anon (pre-auth) and authenticated (app will write via RPC)
DROP POLICY IF EXISTS "auth_login_audit_insert_anon" ON public.auth_login_audit;
CREATE POLICY "auth_login_audit_insert_anon" ON public.auth_login_audit
    FOR INSERT TO anon
    WITH CHECK (true);

DROP POLICY IF EXISTS "auth_login_audit_insert_authenticated" ON public.auth_login_audit;
CREATE POLICY "auth_login_audit_insert_authenticated" ON public.auth_login_audit
    FOR INSERT TO authenticated
    WITH CHECK (tenant_id IS NULL OR tenant_id = public.tenant_id());

-- Select only for tenant admins (authenticated)
DROP POLICY IF EXISTS "auth_login_audit_select_admin" ON public.auth_login_audit;
CREATE POLICY "auth_login_audit_select_admin" ON public.auth_login_audit
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1
            FROM public.users u
            WHERE u.id = auth.uid()
              AND u.is_admin = true
              AND u.tenant_id = auth_login_audit.tenant_id
        )
    );

-- 3) Grants (RLS still applies)
GRANT INSERT ON public.auth_login_audit TO anon, authenticated;
GRANT SELECT ON public.auth_login_audit TO authenticated;

-- 4) RPC function: record_auth_audit
DROP FUNCTION IF EXISTS public.record_auth_audit(text, text, boolean, text, text, jsonb);

CREATE OR REPLACE FUNCTION public.record_auth_audit(
    p_action text,
    p_email text,
    p_success boolean,
    p_error_message text DEFAULT NULL,
    p_tenant_id text DEFAULT NULL,
    p_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_tenant_id text;
    v_headers jsonb;
    v_user_agent text;
    v_ip text;
BEGIN
    IF p_action IS NULL OR btrim(p_action) = '' THEN
        RAISE EXCEPTION 'p_action is required';
    END IF;

    IF p_action NOT IN ('login', 'logout', 'login_oauth') THEN
        RAISE EXCEPTION 'invalid p_action: %', p_action;
    END IF;

    -- tenant_id: prefer explicit parameter (pre-auth), otherwise use JWT-derived tenant id
    v_tenant_id := NULLIF(btrim(COALESCE(p_tenant_id, public.tenant_id())), '');

    -- Best-effort request headers extraction (may be NULL depending on execution context)
    BEGIN
        v_headers := current_setting('request.headers', true)::jsonb;
    EXCEPTION WHEN OTHERS THEN
        v_headers := NULL;
    END;

    v_user_agent := COALESCE(v_headers->>'user-agent', v_headers->>'User-Agent');

    v_ip := NULL;
    IF v_headers ? 'x-forwarded-for' THEN
        v_ip := btrim(split_part(v_headers->>'x-forwarded-for', ',', 1));
    ELSIF v_headers ? 'x-real-ip' THEN
        v_ip := btrim(v_headers->>'x-real-ip');
    END IF;

    INSERT INTO public.auth_login_audit (
        tenant_id,
        email,
        action,
        success,
        error_message,
        user_id,
        ip_address,
        user_agent,
        metadata
    ) VALUES (
        v_tenant_id,
        NULLIF(btrim(p_email), ''),
        p_action,
        p_success,
        NULLIF(btrim(p_error_message), ''),
        auth.uid(),
        NULLIF(v_ip, ''),
        NULLIF(btrim(v_user_agent), ''),
        COALESCE(p_metadata, '{}'::jsonb) || jsonb_build_object('headers', v_headers)
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.record_auth_audit(text, text, boolean, text, text, jsonb) TO anon, authenticated;


-- ======================================================================
-- ProcessGPT DB Functions (Refactor + Index Edition)
-- ======================================================================

-- 0) 공용 대기 작업 조회 및 상태 변경 (agent_orch 인자로 필터, 단건 처리 보장)
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
        -- env 분기
        AND (
              (p_env = 'dev' AND t.tenant_id = 'uengine')
           OR (p_env <> 'dev' AND t.tenant_id <> 'uengine')
        )
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

GRANT EXECUTE ON FUNCTION public.fetch_pending_task(text, text, integer, text) TO anon;

-- 1) 결과 저장 (중간/최종)
DROP FUNCTION IF EXISTS public.save_task_result(uuid, jsonb, boolean);
CREATE OR REPLACE FUNCTION public.save_task_result(
  p_todo_id uuid,
  p_payload jsonb,
  p_final   boolean
)
RETURNS void AS $$
DECLARE
  v_mode text;
BEGIN
  SELECT agent_mode INTO v_mode FROM todolist WHERE id = p_todo_id;

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

GRANT EXECUTE ON FUNCTION public.save_task_result(uuid, jsonb, boolean) TO anon;

-- 2) [신규] 이벤트 다건 저장: record_events_bulk
DROP FUNCTION IF EXISTS public.record_events_bulk(jsonb);
CREATE OR REPLACE FUNCTION public.record_events_bulk(p_events jsonb)
RETURNS void AS $$
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
$$ LANGUAGE plpgsql VOLATILE;

GRANT EXECUTE ON FUNCTION public.record_events_bulk(jsonb) TO anon;

-- 3) [신규] 컨텍스트 번들 조회: 알림 이메일 / MCP / 폼 / 에이전트(원본 행 전체)
DROP FUNCTION IF EXISTS public.fetch_context_bundle(text, text, text, text);
CREATE OR REPLACE FUNCTION public.fetch_context_bundle(
  p_proc_inst_id text,
  p_tenant_id    text,
  p_tool         text,
  p_user_ids     text
) RETURNS TABLE (
  notify_emails text,
  tenant_mcp    jsonb,
  form_id       text,
  form_fields   jsonb,
  form_html     text,
  agents        jsonb
) AS $$
DECLARE
  v_form_id text;
BEGIN
  -- 알림 이메일(사람만)
  SELECT string_agg(u.email, ',')
    INTO notify_emails
    FROM todolist t
    JOIN users u ON u.id::text = ANY(string_to_array(t.user_id, ','))
   WHERE t.proc_inst_id = p_proc_inst_id
     AND (u.is_agent IS NULL OR u.is_agent = false);

  -- MCP
  SELECT mcp INTO tenant_mcp FROM tenants WHERE id = p_tenant_id;

  -- 폼 (필요 시만)
  v_form_id := CASE
                 WHEN p_tool LIKE 'formHandler:%' THEN substring(p_tool from 12)
                 ELSE p_tool
               END;

  SELECT v_form_id,
         COALESCE(fd.fields_json, jsonb_build_array(jsonb_build_object('key', v_form_id, 'type','default','text',''))),
         fd.html
    INTO form_id, form_fields, form_html
    FROM form_def fd
   WHERE fd.id = v_form_id AND fd.tenant_id = p_tenant_id;

  -- 에이전트 목록 (user_ids 유효하면 그중 agent만, 없으면 전체 agent)
  WITH want_ids AS (
    SELECT unnest(string_to_array(COALESCE(p_user_ids, ''), ',')) AS idtxt
  ),
  valid_ids AS (
    SELECT idtxt FROM want_ids WHERE idtxt ~* '^[0-9a-f-]{8}-[0-9a-f-]{4}-[0-9a-f-]{4}-[0-9a-f-]{4}-[0-9a-f]{12}$'
  )
  SELECT jsonb_agg(to_jsonb(u))
    INTO agents
    FROM users u
   WHERE u.is_agent = true
     AND (
       (SELECT count(*) FROM valid_ids) = 0
       OR u.id::text IN (SELECT idtxt FROM valid_ids)
     );

  RETURN;
END;
$$ LANGUAGE plpgsql VOLATILE;

GRANT EXECUTE ON FUNCTION public.fetch_context_bundle(text, text, text, text) TO anon;

-- ======================================================================
-- 인덱스 (성능에 즉효)
-- ======================================================================

-- 폴링 핫패스: IN_PROGRESS + 정렬열
CREATE INDEX IF NOT EXISTS idx_todolist_inprog
ON todolist (agent_orch, tenant_id, start_date)
WHERE status = 'IN_PROGRESS';

-- 번들 RPC에서 proc_inst_id로 참여자 조회
CREATE INDEX IF NOT EXISTS idx_todolist_procinst
ON todolist (proc_inst_id);

-- 번들 RPC에서 폼 조회 (id, tenant_id 조합)
CREATE INDEX IF NOT EXISTS idx_form_def_id_tenant
ON form_def (id, tenant_id);

-- 번들 RPC에서 에이전트 풀 조회 (부분 인덱스)
CREATE INDEX IF NOT EXISTS idx_users_is_agent_true
ON users (is_agent)
WHERE is_agent = true;

-- -- ==========================================
-- -- Mem0 vector store 함수 (vecs 스키마)
-- -- ※ vecs 스키마가 있는 경우에만 아래 함수 생성 쿼리들을 실행하세요
-- -- ==========================================
-- -- 조회 (agent_id 필터링 + limit)
-- create or replace function public.get_memories(agent text, lim int default 100)
-- returns setof vecs.memories
-- language sql stable
-- security definer
-- as $$
--   select *
--   from vecs.memories
--   where (agent is null or metadata->>'agent_id' = agent)
--   order by id
--   limit lim;
-- $$;

-- -- 단일 행 삭제
-- create or replace function public.delete_memory(mem_id text)
-- returns void
-- language sql volatile
-- security definer
-- as $$
--   delete from vecs.memories where id = mem_id;
-- $$;

-- -- 특정 agent_id의 모든 메모리 삭제
-- create or replace function public.delete_memories_by_agent(agent text)
-- returns void
-- language sql volatile
-- security definer
-- as $$
--   delete from vecs.memories where metadata->>'agent_id' = agent;
-- $$;

