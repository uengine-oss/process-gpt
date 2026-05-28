-- =====================================================================
-- E2E seed: completion_notification-push-delivery
-- ---------------------------------------------------------------------
-- Seeds:
--   - tenants: 'e2e-fcm-tenant' (non-uengine — hits ENV=production branch
--              in fetch_unprocessed_notifications) + reuses 'localhost'
--              for the in-app UI user.
--   - user_devices: fake FCM device token for the FCM protocol user.
--   - notifications: one unprocessed row (consumer IS NULL) for the
--                    polling scenario 04. The in-app UI scenario 05
--                    inserts/cleans its own rows at test time so the
--                    polling worker never claims them.
--   - auth.users + public.users: login-capable user for scenario 05.
-- =====================================================================

BEGIN;

-- The fcm_service polling worker writes `updated_at` when it claims a
-- notification row. init.sql does not define that column, so add it
-- here (idempotent). Production environments have it via migrations.
ALTER TABLE public.notifications
    ADD COLUMN IF NOT EXISTS updated_at timestamp with time zone NULL DEFAULT now();

-- Tenant for non-uengine branch (used by FCM protocol scenarios 02/03/04)
INSERT INTO public.tenants (id, owner)
VALUES ('e2e-fcm-tenant', null)
ON CONFLICT (id) DO NOTHING;

-- Registered user device for the FCM protocol scenarios.
INSERT INTO public.user_devices (user_email, device_token, access_page, last_access_at)
VALUES (
    'e2e-fcm-user@uengine.org',
    'fake-device-token-e2e-001',
    '/todolist',
    now()
)
ON CONFLICT (user_email) DO UPDATE
SET device_token = EXCLUDED.device_token,
    last_access_at = EXCLUDED.last_access_at;

-- Unprocessed notification (consumer IS NULL) for polling scenario 04.
INSERT INTO public.notifications (
    id, title, type, description, is_checked, time_stamp,
    user_id, url, consumer, from_user_id, tenant_id
)
VALUES (
    'aaaaaaaa-bbbb-cccc-dddd-eeeeeeee0001',
    '새 워크아이템',
    'workitem_bmp',
    '담당 업무를 확인하세요',
    false,
    now(),
    'e2e-fcm-user@uengine.org',
    '/todolist/abc',
    NULL,
    '프로세스봇',
    'e2e-fcm-tenant'
)
ON CONFLICT (id) DO UPDATE
SET consumer = NULL,
    is_checked = false,
    time_stamp = now();

-- ---------------------------------------------------------------------
-- In-app UI scenario 05 login user.
-- The SPA reads `tenant_id` from `public.users` to scope the realtime
-- subscription, so seed both auth.users + public.users with a stable
-- id under the 'localhost' tenant (matches the default e2e SPA host).
-- ---------------------------------------------------------------------
INSERT INTO auth.users (
    instance_id, id, aud, role,
    email, encrypted_password,
    email_confirmed_at, recovery_sent_at,
    raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at, last_sign_in_at,
    confirmation_token, email_change, email_change_token_new, recovery_token
) VALUES (
    '00000000-0000-0000-0000-000000000000',
    '55555555-5555-5555-5555-555555555555',
    'authenticated', 'authenticated',
    'e2e-fcm-ui@uengine.org',
    crypt('e2epassword', gen_salt('bf')),
    now(), null,
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{}'::jsonb,
    now(), now(), now(),
    '', '', '', ''
) ON CONFLICT (id) DO UPDATE
  SET encrypted_password = EXCLUDED.encrypted_password,
      email_confirmed_at = EXCLUDED.email_confirmed_at,
      updated_at         = now();

INSERT INTO public.users (id, username, email, tenant_id, is_admin, role, is_agent)
VALUES (
    '55555555-5555-5555-5555-555555555555',
    'FCM UI 사용자', 'e2e-fcm-ui@uengine.org', 'localhost', true, 'admin', false
) ON CONFLICT (id, tenant_id) DO UPDATE
  SET username = EXCLUDED.username,
      email    = EXCLUDED.email;

-- Clean any leftover scenario-05 rows from a previous run so the test
-- starts with no unread in-app notifications for this user.
DELETE FROM public.notifications
WHERE user_id = 'e2e-fcm-ui@uengine.org';

COMMIT;
