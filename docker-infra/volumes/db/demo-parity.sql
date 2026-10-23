-- 시연 스키마 보정 — 라이브 DB(시연 녹화 환경)와 init.sql 의 차이. scratchpad gen_parity.py 로 생성, 새 볼륨에서 검증.
SET check_function_bodies = false;
SET client_min_messages = warning;
SET search_path = public, extensions;

-- 1) enum
DO $p$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname='agent_orch' AND typnamespace='public'::regnamespace) THEN CREATE TYPE public.agent_orch AS ENUM ('crewai-action', 'openai-deep-research', 'crewai-deep-research', 'langchain-react', 'browser-automation-agent', 'a2a', 'visionparse'); END IF; END $p$;

-- 2) 함수 38개
DROP FUNCTION IF EXISTS public.duplicate_definition_from_marketplace(p_definition_id text, p_definition_name text, p_author_uid text, p_tenant_id text);
DROP FUNCTION IF EXISTS public.fetch_pending_task(p_agent_orch text, p_consumer text, p_limit integer, p_env text);
CREATE OR REPLACE FUNCTION public.auto_transition_public_feedback()
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    transitioned_count INTEGER := 0;
    rec RECORD;
BEGIN
    FOR rec IN
        SELECT id, proc_def_id, tenant_id
        FROM proc_def_approval_state
        WHERE state = 'public_feedback'
          AND public_feedback_ends_at IS NOT NULL
          AND public_feedback_ends_at <= NOW()
          AND public_feedback_auto_transitioned = FALSE
    LOOP
        UPDATE proc_def_approval_state
        SET state = 'final_edit',
            public_feedback_auto_transitioned = TRUE,
            updated_at = NOW()
        WHERE id = rec.id;

        INSERT INTO proc_def_approval_history
            (proc_def_id, review_id, action, from_state, to_state, actor_id, actor_name, comment, tenant_id)
        VALUES
            (rec.proc_def_id, rec.id, 'auto_transition_final_edit', 'public_feedback', 'final_edit',
             'system', 'System', '30일 공람 기간 만료로 자동 전환', rec.tenant_id);

        transitioned_count := transitioned_count + 1;
    END LOOP;
    RETURN transitioned_count;
END;
$function$;
CREATE OR REPLACE FUNCTION public.backfill_proc_def_property(p_key text, p_tenant text)
 RETURNS integer
 LANGUAGE sql
AS $function$
    WITH updated AS (
        UPDATE public.proc_def
           SET definition = COALESCE(definition, '{}'::jsonb)
                          || jsonb_build_object(p_key, null)
         WHERE tenant_id = p_tenant
           AND NOT (COALESCE(definition, '{}'::jsonb) ? p_key)
        RETURNING 1
    )
    SELECT COUNT(*)::int FROM updated;
$function$;
CREATE OR REPLACE FUNCTION public.check_process_permission_v2(p_proc_def_id text, p_user_id uuid DEFAULT NULL::uuid, p_user_organizations text[] DEFAULT NULL::text[])
 RETURNS TABLE(id text, user_id uuid, proc_def_id text, readable boolean, executable boolean, writable boolean, target_type text, permission_level text, org_group_id uuid, organization_id text)
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
    BEGIN
        RETURN QUERY
        WITH user_org_groups AS (
            -- 사용자가 속한 조직 그룹 조회
            SELECT DISTINCT ocg.id AS group_id
            FROM org_chart_groups ocg
            JOIN org_chart_group_teams ocgt ON ocgt.group_id = ocg.id
            WHERE ocgt.team_id = ANY(p_user_organizations)
            AND ocg.tenant_id = public.tenant_id()
        ),
        all_permissions AS (
            SELECT up.*
            FROM user_permissions up
            WHERE up.tenant_id = public.tenant_id()
            AND (
                -- 직접 사용자 권한
                (up.target_type = 'user' AND up.user_id = p_user_id)
                -- 조직 권한
                OR (up.target_type = 'organization' AND up.organization_id = ANY(p_user_organizations))
                -- 조직 그룹 권한
                OR (up.target_type = 'org_group' AND up.org_group_id IN (SELECT group_id FROM user_org_groups))
            )
        )
        SELECT
            ap.id,
            ap.user_id,
            ap.proc_def_id,
            ap.readable,
            ap.executable,
            ap.writable,
            ap.target_type,
            ap.permission_level,
            ap.org_group_id,
            ap.organization_id
        FROM all_permissions ap
        WHERE (
            -- 직접 매칭
            ap.proc_def_id = p_proc_def_id
            -- 또는 계층적 매칭 (proc_def_ids JSONB 내에서)
            OR EXISTS (
                SELECT 1
                FROM jsonb_array_elements(ap.proc_def_ids->'major_proc_list') AS major_proc,
                    jsonb_array_elements(major_proc->'sub_proc_list') AS sub_proc
                WHERE ap.proc_def_ids->>'id' = p_proc_def_id
                OR major_proc->>'id' = p_proc_def_id
                OR sub_proc->>'id' = p_proc_def_id
            )
        );
    END;
    $function$;
CREATE OR REPLACE FUNCTION public.cleanup_expired_locks()
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_deleted_count INTEGER;
BEGIN
    DELETE FROM public.tb_bpmn_model_lock
    WHERE expires_at IS NOT NULL AND expires_at < NOW();
    GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
    RETURN v_deleted_count;
END;
$function$;
CREATE OR REPLACE FUNCTION public.current_user_role()
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
AS $function$
DECLARE
  v_role text;
  v_uid  uuid;
  v_is_admin boolean;
  v_jwt_role text;
BEGIN
  -- 1) JWT에서 user id 추출
  BEGIN
    v_uid := (current_setting('request.jwt.claims', true)::json ->> 'sub')::uuid;
  EXCEPTION WHEN OTHERS THEN
    v_uid := NULL;
  END;

  -- 2) users 테이블에서 최신 role 조회 (Single Source of Truth)
  IF v_uid IS NOT NULL THEN
    SELECT u.role, u.is_admin
    INTO v_role, v_is_admin
    FROM public.users u
    WHERE u.id = v_uid
      AND u.tenant_id = public.tenant_id()
    LIMIT 1;

    IF v_role IS NOT NULL AND public.get_role_level(v_role) > 0 THEN
      RETURN lower(v_role);
    END IF;

    -- role 컬럼이 비어있으면 is_admin 플래그로 판단
    IF v_is_admin = true THEN
      RETURN 'admin';
    END IF;

    -- DB에 사용자는 있지만 role이 없으면 viewer
    IF v_role IS NOT NULL OR v_is_admin IS NOT NULL THEN
      RETURN 'viewer';
    END IF;
  END IF;

  -- 3) DB 조회 불가 시 JWT claims fallback
  BEGIN
    v_jwt_role := coalesce(
      current_setting('request.jwt.claims', true)::json ->> 'user_role',
      current_setting('request.jwt.claims', true)::json ->> 'role'
    );
  EXCEPTION WHEN OTHERS THEN
    v_jwt_role := NULL;
  END;

  IF v_jwt_role IS NOT NULL
     AND v_jwt_role NOT IN ('authenticated', 'anon', 'service_role', '')
     AND public.get_role_level(v_jwt_role) > 0
  THEN
    RETURN lower(v_jwt_role);
  END IF;

  -- 4) 기본값
  RETURN 'viewer';
END;
$function$;
CREATE OR REPLACE FUNCTION public.duplicate_definition_from_marketplace(p_definition_id text, p_definition_name text, p_tenant_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_proc_def_record RECORD;
    v_form_def_record RECORD;
    v_proc_def_uuid UUID;
    v_form_def_uuid UUID;
    v_new_definition_id TEXT;
    v_new_definition JSONB;
    v_activities JSONB;
    v_activity JSONB;
    v_tool TEXT;
    v_form_id TEXT;
BEGIN
    SELECT *
      INTO v_proc_def_record
      FROM public.proc_def_marketplace
     WHERE id = p_definition_id
       AND name = p_definition_name;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'Process definition not found in marketplace');
    END IF;

    v_new_definition_id := p_definition_id || '_' || gen_random_uuid()::TEXT;

    v_new_definition := v_proc_def_record.definition;
    v_new_definition := jsonb_set(
        v_new_definition,
        '{processDefinitionId}',
        to_jsonb(v_new_definition_id)
    );

    v_activities := COALESCE(v_new_definition->'activities', '[]'::jsonb);

    FOR v_activity IN SELECT * FROM jsonb_array_elements(v_activities)
    LOOP
        v_tool := v_activity->>'tool';
        IF v_tool = 'form' THEN
            v_form_id := v_activity->>'form';
            IF v_form_id IS NOT NULL AND v_form_id <> '' THEN
                v_new_definition := replace(v_new_definition::TEXT, v_form_id, v_new_definition_id || '_' || v_form_id)::jsonb;
            END IF;
        END IF;
    END LOOP;

    INSERT INTO public.proc_def (
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
        bpmn = EXCLUDED.bpmn;

    SELECT uuid
      INTO v_proc_def_uuid
      FROM public.proc_def
     WHERE id = v_new_definition_id
       AND tenant_id = p_tenant_id;

    FOR v_form_def_record IN
        SELECT *
          FROM public.form_def_marketplace
         WHERE proc_def_id = p_definition_id
    LOOP
        v_form_id := v_form_def_record.id;

        INSERT INTO public.form_def (
            id,
            proc_def_id,
            activity_id,
            html,
            tenant_id
        ) VALUES (
            v_new_definition_id || '_' || v_form_id,
            v_new_definition_id,
            v_form_def_record.activity_id,
            v_form_def_record.html,
            p_tenant_id
        )
        ON CONFLICT (id, tenant_id) DO UPDATE SET
            proc_def_id = EXCLUDED.proc_def_id,
            activity_id = EXCLUDED.activity_id,
            html = EXCLUDED.html;

        SELECT uuid
          INTO v_form_def_uuid
          FROM public.form_def
         WHERE id = v_new_definition_id || '_' || v_form_id
           AND tenant_id = p_tenant_id;
    END LOOP;

    RETURN jsonb_build_object(
        'success', true,
        'new_definition_id', v_new_definition_id,
        'proc_def_uuid', v_proc_def_uuid
    );
END;
$function$;
CREATE OR REPLACE FUNCTION public.enqueue_governance_notification(p_tenant_id text, p_event_type text, p_payload jsonb, p_recipient_snapshot jsonb DEFAULT '[]'::jsonb, p_dedupe_key text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_id UUID;
BEGIN
    INSERT INTO governance_notification_outbox (
        tenant_id,
        event_type,
        payload,
        recipient_snapshot,
        dedupe_key
    )
    VALUES (
        p_tenant_id,
        p_event_type,
        COALESCE(p_payload, '{}'::jsonb),
        COALESCE(p_recipient_snapshot, '[]'::jsonb),
        p_dedupe_key
    )
    ON CONFLICT (tenant_id, dedupe_key)
    WHERE dedupe_key IS NOT NULL
    DO UPDATE SET
        payload = EXCLUDED.payload,
        recipient_snapshot = EXCLUDED.recipient_snapshot,
        status = 'PENDING',
        available_at = now(),
        sent_at = NULL,
        last_error = NULL,
        updated_at = now()
    RETURNING id INTO v_id;

    RETURN v_id;
END;
$function$;
CREATE OR REPLACE FUNCTION public.enqueue_proc_def_approval_history_governance_notification()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_payload JSONB;
    v_recipient_snapshot JSONB;
    v_roles JSONB;
    v_role_item JSONB;
    v_role_name TEXT;
    v_role_default TEXT;
    v_role_endpoint TEXT;
    v_user_email TEXT;
    v_user_name TEXT;
BEGIN
    IF NEW.to_state IS NULL OR btrim(NEW.to_state) = '' THEN
        RETURN NEW;
    END IF;

    IF NEW.from_state IS NOT NULL AND NEW.from_state = NEW.to_state THEN
        RETURN NEW;
    END IF;

    v_payload := jsonb_build_object(
        'approval_history_id', NEW.id,
        'processDefinitionId', NEW.proc_def_id,
        'proc_def_id', NEW.proc_def_id,
        'review_id', NEW.review_id,
        'action', NEW.action,
        'previousStatus', NEW.from_state,
        'previous_status', NEW.from_state,
        'status', NEW.to_state,
        'newStatus', NEW.to_state,
        'actor_id', NEW.actor_id,
        'actor_name', NEW.actor_name,
        'comment', NEW.comment,
        'created_at', NEW.created_at,
        'changed_at', NEW.created_at,
        'changed_by', jsonb_build_object(
            'id', NEW.actor_id,
            'name', NEW.actor_name
        ),
        'target', jsonb_build_object(
            'id', NEW.proc_def_id,
            'name', NEW.proc_def_id
        )
    );

    v_recipient_snapshot := '[]'::jsonb;

    SELECT definition->'roles' INTO v_roles
    FROM proc_def
    WHERE id = NEW.proc_def_id AND tenant_id = NEW.tenant_id
    LIMIT 1;

    IF v_roles IS NOT NULL THEN
        FOR v_role_item IN SELECT * FROM jsonb_array_elements(v_roles)
        LOOP
            v_role_name := v_role_item->>'name';
            v_role_default := v_role_item->>'default';
            v_role_endpoint := v_role_item->>'endpoint';

            IF v_role_default IS NOT NULL AND btrim(v_role_default) <> '' AND v_role_default ~* '@' THEN
                v_recipient_snapshot := v_recipient_snapshot || jsonb_build_object(
                    'name', COALESCE(v_role_name, v_role_default),
                    'addr', v_role_default,
                    'role', COALESCE(v_role_name, '')
                );
            ELSIF v_role_default IS NOT NULL AND btrim(v_role_default) <> '' THEN
                SELECT u.email, u.username INTO v_user_email, v_user_name
                FROM users u
                WHERE u.id::text = v_role_default AND u.tenant_id = NEW.tenant_id
                LIMIT 1;

                IF v_user_email IS NOT NULL THEN
                    v_recipient_snapshot := v_recipient_snapshot || jsonb_build_object(
                        'name', COALESCE(v_user_name, v_role_name, v_user_email),
                        'addr', v_user_email,
                        'role', COALESCE(v_role_name, '')
                    );
                END IF;
            END IF;

            IF v_role_endpoint IS NOT NULL AND btrim(v_role_endpoint) <> '' AND v_role_endpoint ~* '@' AND v_role_endpoint IS DISTINCT FROM v_role_default THEN
                v_recipient_snapshot := v_recipient_snapshot || jsonb_build_object(
                    'name', COALESCE(v_role_name, v_role_endpoint),
                    'addr', v_role_endpoint,
                    'role', COALESCE(v_role_name, '')
                );
            ELSIF v_role_endpoint IS NOT NULL AND btrim(v_role_endpoint) <> '' AND v_role_endpoint !~* '@' AND v_role_endpoint IS DISTINCT FROM v_role_default THEN
                SELECT u.email, u.username INTO v_user_email, v_user_name
                FROM users u
                WHERE u.id::text = v_role_endpoint AND u.tenant_id = NEW.tenant_id
                LIMIT 1;

                IF v_user_email IS NOT NULL AND v_user_email IS DISTINCT FROM (
                    SELECT (elem->>'addr')::text
                    FROM jsonb_array_elements(v_recipient_snapshot) AS elem
                    WHERE elem->>'addr' = v_user_email
                    LIMIT 1
                ) THEN
                    v_recipient_snapshot := v_recipient_snapshot || jsonb_build_object(
                        'name', COALESCE(v_user_name, v_role_name, v_user_email),
                        'addr', v_user_email,
                        'role', COALESCE(v_role_name, '')
                    );
                END IF;
            END IF;
        END LOOP;
    END IF;

    PERFORM enqueue_governance_notification(
        NEW.tenant_id,
        'status_change',
        v_payload,
        v_recipient_snapshot,
        'proc_def_approval_history:' || NEW.id::text
    );

    RETURN NEW;
END;
$function$;
CREATE OR REPLACE FUNCTION public.enqueue_proc_def_comment_governance_notification()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_payload JSONB;
    v_recipient_snapshot JSONB;
    v_roles JSONB;
    v_role_item JSONB;
    v_role_name TEXT;
    v_role_default TEXT;
    v_role_endpoint TEXT;
    v_user_email TEXT;
    v_user_name TEXT;
    v_tenant_id TEXT;
BEGIN
    IF NEW.content IS NULL OR btrim(NEW.content) = '' THEN
        RETURN NEW;
    END IF;

    SELECT tenant_id INTO v_tenant_id FROM proc_def WHERE id = NEW.proc_def_id LIMIT 1;
    IF v_tenant_id IS NULL THEN
        v_tenant_id := NEW.tenant_id;
    END IF;

    v_payload := jsonb_build_object(
        'comment_id', NEW.id,
        'processDefinitionId', NEW.proc_def_id,
        'proc_def_id', NEW.proc_def_id,
        'element_id', NEW.element_id,
        'element_type', NEW.element_type,
        'element_name', NEW.element_name,
        'author_id', NEW.author_id,
        'author_name', NEW.author_name,
        'content', NEW.content,
        'feedback', NEW.content,
        'parent_comment_id', NEW.parent_comment_id,
        'reviewer_type', NEW.reviewer_type,
        'is_resolved', NEW.is_resolved,
        'created_at', NEW.created_at,
        'updated_at', NEW.updated_at,
        'created_by', jsonb_build_object(
            'id', NEW.author_id,
            'name', NEW.author_name
        ),
        'target', jsonb_build_object(
            'id', NEW.proc_def_id,
            'name', COALESCE(NULLIF(NEW.element_name, ''), NEW.proc_def_id)
        )
    );

    v_recipient_snapshot := '[]'::jsonb;

    SELECT definition->'roles' INTO v_roles
    FROM proc_def
    WHERE id = NEW.proc_def_id AND tenant_id = v_tenant_id
    LIMIT 1;

    IF v_roles IS NOT NULL THEN
        FOR v_role_item IN SELECT * FROM jsonb_array_elements(v_roles)
        LOOP
            v_role_name := v_role_item->>'name';
            v_role_default := v_role_item->>'default';
            v_role_endpoint := v_role_item->>'endpoint';

            IF v_role_default IS NOT NULL AND btrim(v_role_default) <> '' AND v_role_default ~* '@' THEN
                v_recipient_snapshot := v_recipient_snapshot || jsonb_build_object(
                    'name', COALESCE(v_role_name, v_role_default),
                    'addr', v_role_default,
                    'role', COALESCE(v_role_name, '')
                );
            ELSIF v_role_default IS NOT NULL AND btrim(v_role_default) <> '' THEN
                SELECT u.email, u.username INTO v_user_email, v_user_name
                FROM users u
                WHERE u.id::text = v_role_default AND u.tenant_id = v_tenant_id
                LIMIT 1;

                IF v_user_email IS NOT NULL THEN
                    v_recipient_snapshot := v_recipient_snapshot || jsonb_build_object(
                        'name', COALESCE(v_user_name, v_role_name, v_user_email),
                        'addr', v_user_email,
                        'role', COALESCE(v_role_name, '')
                    );
                END IF;
            END IF;

            IF v_role_endpoint IS NOT NULL AND btrim(v_role_endpoint) <> '' AND v_role_endpoint ~* '@' AND v_role_endpoint IS DISTINCT FROM v_role_default THEN
                v_recipient_snapshot := v_recipient_snapshot || jsonb_build_object(
                    'name', COALESCE(v_role_name, v_role_endpoint),
                    'addr', v_role_endpoint,
                    'role', COALESCE(v_role_name, '')
                );
            ELSIF v_role_endpoint IS NOT NULL AND btrim(v_role_endpoint) <> '' AND v_role_endpoint !~* '@' AND v_role_endpoint IS DISTINCT FROM v_role_default THEN
                SELECT u.email, u.username INTO v_user_email, v_user_name
                FROM users u
                WHERE u.id::text = v_role_endpoint AND u.tenant_id = v_tenant_id
                LIMIT 1;

                IF v_user_email IS NOT NULL AND v_user_email IS DISTINCT FROM (
                    SELECT (elem->>'addr')::text
                    FROM jsonb_array_elements(v_recipient_snapshot) AS elem
                    WHERE elem->>'addr' = v_user_email
                    LIMIT 1
                ) THEN
                    v_recipient_snapshot := v_recipient_snapshot || jsonb_build_object(
                        'name', COALESCE(v_user_name, v_role_name, v_user_email),
                        'addr', v_user_email,
                        'role', COALESCE(v_role_name, '')
                    );
                END IF;
            END IF;
        END LOOP;
    END IF;

    PERFORM enqueue_governance_notification(
        v_tenant_id,
        'feedback_registered',
        v_payload,
        v_recipient_snapshot,
        'proc_def_comment:' || NEW.id::text
    );

    RETURN NEW;
END;
$function$;
CREATE OR REPLACE FUNCTION public.fetch_pending_task(p_agent_orch text, p_consumer text, p_limit integer)
 RETURNS TABLE(id uuid, user_id text, proc_inst_id text, proc_def_id text, activity_id text, activity_name text, start_date timestamp without time zone, end_date timestamp without time zone, description text, tool text, due_date timestamp without time zone, tenant_id text, reference_ids text[], adhoc boolean, assignees jsonb, duration integer, output jsonb, retry integer, consumer text, log text, draft jsonb, project_id uuid, feedback jsonb, updated_at timestamp with time zone, username text, status todo_status, agent_mode agent_mode, agent_orch agent_orch, temp_feedback text, draft_status draft_status, query text, task_type draft_status)
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
         t.agent_mode,
         t.agent_orch,
         t.temp_feedback,
         t.draft_status,
         t.query,
         cte.task_type
    )
    SELECT * FROM upd;
END;
$function$;
CREATE OR REPLACE FUNCTION public.fetch_pending_task(p_agent_orch text, p_consumer text, p_limit integer, p_env text, p_lease_seconds integer DEFAULT NULL::integer, p_max_claims integer DEFAULT 3)
 RETURNS SETOF todolist
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_max_claims integer := GREATEST(coalesce(p_max_claims, 3), 1);
BEGIN
  -- 1) 상한에 닿은 만료 점유를 FAILED 로 종결한다.
  --    폴링마다 돌지만 조건이 idx_todolist_lease_reclaim 그대로라 비용은 없다.
  UPDATE todolist AS t
     SET draft_status = 'FAILED',
         lease_until  = NULL
   WHERE t.status = 'IN_PROGRESS'
     AND t.draft_status = 'STARTED'
     AND t.lease_until IS NOT NULL
     AND t.lease_until < now()
     AND coalesce(t.claim_count, 0) >= v_max_claims
     AND (p_agent_orch IS NULL OR p_agent_orch = '' OR t.agent_orch::text = p_agent_orch);

  -- 2) 집을 수 있는 행 하나를 원자적으로 점유한다.
  RETURN QUERY
    WITH cte AS (
      SELECT t.id
      FROM todolist AS t
      WHERE t.status = 'IN_PROGRESS'
        -- agent_orch 필터(옵션)
        AND (p_agent_orch IS NULL OR p_agent_orch = '' OR t.agent_orch::text = p_agent_orch)
        AND (
          -- 신규 작업
          (t.agent_mode IN ('DRAFT','COMPLETE') AND t.draft IS NULL AND t.draft_status IS NULL)
          -- 사용자 피드백으로 되돌아온 작업
          OR t.draft_status = 'FB_REQUESTED'
          -- 점유가 만료된 작업(= 집은 워커가 더 이상 연장하지 못한다)
          --
          -- draft_status='STARTED' 만 본다. HUMAN_ASKED 처럼 사람 답변을 기다리는
          -- 정상 대기는 여기에 걸리지 않는다. 기다림은 장애가 아니고, 회수해도
          -- 다시 같은 질문 앞에서 멈출 뿐이다.
          OR (
            t.draft_status = 'STARTED'
            AND t.lease_until IS NOT NULL
            AND t.lease_until < now()
            AND coalesce(t.claim_count, 0) < v_max_claims
          )
        )
      ORDER BY t.start_date
      LIMIT p_limit
      FOR UPDATE SKIP LOCKED
    ),
    upd AS (
      UPDATE todolist AS t
         SET draft_status = 'STARTED',
             consumer     = p_consumer,
             lease_until  = CASE
                              WHEN p_lease_seconds IS NULL OR p_lease_seconds <= 0 THEN NULL
                              ELSE now() + make_interval(secs => p_lease_seconds)
                            END,
             -- 회수일 때만 누적한다. 피드백으로 되돌아온 정상 재집행
             -- (FB_REQUESTED)이 상한을 먹으면, 피드백을 몇 번 주고받은 작업이
             -- 멀쩡한데도 FAILED 로 끝난다.
             claim_count  = CASE
                              WHEN t.draft_status = 'STARTED' THEN coalesce(t.claim_count, 0) + 1
                              ELSE 1
                            END
        FROM cte
       WHERE t.id = cte.id
       RETURNING t.*
    )
    SELECT * FROM upd;
