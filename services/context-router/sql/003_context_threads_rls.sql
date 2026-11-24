-- Only servers read and write context_threads: the router as the service role (Supabase REST) and Process GPT
-- Lite's server over its own database connection (the table owner). RLS on with no policy keeps the anon and
-- authenticated keys out, like Lite's pro_* tables (Lite server/sql/050_rls_existing_tables.sql).
alter table public.context_threads enable row level security;
