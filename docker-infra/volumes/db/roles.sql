-- NOTE: change to your own passwords for production environments
\set pgpass `echo "$POSTGRES_PASSWORD"`

ALTER USER authenticator WITH PASSWORD :'pgpass';
ALTER USER pgbouncer WITH PASSWORD :'pgpass';
ALTER USER supabase_auth_admin WITH PASSWORD :'pgpass';
ALTER USER supabase_storage_admin WITH PASSWORD :'pgpass';
-- supabase_functions_admin may not exist yet (created conditionally by
-- 98-webhooks.sql depending on pg_net/schema state, notably under arm64
-- emulation) -- don't let a missing role abort the whole script.
\set ON_ERROR_STOP off
ALTER USER supabase_functions_admin WITH PASSWORD :'pgpass';
\set ON_ERROR_STOP on
