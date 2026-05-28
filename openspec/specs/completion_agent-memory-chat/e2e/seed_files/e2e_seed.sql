-- =====================================================================
-- completion_agent-memory-chat E2E seed
-- ---------------------------------------------------------------------
-- Creates the minimum, deterministic data the suite needs:
--   1. tenants: `localhost` (browser tenant)
--   2. auth.users: e2e@uengine.org login user
--   3. public.users: tenant profile for the login user + a memory agent
--      (agent_type='agent') the browser navigates to via /agent-chat/:id
--   4. Drops any prior mem0 `memories` table so each suite run starts
--      from a clean memory store. mem0 itself recreates the table on
--      first call to Memory.add / Memory.search.
--
-- Idempotent: safe to re-run.
-- =====================================================================
set search_path to public, extensions;

create extension if not exists pgcrypto;
create extension if not exists vector;

-- ---------------------------------------------------------------------
-- 1. Tenants
-- ---------------------------------------------------------------------
insert into public.tenants (id, owner) values ('localhost', null)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------
-- 2. Ensure agent_type column exists on public.users
--    (root init.sql does not declare it; infra migration.sql adds it.)
-- ---------------------------------------------------------------------
alter table public.users add column if not exists agent_type text;
alter table public.users add column if not exists alias text;

-- ---------------------------------------------------------------------
-- 3. Login user (auth.users + public.users)
--    Fixed UUID so the browser session and the public profile row stay
--    in lock-step across reruns.
-- ---------------------------------------------------------------------
insert into auth.users (
    instance_id, id, aud, role,
    email, encrypted_password,
    email_confirmed_at, recovery_sent_at,
    raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at, last_sign_in_at,
    confirmation_token, email_change, email_change_token_new, recovery_token
) values (
    '00000000-0000-0000-0000-000000000000',
    '11111111-1111-1111-1111-111111111111',
    'authenticated', 'authenticated',
    'e2e@uengine.org',
    crypt('e2epassword', gen_salt('bf')),
    now(), null,
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{}'::jsonb,
    now(), now(), now(),
    '', '', '', ''
) on conflict (id) do update
  set encrypted_password = excluded.encrypted_password,
      email_confirmed_at = excluded.email_confirmed_at,
      updated_at         = now();

insert into public.users (id, username, email, tenant_id, is_admin, role, is_agent)
values (
    '11111111-1111-1111-1111-111111111111',
    'E2E 사용자', 'e2e@uengine.org', 'localhost', true, 'admin', false
) on conflict (id, tenant_id) do update
  set username = excluded.username,
      email    = excluded.email,
      is_admin = excluded.is_admin,
      role     = excluded.role,
      is_agent = excluded.is_agent;

-- ---------------------------------------------------------------------
-- 4. Memory agent profile (the /agent-chat/:id target)
-- ---------------------------------------------------------------------
insert into public.users (
    id, username, profile, email, is_admin, role, tenant_id,
    goal, persona, description, is_agent, agent_type, model
) values (
    '00000000-0000-0000-0000-0000000000aa',
    '메모리 에이전트',
    '/images/chat-icon.png',
    'memory-agent@uengine.org',
    false, 'agent', 'localhost',
    '사용자가 학습한 정보를 기억하고 질문에 답한다.',
    '친절한 도우미',
    'E2E 검증용 메모리 에이전트',
    true, 'agent', 'gpt-4o'
) on conflict (id, tenant_id) do update
  set username    = excluded.username,
      agent_type  = excluded.agent_type,
      is_agent    = excluded.is_agent,
      model       = excluded.model,
      goal        = excluded.goal,
      persona     = excluded.persona,
      description = excluded.description;

-- ---------------------------------------------------------------------
-- 5. Reset mem0 memory store (vecs.memories) if it exists.
--    mem0 (vector_store provider=supabase, collection_name=memories)
--    creates the table on first use; we drop it so duplicate-detection
--    tests start from an empty store every run.
-- ---------------------------------------------------------------------
drop table if exists vecs.memories;