END;
$function$;
CREATE OR REPLACE FUNCTION public.get_merged_permission(p_proc_def_id text, p_user_id uuid, p_user_organizations text[] DEFAULT NULL::text[])
 RETURNS TABLE(has_readable boolean, has_executable boolean, has_writable boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
    BEGIN
        RETURN QUERY
        SELECT
            COALESCE(bool_or(readable), false) AS has_readable,
            COALESCE(bool_or(executable), false) AS has_executable,
            COALESCE(bool_or(writable), false) AS has_writable
        FROM check_process_permission_v2(p_proc_def_id, p_user_id, p_user_organizations);
    END;
    $function$;
CREATE OR REPLACE FUNCTION public.get_next_version_number(p_model_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_max_version INTEGER;
BEGIN
    SELECT COALESCE(MAX(version_number), 0) + 1
    INTO v_max_version
    FROM public.tb_bpmn_version
    WHERE model_id = p_model_id;
    RETURN v_max_version;
END;
$function$;
CREATE OR REPLACE FUNCTION public.get_role_level(p_role text)
 RETURNS integer
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT CASE lower(coalesce(p_role, ''))
    WHEN 'superadmin' THEN 120
    WHEN 'admin'      THEN 100
    WHEN 'owner'      THEN 80
    WHEN 'editor'     THEN 60
    WHEN 'reviewer'   THEN 40
    WHEN 'viewer'     THEN 20
    ELSE 0
  END;
$function$;
CREATE OR REPLACE FUNCTION public.has_role_at_least(required_role text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
AS $function$
  SELECT public.get_role_level(public.current_user_role())
      >= public.get_role_level(required_role);
$function$;
CREATE OR REPLACE FUNCTION public.increment_terminology_usage(p_tenant_id text, p_category text, p_term text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
    UPDATE standard_terminology
    SET usage_count = usage_count + 1,
        updated_at = NOW()
    WHERE tenant_id = p_tenant_id
      AND category = p_category
      AND term = p_term;

    IF NOT FOUND THEN
        INSERT INTO standard_terminology (tenant_id, category, term, usage_count)
        VALUES (p_tenant_id, p_category, p_term, 1)
        ON CONFLICT (tenant_id, category, term) DO UPDATE
        SET usage_count = standard_terminology.usage_count + 1,
            updated_at = NOW();
    END IF;
END;
$function$;
CREATE OR REPLACE FUNCTION public.lane_role_groups_depth_guard()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    IF NEW.parent_id IS NOT NULL THEN
        IF EXISTS (
            SELECT 1 FROM public.lane_role_groups p
            WHERE p.id = NEW.parent_id AND p.parent_id IS NOT NULL
        ) THEN
            RAISE EXCEPTION 'lane_role_groups: depth limited to 2 (parent must be a root)';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;
CREATE OR REPLACE FUNCTION public.procmap_ensure_uuids(map jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
  mega_list jsonb;
  new_mega jsonb := '[]'::jsonb;
  mega jsonb;
  major_list jsonb;
  new_major jsonb;
  major jsonb;
  sub_list jsonb;
  new_sub jsonb;
  sub jsonb;
BEGIN
  IF map IS NULL OR jsonb_typeof(map) <> 'object' OR jsonb_typeof(map->'mega_proc_list') <> 'array' THEN
    RETURN map;
  END IF;

  mega_list := map->'mega_proc_list';
  FOR mega IN SELECT * FROM jsonb_array_elements(mega_list) LOOP
    IF jsonb_typeof(mega) = 'object' AND NOT (mega ? 'uuid') THEN
      mega := jsonb_set(mega, '{uuid}', to_jsonb(public.uuid_generate_v7()::text));
    END IF;

    major_list := mega->'major_proc_list';
    IF jsonb_typeof(major_list) = 'array' THEN
      new_major := '[]'::jsonb;
      FOR major IN SELECT * FROM jsonb_array_elements(major_list) LOOP
        IF jsonb_typeof(major) = 'object' AND NOT (major ? 'uuid') THEN
          major := jsonb_set(major, '{uuid}', to_jsonb(public.uuid_generate_v7()::text));
        END IF;

        sub_list := major->'sub_proc_list';
        IF jsonb_typeof(sub_list) = 'array' THEN
          new_sub := '[]'::jsonb;
          FOR sub IN SELECT * FROM jsonb_array_elements(sub_list) LOOP
            IF jsonb_typeof(sub) = 'object' AND NOT (sub ? 'uuid') THEN
              sub := jsonb_set(sub, '{uuid}', to_jsonb(public.uuid_generate_v7()::text));
            END IF;
            new_sub := new_sub || jsonb_build_array(sub);
          END LOOP;
          major := jsonb_set(major, '{sub_proc_list}', new_sub);
        END IF;

        new_major := new_major || jsonb_build_array(major);
      END LOOP;
      mega := jsonb_set(mega, '{major_proc_list}', new_major);
    END IF;

    new_mega := new_mega || jsonb_build_array(mega);
  END LOOP;

  RETURN jsonb_set(map, '{mega_proc_list}', new_mega);
END;
$function$;
CREATE OR REPLACE FUNCTION public.release_task_lease(p_todo_id uuid, p_consumer text)
 RETURNS boolean
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_rows integer;
BEGIN
  IF p_todo_id IS NULL OR coalesce(p_consumer, '') = '' THEN
    RETURN false;
  END IF;

  UPDATE todolist AS t
     SET lease_until = NULL
   WHERE t.id = p_todo_id
     AND t.consumer = p_consumer;

  GET DIAGNOSTICS v_rows = ROW_COUNT;
  RETURN v_rows > 0;
END;
$function$;
CREATE OR REPLACE FUNCTION public.renew_task_lease(p_todo_id uuid, p_consumer text, p_lease_seconds integer)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_status   text;
  v_consumer text;
  v_until    timestamptz;
BEGIN
  IF p_todo_id IS NULL OR coalesce(p_consumer, '') = '' OR coalesce(p_lease_seconds, 0) <= 0 THEN
    RETURN jsonb_build_object('renewed', false, 'reason', 'bad_request');
  END IF;

  SELECT t.draft_status::text, t.consumer
    INTO v_status, v_consumer
    FROM todolist AS t
   WHERE t.id = p_todo_id
     FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('renewed', false, 'reason', 'missing');
  END IF;

  IF v_status IS DISTINCT FROM 'STARTED' THEN
    RETURN jsonb_build_object('renewed', false, 'reason', 'not_started',
                              'draft_status', v_status);
  END IF;

  IF v_consumer IS DISTINCT FROM p_consumer THEN
    RETURN jsonb_build_object('renewed', false, 'reason', 'not_owner',
                              'consumer', v_consumer);
  END IF;

  UPDATE todolist
     SET lease_until = now() + make_interval(secs => p_lease_seconds)
   WHERE id = p_todo_id
   RETURNING lease_until INTO v_until;

  RETURN jsonb_build_object('renewed', true, 'reason', 'ok', 'lease_until', v_until);
END;
$function$;
CREATE OR REPLACE FUNCTION public.set_actual_start_date()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    -- status가 IN_PROGRESS로 변경되고, actual_start_date가 아직 설정되지 않은 경우
    IF NEW.status = 'IN_PROGRESS' AND OLD.status IS DISTINCT FROM 'IN_PROGRESS' THEN
        IF NEW.actual_start_date IS NULL THEN
            NEW.actual_start_date := NOW();
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;
CREATE OR REPLACE FUNCTION public.set_deleted_by_from_jwt()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    jwt_claims JSONB;
    jwt_name   TEXT;
    jwt_org    TEXT;
BEGIN
    -- ① 소프트 딜리트 (NULL → NOT NULL): JWT 에서 추출해 자동 채움
    IF NEW.deleted_at IS NOT NULL AND OLD.deleted_at IS NULL THEN
        jwt_claims := auth.jwt();
        jwt_name   := jwt_claims -> 'user_metadata' ->> 'name';
        jwt_org    := jwt_claims -> 'app_metadata'  ->> 'org_name';

        NEW.deleted_by := CASE
            WHEN jwt_name IS NOT NULL AND jwt_org IS NOT NULL
                THEN jwt_name || E'\n(' || jwt_org || ')'
            WHEN jwt_name IS NOT NULL
                THEN jwt_name
            ELSE 'Unknown'
        END;

    -- ② 복원 (NOT NULL → NULL): deleted_by 도 같이 NULL
    ELSIF NEW.deleted_at IS NULL AND OLD.deleted_at IS NOT NULL THEN
        NEW.deleted_by := NULL;

    -- ③ 이미 삭제 상태에서 다른 컬럼 업데이트: 기존 deleted_by 보존 (사후 위변조 차단)
    ELSIF OLD.deleted_at IS NOT NULL THEN
        NEW.deleted_by := OLD.deleted_by;
    END IF;

    RETURN NEW;
END;
$function$;
CREATE OR REPLACE FUNCTION public.set_proc_inst_actual_start_date()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    -- status가 RUNNING으로 변경되고, actual_start_date가 아직 설정되지 않은 경우
    IF NEW.status = 'RUNNING' AND OLD.status IS DISTINCT FROM 'RUNNING' THEN
        IF NEW.actual_start_date IS NULL THEN
            NEW.actual_start_date := NOW();
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;
CREATE OR REPLACE FUNCTION public.set_todolist_executor_dept()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    -- user_id가 설정되면 해당 사용자의 부서 정보 가져오기
    IF NEW.user_id IS NOT NULL THEN
        SELECT department_id, department_name
        INTO NEW.executor_dept_id, NEW.executor_dept_name
        FROM public.users
        WHERE id::text = NEW.user_id AND tenant_id = NEW.tenant_id
        LIMIT 1;
    END IF;
    RETURN NEW;
END;
$function$;
CREATE OR REPLACE FUNCTION public.sync_departments_from_org_chart(p_tenant_id text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_count INTEGER := 0;
    v_org_chart JSONB;
    v_proc_def RECORD;
BEGIN
    -- proc_def에서 org_chart가 있는 정의 찾기
    FOR v_proc_def IN
        SELECT id, definition->>'org_chart' AS org_chart_json
        FROM public.proc_def
        WHERE tenant_id = p_tenant_id
        AND definition->>'org_chart' IS NOT NULL
        LIMIT 1
    LOOP
        -- 조직도 JSON 파싱 및 부서 추출 로직
        -- (실제 구현은 org_chart JSON 구조에 따라 조정 필요)
        v_count := v_count + 1;
    END LOOP;

    RETURN v_count;
END;
$function$;
CREATE OR REPLACE FUNCTION public.sync_task_execution_on_insert()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
    INSERT INTO public.task_execution_properties (
        tenant_id,
        proc_def_id,
        proc_inst_id,
        activity_id,
        activity_name,
        todo_id,
        tool,
        execution_status,
        started_at,
        executor_email
    ) VALUES (
        NEW.tenant_id,
        NEW.proc_def_id,
        NEW.proc_inst_id,
        NEW.activity_id,
        NEW.activity_name,
        NEW.id,
        NEW.tool,
        'STARTED',
        now(),  -- 실제 태스크 생성 시점 사용 (start_date는 계획 날짜일 수 있음)
        NEW.user_id
    )
    ON CONFLICT DO NOTHING;

    RETURN NEW;
END;
$function$;
CREATE OR REPLACE FUNCTION public.sync_task_execution_on_update()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    new_status text;
    completed_time timestamptz;
BEGIN
    -- 상태 매핑 (todolist ENUM → task_execution_properties TEXT)
    -- todolist status: NEW, RUNNING, DONE, PENDING, IN_PROGRESS, SUBMITTED, COMPLETED, CANCELLED
    IF NEW.status::text IN ('DONE', 'COMPLETED') THEN
        new_status := 'COMPLETED';
    ELSIF NEW.status::text = 'CANCELLED' THEN
        new_status := 'CANCELLED';
    ELSE
        new_status := 'STARTED';
    END IF;

    completed_time := COALESCE(NEW.end_date, NEW.updated_at, now());

    -- 기존 레코드 업데이트
    UPDATE public.task_execution_properties
    SET
        execution_status = new_status,
        completed_at = CASE WHEN new_status IN ('COMPLETED', 'CANCELLED') THEN completed_time ELSE NULL END,
        actual_duration = CASE WHEN new_status IN ('COMPLETED', 'CANCELLED') THEN completed_time - started_at ELSE NULL END,
        executor_email = COALESCE(NEW.user_id, executor_email),
        activity_name = COALESCE(NEW.activity_name, activity_name),
        tool = COALESCE(NEW.tool, tool)
    WHERE todo_id = NEW.id;

    -- 기존 레코드 없으면 새로 생성
    IF NOT FOUND THEN
        INSERT INTO public.task_execution_properties (
            tenant_id, proc_def_id, proc_inst_id, activity_id, activity_name,
            todo_id, tool, execution_status, started_at, completed_at, actual_duration, executor_email
        ) VALUES (
            NEW.tenant_id, NEW.proc_def_id, NEW.proc_inst_id, NEW.activity_id, NEW.activity_name,
            NEW.id, NEW.tool, new_status, now(),  -- 실제 시점 사용
            CASE WHEN new_status IN ('COMPLETED', 'CANCELLED') THEN completed_time ELSE NULL END,
            CASE WHEN new_status IN ('COMPLETED', 'CANCELLED') THEN completed_time - now() ELSE NULL END,
            NEW.user_id
        );
    END IF;

    RETURN NEW;
END;
$function$;
CREATE OR REPLACE FUNCTION public.tenant_id()
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  SELECT NULLIF(
    btrim(
      COALESCE(
        ((current_setting('request.jwt.claims', true)::jsonb ->> 'app_metadata')::jsonb ->> 'tenant_id'),
        (current_setting('request.jwt.claim.tenant_id', true))
      )
    ),
    ''
  );
$function$;
CREATE OR REPLACE FUNCTION public.update_model_counts(p_model_id uuid)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
    UPDATE public.tb_bpmn_model
    SET
        node_count = (SELECT COUNT(*) FROM public.tb_bpmn_node WHERE model_id = p_model_id),
        link_count = (SELECT COUNT(*) FROM public.tb_bpmn_link WHERE model_id = p_model_id),
        lane_count = (SELECT COUNT(*) FROM public.tb_bpmn_lane WHERE model_id = p_model_id),
        parsed_at = NOW()
    WHERE id = p_model_id;
END;
$function$;
CREATE OR REPLACE FUNCTION public.update_proc_def_approval_state_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$function$;
CREATE OR REPLACE FUNCTION public.update_proc_def_comments_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$function$;
CREATE OR REPLACE FUNCTION public.update_tb_bpmn_model_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$function$;
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$function$;
CREATE OR REPLACE FUNCTION public.update_user_department()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    -- department_id가 설정되면 department_name도 자동 업데이트
    IF NEW.department_id IS NOT NULL AND NEW.department_id != '' THEN
        SELECT name INTO NEW.department_name
        FROM public.departments
        WHERE id = NEW.department_id AND tenant_id = NEW.tenant_id;
    END IF;
    RETURN NEW;
END;
$function$;
CREATE OR REPLACE FUNCTION public.uuid_generate_v7()
 RETURNS uuid
 LANGUAGE sql
 PARALLEL SAFE
AS $function$
  SELECT encode(
    set_bit(
      set_bit(
        overlay(
          uuid_send(gen_random_uuid())
          PLACING substring(int8send((extract(epoch FROM clock_timestamp()) * 1000)::bigint) FROM 3)
          FROM 1 FOR 6
        ),
        52, 1
      ),
      53, 1
    ),
    'hex'
  )::uuid;
$function$;

-- 3) 공유 테이블의 빠진 열
ALTER TABLE public."bpm_proc_inst" ADD COLUMN IF NOT EXISTS "actual_start_date" timestamp with time zone;
ALTER TABLE public."lock" ADD COLUMN IF NOT EXISTS "heartbeat_at" timestamp with time zone;
ALTER TABLE public."lock" ADD COLUMN IF NOT EXISTS "force_checkout_by" text;
ALTER TABLE public."lock" ADD COLUMN IF NOT EXISTS "force_checkout_at" timestamp with time zone;
ALTER TABLE public."proc_def" ADD COLUMN IF NOT EXISTS "deleted_at" timestamp with time zone;
ALTER TABLE public."proc_def" ADD COLUMN IF NOT EXISTS "deleted_by" text;
ALTER TABLE public."proc_def" ADD COLUMN IF NOT EXISTS "deleted_from" jsonb;
ALTER TABLE public."proc_def" ADD COLUMN IF NOT EXISTS "saved_at" timestamp with time zone;
ALTER TABLE public."proc_def" ADD COLUMN IF NOT EXISTS "description" text;
ALTER TABLE public."proc_def" ADD COLUMN IF NOT EXISTS "domain_id" text;
ALTER TABLE public."proc_def" ADD COLUMN IF NOT EXISTS "mega_process_id" text;
ALTER TABLE public."proc_def" ADD COLUMN IF NOT EXISTS "major_process_id" text;
ALTER TABLE public."proc_def_version" ADD COLUMN IF NOT EXISTS "owner" text;
ALTER TABLE public."todolist" ADD COLUMN IF NOT EXISTS "agent_config" jsonb;
ALTER TABLE public."todolist" ADD COLUMN IF NOT EXISTS "executor_dept_id" text;
ALTER TABLE public."todolist" ADD COLUMN IF NOT EXISTS "executor_dept_name" text;
ALTER TABLE public."todolist" ADD COLUMN IF NOT EXISTS "lease_until" timestamp with time zone;
ALTER TABLE public."todolist" ADD COLUMN IF NOT EXISTS "claim_count" integer DEFAULT 0 NOT NULL;
ALTER TABLE public."user_permissions" ADD COLUMN IF NOT EXISTS "executable" boolean DEFAULT false NOT NULL;
ALTER TABLE public."user_permissions" ADD COLUMN IF NOT EXISTS "target_type" text DEFAULT 'user'::text NOT NULL;
ALTER TABLE public."user_permissions" ADD COLUMN IF NOT EXISTS "org_group_id" uuid;
ALTER TABLE public."user_permissions" ADD COLUMN IF NOT EXISTS "organization_id" text;
ALTER TABLE public."user_permissions" ADD COLUMN IF NOT EXISTS "permission_level" text DEFAULT 'sub'::text NOT NULL;
ALTER TABLE public."users" ADD COLUMN IF NOT EXISTS "department_id" text;
ALTER TABLE public."users" ADD COLUMN IF NOT EXISTS "department_name" text;
ALTER TABLE public."users" ADD COLUMN IF NOT EXISTS "employee_no" text;
ALTER TABLE public."users" ADD COLUMN IF NOT EXISTS "org_code" text;
ALTER TABLE public."users" ADD COLUMN IF NOT EXISTS "org_name" text;
ALTER TABLE public."users" ADD COLUMN IF NOT EXISTS "permission_ids" uuid[] DEFAULT '{}'::uuid[] NOT NULL;
ALTER TABLE public."users" ADD COLUMN IF NOT EXISTS "last_seen_at" timestamp with time zone;

-- 4) 빠진 테이블·뷰 89개
--
-- PostgreSQL database dump
--

-- Dumped from database version 15.8
-- Dumped by pg_dump version 15.8




--
-- Name: activity_config; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.activity_config (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id character varying(255) NOT NULL,
    proc_def_id character varying(255) NOT NULL,
    activity_id character varying(255) NOT NULL,
    activity_name character varying(500),
    standard_minutes integer DEFAULT 30,
    role_name character varying(255),
    complexity_factor numeric(3,2) DEFAULT 1.0,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by character varying(255)
);


--
-- Name: TABLE activity_config; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.activity_config IS 'Activity별 FTE 계산을 위한 표준 작업 시간 설정';


--
-- Name: admin_audit_log; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.admin_audit_log (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id text NOT NULL,
    actor_id text NOT NULL,
    action text NOT NULL,
    target_type text,
    target_id text,
    target_name text,
    before_value text,
    after_value text,
    comment text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: TABLE admin_audit_log; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.admin_audit_log IS '관리자 감사 로그. append-only (UPDATE/DELETE 차단). actor_id 는 현재 클라이언트 제공값 — 인증 흐름 정리 후 트리거로 강제 덮어쓰기 예정.';


--
-- Name: admin_requests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.admin_requests (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id text NOT NULL,
    username text,
    email text NOT NULL,
    tenant_id text NOT NULL,
    reason text,
    status text DEFAULT 'pending'::text,
    reject_reason text,
    reviewed_by text,
    reviewed_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    requested_role text DEFAULT 'admin'::text,
    CONSTRAINT admin_requests_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text])))
);


--
-- Name: COLUMN admin_requests.requested_role; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.admin_requests.requested_role IS '신청한 역할 (admin, owner, editor, reviewer, viewer)';


--
-- Name: app_usage_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.app_usage_events (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id text DEFAULT 'skt'::text NOT NULL,
    event_type text NOT NULL,
    event_key text,
    session_id text,
    user_id text,
    email text,
    employee_no text,
    user_name text,
    department_id text,
    department_name text,
    org_code text,
    org_name text,
    route text,
    proc_def_id text,
    model_id uuid,
    active_duration_ms bigint DEFAULT 0 NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    occurred_at timestamp with time zone DEFAULT now() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT app_usage_events_event_type_check CHECK ((event_type = ANY (ARRAY['session_start'::text, 'session_end'::text, 'route_view'::text, 'heartbeat'::text, 'model_view'::text, 'model_create'::text, 'model_edit'::text, 'model_save'::text])))
);


--
-- Name: TABLE app_usage_events; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.app_usage_events IS 'Product usage events for adoption, retention, and BPMN model activity dashboards.';


--
-- Name: COLUMN app_usage_events.active_duration_ms; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.app_usage_events.active_duration_ms IS 'Active visible time reported by the browser heartbeat for this event.';


--
-- Name: audit_policy; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.audit_policy (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id text NOT NULL,
    name text NOT NULL,
    kind text NOT NULL,
    file_path text,
    file_size_bytes bigint,
    link_url text,
    author_id text,
    author_name text,
    author_team text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    deleted_by_id text,
    deleted_by_name text,
    deleted_by_team text,
    domains text[] DEFAULT '{}'::text[] NOT NULL,
    CONSTRAINT audit_policy_kind_check CHECK ((kind = ANY (ARRAY['file'::text, 'link'::text]))),
    CONSTRAINT audit_policy_kind_payload CHECK ((((kind = 'file'::text) AND (file_path IS NOT NULL)) OR ((kind = 'link'::text) AND (link_url IS NOT NULL))))
);


--
-- Name: TABLE audit_policy; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.audit_policy IS '사내 정책문서 메타데이터 (BPMN 분석 Agent 참조용)';


--
-- Name: COLUMN audit_policy.kind; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.audit_policy.kind IS 'file = Supabase Storage 업로드 / link = 외부 URL';


--
-- Name: COLUMN audit_policy.file_path; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.audit_policy.file_path IS 'kind=file 일 때, files 버킷 내 객체 경로 (예: uploads/<ts>_<filename>)';


--
-- Name: COLUMN audit_policy.deleted_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.audit_policy.deleted_at IS '소프트 딜리트 시각 (NULL = 활성)';


--
-- Name: COLUMN audit_policy.deleted_by_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.audit_policy.deleted_by_id IS '삭제자 user id';


--
-- Name: COLUMN audit_policy.deleted_by_name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.audit_policy.deleted_by_name IS '삭제자 표시 이름';


--
-- Name: COLUMN audit_policy.deleted_by_team; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.audit_policy.deleted_by_team IS '삭제자 소속 팀/조직';


--
-- Name: COLUMN audit_policy.domains; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.audit_policy.domains IS '연결된 도메인 ID 배열 (configuration.metrics.domains 의 id)';


--
-- Name: bpmn_element_map; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.bpmn_element_map (
    element_uuid uuid DEFAULT public.uuid_generate_v7() NOT NULL,
    proc_def_uuid uuid NOT NULL,
    proc_def_id text NOT NULL,
    element_id text NOT NULL,
    element_type text,
    name text,
    tenant_id text DEFAULT public.tenant_id(),
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: TABLE bpmn_element_map; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.bpmn_element_map IS 'BPMN Element 영구 UUID 매핑. 원본은 proc_def.bpmn 의 uengine:properties json "uuid" 키. 저장 시 동기화(파생 데이터)';


--
-- Name: COLUMN bpmn_element_map.element_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.bpmn_element_map.element_id IS 'legacy id — BPMN XML 요소 id (tracingTag / todolist.activity_id / current_activity_ids 와 동일 체계)';


--
-- Name: checkpoint_blobs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.checkpoint_blobs (
    thread_id text NOT NULL,
    checkpoint_ns text DEFAULT ''::text NOT NULL,
    channel text NOT NULL,
    version text NOT NULL,
    type text NOT NULL,
    blob bytea
);


--
-- Name: checkpoint_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.checkpoint_migrations (
    v integer NOT NULL
);


--
-- Name: checkpoint_writes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.checkpoint_writes (
    thread_id text NOT NULL,
    checkpoint_ns text DEFAULT ''::text NOT NULL,
    checkpoint_id text NOT NULL,
    task_id text NOT NULL,
    idx integer NOT NULL,
    channel text NOT NULL,
    type text,
    blob bytea NOT NULL,
    task_path text DEFAULT ''::text NOT NULL
);


--
-- Name: checkpoints; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.checkpoints (
    thread_id text NOT NULL,
    checkpoint_ns text DEFAULT ''::text NOT NULL,
    checkpoint_id text NOT NULL,
    parent_checkpoint_id text,
    type text,
    checkpoint jsonb NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL
);


--
-- Name: context_threads; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.context_threads (
    tenant_id text NOT NULL,
    user_id text NOT NULL,
    conversation_id text NOT NULL,
    title text NOT NULL,
    summary text DEFAULT ''::text,
    kind text DEFAULT 'conversation'::text,
    turns integer DEFAULT 0,
    updated_at timestamp with time zone DEFAULT now(),
    created_at timestamp with time zone DEFAULT now(),
    gist text DEFAULT ''::text
);


--
-- Name: crm_customer_table; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.crm_customer_table (
    customer_id text NOT NULL,
    customer_name text NOT NULL,
    email text NOT NULL,
    grade text NOT NULL,
    interests text,
    acquisition_channel text,
    company text,
    note text,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: departments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.departments (
    id text NOT NULL,
    name text NOT NULL,
    parent_id text,
    tenant_id text DEFAULT public.tenant_id(),
    level integer DEFAULT 0,
    path text,
    manager_email text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


--
-- Name: TABLE departments; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.departments IS '부서 테이블 - BPM 분석을 위한 조직 구조';


--
-- Name: external_api_health; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.external_api_health (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id character varying(255) DEFAULT 'default'::character varying NOT NULL,
    integration_target_name character varying(255) NOT NULL,
    call_address text NOT NULL,
    health_status character varying(20) NOT NULL,
    last_check_time timestamp with time zone DEFAULT now() NOT NULL,
    error_message_log text,
    manual_sync_enabled boolean DEFAULT true NOT NULL,
    last_manual_sync_requested_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT external_api_health_health_status_check CHECK (((health_status)::text = ANY ((ARRAY['정상'::character varying, '비정상'::character varying])::text[])))
);


--
-- Name: fte_capacity; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.fte_capacity (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id character varying(255) NOT NULL,
    role_name character varying(255) NOT NULL,
    available_fte numeric(5,2) DEFAULT 1.0,
    hours_per_day numeric(4,2) DEFAULT 8.0,
    working_days_per_month integer DEFAULT 20,
    monthly_capacity_hours numeric(8,2) GENERATED ALWAYS AS (((available_fte * hours_per_day) * (working_days_per_month)::numeric)) STORED,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


--
-- Name: TABLE fte_capacity; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.fte_capacity IS 'Role/팀별 가용 FTE 용량 설정';


--
-- Name: fte_snapshot; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.fte_snapshot (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id character varying(255) NOT NULL,
    proc_def_id character varying(255) NOT NULL,
    activity_id character varying(255) NOT NULL,
    snapshot_date date NOT NULL,
    instance_count integer DEFAULT 0,
    total_work_minutes integer DEFAULT 0,
    workload_fte numeric(8,4) DEFAULT 0,
    peak_concurrent integer DEFAULT 0,
    peak_fte numeric(8,4) DEFAULT 0,
    load_ratio numeric(5,4) DEFAULT 0,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: TABLE fte_snapshot; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.fte_snapshot IS 'FTE 지표 일별 스냅샷 (시계열 분석용)';


--
-- Name: governance_notification_outbox; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.governance_notification_outbox (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id text NOT NULL,
    event_type text NOT NULL,
    status text DEFAULT 'PENDING'::text NOT NULL,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    recipient_snapshot jsonb DEFAULT '[]'::jsonb NOT NULL,
    dedupe_key text,
    retry_count integer DEFAULT 0 NOT NULL,
    last_error text,
    available_at timestamp with time zone DEFAULT now() NOT NULL,
    digest_id uuid,
    sent_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT governance_notification_outbox_event_type_check CHECK ((event_type = ANY (ARRAY['status_change'::text, 'feedback_registered'::text]))),
    CONSTRAINT governance_notification_outbox_status_check CHECK ((status = ANY (ARRAY['PENDING'::text, 'SENT'::text, 'FAILED'::text])))
);


--
-- Name: TABLE governance_notification_outbox; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.governance_notification_outbox IS 'Governance status/feedback mail outbox. Rows are sent as a weekly digest every Thursday.';


--
-- Name: inventory; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.inventory (
    product_name text NOT NULL,
    stock integer DEFAULT 0 NOT NULL,
    updated_at timestamp with time zone DEFAULT now()
);


--
-- Name: inventory_log; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.inventory_log (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    product_name text NOT NULL,
    new_stock integer NOT NULL,
    reason text,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: kpi_targets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.kpi_targets (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id text DEFAULT 'default'::text NOT NULL,
    period_type text DEFAULT 'quarterly'::text NOT NULL,
    period_start date NOT NULL,
    period_end date NOT NULL,
    total_target integer DEFAULT 0 NOT NULL,
    domain_targets jsonb DEFAULT '[]'::jsonb,
    org_targets jsonb DEFAULT '[]'::jsonb,
    created_by text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    CONSTRAINT kpi_targets_period_type_check CHECK ((period_type = ANY (ARRAY['monthly'::text, 'quarterly'::text, 'yearly'::text])))
);


--
-- Name: lane_role_group_members; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.lane_role_group_members (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    role_group_id uuid NOT NULL,
    tenant_id text NOT NULL,
    org_id text NOT NULL,
    org_name text,
    sort_order integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by text,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by text,
    deleted_at timestamp with time zone,
    deleted_by text,
    member_type text DEFAULT 'team'::text NOT NULL,
    CONSTRAINT lane_role_group_members_member_type_check CHECK ((member_type = ANY (ARRAY['team'::text, 'supplier'::text])))
);


--
-- Name: TABLE lane_role_group_members; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.lane_role_group_members IS '역할 그룹에 매핑된 팀 (org_id/org_name 컨벤션)';


--
-- Name: COLUMN lane_role_group_members.org_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.lane_role_group_members.org_id IS '팀(조직) 식별자 — adminConsole 컨벤션 통일';


--
-- Name: COLUMN lane_role_group_members.org_name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.lane_role_group_members.org_name IS '표시명 스냅샷 (조직명 변경 시 동기화는 호출 측 책임)';


--
-- Name: COLUMN lane_role_group_members.deleted_by; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.lane_role_group_members.deleted_by IS '삭제자 (JWT 자동 채움)';


--
-- Name: COLUMN lane_role_group_members.member_type; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.lane_role_group_members.member_type IS '멤버 종류: team (SSO 팀) | supplier (공급업체). 같은 그룹에 두 종류 섞기 가능.';


--
-- Name: lane_role_groups; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.lane_role_groups (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id text NOT NULL,
    parent_id uuid,
    name text NOT NULL,
    description text,
    sort_order integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by text,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by text,
    deleted_at timestamp with time zone,
    deleted_by text
);


--
-- Name: TABLE lane_role_groups; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.lane_role_groups IS 'BPMN swimlane "역할 그룹" 그룹 (상위/하위 2계층)';


--
-- Name: COLUMN lane_role_groups.parent_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.lane_role_groups.parent_id IS '상위그룹 id (NULL=상위그룹, NOT NULL=하위그룹). depth 2 강제 트리거 있음';


--
-- Name: COLUMN lane_role_groups.sort_order; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.lane_role_groups.sort_order IS '같은 부모 내 표시 순서';


--
-- Name: COLUMN lane_role_groups.deleted_by; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.lane_role_groups.deleted_by IS '삭제자 (JWT 자동 채움). 형식: "이름\n(팀)"';


--
-- Name: logistics_delivery_demo; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.logistics_delivery_demo (
    order_id text NOT NULL,
    cargo_id text NOT NULL,
    warehouse_id text NOT NULL,
    vehicle_id text NOT NULL,
    route_id text NOT NULL,
    sla_id text NOT NULL,
    current_status text NOT NULL,
    planned_departure timestamp without time zone,
    actual_departure timestamp without time zone,
    promised_arrival timestamp without time zone NOT NULL,
    current_eta timestamp without time zone NOT NULL,
    delay_minutes integer DEFAULT 0 NOT NULL,
    delay_reason text NOT NULL,
    recommended_action text NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: mcp_python_code; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.mcp_python_code (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    proc_def_id text NOT NULL,
    activity_id text NOT NULL,
    tenant_id text NOT NULL,
    compensation text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    code text,
    parameters jsonb
);


--
-- Name: menu_role_overrides; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.menu_role_overrides (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    menu_path text NOT NULL,
    required_role text NOT NULL,
    tenant_id text NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by uuid,
    CONSTRAINT menu_role_overrides_role_check CHECK ((required_role = ANY (ARRAY['admin'::text, 'owner'::text, 'editor'::text, 'reviewer'::text, 'viewer'::text])))
);


--
-- Name: TABLE menu_role_overrides; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.menu_role_overrides IS '메뉴별 최소 접근 역할 운영 조정 (코드 기본값 override)';


--
-- Name: COLUMN menu_role_overrides.id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.menu_role_overrides.id IS 'PK (uuid)';


--
-- Name: COLUMN menu_role_overrides.name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.menu_role_overrides.name IS '메뉴 label (예: PI Flag) — UI 표시·관리 편의';


--
-- Name: COLUMN menu_role_overrides.menu_path; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.menu_role_overrides.menu_path IS '라우트 경로 (예: /admin-console/pi-flags) — 권한 판정 키';


--
-- Name: COLUMN menu_role_overrides.required_role; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.menu_role_overrides.required_role IS '최소 접근 역할 (admin|owner|editor|reviewer|viewer)';


--
-- Name: COLUMN menu_role_overrides.tenant_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.menu_role_overrides.tenant_id IS '테넌트 식별자 (window.$tenantName)';


--
-- Name: COLUMN menu_role_overrides.updated_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.menu_role_overrides.updated_at IS '마지막 수정 시각';


--
-- Name: COLUMN menu_role_overrides.updated_by; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.menu_role_overrides.updated_by IS '마지막 수정자 (users.id 값, FK 미지정 — users PK 가 복합키 (id, tenant_id) 이라 단일 FK 불가)';


--
-- Name: org_chart_group_teams; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.org_chart_group_teams (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    group_id uuid NOT NULL,
    team_id character varying(255) NOT NULL,
    team_name character varying(255) NOT NULL,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: TABLE org_chart_group_teams; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.org_chart_group_teams IS '그룹에 속한 팀 매핑';


--
-- Name: COLUMN org_chart_group_teams.team_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.org_chart_group_teams.team_id IS '조직도의 팀 ID';


--
-- Name: COLUMN org_chart_group_teams.team_name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.org_chart_group_teams.team_name IS '팀 이름 (조회 편의용)';


--
-- Name: org_chart_groups; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.org_chart_groups (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying(255) NOT NULL,
    description text,
    tenant_id character varying(100),
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


--
-- Name: TABLE org_chart_groups; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.org_chart_groups IS '조직도 그룹 - 프로세스 권한 설정용';


--
-- Name: COLUMN org_chart_groups.name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.org_chart_groups.name IS '그룹 이름';


--
-- Name: COLUMN org_chart_groups.description; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.org_chart_groups.description IS '그룹 설명';


--
-- Name: permissions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.permissions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    label text NOT NULL,
    api_path text NOT NULL,
    verb text NOT NULL,
    CONSTRAINT permissions_verb_check CHECK ((verb = ANY (ARRAY['GET'::text, 'POST'::text, 'PUT'::text, 'PATCH'::text, 'DELETE'::text, '*'::text])))
);


--
-- Name: TABLE permissions; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.permissions IS '커스텀 권한 마스터 카탈로그 (verb + api_path 단위)';


--
-- Name: COLUMN permissions.id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.permissions.id IS '권한 PK (uuid)';


--
-- Name: COLUMN permissions.name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.permissions.name IS '권한 코드 (예: kpi_read, recycle_delete) — 어플리케이션에서 식별자로 사용';


--
-- Name: COLUMN permissions.label; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.permissions.label IS '권한 표시 이름 (한국어, UI 노출용)';


--
-- Name: COLUMN permissions.api_path; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.permissions.api_path IS '대상 API endpoint / 페이지 경로';


--
-- Name: COLUMN permissions.verb; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.permissions.verb IS 'HTTP verb: GET | POST | PUT | PATCH | DELETE | * (모든 verb)';


--
-- Name: pro_actions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pro_actions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    verb text NOT NULL,
    text text NOT NULL,
    icon text,
    due text,
    prompt text,
    source jsonb,
    status text DEFAULT 'open'::text,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: pro_mail_accounts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pro_mail_accounts (
    user_id uuid NOT NULL,
    provider text NOT NULL,
    address text,
    vault_item uuid,
    cursor text,
    last_poll timestamp with time zone
);


--
-- Name: pro_mail_seen; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pro_mail_seen (
    user_id uuid NOT NULL,
    mail_id text NOT NULL
);


--
-- Name: pro_messages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pro_messages (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    thread_id uuid NOT NULL,
    role text NOT NULL,
    kind text DEFAULT 'text'::text NOT NULL,
    content jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: pro_mission_runs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pro_mission_runs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    schedule_id uuid NOT NULL,
    trigger text DEFAULT 'cron'::text,
    started_at timestamp with time zone DEFAULT now(),
    finished_at timestamp with time zone,
    status text DEFAULT 'running'::text,
    changed boolean,
    summary text,
    result jsonb,
    conversation_id text
);


--
-- Name: pro_panels; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pro_panels (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    title text NOT NULL,
    icon text,
    spec jsonb NOT NULL,
    data jsonb DEFAULT '{}'::jsonb,
    refresh jsonb,
    sort integer DEFAULT 100,
    updated_at timestamp with time zone DEFAULT now()
);


--
-- Name: pro_profile; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pro_profile (
    user_id uuid NOT NULL,
    name text,
    email text,
    birth date,
    lat double precision,
    lon double precision,
    place text,
    onboarded_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: pro_role_assignments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pro_role_assignments (
    tenant_id text NOT NULL,
    proc_def_id text DEFAULT '*'::text NOT NULL,
    role text NOT NULL,
    user_id uuid NOT NULL,
    updated_by uuid,
    updated_at timestamp with time zone DEFAULT now()
);


--
-- Name: pro_schedules; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pro_schedules (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    name text NOT NULL,
    cron text NOT NULL,
    prompt text NOT NULL,
    thread_id uuid,
    job_name text,
    last_run timestamp with time zone,
    created_at timestamp with time zone DEFAULT now(),
    skill text,
    params jsonb DEFAULT '{}'::jsonb,
    notify text DEFAULT 'on_change'::text,
    paused boolean DEFAULT false,
    state jsonb DEFAULT '{}'::jsonb,
    agent jsonb DEFAULT '{"orch": "deepagents"}'::jsonb,
    process_id text
);


--
-- Name: pro_team_members; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pro_team_members (
    tenant_id text NOT NULL,
    user_id uuid NOT NULL,
    added_by uuid,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: pro_threads; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pro_threads (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    kind text DEFAULT 'chat'::text NOT NULL,
    title text,
    status text,
    conversation_id text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    ref text
);


--
-- Name: pro_vault_audit; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pro_vault_audit (
    id bigint NOT NULL,
    user_id uuid NOT NULL,
    item_id uuid,
    kind text,
    site text,
    action text NOT NULL,
    actor text NOT NULL,
    task_id uuid,
    detail jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: pro_vault_audit_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.pro_vault_audit_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: pro_vault_audit_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.pro_vault_audit_id_seq OWNED BY public.pro_vault_audit.id;


--
-- Name: pro_vault_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pro_vault_items (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    kind text NOT NULL,
    site text NOT NULL,
    label text,
    secret text NOT NULL,
    status text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    fingerprint text,
    meta jsonb DEFAULT '{}'::jsonb NOT NULL,
    dek_version integer DEFAULT 1 NOT NULL,
    last_used_at timestamp with time zone,
    use_count integer DEFAULT 0 NOT NULL
);


--
-- Name: pro_vault_keys; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pro_vault_keys (
    user_id uuid NOT NULL,
    kek_id text NOT NULL,
    wrapped_dek text NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    dek_version integer DEFAULT 1 NOT NULL,
    rotated_at timestamp with time zone
);


--
-- Name: proc_def_approval_history; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.proc_def_approval_history (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    proc_def_id text NOT NULL,
    review_id uuid,
    action text NOT NULL,
    from_state text,
    to_state text NOT NULL,
    actor_id text NOT NULL,
    actor_name text,
    comment text,
    tenant_id text DEFAULT 'default'::text,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: proc_def_approval_state; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.proc_def_approval_state (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    proc_def_id text NOT NULL,
    state text DEFAULT 'draft'::text NOT NULL,
    version text,
    major_version integer DEFAULT 0,
    minor_version integer DEFAULT 1,
    version_label text,
    submitted_by_id text,
    submitted_by text,
    submitted_at timestamp with time zone,
    submit_comment text,
    reviewer_level1_id text,
    reviewer_level1_name text,
    reviewed_at_level1 timestamp with time zone,
    review_comment_level1 text,
    reviewer_level2_id text,
    reviewer_level2_name text,
    reviewed_at_level2 timestamp with time zone,
    review_comment_level2 text,
    hq_reviewer_id text,
    hq_reviewer_name text,
    hq_reviewed_at timestamp with time zone,
    hq_review_comment text,
    hq_status text DEFAULT 'pending'::text,
    field_reviewer_id text,
    field_reviewer_name text,
    field_reviewed_at timestamp with time zone,
    field_review_comment text,
    field_status text DEFAULT 'pending'::text,
    public_feedback_started_at timestamp with time zone,
    public_feedback_ends_at timestamp with time zone,
    public_feedback_auto_transitioned boolean DEFAULT false,
    confirmed_by_id text,
    confirmed_by_name text,
    confirmed_at timestamp with time zone,
    confirm_comment text,
    published_by_id text,
    published_by_name text,
    published_at timestamp with time zone,
    publish_comment text,
    rejected_by_id text,
    rejected_by_name text,
    rejected_at timestamp with time zone,
    reject_comment text,
    reopen_requested_by text,
    reopen_requested_at timestamp with time zone,
    reopen_reason text,
    reopen_approved_by text,
    reopen_approved_at timestamp with time zone,
    root_cause_review_id uuid,
    assigned_reviewer_id text,
    assigned_reviewer_name text,
    tenant_id text DEFAULT 'default'::text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    CONSTRAINT proc_def_approval_state_field_status_check CHECK (((field_status IS NULL) OR (field_status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text])))),
    CONSTRAINT proc_def_approval_state_hq_status_check CHECK (((hq_status IS NULL) OR (hq_status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text])))),
    CONSTRAINT proc_def_approval_state_state_check CHECK ((state = ANY (ARRAY['draft'::text, 'in_review'::text, 'public_feedback'::text, 'final_edit'::text, 'published'::text, 'reopen_requested'::text, 'archived'::text, 'rejected'::text, 'cancelled'::text])))
);

ALTER TABLE ONLY public.proc_def_approval_state REPLICA IDENTITY FULL;


--
-- Name: proc_def_comments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.proc_def_comments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    proc_def_id text NOT NULL,
    element_id text NOT NULL,
    element_type text,
    element_name text,
    author_id text NOT NULL,
    author_name text,
    content text NOT NULL,
    parent_comment_id uuid,
    is_resolved boolean DEFAULT false,
    resolved_by text,
    resolved_at timestamp with time zone,
    resolve_action_text text,
    reviewer_type text,
    tenant_id text DEFAULT 'default'::text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    submission_round integer DEFAULT 1,
    CONSTRAINT proc_def_comments_reviewer_type_check CHECK (((reviewer_type IS NULL) OR (reviewer_type = ANY (ARRAY['hq'::text, 'field'::text, 'public'::text]))))
);


--
-- Name: proc_def_copilot_log; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.proc_def_copilot_log (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    proc_def_id text NOT NULL,
    question text NOT NULL,
    answer text,
    created_by text NOT NULL,
    tenant_id text DEFAULT 'default'::text,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: proc_def_element_comment_counts; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.proc_def_element_comment_counts AS
 SELECT proc_def_comments.proc_def_id,
    proc_def_comments.element_id,
    count(*) AS total_count,
    count(*) FILTER (WHERE (NOT proc_def_comments.is_resolved)) AS unresolved_count,
    count(*) FILTER (WHERE proc_def_comments.is_resolved) AS resolved_count
   FROM public.proc_def_comments
  WHERE (proc_def_comments.parent_comment_id IS NULL)
  GROUP BY proc_def_comments.proc_def_id, proc_def_comments.element_id;


--
-- Name: proc_def_snapshots; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.proc_def_snapshots (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    review_id uuid,
    proc_def_id text NOT NULL,
    stage text NOT NULL,
    major_version integer,
    minor_version integer,
    bpmn_xml text,
    bpmn_json jsonb,
    metadata jsonb DEFAULT '{}'::jsonb,
    tenant_id text DEFAULT 'default'::text,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: product_table; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.product_table (
    product_name text,
    product_id text,
    category text,
    unit_price numeric,
    unit text,
    description text,
    stock_quantity numeric,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: skill_contributions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.skill_contributions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id text NOT NULL,
    skill_name text NOT NULL,
    contributor_user_id text NOT NULL,
    contributor_name text,
    contribution_type text NOT NULL,
    source_proposal_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT skill_contributions_contribution_type_check CHECK ((contribution_type = ANY (ARRAY['CREATED'::text, 'MODIFIED'::text, 'PROPOSAL_APPROVED'::text])))
);


--
-- Name: standard_terminology; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.standard_terminology (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id text DEFAULT 'default'::text NOT NULL,
    category text NOT NULL,
    term text NOT NULL,
    description text,
    usage_count integer DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


--
-- Name: strategy_initiatives; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.strategy_initiatives (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id text NOT NULL,
    objective_id uuid NOT NULL,
    name text NOT NULL,
    description text,
    owner_email text,
    status text DEFAULT 'planned'::text NOT NULL,
    progress integer DEFAULT 0 NOT NULL,
    proc_def_id text,
    start_date date,
    due_date date,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: strategy_kpi_measurements; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.strategy_kpi_measurements (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    kpi_id uuid NOT NULL,
    tenant_id text NOT NULL,
    value numeric,
    source text DEFAULT 'auto'::text NOT NULL,
    measured_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: strategy_kpis; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.strategy_kpis (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id text NOT NULL,
    objective_id uuid NOT NULL,
    name text NOT NULL,
    description text,
    unit text,
    measure_type text DEFAULT 'manual'::text NOT NULL,
    proc_def_id text,
    direction text DEFAULT 'increase'::text NOT NULL,
    baseline_value numeric,
    target_value numeric,
    current_value numeric,
    period_start date,
    period_end date,
    survey_questions jsonb DEFAULT '[]'::jsonb NOT NULL,
    last_measured_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: strategy_objectives; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.strategy_objectives (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id text NOT NULL,
    name text NOT NULL,
    description text,
    perspective text DEFAULT 'financial'::text NOT NULL,
    parents jsonb DEFAULT '[]'::jsonb NOT NULL,
    sort_order integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: strategy_survey_requests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.strategy_survey_requests (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id text NOT NULL,
    kpi_id uuid NOT NULL,
    proc_inst_id text,
    proc_inst_name text,
    respondent_email text NOT NULL,
    respondent_name text,
    status text DEFAULT 'SENT'::text NOT NULL,
    questions jsonb DEFAULT '[]'::jsonb NOT NULL,
    answers jsonb,
    score numeric,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    answered_at timestamp with time zone
);


--
-- Name: strategy_sync_state; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.strategy_sync_state (
    key text NOT NULL,
    value text
);


--
-- Name: suppliers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.suppliers (
    id uuid NOT NULL,
    tenant_id text NOT NULL,
    name text NOT NULL,
    normalized_name text NOT NULL,
    registration_type text,
    registered_at date,
    business_number text,
    source_file text NOT NULL,
    source_sheet text NOT NULL,
    source_row integer NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    deleted_by text
);


--
-- Name: systems; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.systems (
    id text NOT NULL,
    tenant_id text NOT NULL,
    name text NOT NULL,
    system_type text,
    category text,
    description text,
    shortcut_link text,
    is_active integer DEFAULT 1 NOT NULL,
    responsible_org_id text,
    responsible_person text,
    registration_status text DEFAULT 'active'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by text,
    created_by_display text,
    deleted_at timestamp with time zone,
    deleted_by text
);


--
-- Name: task_execution_properties; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.task_execution_properties (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id text DEFAULT public.tenant_id(),
    proc_def_id text,
    proc_inst_id text NOT NULL,
    activity_id text,
    activity_name text,
    todo_id uuid,
    role text,
    duration integer,
    instruction text,
    description text,
    checkpoints text[],
    agent_id text,
    agent_mode text,
    orchestration text,
    tool text,
    system_name text,
    menu_name text,
    input_data jsonb DEFAULT '[]'::jsonb,
    custom_properties jsonb DEFAULT '[]'::jsonb,
    execution_status text DEFAULT 'STARTED'::text NOT NULL,
    started_at timestamp with time zone DEFAULT now() NOT NULL,
    completed_at timestamp with time zone,
    actual_duration interval,
    executor_email text,
    executor_dept_id text,
    executor_dept_name text
);


--
-- Name: tb_bpmn_lane; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tb_bpmn_lane (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    model_id uuid NOT NULL,
    element_id character varying(255) NOT NULL,
    element_type character varying(100) NOT NULL,
    name character varying(500),
    participant_ref character varying(255),
    parent_lane_id uuid,
    is_horizontal boolean DEFAULT true,
    x numeric,
    y numeric,
    width numeric,
    height numeric,
    properties jsonb DEFAULT '{}'::jsonb,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: tb_bpmn_link; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tb_bpmn_link (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    model_id uuid NOT NULL,
    element_id character varying(255) NOT NULL,
    element_type character varying(100) NOT NULL,
    name character varying(500),
    source_node_id uuid,
    target_node_id uuid,
    source_element_id character varying(255),
    target_element_id character varying(255),
    condition_expression text,
    is_default boolean DEFAULT false,
    waypoints jsonb,
    properties jsonb DEFAULT '{}'::jsonb,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: tb_bpmn_model; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tb_bpmn_model (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id text DEFAULT 'default'::text NOT NULL,
    proc_def_id text NOT NULL,
    name character varying(500),
    description text,
    status character varying(50) DEFAULT 'draft'::character varying,
    parent_proc_def_id text,
    domain_id text,
    hierarchy_level character varying(20),
    process_id character varying(255),
    is_executable boolean DEFAULT false,
    xml_hash character varying(64),
    node_count integer DEFAULT 0,
    link_count integer DEFAULT 0,
    lane_count integer DEFAULT 0,
    parsed_at timestamp with time zone,
    created_by text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    deleted_at timestamp with time zone,
    deleted_by text
);


--
-- Name: tb_bpmn_model_lock; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tb_bpmn_model_lock (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    model_id uuid NOT NULL,
    locked_by text NOT NULL,
    locked_by_name character varying(255),
    locked_at timestamp with time zone DEFAULT now(),
    expires_at timestamp with time zone
);


--
-- Name: tb_bpmn_node; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tb_bpmn_node (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    model_id uuid NOT NULL,
    element_id character varying(255) NOT NULL,
    element_type character varying(100) NOT NULL,
    name character varying(500),
    x numeric,
    y numeric,
    width numeric,
    height numeric,
    lane_id uuid,
    task_type character varying(50),
    assignee text,
    candidate_groups text,
    candidate_users text,
    due_date text,
    gateway_direction character varying(20),
    event_type character varying(50),
    event_definition character varying(50),
    is_expanded boolean DEFAULT true,
    called_element character varying(255),
    documentation text,
    properties jsonb DEFAULT '{}'::jsonb,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: tb_bpmn_version; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tb_bpmn_version (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    model_id uuid NOT NULL,
    version_number integer NOT NULL,
    version_label character varying(50),
    xml_snapshot text NOT NULL,
    change_log text,
    node_count integer DEFAULT 0,
    link_count integer DEFAULT 0,
    created_by text,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: v_activity_bottleneck; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_activity_bottleneck AS
 WITH task_sequence AS (
         SELECT t.id,
            t.proc_inst_id,
            t.activity_id,
            t.activity_name,
            t.tenant_id,
            t.start_date,
            t.end_date,
            lag(t.end_date) OVER (PARTITION BY t.proc_inst_id ORDER BY t.start_date) AS prev_end_date,
            EXTRACT(epoch FROM (t.end_date - t.start_date)) AS processing_time_sec
           FROM public.todolist t
          WHERE ((t.start_date IS NOT NULL) AND (t.proc_inst_id IS NOT NULL) AND (t.activity_id IS NOT NULL))
        )
 SELECT ts.activity_id,
    ts.activity_name,
    ts.tenant_id,
    count(*) AS execution_count,
    avg(ts.processing_time_sec) AS avg_processing_time_sec,
    avg(EXTRACT(epoch FROM (ts.start_date - ts.prev_end_date))) AS avg_wait_time_sec,
    sum(ts.processing_time_sec) AS total_processing_time_sec,
    sum(EXTRACT(epoch FROM (ts.start_date - ts.prev_end_date))) AS total_wait_time_sec
   FROM task_sequence ts
  GROUP BY ts.activity_id, ts.activity_name, ts.tenant_id;


--
-- Name: VIEW v_activity_bottleneck; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.v_activity_bottleneck IS '활동별 병목 분석 (Wait Time, Processing Time)';


--
-- Name: v_department_task_stats; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_department_task_stats AS
 SELECT COALESCE(t.executor_dept_id, u.department_id, 'UNASSIGNED'::text) AS dept_id,
    COALESCE(t.executor_dept_name, u.department_name, '미지정'::text) AS dept_name,
    t.tenant_id,
    count(*) AS total_tasks,
    count(
        CASE
            WHEN (t.agent_orch IS NOT NULL) THEN 1
            ELSE NULL::integer
        END) AS agent_tasks,
    count(
        CASE
            WHEN ((t.agent_orch IS NULL) AND (t.user_id IS NOT NULL)) THEN 1
            ELSE NULL::integer
        END) AS human_tasks,
    count(
        CASE
            WHEN (t.status = 'DONE'::public.todo_status) THEN 1
            ELSE NULL::integer
        END) AS completed_tasks,
    count(
        CASE
            WHEN (t.status = ANY (ARRAY['NEW'::public.todo_status, 'TODO'::public.todo_status, 'IN_PROGRESS'::public.todo_status])) THEN 1
            ELSE NULL::integer
        END) AS pending_tasks,
    avg(EXTRACT(epoch FROM (t.end_date - t.start_date))) AS avg_duration_sec,
    sum(COALESCE(t.rework_count, 0)) AS total_rework,
    count(
        CASE
            WHEN (t.rework_count > 0) THEN 1
            ELSE NULL::integer
        END) AS tasks_with_rework
   FROM (public.todolist t
     LEFT JOIN public.users u ON (((t.user_id = (u.id)::text) AND (t.tenant_id = u.tenant_id))))
  WHERE (t.start_date IS NOT NULL)
  GROUP BY COALESCE(t.executor_dept_id, u.department_id, 'UNASSIGNED'::text), COALESCE(t.executor_dept_name, u.department_name, '미지정'::text), t.tenant_id;


--
-- Name: VIEW v_department_task_stats; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.v_department_task_stats IS '부서별 Task 통계';


--
-- Name: v_kpi_domain_progress; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_kpi_domain_progress AS
 SELECT m.domain_id,
    m.tenant_id,
    count(*) AS total_processes,
    count(
        CASE
            WHEN (lr.state = 'published'::text) THEN 1
            ELSE NULL::integer
        END) AS published_count,
    count(
        CASE
            WHEN (lr.state = 'draft'::text) THEN 1
            ELSE NULL::integer
        END) AS draft_count,
    count(
        CASE
            WHEN (lr.state = 'in_review'::text) THEN 1
            ELSE NULL::integer
        END) AS in_review_count,
    count(
        CASE
            WHEN (lr.state = 'public_feedback'::text) THEN 1
            ELSE NULL::integer
        END) AS public_feedback_count,
    count(
        CASE
            WHEN (lr.state = 'final_edit'::text) THEN 1
            ELSE NULL::integer
        END) AS final_edit_count
   FROM (public.tb_bpmn_model m
     LEFT JOIN ( SELECT DISTINCT ON (proc_def_approval_state.proc_def_id, proc_def_approval_state.tenant_id) proc_def_approval_state.proc_def_id,
            proc_def_approval_state.tenant_id,
            proc_def_approval_state.state
           FROM public.proc_def_approval_state
          ORDER BY proc_def_approval_state.proc_def_id, proc_def_approval_state.tenant_id, proc_def_approval_state.created_at DESC) lr ON (((m.proc_def_id = lr.proc_def_id) AND (m.tenant_id = lr.tenant_id))))
  WHERE (m.deleted_at IS NULL)
  GROUP BY m.domain_id, m.tenant_id;


--
-- Name: v_kpi_pipeline_summary; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_kpi_pipeline_summary AS
 SELECT latest_reviews.tenant_id,
    count(*) AS total_processes,
    count(
        CASE
            WHEN (latest_reviews.state = 'draft'::text) THEN 1
            ELSE NULL::integer
        END) AS draft_count,
    count(
        CASE
            WHEN (latest_reviews.state = 'in_review'::text) THEN 1
            ELSE NULL::integer
        END) AS in_review_count,
    count(
        CASE
            WHEN (latest_reviews.state = 'public_feedback'::text) THEN 1
            ELSE NULL::integer
        END) AS public_feedback_count,
    count(
        CASE
            WHEN (latest_reviews.state = 'final_edit'::text) THEN 1
            ELSE NULL::integer
        END) AS final_edit_count,
    count(
        CASE
            WHEN (latest_reviews.state = 'published'::text) THEN 1
            ELSE NULL::integer
        END) AS published_count,
    count(
        CASE
            WHEN (latest_reviews.state = 'reopen_requested'::text) THEN 1
            ELSE NULL::integer
        END) AS reopen_requested_count,
    count(
        CASE
            WHEN (latest_reviews.state = 'rejected'::text) THEN 1
            ELSE NULL::integer
        END) AS rejected_count,
    count(
        CASE
            WHEN (latest_reviews.state = 'archived'::text) THEN 1
            ELSE NULL::integer
        END) AS archived_count
   FROM ( SELECT DISTINCT ON (proc_def_approval_state.proc_def_id, proc_def_approval_state.tenant_id) proc_def_approval_state.proc_def_id,
            proc_def_approval_state.tenant_id,
            proc_def_approval_state.state
           FROM public.proc_def_approval_state
          ORDER BY proc_def_approval_state.proc_def_id, proc_def_approval_state.tenant_id, proc_def_approval_state.created_at DESC) latest_reviews
  GROUP BY latest_reviews.tenant_id;


--
-- Name: v_monthly_trend; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_monthly_trend AS
 SELECT date_trunc('month'::text, t.start_date) AS month,
    t.tenant_id,
    count(*) AS total_tasks,
    count(
        CASE
            WHEN (t.agent_orch IS NOT NULL) THEN 1
            ELSE NULL::integer
        END) AS agent_tasks,
    count(
        CASE
            WHEN ((t.agent_orch IS NULL) AND (t.user_id IS NOT NULL)) THEN 1
            ELSE NULL::integer
        END) AS human_tasks,
    count(
        CASE
            WHEN (t.status = 'DONE'::public.todo_status) THEN 1
            ELSE NULL::integer
        END) AS completed_tasks,
    avg(EXTRACT(epoch FROM (t.end_date - t.start_date))) AS avg_duration_sec,
    sum(COALESCE(t.rework_count, 0)) AS total_rework
   FROM public.todolist t
  WHERE (t.start_date IS NOT NULL)
  GROUP BY (date_trunc('month'::text, t.start_date)), t.tenant_id
  ORDER BY (date_trunc('month'::text, t.start_date)) DESC;


--
-- Name: VIEW v_monthly_trend; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.v_monthly_trend IS '월별 Task 트렌드';


--
-- Name: v_process_performance; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_process_performance AS
 SELECT pi.proc_def_id,
    pd.name AS process_name,
    pi.tenant_id,
    count(*) AS total_instances,
    count(
        CASE
            WHEN (pi.status = 'COMPLETED'::public.process_status) THEN 1
            ELSE NULL::integer
        END) AS completed_instances,
    count(
        CASE
            WHEN (pi.status = 'RUNNING'::public.process_status) THEN 1
            ELSE NULL::integer
        END) AS running_instances,
    avg(EXTRACT(epoch FROM (pi.end_date - pi.start_date))) AS avg_cycle_time_sec,
    min(EXTRACT(epoch FROM (pi.end_date - pi.start_date))) AS min_cycle_time_sec,
    max(EXTRACT(epoch FROM (pi.end_date - pi.start_date))) AS max_cycle_time_sec,
    percentile_cont((0.5)::double precision) WITHIN GROUP (ORDER BY ((EXTRACT(epoch FROM (pi.end_date - pi.start_date)))::double precision)) AS median_cycle_time_sec,
    percentile_cont((0.95)::double precision) WITHIN GROUP (ORDER BY ((EXTRACT(epoch FROM (pi.end_date - pi.start_date)))::double precision)) AS p95_cycle_time_sec
   FROM (public.bpm_proc_inst pi
     LEFT JOIN public.proc_def pd ON (((pi.proc_def_id = pd.id) AND (pi.tenant_id = pd.tenant_id))))
  WHERE (pi.is_deleted = false)
  GROUP BY pi.proc_def_id, pd.name, pi.tenant_id;


--
-- Name: VIEW v_process_performance; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.v_process_performance IS '프로세스 성능 지표 (Cycle Time, Throughput)';


--
-- Name: v_review_board; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_review_board AS
 SELECT pas.id AS review_id,
    pas.proc_def_id,
    pd.name AS process_name,
    pd.owner,
    pas.state,
    pas.version,
    pas.submitted_by,
    pas.submitted_at,
    pas.reviewer_level1_name,
    pas.reviewed_at_level1,
    pas.confirmed_by_name,
    pas.confirmed_at,
    pas.rejected_by_name,
    pas.rejected_at,
    pas.reject_comment,
    m.domain_id,
    COALESCE(cc.comment_count, (0)::bigint) AS comment_count,
    pas.tenant_id,
    pas.updated_at
   FROM (((public.proc_def_approval_state pas
     JOIN public.proc_def pd ON (((pas.proc_def_id = pd.id) AND (pas.tenant_id = pd.tenant_id))))
     LEFT JOIN public.tb_bpmn_model m ON (((pas.proc_def_id = m.proc_def_id) AND (pas.tenant_id = m.tenant_id))))
     LEFT JOIN ( SELECT proc_def_comments.proc_def_id,
            proc_def_comments.tenant_id,
            count(*) AS comment_count
           FROM public.proc_def_comments
          GROUP BY proc_def_comments.proc_def_id, proc_def_comments.tenant_id) cc ON (((pas.proc_def_id = cc.proc_def_id) AND (pas.tenant_id = cc.tenant_id))))
  WHERE (pd.isdeleted = false);


--
-- Name: v_sla_compliance; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_sla_compliance AS
 SELECT t.proc_def_id,
    pd.name AS process_name,
    t.activity_id,
    t.activity_name,
    t.tenant_id,
    count(*) AS total_tasks,
    count(
        CASE
            WHEN ((t.due_date IS NOT NULL) AND (t.end_date <= t.due_date)) THEN 1
            ELSE NULL::integer
        END) AS on_time_tasks,
    count(
        CASE
            WHEN ((t.due_date IS NOT NULL) AND (t.end_date > t.due_date)) THEN 1
            ELSE NULL::integer
        END) AS overdue_tasks,
        CASE
            WHEN (count(
            CASE
                WHEN (t.due_date IS NOT NULL) THEN 1
                ELSE NULL::integer
            END) > 0) THEN round(((100.0 * (count(
            CASE
                WHEN ((t.due_date IS NOT NULL) AND (t.end_date <= t.due_date)) THEN 1
                ELSE NULL::integer
            END))::numeric) / (count(
            CASE
                WHEN (t.due_date IS NOT NULL) THEN 1
                ELSE NULL::integer
            END))::numeric), 2)
            ELSE NULL::numeric
        END AS sla_compliance_rate
   FROM (public.todolist t
     LEFT JOIN public.proc_def pd ON (((t.proc_def_id = pd.id) AND (t.tenant_id = pd.tenant_id))))
  WHERE ((t.status = 'DONE'::public.todo_status) AND (t.proc_def_id IS NOT NULL) AND (t.activity_id IS NOT NULL))
  GROUP BY t.proc_def_id, pd.name, t.activity_id, t.activity_name, t.tenant_id;


--
-- Name: VIEW v_sla_compliance; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.v_sla_compliance IS 'SLA 준수율 통계';


--
-- Name: v_weekly_deployment_velocity; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_weekly_deployment_velocity AS
 SELECT h.tenant_id,
    date_trunc('week'::text, h.created_at) AS week_start,
    count(*) AS deployments
   FROM public.proc_def_approval_history h
  WHERE ((h.action = 'publish'::text) AND (h.to_state = 'published'::text))
  GROUP BY h.tenant_id, (date_trunc('week'::text, h.created_at))
  ORDER BY (date_trunc('week'::text, h.created_at)) DESC;


--
-- Name: vw_dashboard_proc_domain; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.vw_dashboard_proc_domain AS
 SELECT (sub.value ->> 'proc_def_id'::text) AS proc_def_id,
    (major.value ->> 'domain'::text) AS domain,
    c.tenant_id
   FROM public.configuration c,
    LATERAL jsonb_array_elements((c.value -> 'mega_proc_list'::text)) mega(value),
    LATERAL jsonb_array_elements((mega.value -> 'major_proc_list'::text)) major(value),
    LATERAL jsonb_array_elements((major.value -> 'sub_proc_list'::text)) sub(value)
  WHERE ((c.key = 'proc_map'::text) AND ((sub.value ->> 'proc_def_id'::text) IS NOT NULL));


--
-- Name: vw_dashboard_activity_types; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.vw_dashboard_activity_types AS
 SELECT
        CASE
            WHEN ((act.value ->> 'type'::text) ~~* '%%manual%%'::text) THEN 'manual'::text
            WHEN (((act.value ->> 'type'::text) ~~* '%%service%%'::text) OR ((act.value ->> 'type'::text) ~~* '%%script%%'::text)) THEN 'service'::text
            WHEN ((act.value ->> 'type'::text) ~~* '%%send%%'::text) THEN 'send'::text
            WHEN ((act.value ->> 'type'::text) ~~* '%%receive%%'::text) THEN 'receive'::text
            WHEN ((act.value ->> 'type'::text) ~~* '%%user%%'::text) THEN 'user'::text
            ELSE 'other'::text
        END AS classified_type,
    COALESCE(dm.domain, '미분류'::text) AS domain,
    count(*) AS task_count,
    pd.tenant_id
   FROM ((public.proc_def pd
     CROSS JOIN LATERAL jsonb_array_elements(
        CASE
            WHEN ((pd.definition -> 'activities'::text) IS NOT NULL) THEN (pd.definition -> 'activities'::text)
            ELSE '[]'::jsonb
        END) act(value))
     LEFT JOIN public.vw_dashboard_proc_domain dm ON (((dm.proc_def_id = pd.id) AND (dm.tenant_id = pd.tenant_id))))
  WHERE (pd.isdeleted = false)
  GROUP BY
        CASE
            WHEN ((act.value ->> 'type'::text) ~~* '%%manual%%'::text) THEN 'manual'::text
            WHEN (((act.value ->> 'type'::text) ~~* '%%service%%'::text) OR ((act.value ->> 'type'::text) ~~* '%%script%%'::text)) THEN 'service'::text
            WHEN ((act.value ->> 'type'::text) ~~* '%%send%%'::text) THEN 'send'::text
            WHEN ((act.value ->> 'type'::text) ~~* '%%receive%%'::text) THEN 'receive'::text
            WHEN ((act.value ->> 'type'::text) ~~* '%%user%%'::text) THEN 'user'::text
            ELSE 'other'::text
        END, dm.domain, pd.tenant_id;


--
-- Name: vw_dashboard_asset_status; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.vw_dashboard_asset_status AS
 SELECT COALESCE(dm.domain, '미분류'::text) AS domain,
    COALESCE(ls.current_status, 'draft'::text) AS status,
    count(*) AS cnt,
    pd.tenant_id
   FROM ((public.proc_def pd
     LEFT JOIN LATERAL ( SELECT pah.to_state AS current_status
           FROM public.proc_def_approval_history pah
          WHERE ((pah.proc_def_id = pd.id) AND (pah.tenant_id = pd.tenant_id))
          ORDER BY pah.created_at DESC
         LIMIT 1) ls ON (true))
     LEFT JOIN public.vw_dashboard_proc_domain dm ON (((dm.proc_def_id = pd.id) AND (dm.tenant_id = pd.tenant_id))))
  WHERE (pd.isdeleted = false)
  GROUP BY dm.domain, COALESCE(ls.current_status, 'draft'::text), pd.tenant_id;


--
-- Name: vw_dashboard_error_processes; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.vw_dashboard_error_processes AS
 SELECT pd.id AS proc_def_id,
    pd.name AS proc_def_name,
    COALESCE(dm.domain, '미분류'::text) AS domain,
        CASE
            WHEN (NOT (EXISTS ( SELECT 1
               FROM jsonb_array_elements(
                    CASE
                        WHEN ((pd.definition -> 'gateways'::text) IS NOT NULL) THEN (pd.definition -> 'gateways'::text)
                        ELSE '[]'::jsonb
                    END) gw(value)
              WHERE ((gw.value ->> 'type'::text) = 'endEvent'::text)))) THEN 'missing_end_event'::text
            WHEN (NOT (EXISTS ( SELECT 1
               FROM jsonb_array_elements(
                    CASE
                        WHEN ((pd.definition -> 'gateways'::text) IS NOT NULL) THEN (pd.definition -> 'gateways'::text)
                        ELSE '[]'::jsonb
                    END) gw(value)
              WHERE ((gw.value ->> 'type'::text) = 'startEvent'::text)))) THEN 'missing_start_event'::text
            ELSE NULL::text
        END AS error_type,
    pd.tenant_id
   FROM (public.proc_def pd
     LEFT JOIN public.vw_dashboard_proc_domain dm ON (((dm.proc_def_id = pd.id) AND (dm.tenant_id = pd.tenant_id))))
  WHERE ((pd.isdeleted = false) AND (pd.definition IS NOT NULL) AND ((NOT (EXISTS ( SELECT 1
           FROM jsonb_array_elements(
                CASE
                    WHEN ((pd.definition -> 'gateways'::text) IS NOT NULL) THEN (pd.definition -> 'gateways'::text)
                    ELSE '[]'::jsonb
                END) gw(value)
          WHERE ((gw.value ->> 'type'::text) = 'endEvent'::text)))) OR (NOT (EXISTS ( SELECT 1
           FROM jsonb_array_elements(
                CASE
                    WHEN ((pd.definition -> 'gateways'::text) IS NOT NULL) THEN (pd.definition -> 'gateways'::text)
                    ELSE '[]'::jsonb
                END) gw(value)
          WHERE ((gw.value ->> 'type'::text) = 'startEvent'::text))))));


--
-- Name: vw_dashboard_kpi_division; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.vw_dashboard_kpi_division AS
 SELECT COALESCE(dm.domain, '미분류'::text) AS division,
    COALESCE(ls.current_status, 'draft'::text) AS status,
    count(*) AS cnt,
    pd.tenant_id
   FROM ((public.proc_def pd
     LEFT JOIN LATERAL ( SELECT pah.to_state AS current_status
           FROM public.proc_def_approval_history pah
          WHERE ((pah.proc_def_id = pd.id) AND (pah.tenant_id = pd.tenant_id))
          ORDER BY pah.created_at DESC
         LIMIT 1) ls ON (true))
     LEFT JOIN public.vw_dashboard_proc_domain dm ON (((dm.proc_def_id = pd.id) AND (dm.tenant_id = pd.tenant_id))))
  WHERE (pd.isdeleted = false)
  GROUP BY dm.domain, COALESCE(ls.current_status, 'draft'::text), pd.tenant_id;


--
-- Name: vw_dashboard_proc_state; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.vw_dashboard_proc_state AS
 WITH approval_states AS (
         SELECT pah.proc_def_id,
            pah.to_state AS current_status,
            pah.from_state AS previous_status,
            pah.actor_id,
            pah.actor_name,
            pah.created_at,
            row_number() OVER (PARTITION BY pah.proc_def_id ORDER BY pah.created_at DESC) AS rn
           FROM public.proc_def_approval_history pah
        )
 SELECT pd.id AS proc_def_id,
    pd.name AS proc_def_name,
    COALESCE(dm.domain, '미분류'::text) AS domain,
    pd.description,
    COALESCE(ls.current_status, 'draft'::text) AS current_status,
    ls.previous_status,
    ls.actor_name AS last_actor,
    ls.created_at AS last_status_change_at,
    pd.saved_at,
    pd.tenant_id
   FROM ((public.proc_def pd
     LEFT JOIN approval_states ls ON (((ls.proc_def_id = pd.id) AND (ls.rn = 1))))
     LEFT JOIN public.vw_dashboard_proc_domain dm ON (((dm.proc_def_id = pd.id) AND (dm.tenant_id = pd.tenant_id))))
  WHERE (pd.isdeleted = false);


--
-- Name: vw_dashboard_quality_detail; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.vw_dashboard_quality_detail AS
 SELECT pd.id AS proc_def_id,
    pd.name AS proc_def_name,
    COALESCE(dm.domain, '미분류'::text) AS domain,
        CASE
            WHEN (((pd.definition ->> 'description'::text) IS NOT NULL) AND ((pd.definition ->> 'description'::text) <> ''::text)) THEN 1
            ELSE 0
        END AS has_description,
        CASE
            WHEN ((pd.name IS NOT NULL) AND (pd.name <> ''::text)) THEN 1
            ELSE 0
        END AS has_name,
        CASE
            WHEN (jsonb_array_length(
            CASE
                WHEN ((pd.definition -> 'roles'::text) IS NOT NULL) THEN (pd.definition -> 'roles'::text)
                ELSE '[]'::jsonb
            END) > 0) THEN 1
            ELSE 0
        END AS has_roles,
        CASE
            WHEN (NOT (EXISTS ( SELECT 1
               FROM jsonb_array_elements(
                    CASE
                        WHEN ((pd.definition -> 'activities'::text) IS NOT NULL) THEN (pd.definition -> 'activities'::text)
                        ELSE '[]'::jsonb
                    END) act(value)
              WHERE (((act.value ->> 'description'::text) IS NULL) OR ((act.value ->> 'description'::text) = ''::text))))) THEN 1
            ELSE 0
        END AS activities_have_description,
        CASE
            WHEN (NOT (EXISTS ( SELECT 1
               FROM jsonb_array_elements(
                    CASE
                        WHEN ((pd.definition -> 'activities'::text) IS NOT NULL) THEN (pd.definition -> 'activities'::text)
                        ELSE '[]'::jsonb
                    END) act(value)
              WHERE (((act.value ->> 'role'::text) IS NULL) OR ((act.value ->> 'role'::text) = ''::text))))) THEN 1
            ELSE 0
        END AS activities_have_role,
        CASE
            WHEN (EXISTS ( SELECT 1
               FROM jsonb_array_elements(
                    CASE
                        WHEN ((pd.definition -> 'gateways'::text) IS NOT NULL) THEN (pd.definition -> 'gateways'::text)
                        ELSE '[]'::jsonb
                    END) gw(value)
              WHERE ((gw.value ->> 'type'::text) = 'endEvent'::text))) THEN 1
            ELSE 0
        END AS has_end_event,
    pd.tenant_id
   FROM (public.proc_def pd
     LEFT JOIN public.vw_dashboard_proc_domain dm ON (((dm.proc_def_id = pd.id) AND (dm.tenant_id = pd.tenant_id))))
  WHERE (pd.isdeleted = false);


--
-- Name: vw_dashboard_rr_heatmap; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.vw_dashboard_rr_heatmap AS
 SELECT (act.value ->> 'role'::text) AS role_name,
    COALESCE(dm.domain, '미분류'::text) AS domain,
    count(*) AS task_count,
    count(DISTINCT pd.id) AS process_count,
    pd.tenant_id
   FROM ((public.proc_def pd
     CROSS JOIN LATERAL jsonb_array_elements(
        CASE
            WHEN ((pd.definition -> 'activities'::text) IS NOT NULL) THEN (pd.definition -> 'activities'::text)
            ELSE '[]'::jsonb
        END) act(value))
     LEFT JOIN public.vw_dashboard_proc_domain dm ON (((dm.proc_def_id = pd.id) AND (dm.tenant_id = pd.tenant_id))))
  WHERE ((pd.isdeleted = false) AND ((act.value ->> 'role'::text) IS NOT NULL) AND ((act.value ->> 'role'::text) <> ''::text))
  GROUP BY (act.value ->> 'role'::text), dm.domain, pd.tenant_id;


--
-- Name: vw_dashboard_system_map; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.vw_dashboard_system_map AS
 SELECT (act.value ->> 'tool'::text) AS tool_name,
    COALESCE(dm.domain, '미분류'::text) AS domain,
    count(*) AS task_count,
    count(DISTINCT pd.id) AS process_count,
    pd.tenant_id
   FROM ((public.proc_def pd
     CROSS JOIN LATERAL jsonb_array_elements(
        CASE
            WHEN ((pd.definition -> 'activities'::text) IS NOT NULL) THEN (pd.definition -> 'activities'::text)
            ELSE '[]'::jsonb
        END) act(value))
     LEFT JOIN public.vw_dashboard_proc_domain dm ON (((dm.proc_def_id = pd.id) AND (dm.tenant_id = pd.tenant_id))))
  WHERE ((pd.isdeleted = false) AND ((act.value ->> 'tool'::text) IS NOT NULL) AND ((act.value ->> 'tool'::text) <> ''::text))
  GROUP BY (act.value ->> 'tool'::text), dm.domain, pd.tenant_id;


--
-- Name: vw_dashboard_version_frequency; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.vw_dashboard_version_frequency AS
 SELECT pah.proc_def_id,
    pd.name AS proc_def_name,
    COALESCE(dm.domain, '미분류'::text) AS domain,
    date_trunc('month'::text, pah.created_at) AS change_month,
    count(*) AS change_count,
    max(pah.created_at) AS last_changed_at,
    pah.tenant_id
   FROM ((public.proc_def_approval_history pah
     JOIN public.proc_def pd ON (((pd.id = pah.proc_def_id) AND (pd.tenant_id = pah.tenant_id))))
     LEFT JOIN public.vw_dashboard_proc_domain dm ON (((dm.proc_def_id = pd.id) AND (dm.tenant_id = pd.tenant_id))))
  GROUP BY pah.proc_def_id, pd.name, dm.domain, (date_trunc('month'::text, pah.created_at)), pah.tenant_id;


--
-- Name: vw_dashboard_weekly_velocity; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.vw_dashboard_weekly_velocity AS
 SELECT date_trunc('week'::text, pah.created_at) AS week_start,
    to_char(date_trunc('week'::text, pah.created_at), 'YYYY-"W"WW'::text) AS week_label,
    count(DISTINCT pah.proc_def_id) FILTER (WHERE (pah.to_state = 'published'::text)) AS published_count,
    count(DISTINCT pah.proc_def_id) AS total_changes,
    pah.tenant_id
   FROM public.proc_def_approval_history pah
  GROUP BY (date_trunc('week'::text, pah.created_at)), pah.tenant_id;


--
-- Name: vw_dashboard_xor_gateways; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.vw_dashboard_xor_gateways AS
 SELECT pd.id AS proc_def_id,
    pd.name AS proc_def_name,
    COALESCE(dm.domain, '미분류'::text) AS domain,
    (gw.value ->> 'id'::text) AS gateway_id,
    (gw.value ->> 'name'::text) AS gateway_name,
    (gw.value ->> 'type'::text) AS gateway_type,
    ( SELECT count(*) AS count
           FROM jsonb_array_elements(
                CASE
                    WHEN ((pd.definition -> 'sequences'::text) IS NOT NULL) THEN (pd.definition -> 'sequences'::text)
                    ELSE '[]'::jsonb
                END) seq(value)
          WHERE ((seq.value ->> 'source'::text) = (gw.value ->> 'id'::text))) AS outgoing_count,
    pd.tenant_id
   FROM ((public.proc_def pd
     CROSS JOIN LATERAL jsonb_array_elements(
        CASE
            WHEN ((pd.definition -> 'gateways'::text) IS NOT NULL) THEN (pd.definition -> 'gateways'::text)
            ELSE '[]'::jsonb
        END) gw(value))
     LEFT JOIN public.vw_dashboard_proc_domain dm ON (((dm.proc_def_id = pd.id) AND (dm.tenant_id = pd.tenant_id))))
  WHERE ((pd.isdeleted = false) AND ((gw.value ->> 'type'::text) ~~* '%%Gateway%%'::text));


--
-- Name: workitem_app; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.workitem_app (
    tenant_id text DEFAULT public.tenant_id() NOT NULL,
    app_id text NOT NULL,
    name text NOT NULL,
    base_url text NOT NULL,
    allowed_origin text,
    description text,
    enabled boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: workitem_app_binding; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.workitem_app_binding (
    tenant_id text DEFAULT public.tenant_id() NOT NULL,
    form_id text NOT NULL,
    app_id text NOT NULL,
    view_path text NOT NULL,
    mode text DEFAULT 'replace'::text NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: pro_vault_audit id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pro_vault_audit ALTER COLUMN id SET DEFAULT nextval('public.pro_vault_audit_id_seq'::regclass);


--
-- Name: activity_config activity_config_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.activity_config
    ADD CONSTRAINT activity_config_pkey PRIMARY KEY (id);


--
-- Name: activity_config activity_config_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.activity_config
    ADD CONSTRAINT activity_config_unique UNIQUE (tenant_id, proc_def_id, activity_id);


--
-- Name: admin_audit_log admin_audit_log_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.admin_audit_log
    ADD CONSTRAINT admin_audit_log_pkey PRIMARY KEY (id);


--
-- Name: admin_requests admin_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.admin_requests
    ADD CONSTRAINT admin_requests_pkey PRIMARY KEY (id);


--
-- Name: app_usage_events app_usage_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_usage_events
    ADD CONSTRAINT app_usage_events_pkey PRIMARY KEY (id);


--
-- Name: audit_policy audit_policy_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_policy
    ADD CONSTRAINT audit_policy_pkey PRIMARY KEY (id);


--
-- Name: bpmn_element_map bpmn_element_map_def_element_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bpmn_element_map
    ADD CONSTRAINT bpmn_element_map_def_element_unique UNIQUE (proc_def_uuid, element_id);


--
-- Name: bpmn_element_map bpmn_element_map_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bpmn_element_map
    ADD CONSTRAINT bpmn_element_map_pkey PRIMARY KEY (element_uuid);


--
-- Name: checkpoint_blobs checkpoint_blobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.checkpoint_blobs
    ADD CONSTRAINT checkpoint_blobs_pkey PRIMARY KEY (thread_id, checkpoint_ns, channel, version);


--
-- Name: checkpoint_migrations checkpoint_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.checkpoint_migrations
    ADD CONSTRAINT checkpoint_migrations_pkey PRIMARY KEY (v);


--
-- Name: checkpoint_writes checkpoint_writes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.checkpoint_writes
    ADD CONSTRAINT checkpoint_writes_pkey PRIMARY KEY (thread_id, checkpoint_ns, checkpoint_id, task_id, idx);


--
-- Name: checkpoints checkpoints_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.checkpoints
    ADD CONSTRAINT checkpoints_pkey PRIMARY KEY (thread_id, checkpoint_ns, checkpoint_id);


--
-- Name: context_threads context_threads_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.context_threads
    ADD CONSTRAINT context_threads_pkey PRIMARY KEY (tenant_id, user_id, conversation_id);


--
-- Name: crm_customer_table crm_customer_table_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.crm_customer_table
    ADD CONSTRAINT crm_customer_table_pkey PRIMARY KEY (customer_id);


--
-- Name: departments departments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departments
    ADD CONSTRAINT departments_pkey PRIMARY KEY (id);


--
-- Name: external_api_health external_api_health_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.external_api_health
    ADD CONSTRAINT external_api_health_pkey PRIMARY KEY (id);


--
-- Name: fte_capacity fte_capacity_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fte_capacity
    ADD CONSTRAINT fte_capacity_pkey PRIMARY KEY (id);


--
-- Name: fte_capacity fte_capacity_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fte_capacity
    ADD CONSTRAINT fte_capacity_unique UNIQUE (tenant_id, role_name);


--
-- Name: fte_snapshot fte_snapshot_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fte_snapshot
    ADD CONSTRAINT fte_snapshot_pkey PRIMARY KEY (id);


--
-- Name: fte_snapshot fte_snapshot_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fte_snapshot
    ADD CONSTRAINT fte_snapshot_unique UNIQUE (tenant_id, proc_def_id, activity_id, snapshot_date);


--
-- Name: governance_notification_outbox governance_notification_outbox_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.governance_notification_outbox
    ADD CONSTRAINT governance_notification_outbox_pkey PRIMARY KEY (id);


--
-- Name: inventory_log inventory_log_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_log
    ADD CONSTRAINT inventory_log_pkey PRIMARY KEY (id);


--
-- Name: inventory inventory_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory
    ADD CONSTRAINT inventory_pkey PRIMARY KEY (product_name);


--
-- Name: kpi_targets kpi_targets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.kpi_targets
    ADD CONSTRAINT kpi_targets_pkey PRIMARY KEY (id);


--
-- Name: kpi_targets kpi_targets_tenant_id_period_type_period_start_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.kpi_targets
    ADD CONSTRAINT kpi_targets_tenant_id_period_type_period_start_key UNIQUE (tenant_id, period_type, period_start);


--
-- Name: lane_role_group_members lane_role_group_members_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lane_role_group_members
    ADD CONSTRAINT lane_role_group_members_pkey PRIMARY KEY (id);


--
-- Name: lane_role_groups lane_role_groups_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lane_role_groups
    ADD CONSTRAINT lane_role_groups_pkey PRIMARY KEY (id);


--
-- Name: logistics_delivery_demo logistics_delivery_demo_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.logistics_delivery_demo
    ADD CONSTRAINT logistics_delivery_demo_pkey PRIMARY KEY (order_id);


--
-- Name: mcp_python_code mcp_python_code_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mcp_python_code
    ADD CONSTRAINT mcp_python_code_pkey PRIMARY KEY (id);


--
-- Name: menu_role_overrides menu_role_overrides_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.menu_role_overrides
    ADD CONSTRAINT menu_role_overrides_pkey PRIMARY KEY (id);


--
-- Name: menu_role_overrides menu_role_overrides_tenant_path_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.menu_role_overrides
    ADD CONSTRAINT menu_role_overrides_tenant_path_key UNIQUE (tenant_id, menu_path);


--
-- Name: org_chart_group_teams org_chart_group_teams_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.org_chart_group_teams
    ADD CONSTRAINT org_chart_group_teams_pkey PRIMARY KEY (id);


--
-- Name: org_chart_groups org_chart_groups_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.org_chart_groups
    ADD CONSTRAINT org_chart_groups_pkey PRIMARY KEY (id);


--
-- Name: permissions permissions_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.permissions
    ADD CONSTRAINT permissions_name_key UNIQUE (name);


--
-- Name: permissions permissions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.permissions
    ADD CONSTRAINT permissions_pkey PRIMARY KEY (id);


--
-- Name: pro_actions pro_actions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pro_actions
    ADD CONSTRAINT pro_actions_pkey PRIMARY KEY (id);


--
-- Name: pro_mail_accounts pro_mail_accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pro_mail_accounts
    ADD CONSTRAINT pro_mail_accounts_pkey PRIMARY KEY (user_id);


--
-- Name: pro_mail_seen pro_mail_seen_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pro_mail_seen
    ADD CONSTRAINT pro_mail_seen_pkey PRIMARY KEY (user_id, mail_id);


--
-- Name: pro_messages pro_messages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pro_messages
    ADD CONSTRAINT pro_messages_pkey PRIMARY KEY (id);


--
-- Name: pro_mission_runs pro_mission_runs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pro_mission_runs
    ADD CONSTRAINT pro_mission_runs_pkey PRIMARY KEY (id);


--
-- Name: pro_panels pro_panels_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pro_panels
    ADD CONSTRAINT pro_panels_pkey PRIMARY KEY (id);


--
-- Name: pro_profile pro_profile_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pro_profile
    ADD CONSTRAINT pro_profile_pkey PRIMARY KEY (user_id);


--
-- Name: pro_role_assignments pro_role_assignments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pro_role_assignments
    ADD CONSTRAINT pro_role_assignments_pkey PRIMARY KEY (tenant_id, proc_def_id, role);


--
-- Name: pro_schedules pro_schedules_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pro_schedules
    ADD CONSTRAINT pro_schedules_pkey PRIMARY KEY (id);


--
-- Name: pro_team_members pro_team_members_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pro_team_members
    ADD CONSTRAINT pro_team_members_pkey PRIMARY KEY (tenant_id, user_id);


--
-- Name: pro_threads pro_threads_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pro_threads
    ADD CONSTRAINT pro_threads_pkey PRIMARY KEY (id);


--
-- Name: pro_vault_audit pro_vault_audit_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pro_vault_audit
    ADD CONSTRAINT pro_vault_audit_pkey PRIMARY KEY (id);


--
-- Name: pro_vault_items pro_vault_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pro_vault_items
    ADD CONSTRAINT pro_vault_items_pkey PRIMARY KEY (id);


--
-- Name: pro_vault_keys pro_vault_keys_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pro_vault_keys
    ADD CONSTRAINT pro_vault_keys_pkey PRIMARY KEY (user_id);


--
-- Name: proc_def_approval_history proc_def_approval_history_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.proc_def_approval_history
    ADD CONSTRAINT proc_def_approval_history_pkey PRIMARY KEY (id);


--
-- Name: proc_def_approval_state proc_def_approval_state_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.proc_def_approval_state
    ADD CONSTRAINT proc_def_approval_state_pkey PRIMARY KEY (id);


--
-- Name: proc_def_comments proc_def_comments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.proc_def_comments
    ADD CONSTRAINT proc_def_comments_pkey PRIMARY KEY (id);


--
-- Name: proc_def_copilot_log proc_def_copilot_log_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.proc_def_copilot_log
    ADD CONSTRAINT proc_def_copilot_log_pkey PRIMARY KEY (id);


--
-- Name: proc_def_snapshots proc_def_snapshots_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.proc_def_snapshots
    ADD CONSTRAINT proc_def_snapshots_pkey PRIMARY KEY (id);


--
-- Name: skill_contributions skill_contributions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.skill_contributions
    ADD CONSTRAINT skill_contributions_pkey PRIMARY KEY (id);


--
-- Name: standard_terminology standard_terminology_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.standard_terminology
    ADD CONSTRAINT standard_terminology_pkey PRIMARY KEY (id);


--
-- Name: standard_terminology standard_terminology_tenant_id_category_term_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.standard_terminology
    ADD CONSTRAINT standard_terminology_tenant_id_category_term_key UNIQUE (tenant_id, category, term);


--
-- Name: strategy_initiatives strategy_initiatives_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.strategy_initiatives
    ADD CONSTRAINT strategy_initiatives_pkey PRIMARY KEY (id);


--
-- Name: strategy_kpi_measurements strategy_kpi_measurements_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.strategy_kpi_measurements
    ADD CONSTRAINT strategy_kpi_measurements_pkey PRIMARY KEY (id);


--
-- Name: strategy_kpis strategy_kpis_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.strategy_kpis
    ADD CONSTRAINT strategy_kpis_pkey PRIMARY KEY (id);


--
-- Name: strategy_objectives strategy_objectives_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.strategy_objectives
    ADD CONSTRAINT strategy_objectives_pkey PRIMARY KEY (id);


--
-- Name: strategy_survey_requests strategy_survey_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.strategy_survey_requests
    ADD CONSTRAINT strategy_survey_requests_pkey PRIMARY KEY (id);


--
-- Name: strategy_sync_state strategy_sync_state_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.strategy_sync_state
    ADD CONSTRAINT strategy_sync_state_pkey PRIMARY KEY (key);


--
-- Name: suppliers suppliers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.suppliers
    ADD CONSTRAINT suppliers_pkey PRIMARY KEY (id);


--
-- Name: systems systems_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.systems
    ADD CONSTRAINT systems_pkey PRIMARY KEY (id);


--
-- Name: task_execution_properties task_execution_properties_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_execution_properties
    ADD CONSTRAINT task_execution_properties_pkey PRIMARY KEY (id);


--
-- Name: tb_bpmn_lane tb_bpmn_lane_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tb_bpmn_lane
    ADD CONSTRAINT tb_bpmn_lane_pkey PRIMARY KEY (id);


--
-- Name: tb_bpmn_lane tb_bpmn_lane_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tb_bpmn_lane
    ADD CONSTRAINT tb_bpmn_lane_unique UNIQUE (model_id, element_id);


--
-- Name: tb_bpmn_link tb_bpmn_link_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tb_bpmn_link
    ADD CONSTRAINT tb_bpmn_link_pkey PRIMARY KEY (id);


--
-- Name: tb_bpmn_link tb_bpmn_link_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tb_bpmn_link
    ADD CONSTRAINT tb_bpmn_link_unique UNIQUE (model_id, element_id);


--
-- Name: tb_bpmn_model_lock tb_bpmn_model_lock_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tb_bpmn_model_lock
    ADD CONSTRAINT tb_bpmn_model_lock_pkey PRIMARY KEY (id);


--
-- Name: tb_bpmn_model_lock tb_bpmn_model_lock_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tb_bpmn_model_lock
    ADD CONSTRAINT tb_bpmn_model_lock_unique UNIQUE (model_id);


--
-- Name: tb_bpmn_model tb_bpmn_model_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tb_bpmn_model
    ADD CONSTRAINT tb_bpmn_model_pkey PRIMARY KEY (id);


--
-- Name: tb_bpmn_model tb_bpmn_model_proc_def_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tb_bpmn_model
    ADD CONSTRAINT tb_bpmn_model_proc_def_unique UNIQUE (tenant_id, proc_def_id);


--
-- Name: tb_bpmn_node tb_bpmn_node_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tb_bpmn_node
    ADD CONSTRAINT tb_bpmn_node_pkey PRIMARY KEY (id);


--
-- Name: tb_bpmn_node tb_bpmn_node_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tb_bpmn_node
    ADD CONSTRAINT tb_bpmn_node_unique UNIQUE (model_id, element_id);


--
-- Name: tb_bpmn_version tb_bpmn_version_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tb_bpmn_version
    ADD CONSTRAINT tb_bpmn_version_pkey PRIMARY KEY (id);


--
-- Name: tb_bpmn_version tb_bpmn_version_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tb_bpmn_version
    ADD CONSTRAINT tb_bpmn_version_unique UNIQUE (model_id, version_number);


--
-- Name: strategy_survey_requests uq_strategy_survey_request; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.strategy_survey_requests
    ADD CONSTRAINT uq_strategy_survey_request UNIQUE (kpi_id, proc_inst_id, respondent_email);


--
-- Name: workitem_app_binding workitem_app_binding_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workitem_app_binding
    ADD CONSTRAINT workitem_app_binding_pkey PRIMARY KEY (tenant_id, form_id);


--
-- Name: workitem_app workitem_app_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workitem_app
    ADD CONSTRAINT workitem_app_pkey PRIMARY KEY (tenant_id, app_id);


--
-- Name: checkpoint_blobs_thread_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX checkpoint_blobs_thread_id_idx ON public.checkpoint_blobs USING btree (thread_id);


--
-- Name: checkpoint_writes_thread_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX checkpoint_writes_thread_id_idx ON public.checkpoint_writes USING btree (thread_id);


--
-- Name: checkpoints_thread_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX checkpoints_thread_id_idx ON public.checkpoints USING btree (thread_id);


--
-- Name: context_threads_recent; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX context_threads_recent ON public.context_threads USING btree (tenant_id, user_id, updated_at DESC);


--
-- Name: idx_activity_config_tenant_proc; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_activity_config_tenant_proc ON public.activity_config USING btree (tenant_id, proc_def_id);


--
-- Name: idx_admin_audit_log_action; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_admin_audit_log_action ON public.admin_audit_log USING btree (action);


--
-- Name: idx_admin_audit_log_actor; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_admin_audit_log_actor ON public.admin_audit_log USING btree (actor_id);


--
-- Name: idx_admin_audit_log_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_admin_audit_log_created ON public.admin_audit_log USING btree (created_at DESC);


--
-- Name: idx_admin_audit_log_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_admin_audit_log_tenant ON public.admin_audit_log USING btree (tenant_id);


--
-- Name: idx_admin_requests_tenant_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_admin_requests_tenant_status ON public.admin_requests USING btree (tenant_id, status);


--
-- Name: idx_admin_requests_user_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_admin_requests_user_tenant ON public.admin_requests USING btree (user_id, tenant_id);


--
-- Name: idx_app_usage_events_email_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_app_usage_events_email_time ON public.app_usage_events USING btree (tenant_id, email, occurred_at DESC);


--
-- Name: idx_app_usage_events_event_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_app_usage_events_event_key ON public.app_usage_events USING btree (tenant_id, event_key) WHERE (event_key IS NOT NULL);


--
-- Name: idx_app_usage_events_model; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_app_usage_events_model ON public.app_usage_events USING btree (tenant_id, proc_def_id, model_id, occurred_at DESC);


--
-- Name: idx_app_usage_events_session; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_app_usage_events_session ON public.app_usage_events USING btree (tenant_id, session_id);


--
-- Name: idx_app_usage_events_tenant_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_app_usage_events_tenant_time ON public.app_usage_events USING btree (tenant_id, occurred_at DESC);


--
-- Name: idx_app_usage_events_type_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_app_usage_events_type_time ON public.app_usage_events USING btree (tenant_id, event_type, occurred_at DESC);


--
-- Name: idx_app_usage_events_user_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_app_usage_events_user_time ON public.app_usage_events USING btree (tenant_id, user_id, occurred_at DESC);


--
-- Name: idx_approval_state_feedback_end; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_approval_state_feedback_end ON public.proc_def_approval_state USING btree (public_feedback_ends_at) WHERE (state = 'public_feedback'::text);


--
-- Name: idx_approval_state_field_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_approval_state_field_status ON public.proc_def_approval_state USING btree (field_status);


--
-- Name: idx_approval_state_hq_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_approval_state_hq_status ON public.proc_def_approval_state USING btree (hq_status);


--
-- Name: idx_approval_state_major_version; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_approval_state_major_version ON public.proc_def_approval_state USING btree (proc_def_id, major_version);


--
-- Name: idx_audit_policy_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_policy_created ON public.audit_policy USING btree (created_at DESC);


--
-- Name: idx_audit_policy_deleted_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_policy_deleted_at ON public.audit_policy USING btree (deleted_at) WHERE (deleted_at IS NOT NULL);


--
-- Name: idx_audit_policy_domains; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_policy_domains ON public.audit_policy USING gin (domains);


--
-- Name: idx_audit_policy_kind; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_policy_kind ON public.audit_policy USING btree (kind);


--
-- Name: idx_audit_policy_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_policy_tenant ON public.audit_policy USING btree (tenant_id);


--
-- Name: idx_bpmn_element_map_def_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_bpmn_element_map_def_id ON public.bpmn_element_map USING btree (proc_def_id, tenant_id);


--
-- Name: idx_bpmn_element_map_element_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_bpmn_element_map_element_id ON public.bpmn_element_map USING btree (element_id);


--
-- Name: idx_departments_parent; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_departments_parent ON public.departments USING btree (parent_id);


--
-- Name: idx_departments_path; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_departments_path ON public.departments USING btree (path);


--
-- Name: idx_departments_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_departments_tenant ON public.departments USING btree (tenant_id);


--
-- Name: idx_external_api_health_last_check_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_external_api_health_last_check_time ON public.external_api_health USING btree (last_check_time DESC);


--
-- Name: idx_external_api_health_tenant_target; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_external_api_health_tenant_target ON public.external_api_health USING btree (tenant_id, integration_target_name);


--
-- Name: idx_fte_capacity_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_fte_capacity_tenant ON public.fte_capacity USING btree (tenant_id);


--
-- Name: idx_fte_snapshot_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_fte_snapshot_date ON public.fte_snapshot USING btree (tenant_id, proc_def_id, snapshot_date);


--
-- Name: idx_governance_notification_outbox_pending; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_governance_notification_outbox_pending ON public.governance_notification_outbox USING btree (tenant_id, status, available_at, created_at);


--
-- Name: idx_kpi_targets_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_kpi_targets_tenant ON public.kpi_targets USING btree (tenant_id);


--
-- Name: idx_lane_role_group_members_group; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_lane_role_group_members_group ON public.lane_role_group_members USING btree (role_group_id);


--
-- Name: idx_lane_role_group_members_org; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_lane_role_group_members_org ON public.lane_role_group_members USING btree (tenant_id, org_id);


--
-- Name: idx_lane_role_group_members_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_lane_role_group_members_tenant ON public.lane_role_group_members USING btree (tenant_id);


--
-- Name: idx_lane_role_groups_parent; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_lane_role_groups_parent ON public.lane_role_groups USING btree (parent_id);


--
-- Name: idx_lane_role_groups_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_lane_role_groups_tenant ON public.lane_role_groups USING btree (tenant_id);


--
-- Name: idx_menu_role_overrides_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_menu_role_overrides_tenant ON public.menu_role_overrides USING btree (tenant_id);


--
-- Name: idx_org_chart_group_teams_group; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_org_chart_group_teams_group ON public.org_chart_group_teams USING btree (group_id);


--
-- Name: idx_org_chart_group_teams_team; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_org_chart_group_teams_team ON public.org_chart_group_teams USING btree (team_id);


--
-- Name: idx_org_chart_groups_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_org_chart_groups_tenant ON public.org_chart_groups USING btree (tenant_id);


--
-- Name: idx_proc_def_approval_history_def; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_proc_def_approval_history_def ON public.proc_def_approval_history USING btree (proc_def_id);


--
-- Name: idx_proc_def_approval_history_review; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_proc_def_approval_history_review ON public.proc_def_approval_history USING btree (review_id);


--
-- Name: idx_proc_def_approval_history_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_proc_def_approval_history_tenant ON public.proc_def_approval_history USING btree (tenant_id);


--
-- Name: idx_proc_def_approval_state_def; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_proc_def_approval_state_def ON public.proc_def_approval_state USING btree (proc_def_id);


--
-- Name: idx_proc_def_approval_state_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_proc_def_approval_state_status ON public.proc_def_approval_state USING btree (state);


--
-- Name: idx_proc_def_approval_state_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_proc_def_approval_state_tenant ON public.proc_def_approval_state USING btree (tenant_id);


--
-- Name: idx_proc_def_comments_def_element; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_proc_def_comments_def_element ON public.proc_def_comments USING btree (proc_def_id, element_id);


--
-- Name: idx_proc_def_comments_parent; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_proc_def_comments_parent ON public.proc_def_comments USING btree (parent_comment_id);


--
-- Name: idx_proc_def_comments_round; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_proc_def_comments_round ON public.proc_def_comments USING btree (proc_def_id, submission_round);


--
-- Name: idx_proc_def_comments_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_proc_def_comments_tenant ON public.proc_def_comments USING btree (tenant_id);


--
-- Name: idx_proc_def_copilot_log_def_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_proc_def_copilot_log_def_user ON public.proc_def_copilot_log USING btree (proc_def_id, created_by);


--
-- Name: idx_proc_def_copilot_log_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_proc_def_copilot_log_tenant ON public.proc_def_copilot_log USING btree (tenant_id);


--
-- Name: idx_proc_def_snapshots_proc; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_proc_def_snapshots_proc ON public.proc_def_snapshots USING btree (proc_def_id);


--
-- Name: idx_proc_def_snapshots_review; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_proc_def_snapshots_review ON public.proc_def_snapshots USING btree (review_id);


--
-- Name: idx_proc_def_snapshots_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_proc_def_snapshots_tenant ON public.proc_def_snapshots USING btree (tenant_id);


--
-- Name: idx_strategy_initiatives_objective; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_strategy_initiatives_objective ON public.strategy_initiatives USING btree (objective_id);


--
-- Name: idx_strategy_initiatives_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_strategy_initiatives_tenant ON public.strategy_initiatives USING btree (tenant_id);


--
-- Name: idx_strategy_kpi_measurements_kpi; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_strategy_kpi_measurements_kpi ON public.strategy_kpi_measurements USING btree (kpi_id, measured_at);


--
-- Name: idx_strategy_kpis_objective; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_strategy_kpis_objective ON public.strategy_kpis USING btree (objective_id);


--
-- Name: idx_strategy_kpis_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_strategy_kpis_tenant ON public.strategy_kpis USING btree (tenant_id);


--
-- Name: idx_strategy_objectives_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_strategy_objectives_tenant ON public.strategy_objectives USING btree (tenant_id);


--
-- Name: idx_strategy_survey_requests_kpi; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_strategy_survey_requests_kpi ON public.strategy_survey_requests USING btree (kpi_id);


--
-- Name: idx_strategy_survey_requests_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_strategy_survey_requests_tenant ON public.strategy_survey_requests USING btree (tenant_id);


--
-- Name: idx_suppliers_tenant_deleted_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_suppliers_tenant_deleted_at ON public.suppliers USING btree (tenant_id, deleted_at);


--
-- Name: idx_systems_tenant_deleted_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_systems_tenant_deleted_at ON public.systems USING btree (tenant_id, deleted_at);


--
-- Name: idx_tb_bpmn_lane_model; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tb_bpmn_lane_model ON public.tb_bpmn_lane USING btree (model_id);


--
-- Name: idx_tb_bpmn_lane_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tb_bpmn_lane_type ON public.tb_bpmn_lane USING btree (element_type);


--
-- Name: idx_tb_bpmn_link_model; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tb_bpmn_link_model ON public.tb_bpmn_link USING btree (model_id);


--
-- Name: idx_tb_bpmn_link_source; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tb_bpmn_link_source ON public.tb_bpmn_link USING btree (source_node_id);


--
-- Name: idx_tb_bpmn_link_target; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tb_bpmn_link_target ON public.tb_bpmn_link USING btree (target_node_id);


--
-- Name: idx_tb_bpmn_model_domain; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tb_bpmn_model_domain ON public.tb_bpmn_model USING btree (domain_id);


--
-- Name: idx_tb_bpmn_model_parent; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tb_bpmn_model_parent ON public.tb_bpmn_model USING btree (parent_proc_def_id);


--
-- Name: idx_tb_bpmn_model_proc_def; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tb_bpmn_model_proc_def ON public.tb_bpmn_model USING btree (proc_def_id);


--
-- Name: idx_tb_bpmn_model_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tb_bpmn_model_status ON public.tb_bpmn_model USING btree (status);


--
-- Name: idx_tb_bpmn_model_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tb_bpmn_model_tenant ON public.tb_bpmn_model USING btree (tenant_id);


--
-- Name: idx_tb_bpmn_node_lane; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tb_bpmn_node_lane ON public.tb_bpmn_node USING btree (lane_id);


--
-- Name: idx_tb_bpmn_node_model; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tb_bpmn_node_model ON public.tb_bpmn_node USING btree (model_id);


--
-- Name: idx_tb_bpmn_node_task_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tb_bpmn_node_task_type ON public.tb_bpmn_node USING btree (task_type);


--
-- Name: idx_tb_bpmn_node_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tb_bpmn_node_type ON public.tb_bpmn_node USING btree (element_type);


--
-- Name: idx_tb_bpmn_version_model; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tb_bpmn_version_model ON public.tb_bpmn_version USING btree (model_id);


--
-- Name: idx_tep_activity; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tep_activity ON public.task_execution_properties USING btree (activity_id);


--
-- Name: idx_tep_execution_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tep_execution_status ON public.task_execution_properties USING btree (execution_status);


--
-- Name: idx_tep_proc_inst; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tep_proc_inst ON public.task_execution_properties USING btree (proc_inst_id);


--
-- Name: idx_tep_started_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tep_started_at ON public.task_execution_properties USING btree (started_at DESC);


--
-- Name: idx_tep_tenant_proc_def; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tep_tenant_proc_def ON public.task_execution_properties USING btree (tenant_id, proc_def_id);


--
-- Name: idx_terminology_tenant_category; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_terminology_tenant_category ON public.standard_terminology USING btree (tenant_id, category);


--
-- Name: idx_terminology_usage; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_terminology_usage ON public.standard_terminology USING btree (tenant_id, category, usage_count DESC);


--
-- Name: pro_actions_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX pro_actions_user ON public.pro_actions USING btree (user_id, status, created_at DESC);


--
-- Name: pro_messages_thread; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX pro_messages_thread ON public.pro_messages USING btree (thread_id, created_at);


--
-- Name: pro_mission_runs_schedule; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX pro_mission_runs_schedule ON public.pro_mission_runs USING btree (schedule_id, started_at DESC);


--
-- Name: pro_threads_ref; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX pro_threads_ref ON public.pro_threads USING btree (user_id, ref);


--
-- Name: pro_threads_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX pro_threads_user ON public.pro_threads USING btree (user_id, kind, updated_at DESC);


--
-- Name: pro_vault_audit_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX pro_vault_audit_user ON public.pro_vault_audit USING btree (user_id, created_at DESC);


--
-- Name: pro_vault_items_identity; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX pro_vault_items_identity ON public.pro_vault_items USING btree (user_id, kind, site, fingerprint);


--
-- Name: pro_vault_items_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX pro_vault_items_user ON public.pro_vault_items USING btree (user_id, kind);


--
-- Name: skill_contributions_skill_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX skill_contributions_skill_idx ON public.skill_contributions USING btree (tenant_id, skill_name);


--
-- Name: suppliers_tenant_business_number_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX suppliers_tenant_business_number_idx ON public.suppliers USING btree (tenant_id, business_number);


--
-- Name: suppliers_tenant_normalized_name_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX suppliers_tenant_normalized_name_idx ON public.suppliers USING btree (tenant_id, normalized_name);


--
-- Name: systems_tenant_deleted_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX systems_tenant_deleted_at_idx ON public.systems USING btree (tenant_id, deleted_at);


--
-- Name: systems_tenant_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX systems_tenant_id_idx ON public.systems USING btree (tenant_id);


--
-- Name: systems_tenant_name_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX systems_tenant_name_idx ON public.systems USING btree (tenant_id, name);


--
-- Name: uidx_lane_role_group_members_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uidx_lane_role_group_members_unique ON public.lane_role_group_members USING btree (role_group_id, org_id) WHERE (deleted_at IS NULL);


--
-- Name: uidx_lane_role_groups_child_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uidx_lane_role_groups_child_name ON public.lane_role_groups USING btree (tenant_id, parent_id, name) WHERE ((parent_id IS NOT NULL) AND (deleted_at IS NULL));


--
-- Name: uidx_lane_role_groups_root_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uidx_lane_role_groups_root_name ON public.lane_role_groups USING btree (tenant_id, name) WHERE ((parent_id IS NULL) AND (deleted_at IS NULL));


--
-- Name: uq_governance_notification_outbox_dedupe; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_governance_notification_outbox_dedupe ON public.governance_notification_outbox USING btree (tenant_id, dedupe_key) WHERE (dedupe_key IS NOT NULL);


--
-- Name: activity_config activity_config_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER activity_config_updated_at BEFORE UPDATE ON public.activity_config FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: audit_policy audit_policy_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_policy_updated_at BEFORE UPDATE ON public.audit_policy FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: fte_capacity fte_capacity_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER fte_capacity_updated_at BEFORE UPDATE ON public.fte_capacity FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: proc_def_approval_state proc_def_approval_state_updated_at_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER proc_def_approval_state_updated_at_trigger BEFORE UPDATE ON public.proc_def_approval_state FOR EACH ROW EXECUTE FUNCTION public.update_proc_def_approval_state_updated_at();


--
-- Name: proc_def_comments proc_def_comments_updated_at_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER proc_def_comments_updated_at_trigger BEFORE UPDATE ON public.proc_def_comments FOR EACH ROW EXECUTE FUNCTION public.update_proc_def_comments_updated_at();


--
-- Name: lane_role_groups trg_lane_role_groups_depth_guard; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_lane_role_groups_depth_guard BEFORE INSERT OR UPDATE OF parent_id ON public.lane_role_groups FOR EACH ROW EXECUTE FUNCTION public.lane_role_groups_depth_guard();


--
-- Name: proc_def_approval_history trg_proc_def_approval_history_governance_outbox; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_proc_def_approval_history_governance_outbox AFTER INSERT ON public.proc_def_approval_history FOR EACH ROW EXECUTE FUNCTION public.enqueue_proc_def_approval_history_governance_notification();


--
-- Name: proc_def_comments trg_proc_def_comments_governance_outbox; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_proc_def_comments_governance_outbox AFTER INSERT ON public.proc_def_comments FOR EACH ROW EXECUTE FUNCTION public.enqueue_proc_def_comment_governance_notification();


--
-- Name: audit_policy trg_set_deleted_by_audit_policy; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_set_deleted_by_audit_policy BEFORE UPDATE ON public.audit_policy FOR EACH ROW EXECUTE FUNCTION public.set_deleted_by_from_jwt();


--
-- Name: tb_bpmn_model trg_set_deleted_by_tb_bpmn_model; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_set_deleted_by_tb_bpmn_model BEFORE UPDATE ON public.tb_bpmn_model FOR EACH ROW EXECUTE FUNCTION public.set_deleted_by_from_jwt();


--
-- Name: tb_bpmn_model trigger_tb_bpmn_model_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_tb_bpmn_model_updated_at BEFORE UPDATE ON public.tb_bpmn_model FOR EACH ROW EXECUTE FUNCTION public.update_tb_bpmn_model_updated_at();


--
-- Name: bpmn_element_map bpmn_element_map_proc_def_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bpmn_element_map
    ADD CONSTRAINT bpmn_element_map_proc_def_fkey FOREIGN KEY (proc_def_uuid) REFERENCES public.proc_def(uuid) ON DELETE CASCADE;


--
-- Name: departments departments_parent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departments
    ADD CONSTRAINT departments_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES public.departments(id) ON DELETE SET NULL;


--
-- Name: departments departments_tenant_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departments
    ADD CONSTRAINT departments_tenant_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: lane_role_group_members lane_role_group_members_group_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lane_role_group_members
    ADD CONSTRAINT lane_role_group_members_group_fk FOREIGN KEY (role_group_id) REFERENCES public.lane_role_groups(id) ON DELETE CASCADE;


--
-- Name: lane_role_groups lane_role_groups_parent_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lane_role_groups
    ADD CONSTRAINT lane_role_groups_parent_fk FOREIGN KEY (parent_id) REFERENCES public.lane_role_groups(id) ON DELETE CASCADE;


--
-- Name: org_chart_group_teams org_chart_group_teams_group_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.org_chart_group_teams
    ADD CONSTRAINT org_chart_group_teams_group_id_fkey FOREIGN KEY (group_id) REFERENCES public.org_chart_groups(id) ON DELETE CASCADE;


--
-- Name: pro_messages pro_messages_thread_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pro_messages
    ADD CONSTRAINT pro_messages_thread_id_fkey FOREIGN KEY (thread_id) REFERENCES public.pro_threads(id) ON DELETE CASCADE;


--
-- Name: pro_mission_runs pro_mission_runs_schedule_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pro_mission_runs
    ADD CONSTRAINT pro_mission_runs_schedule_id_fkey FOREIGN KEY (schedule_id) REFERENCES public.pro_schedules(id) ON DELETE CASCADE;


--
-- Name: proc_def_approval_history proc_def_approval_history_review_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.proc_def_approval_history
    ADD CONSTRAINT proc_def_approval_history_review_id_fkey FOREIGN KEY (review_id) REFERENCES public.proc_def_approval_state(id);


--
-- Name: proc_def_comments proc_def_comments_parent_comment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.proc_def_comments
    ADD CONSTRAINT proc_def_comments_parent_comment_id_fkey FOREIGN KEY (parent_comment_id) REFERENCES public.proc_def_comments(id) ON DELETE CASCADE;


--
-- Name: proc_def_snapshots proc_def_snapshots_review_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.proc_def_snapshots
    ADD CONSTRAINT proc_def_snapshots_review_id_fkey FOREIGN KEY (review_id) REFERENCES public.proc_def_approval_state(id) ON DELETE CASCADE;


--
-- Name: strategy_initiatives strategy_initiatives_objective_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.strategy_initiatives
    ADD CONSTRAINT strategy_initiatives_objective_id_fkey FOREIGN KEY (objective_id) REFERENCES public.strategy_objectives(id) ON DELETE CASCADE;


--
-- Name: strategy_kpis strategy_kpis_objective_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.strategy_kpis
    ADD CONSTRAINT strategy_kpis_objective_id_fkey FOREIGN KEY (objective_id) REFERENCES public.strategy_objectives(id) ON DELETE CASCADE;


--
-- Name: task_execution_properties task_execution_properties_tenant_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_execution_properties
    ADD CONSTRAINT task_execution_properties_tenant_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: tb_bpmn_lane tb_bpmn_lane_model_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tb_bpmn_lane
    ADD CONSTRAINT tb_bpmn_lane_model_id_fkey FOREIGN KEY (model_id) REFERENCES public.tb_bpmn_model(id) ON DELETE CASCADE;


--
-- Name: tb_bpmn_lane tb_bpmn_lane_parent_lane_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tb_bpmn_lane
    ADD CONSTRAINT tb_bpmn_lane_parent_lane_id_fkey FOREIGN KEY (parent_lane_id) REFERENCES public.tb_bpmn_lane(id) ON DELETE SET NULL;


--
-- Name: tb_bpmn_link tb_bpmn_link_model_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tb_bpmn_link
    ADD CONSTRAINT tb_bpmn_link_model_id_fkey FOREIGN KEY (model_id) REFERENCES public.tb_bpmn_model(id) ON DELETE CASCADE;


--
-- Name: tb_bpmn_link tb_bpmn_link_source_node_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tb_bpmn_link
    ADD CONSTRAINT tb_bpmn_link_source_node_id_fkey FOREIGN KEY (source_node_id) REFERENCES public.tb_bpmn_node(id) ON DELETE SET NULL;


--
-- Name: tb_bpmn_link tb_bpmn_link_target_node_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tb_bpmn_link
    ADD CONSTRAINT tb_bpmn_link_target_node_id_fkey FOREIGN KEY (target_node_id) REFERENCES public.tb_bpmn_node(id) ON DELETE SET NULL;


--
-- Name: tb_bpmn_model_lock tb_bpmn_model_lock_model_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tb_bpmn_model_lock
    ADD CONSTRAINT tb_bpmn_model_lock_model_id_fkey FOREIGN KEY (model_id) REFERENCES public.tb_bpmn_model(id) ON DELETE CASCADE;


--
-- Name: tb_bpmn_node tb_bpmn_node_lane_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tb_bpmn_node
    ADD CONSTRAINT tb_bpmn_node_lane_id_fkey FOREIGN KEY (lane_id) REFERENCES public.tb_bpmn_lane(id) ON DELETE SET NULL;


--
-- Name: tb_bpmn_node tb_bpmn_node_model_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tb_bpmn_node
    ADD CONSTRAINT tb_bpmn_node_model_id_fkey FOREIGN KEY (model_id) REFERENCES public.tb_bpmn_model(id) ON DELETE CASCADE;


--
-- Name: tb_bpmn_version tb_bpmn_version_model_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tb_bpmn_version
    ADD CONSTRAINT tb_bpmn_version_model_id_fkey FOREIGN KEY (model_id) REFERENCES public.tb_bpmn_model(id) ON DELETE CASCADE;


--
-- Name: workitem_app_binding workitem_app_binding_tenant_id_app_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workitem_app_binding
    ADD CONSTRAINT workitem_app_binding_tenant_id_app_id_fkey FOREIGN KEY (tenant_id, app_id) REFERENCES public.workitem_app(tenant_id, app_id) ON DELETE CASCADE;


--
-- Name: activity_config; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.activity_config ENABLE ROW LEVEL SECURITY;

--
-- Name: activity_config activity_config_public_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY activity_config_public_read ON public.activity_config FOR SELECT USING (true);


--
-- Name: activity_config activity_config_public_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY activity_config_public_write ON public.activity_config USING (true);


--
-- Name: activity_config activity_config_tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY activity_config_tenant_isolation ON public.activity_config USING (((tenant_id)::text = current_setting('app.tenant_id'::text, true)));


--
-- Name: admin_audit_log; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.admin_audit_log ENABLE ROW LEVEL SECURITY;

--
-- Name: admin_audit_log admin_audit_log_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY admin_audit_log_insert ON public.admin_audit_log FOR INSERT TO authenticated, anon WITH CHECK (true);


--
-- Name: admin_audit_log admin_audit_log_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY admin_audit_log_select ON public.admin_audit_log FOR SELECT TO authenticated, anon USING (true);


--
-- Name: app_usage_events; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.app_usage_events ENABLE ROW LEVEL SECURITY;

--
-- Name: app_usage_events app_usage_events_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY app_usage_events_all ON public.app_usage_events USING (true) WITH CHECK (true);


--
-- Name: audit_policy; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.audit_policy ENABLE ROW LEVEL SECURITY;

--
-- Name: audit_policy audit_policy_authenticated_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY audit_policy_authenticated_read ON public.audit_policy FOR SELECT TO authenticated USING (true);


--
-- Name: audit_policy audit_policy_authenticated_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY audit_policy_authenticated_write ON public.audit_policy TO authenticated USING (true) WITH CHECK (true);


--
-- Name: audit_policy audit_policy_tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY audit_policy_tenant_isolation ON public.audit_policy TO authenticated USING ((tenant_id = current_setting('app.tenant_id'::text, true)));


--
-- Name: bpmn_element_map; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.bpmn_element_map ENABLE ROW LEVEL SECURITY;

--
-- Name: bpmn_element_map bpmn_element_map_delete_editor; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY bpmn_element_map_delete_editor ON public.bpmn_element_map FOR DELETE USING (public.has_role_at_least('editor'::text));


--
-- Name: bpmn_element_map bpmn_element_map_insert_editor; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY bpmn_element_map_insert_editor ON public.bpmn_element_map FOR INSERT WITH CHECK (public.has_role_at_least('editor'::text));


--
-- Name: bpmn_element_map bpmn_element_map_select_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY bpmn_element_map_select_all ON public.bpmn_element_map FOR SELECT USING (true);


--
-- Name: bpmn_element_map bpmn_element_map_update_editor; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY bpmn_element_map_update_editor ON public.bpmn_element_map FOR UPDATE USING (public.has_role_at_least('editor'::text));


--
-- Name: crm_customer_table crm_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY crm_all ON public.crm_customer_table TO authenticated, anon USING (true) WITH CHECK (true);


--
-- Name: crm_customer_table; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.crm_customer_table ENABLE ROW LEVEL SECURITY;

--
-- Name: departments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.departments ENABLE ROW LEVEL SECURITY;

--
-- Name: departments departments_tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY departments_tenant_isolation ON public.departments USING ((tenant_id = public.tenant_id()));


--
-- Name: external_api_health; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.external_api_health ENABLE ROW LEVEL SECURITY;

--
-- Name: external_api_health external_api_health_public_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY external_api_health_public_read ON public.external_api_health FOR SELECT USING (true);


--
-- Name: external_api_health external_api_health_public_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY external_api_health_public_write ON public.external_api_health USING (true) WITH CHECK (true);


--
-- Name: fte_capacity; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.fte_capacity ENABLE ROW LEVEL SECURITY;

--
-- Name: fte_capacity fte_capacity_public_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY fte_capacity_public_read ON public.fte_capacity FOR SELECT USING (true);


--
-- Name: fte_capacity fte_capacity_public_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY fte_capacity_public_write ON public.fte_capacity USING (true);


--
-- Name: fte_capacity fte_capacity_tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY fte_capacity_tenant_isolation ON public.fte_capacity USING (((tenant_id)::text = current_setting('app.tenant_id'::text, true)));


--
-- Name: fte_snapshot; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.fte_snapshot ENABLE ROW LEVEL SECURITY;

--
-- Name: fte_snapshot fte_snapshot_public_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY fte_snapshot_public_read ON public.fte_snapshot FOR SELECT USING (true);


--
-- Name: fte_snapshot fte_snapshot_tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY fte_snapshot_tenant_isolation ON public.fte_snapshot USING (((tenant_id)::text = current_setting('app.tenant_id'::text, true)));


--
-- Name: kpi_targets; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.kpi_targets ENABLE ROW LEVEL SECURITY;

--
-- Name: kpi_targets kpi_targets_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY kpi_targets_all ON public.kpi_targets USING (true) WITH CHECK (true);


--
-- Name: lane_role_group_members; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.lane_role_group_members ENABLE ROW LEVEL SECURITY;

--
-- Name: lane_role_group_members lane_role_group_members_admin_owner_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY lane_role_group_members_admin_owner_all ON public.lane_role_group_members USING ((EXISTS ( SELECT 1
   FROM public.users u
  WHERE ((u.id = auth.uid()) AND ((u.is_admin = true) OR (u.role = ANY (ARRAY['admin'::text, 'owner'::text]))))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM public.users u
  WHERE ((u.id = auth.uid()) AND ((u.is_admin = true) OR (u.role = ANY (ARRAY['admin'::text, 'owner'::text])))))));


--
-- Name: lane_role_group_members lane_role_group_members_authenticated_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY lane_role_group_members_authenticated_read ON public.lane_role_group_members FOR SELECT USING ((auth.role() = 'authenticated'::text));


--
-- Name: lane_role_groups; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.lane_role_groups ENABLE ROW LEVEL SECURITY;

--
-- Name: lane_role_groups lane_role_groups_admin_owner_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY lane_role_groups_admin_owner_all ON public.lane_role_groups USING ((EXISTS ( SELECT 1
   FROM public.users u
  WHERE ((u.id = auth.uid()) AND ((u.is_admin = true) OR (u.role = ANY (ARRAY['admin'::text, 'owner'::text]))))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM public.users u
  WHERE ((u.id = auth.uid()) AND ((u.is_admin = true) OR (u.role = ANY (ARRAY['admin'::text, 'owner'::text])))))));


--
-- Name: lane_role_groups lane_role_groups_authenticated_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY lane_role_groups_authenticated_read ON public.lane_role_groups FOR SELECT USING ((auth.role() = 'authenticated'::text));


--
-- Name: logistics_delivery_demo; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.logistics_delivery_demo ENABLE ROW LEVEL SECURITY;

--
-- Name: logistics_delivery_demo logistics_delivery_demo_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY logistics_delivery_demo_read ON public.logistics_delivery_demo FOR SELECT TO authenticated, anon USING (true);


--
-- Name: menu_role_overrides; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.menu_role_overrides ENABLE ROW LEVEL SECURITY;

--
-- Name: menu_role_overrides menu_role_overrides_admin_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY menu_role_overrides_admin_all ON public.menu_role_overrides USING ((EXISTS ( SELECT 1
   FROM public.users u
  WHERE ((u.id = auth.uid()) AND ((u.is_admin = true) OR (u.role = 'admin'::text)))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM public.users u
  WHERE ((u.id = auth.uid()) AND ((u.is_admin = true) OR (u.role = 'admin'::text))))));


--
-- Name: menu_role_overrides menu_role_overrides_authenticated_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY menu_role_overrides_authenticated_read ON public.menu_role_overrides FOR SELECT USING ((auth.role() = 'authenticated'::text));


--
-- Name: org_chart_group_teams; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.org_chart_group_teams ENABLE ROW LEVEL SECURITY;

--
-- Name: org_chart_group_teams org_chart_group_teams_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY org_chart_group_teams_delete ON public.org_chart_group_teams FOR DELETE USING ((EXISTS ( SELECT 1
   FROM public.org_chart_groups g
  WHERE ((g.id = org_chart_group_teams.group_id) AND ((g.tenant_id)::text = public.tenant_id())))));


--
-- Name: org_chart_group_teams org_chart_group_teams_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY org_chart_group_teams_insert ON public.org_chart_group_teams FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM public.org_chart_groups g
  WHERE ((g.id = org_chart_group_teams.group_id) AND ((g.tenant_id)::text = public.tenant_id())))));


--
-- Name: org_chart_group_teams org_chart_group_teams_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY org_chart_group_teams_select ON public.org_chart_group_teams FOR SELECT USING ((EXISTS ( SELECT 1
   FROM public.org_chart_groups g
  WHERE ((g.id = org_chart_group_teams.group_id) AND ((g.tenant_id)::text = public.tenant_id())))));


--
-- Name: org_chart_group_teams org_chart_group_teams_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY org_chart_group_teams_update ON public.org_chart_group_teams FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM public.org_chart_groups g
  WHERE ((g.id = org_chart_group_teams.group_id) AND ((g.tenant_id)::text = public.tenant_id())))));


--
-- Name: org_chart_groups; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.org_chart_groups ENABLE ROW LEVEL SECURITY;

--
-- Name: org_chart_groups org_chart_groups_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY org_chart_groups_delete ON public.org_chart_groups FOR DELETE USING (((tenant_id)::text = public.tenant_id()));


--
-- Name: org_chart_groups org_chart_groups_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY org_chart_groups_insert ON public.org_chart_groups FOR INSERT WITH CHECK (((tenant_id)::text = public.tenant_id()));


--
-- Name: org_chart_groups org_chart_groups_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY org_chart_groups_select ON public.org_chart_groups FOR SELECT USING (((tenant_id)::text = public.tenant_id()));


--
-- Name: org_chart_groups org_chart_groups_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY org_chart_groups_update ON public.org_chart_groups FOR UPDATE USING (((tenant_id)::text = public.tenant_id()));


--
-- Name: proc_def_approval_history; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.proc_def_approval_history ENABLE ROW LEVEL SECURITY;

--
-- Name: proc_def_approval_history proc_def_approval_history_insert_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY proc_def_approval_history_insert_policy ON public.proc_def_approval_history FOR INSERT WITH CHECK (true);


--
-- Name: proc_def_approval_history proc_def_approval_history_insert_role_aligned; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY proc_def_approval_history_insert_role_aligned ON public.proc_def_approval_history FOR INSERT WITH CHECK (
CASE
    WHEN (action = ANY (ARRAY['comment'::text, 'request_reopen'::text])) THEN public.has_role_at_least('reviewer'::text)
    WHEN (action = ANY (ARRAY['publish'::text, 'approve_reopen'::text, 'reject_reopen'::text])) THEN public.has_role_at_least('owner'::text)
    ELSE public.has_role_at_least('editor'::text)
END);


--
-- Name: proc_def_approval_history proc_def_approval_history_select_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY proc_def_approval_history_select_all ON public.proc_def_approval_history FOR SELECT USING (true);


--
-- Name: proc_def_approval_history proc_def_approval_history_select_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY proc_def_approval_history_select_policy ON public.proc_def_approval_history FOR SELECT USING (true);


--
-- Name: proc_def_approval_state; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.proc_def_approval_state ENABLE ROW LEVEL SECURITY;

--
-- Name: proc_def_approval_state proc_def_approval_state_insert_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY proc_def_approval_state_insert_policy ON public.proc_def_approval_state FOR INSERT WITH CHECK (true);


--
-- Name: proc_def_approval_state proc_def_approval_state_insert_role_aligned; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY proc_def_approval_state_insert_role_aligned ON public.proc_def_approval_state FOR INSERT WITH CHECK (
CASE
    WHEN (state = ANY (ARRAY['published'::text, 'archived'::text])) THEN public.has_role_at_least('owner'::text)
    WHEN (state = 'reopen_requested'::text) THEN public.has_role_at_least('reviewer'::text)
    ELSE public.has_role_at_least('editor'::text)
END);


--
-- Name: proc_def_approval_state proc_def_approval_state_select_editor; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY proc_def_approval_state_select_editor ON public.proc_def_approval_state FOR SELECT USING (public.has_role_at_least('editor'::text));


--
-- Name: proc_def_approval_state proc_def_approval_state_select_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY proc_def_approval_state_select_policy ON public.proc_def_approval_state FOR SELECT USING (true);


--
-- Name: proc_def_approval_state proc_def_approval_state_update_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY proc_def_approval_state_update_policy ON public.proc_def_approval_state FOR UPDATE USING (true);


--
-- Name: proc_def_approval_state proc_def_approval_state_update_role_aligned; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY proc_def_approval_state_update_role_aligned ON public.proc_def_approval_state FOR UPDATE USING ((public.has_role_at_least('editor'::text) OR (public.has_role_at_least('reviewer'::text) AND (state = 'published'::text)) OR (public.has_role_at_least('owner'::text) AND (state = 'reopen_requested'::text)))) WITH CHECK (
CASE
    WHEN (state = ANY (ARRAY['published'::text, 'archived'::text])) THEN public.has_role_at_least('owner'::text)
    WHEN (state = 'reopen_requested'::text) THEN public.has_role_at_least('reviewer'::text)
    ELSE public.has_role_at_least('editor'::text)
END);


--
-- Name: proc_def_comments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.proc_def_comments ENABLE ROW LEVEL SECURITY;

--
-- Name: proc_def_comments proc_def_comments_delete_own_or_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY proc_def_comments_delete_own_or_admin ON public.proc_def_comments FOR DELETE USING (public.has_role_at_least('reviewer'::text));


--
-- Name: proc_def_comments proc_def_comments_delete_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY proc_def_comments_delete_policy ON public.proc_def_comments FOR DELETE USING (true);


--
-- Name: proc_def_comments proc_def_comments_insert_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY proc_def_comments_insert_policy ON public.proc_def_comments FOR INSERT WITH CHECK (true);


--
-- Name: proc_def_comments proc_def_comments_insert_reviewer; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY proc_def_comments_insert_reviewer ON public.proc_def_comments FOR INSERT WITH CHECK (public.has_role_at_least('reviewer'::text));


--
-- Name: proc_def_comments proc_def_comments_select_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY proc_def_comments_select_all ON public.proc_def_comments FOR SELECT USING (true);


--
-- Name: proc_def_comments proc_def_comments_select_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY proc_def_comments_select_policy ON public.proc_def_comments FOR SELECT USING (true);


--
-- Name: proc_def_comments proc_def_comments_update_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY proc_def_comments_update_own ON public.proc_def_comments FOR UPDATE USING (true);


--
-- Name: proc_def_comments proc_def_comments_update_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY proc_def_comments_update_policy ON public.proc_def_comments FOR UPDATE USING (true);


--
-- Name: proc_def_copilot_log; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.proc_def_copilot_log ENABLE ROW LEVEL SECURITY;

--
-- Name: proc_def_copilot_log proc_def_copilot_log_delete_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY proc_def_copilot_log_delete_policy ON public.proc_def_copilot_log FOR DELETE USING (true);


--
-- Name: proc_def_copilot_log proc_def_copilot_log_insert_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY proc_def_copilot_log_insert_policy ON public.proc_def_copilot_log FOR INSERT WITH CHECK (true);


--
-- Name: proc_def_copilot_log proc_def_copilot_log_select_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY proc_def_copilot_log_select_policy ON public.proc_def_copilot_log FOR SELECT USING (true);


--
-- Name: proc_def_snapshots; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.proc_def_snapshots ENABLE ROW LEVEL SECURITY;

--
-- Name: proc_def_snapshots proc_def_snapshots_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY proc_def_snapshots_delete ON public.proc_def_snapshots FOR DELETE USING (true);


--
-- Name: proc_def_snapshots proc_def_snapshots_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY proc_def_snapshots_insert ON public.proc_def_snapshots FOR INSERT WITH CHECK (true);


--
-- Name: proc_def_snapshots proc_def_snapshots_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY proc_def_snapshots_select ON public.proc_def_snapshots FOR SELECT USING (true);


--
-- Name: product_table; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.product_table ENABLE ROW LEVEL SECURITY;

--
-- Name: product_table product_table_modify; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY product_table_modify ON public.product_table TO authenticated, anon USING (true) WITH CHECK (true);


--
-- Name: product_table product_table_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY product_table_select ON public.product_table FOR SELECT TO authenticated, anon USING (true);


--
-- Name: standard_terminology; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.standard_terminology ENABLE ROW LEVEL SECURITY;

--
-- Name: task_execution_properties; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.task_execution_properties ENABLE ROW LEVEL SECURITY;

--
-- Name: task_execution_properties task_execution_properties_tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY task_execution_properties_tenant_isolation ON public.task_execution_properties USING ((tenant_id = public.tenant_id()));


--
-- Name: tb_bpmn_lane; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.tb_bpmn_lane ENABLE ROW LEVEL SECURITY;

--
-- Name: tb_bpmn_lane tb_bpmn_lane_delete_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tb_bpmn_lane_delete_policy ON public.tb_bpmn_lane FOR DELETE USING (true);


--
-- Name: tb_bpmn_lane tb_bpmn_lane_insert_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tb_bpmn_lane_insert_policy ON public.tb_bpmn_lane FOR INSERT WITH CHECK (true);


--
-- Name: tb_bpmn_lane tb_bpmn_lane_select_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tb_bpmn_lane_select_policy ON public.tb_bpmn_lane FOR SELECT USING (true);


--
-- Name: tb_bpmn_lane tb_bpmn_lane_update_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tb_bpmn_lane_update_policy ON public.tb_bpmn_lane FOR UPDATE USING (true);


--
-- Name: tb_bpmn_link; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.tb_bpmn_link ENABLE ROW LEVEL SECURITY;

--
-- Name: tb_bpmn_link tb_bpmn_link_delete_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tb_bpmn_link_delete_policy ON public.tb_bpmn_link FOR DELETE USING (true);


--
-- Name: tb_bpmn_link tb_bpmn_link_insert_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tb_bpmn_link_insert_policy ON public.tb_bpmn_link FOR INSERT WITH CHECK (true);


--
-- Name: tb_bpmn_link tb_bpmn_link_select_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tb_bpmn_link_select_policy ON public.tb_bpmn_link FOR SELECT USING (true);


--
-- Name: tb_bpmn_link tb_bpmn_link_update_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tb_bpmn_link_update_policy ON public.tb_bpmn_link FOR UPDATE USING (true);


--
-- Name: tb_bpmn_model; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.tb_bpmn_model ENABLE ROW LEVEL SECURITY;

--
-- Name: tb_bpmn_model tb_bpmn_model_delete_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tb_bpmn_model_delete_policy ON public.tb_bpmn_model FOR DELETE USING (true);


--
-- Name: tb_bpmn_model tb_bpmn_model_insert_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tb_bpmn_model_insert_policy ON public.tb_bpmn_model FOR INSERT WITH CHECK (true);


--
-- Name: tb_bpmn_model_lock; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.tb_bpmn_model_lock ENABLE ROW LEVEL SECURITY;

--
-- Name: tb_bpmn_model_lock tb_bpmn_model_lock_delete_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tb_bpmn_model_lock_delete_policy ON public.tb_bpmn_model_lock FOR DELETE USING (true);


--
-- Name: tb_bpmn_model_lock tb_bpmn_model_lock_insert_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tb_bpmn_model_lock_insert_policy ON public.tb_bpmn_model_lock FOR INSERT WITH CHECK (true);


--
-- Name: tb_bpmn_model_lock tb_bpmn_model_lock_select_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tb_bpmn_model_lock_select_policy ON public.tb_bpmn_model_lock FOR SELECT USING (true);


--
-- Name: tb_bpmn_model_lock tb_bpmn_model_lock_update_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tb_bpmn_model_lock_update_policy ON public.tb_bpmn_model_lock FOR UPDATE USING (true);


--
-- Name: tb_bpmn_model tb_bpmn_model_select_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tb_bpmn_model_select_policy ON public.tb_bpmn_model FOR SELECT USING (true);


--
-- Name: tb_bpmn_model tb_bpmn_model_update_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tb_bpmn_model_update_policy ON public.tb_bpmn_model FOR UPDATE USING (true);


--
-- Name: tb_bpmn_node; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.tb_bpmn_node ENABLE ROW LEVEL SECURITY;

--
-- Name: tb_bpmn_node tb_bpmn_node_delete_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tb_bpmn_node_delete_policy ON public.tb_bpmn_node FOR DELETE USING (true);


--
-- Name: tb_bpmn_node tb_bpmn_node_insert_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tb_bpmn_node_insert_policy ON public.tb_bpmn_node FOR INSERT WITH CHECK (true);


--
-- Name: tb_bpmn_node tb_bpmn_node_select_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tb_bpmn_node_select_policy ON public.tb_bpmn_node FOR SELECT USING (true);


--
-- Name: tb_bpmn_node tb_bpmn_node_update_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tb_bpmn_node_update_policy ON public.tb_bpmn_node FOR UPDATE USING (true);


--
-- Name: tb_bpmn_version; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.tb_bpmn_version ENABLE ROW LEVEL SECURITY;

--
-- Name: tb_bpmn_version tb_bpmn_version_delete_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tb_bpmn_version_delete_policy ON public.tb_bpmn_version FOR DELETE USING (true);


--
-- Name: tb_bpmn_version tb_bpmn_version_insert_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tb_bpmn_version_insert_policy ON public.tb_bpmn_version FOR INSERT WITH CHECK (true);


--
-- Name: tb_bpmn_version tb_bpmn_version_select_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tb_bpmn_version_select_policy ON public.tb_bpmn_version FOR SELECT USING (true);


--
-- Name: tb_bpmn_version tb_bpmn_version_update_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tb_bpmn_version_update_policy ON public.tb_bpmn_version FOR UPDATE USING (true);


--
-- Name: standard_terminology tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.standard_terminology USING (((tenant_id = current_setting('app.tenant_id'::text, true)) OR (tenant_id = 'default'::text)));


--
-- Name: workitem_app; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.workitem_app ENABLE ROW LEVEL SECURITY;

--
-- Name: workitem_app_binding; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.workitem_app_binding ENABLE ROW LEVEL SECURITY;

--
-- Name: workitem_app_binding workitem_app_binding_select_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY workitem_app_binding_select_policy ON public.workitem_app_binding FOR SELECT TO authenticated USING ((tenant_id = public.tenant_id()));


--
-- Name: workitem_app_binding workitem_app_binding_write_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY workitem_app_binding_write_policy ON public.workitem_app_binding TO authenticated USING ((tenant_id = public.tenant_id())) WITH CHECK ((tenant_id = public.tenant_id()));


--
-- Name: workitem_app workitem_app_select_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY workitem_app_select_policy ON public.workitem_app FOR SELECT TO authenticated USING ((tenant_id = public.tenant_id()));


--
-- Name: workitem_app workitem_app_write_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY workitem_app_write_policy ON public.workitem_app TO authenticated USING ((tenant_id = public.tenant_id())) WITH CHECK ((tenant_id = public.tenant_id()));


--
-- Name: TABLE activity_config; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.activity_config TO anon;
GRANT ALL ON TABLE public.activity_config TO authenticated;
GRANT ALL ON TABLE public.activity_config TO service_role;


--
-- Name: TABLE admin_audit_log; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,REFERENCES,TRIGGER,TRUNCATE ON TABLE public.admin_audit_log TO anon;
GRANT SELECT,INSERT,REFERENCES,TRIGGER,TRUNCATE ON TABLE public.admin_audit_log TO authenticated;
GRANT ALL ON TABLE public.admin_audit_log TO service_role;


--
-- Name: TABLE admin_requests; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.admin_requests TO anon;
GRANT ALL ON TABLE public.admin_requests TO authenticated;
GRANT ALL ON TABLE public.admin_requests TO service_role;


--
-- Name: TABLE app_usage_events; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.app_usage_events TO anon;
GRANT ALL ON TABLE public.app_usage_events TO authenticated;
GRANT ALL ON TABLE public.app_usage_events TO service_role;


--
-- Name: TABLE audit_policy; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.audit_policy TO authenticated;
GRANT ALL ON TABLE public.audit_policy TO service_role;


--
-- Name: TABLE bpmn_element_map; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.bpmn_element_map TO anon;
GRANT ALL ON TABLE public.bpmn_element_map TO authenticated;
GRANT ALL ON TABLE public.bpmn_element_map TO service_role;


--
-- Name: TABLE checkpoint_blobs; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.checkpoint_blobs TO anon;
GRANT ALL ON TABLE public.checkpoint_blobs TO authenticated;
GRANT ALL ON TABLE public.checkpoint_blobs TO service_role;


--
-- Name: TABLE checkpoint_migrations; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.checkpoint_migrations TO anon;
GRANT ALL ON TABLE public.checkpoint_migrations TO authenticated;
GRANT ALL ON TABLE public.checkpoint_migrations TO service_role;


--
-- Name: TABLE checkpoint_writes; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.checkpoint_writes TO anon;
GRANT ALL ON TABLE public.checkpoint_writes TO authenticated;
GRANT ALL ON TABLE public.checkpoint_writes TO service_role;


--
-- Name: TABLE checkpoints; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.checkpoints TO anon;
GRANT ALL ON TABLE public.checkpoints TO authenticated;
GRANT ALL ON TABLE public.checkpoints TO service_role;


--
-- Name: TABLE context_threads; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.context_threads TO anon;
GRANT ALL ON TABLE public.context_threads TO authenticated;
GRANT ALL ON TABLE public.context_threads TO service_role;


--
-- Name: TABLE crm_customer_table; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.crm_customer_table TO postgres;
GRANT ALL ON TABLE public.crm_customer_table TO anon;
GRANT ALL ON TABLE public.crm_customer_table TO authenticated;
GRANT ALL ON TABLE public.crm_customer_table TO service_role;


--
-- Name: TABLE departments; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.departments TO anon;
GRANT ALL ON TABLE public.departments TO authenticated;
GRANT ALL ON TABLE public.departments TO service_role;


--
-- Name: TABLE external_api_health; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.external_api_health TO anon;
GRANT ALL ON TABLE public.external_api_health TO authenticated;
GRANT ALL ON TABLE public.external_api_health TO service_role;


--
-- Name: TABLE fte_capacity; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.fte_capacity TO anon;
GRANT ALL ON TABLE public.fte_capacity TO authenticated;
GRANT ALL ON TABLE public.fte_capacity TO service_role;


--
-- Name: TABLE fte_snapshot; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.fte_snapshot TO anon;
GRANT ALL ON TABLE public.fte_snapshot TO authenticated;
GRANT ALL ON TABLE public.fte_snapshot TO service_role;


--
-- Name: TABLE governance_notification_outbox; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.governance_notification_outbox TO anon;
GRANT ALL ON TABLE public.governance_notification_outbox TO authenticated;
GRANT ALL ON TABLE public.governance_notification_outbox TO service_role;


--
-- Name: TABLE inventory; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.inventory TO anon;
GRANT ALL ON TABLE public.inventory TO authenticated;
GRANT ALL ON TABLE public.inventory TO service_role;
GRANT ALL ON TABLE public.inventory TO supabase_admin;


--
-- Name: TABLE inventory_log; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.inventory_log TO anon;
GRANT ALL ON TABLE public.inventory_log TO authenticated;
GRANT ALL ON TABLE public.inventory_log TO service_role;
GRANT ALL ON TABLE public.inventory_log TO supabase_admin;


--
-- Name: TABLE kpi_targets; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.kpi_targets TO anon;
GRANT ALL ON TABLE public.kpi_targets TO authenticated;
GRANT ALL ON TABLE public.kpi_targets TO service_role;


--
-- Name: TABLE lane_role_group_members; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.lane_role_group_members TO anon;
GRANT ALL ON TABLE public.lane_role_group_members TO authenticated;
GRANT ALL ON TABLE public.lane_role_group_members TO service_role;


--
-- Name: TABLE lane_role_groups; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.lane_role_groups TO anon;
GRANT ALL ON TABLE public.lane_role_groups TO authenticated;
GRANT ALL ON TABLE public.lane_role_groups TO service_role;


--
-- Name: TABLE logistics_delivery_demo; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.logistics_delivery_demo TO postgres;
GRANT ALL ON TABLE public.logistics_delivery_demo TO anon;
GRANT ALL ON TABLE public.logistics_delivery_demo TO authenticated;
GRANT ALL ON TABLE public.logistics_delivery_demo TO service_role;


--
-- Name: TABLE mcp_python_code; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.mcp_python_code TO anon;
GRANT ALL ON TABLE public.mcp_python_code TO authenticated;
GRANT ALL ON TABLE public.mcp_python_code TO service_role;
GRANT ALL ON TABLE public.mcp_python_code TO supabase_admin;


--
-- Name: TABLE menu_role_overrides; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.menu_role_overrides TO anon;
GRANT ALL ON TABLE public.menu_role_overrides TO authenticated;
GRANT ALL ON TABLE public.menu_role_overrides TO service_role;


--
-- Name: TABLE org_chart_group_teams; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.org_chart_group_teams TO anon;
GRANT ALL ON TABLE public.org_chart_group_teams TO authenticated;
GRANT ALL ON TABLE public.org_chart_group_teams TO service_role;


--
-- Name: TABLE org_chart_groups; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.org_chart_groups TO anon;
GRANT ALL ON TABLE public.org_chart_groups TO authenticated;
GRANT ALL ON TABLE public.org_chart_groups TO service_role;


--
-- Name: TABLE permissions; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.permissions TO anon;
GRANT ALL ON TABLE public.permissions TO authenticated;
GRANT ALL ON TABLE public.permissions TO service_role;


--
-- Name: TABLE pro_actions; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.pro_actions TO anon;
GRANT ALL ON TABLE public.pro_actions TO authenticated;
GRANT ALL ON TABLE public.pro_actions TO service_role;


--
-- Name: TABLE pro_mail_accounts; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.pro_mail_accounts TO anon;
GRANT ALL ON TABLE public.pro_mail_accounts TO authenticated;
GRANT ALL ON TABLE public.pro_mail_accounts TO service_role;


--
-- Name: TABLE pro_mail_seen; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.pro_mail_seen TO anon;
GRANT ALL ON TABLE public.pro_mail_seen TO authenticated;
GRANT ALL ON TABLE public.pro_mail_seen TO service_role;


--
-- Name: TABLE pro_messages; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.pro_messages TO anon;
GRANT ALL ON TABLE public.pro_messages TO authenticated;
GRANT ALL ON TABLE public.pro_messages TO service_role;


--
-- Name: TABLE pro_mission_runs; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.pro_mission_runs TO anon;
GRANT ALL ON TABLE public.pro_mission_runs TO authenticated;
GRANT ALL ON TABLE public.pro_mission_runs TO service_role;


--
-- Name: TABLE pro_panels; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.pro_panels TO anon;
GRANT ALL ON TABLE public.pro_panels TO authenticated;
GRANT ALL ON TABLE public.pro_panels TO service_role;


--
-- Name: TABLE pro_profile; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.pro_profile TO anon;
GRANT ALL ON TABLE public.pro_profile TO authenticated;
GRANT ALL ON TABLE public.pro_profile TO service_role;


--
-- Name: TABLE pro_role_assignments; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.pro_role_assignments TO anon;
GRANT ALL ON TABLE public.pro_role_assignments TO authenticated;
GRANT ALL ON TABLE public.pro_role_assignments TO service_role;


--
-- Name: TABLE pro_schedules; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.pro_schedules TO anon;
GRANT ALL ON TABLE public.pro_schedules TO authenticated;
GRANT ALL ON TABLE public.pro_schedules TO service_role;


--
-- Name: TABLE pro_team_members; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.pro_team_members TO anon;
GRANT ALL ON TABLE public.pro_team_members TO authenticated;
GRANT ALL ON TABLE public.pro_team_members TO service_role;


--
-- Name: TABLE pro_threads; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.pro_threads TO anon;
GRANT ALL ON TABLE public.pro_threads TO authenticated;
GRANT ALL ON TABLE public.pro_threads TO service_role;


--
-- Name: TABLE pro_vault_audit; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.pro_vault_audit TO anon;
GRANT ALL ON TABLE public.pro_vault_audit TO authenticated;
GRANT ALL ON TABLE public.pro_vault_audit TO service_role;


--
-- Name: SEQUENCE pro_vault_audit_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON SEQUENCE public.pro_vault_audit_id_seq TO anon;
GRANT ALL ON SEQUENCE public.pro_vault_audit_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.pro_vault_audit_id_seq TO service_role;


--
-- Name: TABLE pro_vault_items; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.pro_vault_items TO anon;
GRANT ALL ON TABLE public.pro_vault_items TO authenticated;
GRANT ALL ON TABLE public.pro_vault_items TO service_role;


--
-- Name: TABLE pro_vault_keys; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.pro_vault_keys TO anon;
GRANT ALL ON TABLE public.pro_vault_keys TO authenticated;
GRANT ALL ON TABLE public.pro_vault_keys TO service_role;


--
-- Name: TABLE proc_def_approval_history; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.proc_def_approval_history TO anon;
GRANT ALL ON TABLE public.proc_def_approval_history TO authenticated;
GRANT ALL ON TABLE public.proc_def_approval_history TO service_role;


--
-- Name: TABLE proc_def_approval_state; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.proc_def_approval_state TO anon;
GRANT ALL ON TABLE public.proc_def_approval_state TO authenticated;
GRANT ALL ON TABLE public.proc_def_approval_state TO service_role;


--
-- Name: TABLE proc_def_comments; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.proc_def_comments TO anon;
GRANT ALL ON TABLE public.proc_def_comments TO authenticated;
GRANT ALL ON TABLE public.proc_def_comments TO service_role;


--
-- Name: TABLE proc_def_copilot_log; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.proc_def_copilot_log TO anon;
GRANT ALL ON TABLE public.proc_def_copilot_log TO authenticated;
GRANT ALL ON TABLE public.proc_def_copilot_log TO service_role;


--
-- Name: TABLE proc_def_element_comment_counts; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.proc_def_element_comment_counts TO anon;
GRANT ALL ON TABLE public.proc_def_element_comment_counts TO authenticated;
GRANT ALL ON TABLE public.proc_def_element_comment_counts TO service_role;


--
-- Name: TABLE proc_def_snapshots; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.proc_def_snapshots TO anon;
GRANT ALL ON TABLE public.proc_def_snapshots TO authenticated;
GRANT ALL ON TABLE public.proc_def_snapshots TO service_role;


--
-- Name: TABLE product_table; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.product_table TO postgres;
GRANT ALL ON TABLE public.product_table TO anon;
GRANT ALL ON TABLE public.product_table TO authenticated;
GRANT ALL ON TABLE public.product_table TO service_role;


--
-- Name: TABLE skill_contributions; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.skill_contributions TO anon;
GRANT ALL ON TABLE public.skill_contributions TO authenticated;
GRANT ALL ON TABLE public.skill_contributions TO service_role;


--
-- Name: TABLE standard_terminology; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.standard_terminology TO anon;
GRANT ALL ON TABLE public.standard_terminology TO authenticated;
GRANT ALL ON TABLE public.standard_terminology TO service_role;


--
-- Name: TABLE strategy_initiatives; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.strategy_initiatives TO anon;
GRANT ALL ON TABLE public.strategy_initiatives TO authenticated;
GRANT ALL ON TABLE public.strategy_initiatives TO service_role;


--
-- Name: TABLE strategy_kpi_measurements; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.strategy_kpi_measurements TO anon;
GRANT ALL ON TABLE public.strategy_kpi_measurements TO authenticated;
GRANT ALL ON TABLE public.strategy_kpi_measurements TO service_role;


--
-- Name: TABLE strategy_kpis; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.strategy_kpis TO anon;
GRANT ALL ON TABLE public.strategy_kpis TO authenticated;
GRANT ALL ON TABLE public.strategy_kpis TO service_role;


--
-- Name: TABLE strategy_objectives; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.strategy_objectives TO anon;
GRANT ALL ON TABLE public.strategy_objectives TO authenticated;
GRANT ALL ON TABLE public.strategy_objectives TO service_role;


--
-- Name: TABLE strategy_survey_requests; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.strategy_survey_requests TO anon;
GRANT ALL ON TABLE public.strategy_survey_requests TO authenticated;
GRANT ALL ON TABLE public.strategy_survey_requests TO service_role;


--
-- Name: TABLE strategy_sync_state; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.strategy_sync_state TO anon;
GRANT ALL ON TABLE public.strategy_sync_state TO authenticated;
GRANT ALL ON TABLE public.strategy_sync_state TO service_role;


--
-- Name: TABLE suppliers; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.suppliers TO anon;
GRANT ALL ON TABLE public.suppliers TO authenticated;
GRANT ALL ON TABLE public.suppliers TO service_role;


--
-- Name: TABLE systems; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.systems TO anon;
GRANT ALL ON TABLE public.systems TO authenticated;
GRANT ALL ON TABLE public.systems TO service_role;


--
-- Name: TABLE task_execution_properties; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.task_execution_properties TO anon;
GRANT ALL ON TABLE public.task_execution_properties TO authenticated;
GRANT ALL ON TABLE public.task_execution_properties TO service_role;


--
-- Name: TABLE tb_bpmn_lane; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.tb_bpmn_lane TO anon;
GRANT ALL ON TABLE public.tb_bpmn_lane TO authenticated;
GRANT ALL ON TABLE public.tb_bpmn_lane TO service_role;


--
-- Name: TABLE tb_bpmn_link; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.tb_bpmn_link TO anon;
GRANT ALL ON TABLE public.tb_bpmn_link TO authenticated;
GRANT ALL ON TABLE public.tb_bpmn_link TO service_role;


--
-- Name: TABLE tb_bpmn_model; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.tb_bpmn_model TO anon;
GRANT ALL ON TABLE public.tb_bpmn_model TO authenticated;
GRANT ALL ON TABLE public.tb_bpmn_model TO service_role;


--
-- Name: TABLE tb_bpmn_model_lock; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.tb_bpmn_model_lock TO anon;
GRANT ALL ON TABLE public.tb_bpmn_model_lock TO authenticated;
GRANT ALL ON TABLE public.tb_bpmn_model_lock TO service_role;


--
-- Name: TABLE tb_bpmn_node; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.tb_bpmn_node TO anon;
GRANT ALL ON TABLE public.tb_bpmn_node TO authenticated;
GRANT ALL ON TABLE public.tb_bpmn_node TO service_role;


--
-- Name: TABLE tb_bpmn_version; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.tb_bpmn_version TO anon;
GRANT ALL ON TABLE public.tb_bpmn_version TO authenticated;
GRANT ALL ON TABLE public.tb_bpmn_version TO service_role;


--
-- Name: TABLE v_activity_bottleneck; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.v_activity_bottleneck TO anon;
GRANT ALL ON TABLE public.v_activity_bottleneck TO authenticated;
GRANT ALL ON TABLE public.v_activity_bottleneck TO service_role;


--
-- Name: TABLE v_department_task_stats; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.v_department_task_stats TO anon;
GRANT ALL ON TABLE public.v_department_task_stats TO authenticated;
GRANT ALL ON TABLE public.v_department_task_stats TO service_role;


--
-- Name: TABLE v_kpi_domain_progress; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.v_kpi_domain_progress TO anon;
GRANT ALL ON TABLE public.v_kpi_domain_progress TO authenticated;
GRANT ALL ON TABLE public.v_kpi_domain_progress TO service_role;


--
-- Name: TABLE v_kpi_pipeline_summary; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.v_kpi_pipeline_summary TO anon;
GRANT ALL ON TABLE public.v_kpi_pipeline_summary TO authenticated;
GRANT ALL ON TABLE public.v_kpi_pipeline_summary TO service_role;


--
-- Name: TABLE v_monthly_trend; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.v_monthly_trend TO anon;
GRANT ALL ON TABLE public.v_monthly_trend TO authenticated;
GRANT ALL ON TABLE public.v_monthly_trend TO service_role;


--
-- Name: TABLE v_process_performance; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.v_process_performance TO anon;
GRANT ALL ON TABLE public.v_process_performance TO authenticated;
GRANT ALL ON TABLE public.v_process_performance TO service_role;


--
-- Name: TABLE v_review_board; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.v_review_board TO anon;
GRANT ALL ON TABLE public.v_review_board TO authenticated;
GRANT ALL ON TABLE public.v_review_board TO service_role;


--
-- Name: TABLE v_sla_compliance; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.v_sla_compliance TO anon;
GRANT ALL ON TABLE public.v_sla_compliance TO authenticated;
GRANT ALL ON TABLE public.v_sla_compliance TO service_role;


--
-- Name: TABLE v_weekly_deployment_velocity; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.v_weekly_deployment_velocity TO anon;
GRANT ALL ON TABLE public.v_weekly_deployment_velocity TO authenticated;
GRANT ALL ON TABLE public.v_weekly_deployment_velocity TO service_role;


--
-- Name: TABLE vw_dashboard_proc_domain; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.vw_dashboard_proc_domain TO anon;
GRANT ALL ON TABLE public.vw_dashboard_proc_domain TO authenticated;
GRANT ALL ON TABLE public.vw_dashboard_proc_domain TO service_role;


--
-- Name: TABLE vw_dashboard_activity_types; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.vw_dashboard_activity_types TO anon;
GRANT ALL ON TABLE public.vw_dashboard_activity_types TO authenticated;
GRANT ALL ON TABLE public.vw_dashboard_activity_types TO service_role;


--
-- Name: TABLE vw_dashboard_asset_status; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.vw_dashboard_asset_status TO anon;
GRANT ALL ON TABLE public.vw_dashboard_asset_status TO authenticated;
GRANT ALL ON TABLE public.vw_dashboard_asset_status TO service_role;


--
-- Name: TABLE vw_dashboard_error_processes; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.vw_dashboard_error_processes TO anon;
GRANT ALL ON TABLE public.vw_dashboard_error_processes TO authenticated;
GRANT ALL ON TABLE public.vw_dashboard_error_processes TO service_role;


--
-- Name: TABLE vw_dashboard_kpi_division; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.vw_dashboard_kpi_division TO anon;
GRANT ALL ON TABLE public.vw_dashboard_kpi_division TO authenticated;
GRANT ALL ON TABLE public.vw_dashboard_kpi_division TO service_role;


--
-- Name: TABLE vw_dashboard_proc_state; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.vw_dashboard_proc_state TO anon;
GRANT ALL ON TABLE public.vw_dashboard_proc_state TO authenticated;
GRANT ALL ON TABLE public.vw_dashboard_proc_state TO service_role;


--
-- Name: TABLE vw_dashboard_quality_detail; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.vw_dashboard_quality_detail TO anon;
GRANT ALL ON TABLE public.vw_dashboard_quality_detail TO authenticated;
GRANT ALL ON TABLE public.vw_dashboard_quality_detail TO service_role;


--
-- Name: TABLE vw_dashboard_rr_heatmap; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.vw_dashboard_rr_heatmap TO anon;
GRANT ALL ON TABLE public.vw_dashboard_rr_heatmap TO authenticated;
GRANT ALL ON TABLE public.vw_dashboard_rr_heatmap TO service_role;


--
-- Name: TABLE vw_dashboard_system_map; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.vw_dashboard_system_map TO anon;
GRANT ALL ON TABLE public.vw_dashboard_system_map TO authenticated;
GRANT ALL ON TABLE public.vw_dashboard_system_map TO service_role;


--
-- Name: TABLE vw_dashboard_version_frequency; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.vw_dashboard_version_frequency TO anon;
GRANT ALL ON TABLE public.vw_dashboard_version_frequency TO authenticated;
GRANT ALL ON TABLE public.vw_dashboard_version_frequency TO service_role;


--
-- Name: TABLE vw_dashboard_weekly_velocity; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.vw_dashboard_weekly_velocity TO anon;
GRANT ALL ON TABLE public.vw_dashboard_weekly_velocity TO authenticated;
GRANT ALL ON TABLE public.vw_dashboard_weekly_velocity TO service_role;


--
-- Name: TABLE vw_dashboard_xor_gateways; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.vw_dashboard_xor_gateways TO anon;
GRANT ALL ON TABLE public.vw_dashboard_xor_gateways TO authenticated;
GRANT ALL ON TABLE public.vw_dashboard_xor_gateways TO service_role;


--
-- Name: TABLE workitem_app; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.workitem_app TO anon;
GRANT ALL ON TABLE public.workitem_app TO authenticated;
GRANT ALL ON TABLE public.workitem_app TO service_role;


--
-- Name: TABLE workitem_app_binding; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.workitem_app_binding TO anon;
GRANT ALL ON TABLE public.workitem_app_binding TO authenticated;
GRANT ALL ON TABLE public.workitem_app_binding TO service_role;


--
-- PostgreSQL database dump complete
--

SET search_path = public, extensions;

-- 5) 공유 테이블의 빠진 트리거
DROP TRIGGER IF EXISTS "trg_set_proc_inst_actual_start_date" ON public."bpm_proc_inst";
CREATE TRIGGER trg_set_proc_inst_actual_start_date BEFORE UPDATE OF status ON public.bpm_proc_inst FOR EACH ROW EXECUTE FUNCTION set_proc_inst_actual_start_date();
DROP TRIGGER IF EXISTS "trg_set_deleted_by_proc_def" ON public."proc_def";
CREATE TRIGGER trg_set_deleted_by_proc_def BEFORE UPDATE ON public.proc_def FOR EACH ROW EXECUTE FUNCTION set_deleted_by_from_jwt();
DROP TRIGGER IF EXISTS "trg_set_actual_start_date" ON public."todolist";
CREATE TRIGGER trg_set_actual_start_date BEFORE UPDATE OF status ON public.todolist FOR EACH ROW EXECUTE FUNCTION set_actual_start_date();
DROP TRIGGER IF EXISTS "trg_set_todolist_executor_dept" ON public."todolist";
CREATE TRIGGER trg_set_todolist_executor_dept BEFORE INSERT OR UPDATE OF user_id ON public.todolist FOR EACH ROW EXECUTE FUNCTION set_todolist_executor_dept();
DROP TRIGGER IF EXISTS "trg_task_execution_insert" ON public."todolist";
CREATE TRIGGER trg_task_execution_insert AFTER INSERT ON public.todolist FOR EACH ROW EXECUTE FUNCTION sync_task_execution_on_insert();
DROP TRIGGER IF EXISTS "trg_task_execution_update" ON public."todolist";
CREATE TRIGGER trg_task_execution_update AFTER UPDATE ON public.todolist FOR EACH ROW WHEN ((old.status IS DISTINCT FROM new.status)) EXECUTE FUNCTION sync_task_execution_on_update();
DROP TRIGGER IF EXISTS "trg_update_user_department" ON public."users";
CREATE TRIGGER trg_update_user_department BEFORE INSERT OR UPDATE OF department_id ON public.users FOR EACH ROW EXECUTE FUNCTION update_user_department();

-- 6) 공유 테이블의 빠진 RLS 정책
DROP POLICY IF EXISTS "configuration_modify_admin" ON public."configuration";
CREATE POLICY "configuration_modify_admin" ON public."configuration" AS PERMISSIVE FOR ALL TO public USING (has_role_at_least('admin'::text)) WITH CHECK (has_role_at_least('admin'::text));
DROP POLICY IF EXISTS "configuration_select_all" ON public."configuration";
CREATE POLICY "configuration_select_all" ON public."configuration" AS PERMISSIVE FOR SELECT TO public USING (true);
DROP POLICY IF EXISTS "proc_def_delete_admin" ON public."proc_def";
CREATE POLICY "proc_def_delete_admin" ON public."proc_def" AS PERMISSIVE FOR DELETE TO public USING (has_role_at_least('admin'::text));
DROP POLICY IF EXISTS "proc_def_insert_owner" ON public."proc_def";
CREATE POLICY "proc_def_insert_owner" ON public."proc_def" AS PERMISSIVE FOR INSERT TO public WITH CHECK (has_role_at_least('owner'::text));
DROP POLICY IF EXISTS "proc_def_select_all" ON public."proc_def";
CREATE POLICY "proc_def_select_all" ON public."proc_def" AS PERMISSIVE FOR SELECT TO public USING (true);
DROP POLICY IF EXISTS "proc_def_update_editor" ON public."proc_def";
CREATE POLICY "proc_def_update_editor" ON public."proc_def" AS PERMISSIVE FOR UPDATE TO public USING (has_role_at_least('editor'::text));
DROP POLICY IF EXISTS "user_permissions_modify_admin" ON public."user_permissions";
CREATE POLICY "user_permissions_modify_admin" ON public."user_permissions" AS PERMISSIVE FOR ALL TO public USING (has_role_at_least('admin'::text)) WITH CHECK (has_role_at_least('admin'::text));
DROP POLICY IF EXISTS "user_permissions_select_editor" ON public."user_permissions";
CREATE POLICY "user_permissions_select_editor" ON public."user_permissions" AS PERMISSIVE FOR SELECT TO public USING (has_role_at_least('editor'::text));
DROP POLICY IF EXISTS "users_delete_admin" ON public."users";
CREATE POLICY "users_delete_admin" ON public."users" AS PERMISSIVE FOR DELETE TO public USING (has_role_at_least('admin'::text));
DROP POLICY IF EXISTS "users_insert_admin" ON public."users";
CREATE POLICY "users_insert_admin" ON public."users" AS PERMISSIVE FOR INSERT TO public WITH CHECK (has_role_at_least('admin'::text));
DROP POLICY IF EXISTS "users_select_all" ON public."users";
CREATE POLICY "users_select_all" ON public."users" AS PERMISSIVE FOR SELECT TO public USING (true);
DROP POLICY IF EXISTS "users_update_self_or_admin" ON public."users";
CREATE POLICY "users_update_self_or_admin" ON public."users" AS PERMISSIVE FOR UPDATE TO public USING ((((id)::text = COALESCE(NULLIF(((current_setting('request.jwt.claims'::text, true))::json ->> 'sub'::text), ''::text), '00000000-0000-0000-0000-000000000000'::text)) OR has_role_at_least('admin'::text)));

-- 7) realtime 게시
ALTER PUBLICATION supabase_realtime ADD TABLE public."proc_def_approval_state";
