-- =====================================================================
-- completion_agent-memory-chat E2E seed
-- ---------------------------------------------------------------------
-- Creates the minimum data the suite needs:
--   1. one login user in Supabase auth (GoTrue) + its email identity
--   2. the matching public.users profile row (tenant: localhost)
--   3. one memory agent (is_agent = true) the browser navigates to
--
-- The frontend resolves its tenant from the host name, so on localhost
-- every profile/chat row lives in the `localhost` tenant. The login
-- JWT app_metadata.tenant_id must match so public.tenant_id() = 'localhost'.
--
-- Idempotent: safe to re-run. Runs after `db` and `auth` are healthy so
-- the GoTrue `auth.*` schema/columns already exist.
-- =====================================================================
set search_path to public, auth, extensions;
create extension if not exists pgcrypto;

-- Tenant the frontend uses on localhost
insert into public.tenants (id, owner) values ('localhost', null)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------
-- 1. Login user (auth.users)
--    Email/password login: e2e@uengine.org / e2epassword
--    Delete-then-insert keeps the row fully deterministic across re-runs
--    (deleting the user cascades to its identities/sessions).
-- ---------------------------------------------------------------------
delete from auth.users
where id = '11111111-1111-1111-1111-111111111111'
   or email = 'e2e@uengine.org';

insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at,
    raw_app_meta_data, raw_user_meta_data,
    confirmation_token, recovery_token, email_change_token_new, email_change
) values (
    '00000000-0000-0000-0000-000000000000',
    '11111111-1111-1111-1111-111111111111',
    'authenticated', 'authenticated',
    'e2e@uengine.org',
    crypt('e2epassword', gen_salt('bf')),
    now(), now(), now(),
    '{"provider":"email","providers":["email"],"tenant_id":"localhost"}'::jsonb,
    '{"name":"E2E 사용자"}'::jsonb,
    '', '', '', ''
);

-- Email identity (required by GoTrue for password sign-in)
insert into auth.identities (
    provider_id, user_id, identity_data, provider,
    last_sign_in_at, created_at, updated_at
) values (
    '11111111-1111-1111-1111-111111111111',
    '11111111-1111-1111-1111-111111111111',
    '{"sub":"11111111-1111-1111-1111-111111111111","email":"e2e@uengine.org","email_verified":true}'::jsonb,
    'email', now(), now(), now()
);

-- ---------------------------------------------------------------------
-- 2. Login user profile (public.users) - tenant localhost, admin
-- ---------------------------------------------------------------------
delete from public.users
where id in ('11111111-1111-1111-1111-111111111111',
             '22222222-2222-2222-2222-222222222222');

insert into public.users (id, username, email, tenant_id, is_admin, role, is_agent)
values (
    '11111111-1111-1111-1111-111111111111',
    'E2E 사용자', 'e2e@uengine.org', 'localhost', true, 'admin', false
);

-- ---------------------------------------------------------------------
-- 3. Memory agent (public.users, is_agent = true)
--    Browser navigates to /agent-chat/22222222-2222-2222-2222-222222222222
-- ---------------------------------------------------------------------
-- agent_type = 'agent' makes the 학습/질의/지식 tabs visible in AgentChatInfo.
insert into public.users (
    id, username, email, tenant_id, is_admin, is_agent, agent_type,
    goal, persona, description, model, profile
) values (
    '22222222-2222-2222-2222-222222222222',
    '메모리 에이전트', 'memory-agent@uengine.org', 'localhost', false, true, 'agent',
    '사용자가 학습시킨 정보를 기억하고 질문에 답변한다',
    '친절한 메모리 도우미',
    'E2E 검증용 에이전트 메모리 대화 에이전트',
    'gpt-4o', '/images/chat-icon.png'
);
