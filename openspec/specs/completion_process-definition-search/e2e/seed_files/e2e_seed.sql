-- =====================================================================
-- completion_process-definition-search E2E seed
-- ---------------------------------------------------------------------
-- Idempotent seed that prepares the minimum data the spec needs:
--   1. tenants: `localhost` (default browser subdomain) + `tenant-b`
--                (cross-tenant isolation check). `empty-tenant` is not
--                inserted so its document filter returns [].
--   2. auth.users / public.users: e2e@uengine.org login user
--   3. public.proc_def: human-readable process definition rows that the
--                       frontend Searchbar resolves by id after the
--                       vector search returns processDefinitionIds.
--   4. public.documents: 1536-d embeddings filtered by
--                        metadata @> {tenant_id, type=process_definition}.
--                        With identical embedding vectors per tenant the
--                        top-k=3 in `localhost` returns its 3 rows and
--                        `empty-tenant` returns [] (no rows seeded).
-- =====================================================================
set search_path to public, extensions;

create extension if not exists pgcrypto;
create extension if not exists vector;

-- ---------------------------------------------------------------------
-- 1. Tenants
-- ---------------------------------------------------------------------
insert into public.tenants (id, owner) values ('localhost', null) on conflict (id) do nothing;
insert into public.tenants (id, owner) values ('tenant-b', null)  on conflict (id) do nothing;

-- ---------------------------------------------------------------------
-- 2. Login user (uses Supabase pgcrypto bcrypt)
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
values
  ('11111111-1111-1111-1111-111111111111', 'E2E 사용자', 'e2e@uengine.org', 'localhost', true, 'admin', false)
on conflict (id, tenant_id) do update
  set username = excluded.username,
      email    = excluded.email,
      is_admin = excluded.is_admin,
      role     = excluded.role,
      is_agent = excluded.is_agent;

-- ---------------------------------------------------------------------
-- 3. proc_def rows (Searchbar maps processDefinitionId -> human row)
-- ---------------------------------------------------------------------
insert into public.proc_def (id, name, tenant_id, isdeleted, bpmn) values
    ('vacation_request_process',  '휴가신청',  'localhost', false, '<bpmn:dummy/>'),
    ('purchase_request_process',  '구매요청',  'localhost', false, '<bpmn:dummy/>'),
    ('business_trip_process',     '출장신청',  'localhost', false, '<bpmn:dummy/>'),
    ('meeting_room_process',      '회의실예약', 'tenant-b', false, '<bpmn:dummy/>'),
    ('equipment_rental_process',  '장비대여',   'tenant-b', false, '<bpmn:dummy/>')
on conflict do nothing;

-- ---------------------------------------------------------------------
-- 4. documents rows
--    All seed embeddings use a single non-zero dim (dim 0 = 1.0) so
--    cosine distance against any non-zero query is finite and the top-k
--    rank is stable. metadata.tenant_id + metadata.type drive the
--    backend filter.
-- ---------------------------------------------------------------------
do $$
declare
  vec vector(1536);
begin
  vec := (
    '[' || '1.0' || repeat(',0', 1535) || ']'
  )::vector(1536);

  -- localhost tenant
  insert into public.documents (id, content, metadata, embedding) values
    (
      '22222222-2222-2222-2222-22222222a001',
      'processDefinitionId: {"processDefinitionId":"vacation_request_process","processDefinitionName":"휴가신청"}',
      '{"tenant_id":"localhost","type":"process_definition","processDefinitionId":"vacation_request_process"}'::jsonb,
      vec
    ),
    (
      '22222222-2222-2222-2222-22222222a002',
      'processDefinitionId: {"processDefinitionId":"purchase_request_process","processDefinitionName":"구매요청"}',
      '{"tenant_id":"localhost","type":"process_definition","processDefinitionId":"purchase_request_process"}'::jsonb,
      vec
    ),
    (
      '22222222-2222-2222-2222-22222222a003',
      'processDefinitionId: {"processDefinitionId":"business_trip_process","processDefinitionName":"출장신청"}',
      '{"tenant_id":"localhost","type":"process_definition","processDefinitionId":"business_trip_process"}'::jsonb,
      vec
    ),
    -- tenant-b tenant
    (
      '22222222-2222-2222-2222-22222222b001',
      'processDefinitionId: {"processDefinitionId":"meeting_room_process","processDefinitionName":"회의실예약"}',
      '{"tenant_id":"tenant-b","type":"process_definition","processDefinitionId":"meeting_room_process"}'::jsonb,
      vec
    ),
    (
      '22222222-2222-2222-2222-22222222b002',
      'processDefinitionId: {"processDefinitionId":"equipment_rental_process","processDefinitionName":"장비대여"}',
      '{"tenant_id":"tenant-b","type":"process_definition","processDefinitionId":"equipment_rental_process"}'::jsonb,
      vec
    )
  on conflict (id) do update
    set content   = excluded.content,
        metadata  = excluded.metadata,
        embedding = excluded.embedding;
end $$;

-- Ask PostgREST to reload its schema cache (harmless if no listener)
notify pgrst, 'reload schema';
