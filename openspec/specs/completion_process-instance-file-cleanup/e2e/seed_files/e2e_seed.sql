-- =====================================================================
-- E2E seed: completion_process-instance-file-cleanup
-- ---------------------------------------------------------------------
-- Seeds a tenant, a 'files' bucket row in storage.buckets (idempotent),
-- one COMPLETED + is_clean_up=false bpm_proc_inst, and one
-- proc_inst_source row whose file_path points at the seeded storage
-- object pifc/completed.txt. A second object pifc/keep.txt is uploaded
-- by storage-seed-pifc and is NOT referenced by any proc_inst_source —
-- scenario 02 uses it to confirm the worker leaves unrelated files
-- alone.
-- =====================================================================

BEGIN;

-- Tenant. The polling worker defaults `subdomain_var` to 'localhost' when
-- no Subdomain header is provided, and `cleanup_completed_process_files`
-- filters by exactly that value. We seed `localhost` to match.
INSERT INTO public.tenants (id, owner)
VALUES ('localhost', null)
ON CONFLICT (id) DO NOTHING;

-- Bucket row in storage schema. The storage container creates this
-- schema on first boot; insertion is idempotent.
INSERT INTO storage.buckets (id, name, public)
VALUES ('files', 'files', true)
ON CONFLICT (id) DO UPDATE SET public = true;

-- COMPLETED process instance awaiting cleanup
INSERT INTO public.bpm_proc_inst (
    proc_inst_id, proc_inst_name, status, tenant_id, is_clean_up
)
VALUES (
    'e2e-pifc-inst-001',
    'PIFC E2E Completed Instance',
    'COMPLETED',
    'localhost',
    false
)
ON CONFLICT (proc_inst_id) DO UPDATE
SET status = 'COMPLETED', is_clean_up = false, tenant_id = 'localhost';

-- proc_inst_source pointing at the seeded storage object.
-- file_path uses the public storage URL form the cleanup logic parses
-- with parse_storage_url(): /storage/v1/object/public/<bucket>/<path>.
-- The host (kong) only matters for parse_storage_url's regex match;
-- the worker re-issues the list/remove calls through its configured
-- SUPABASE_URL, so 'kong' inside the URL is acceptable.
DELETE FROM public.proc_inst_source WHERE proc_inst_id = 'e2e-pifc-inst-001';
INSERT INTO public.proc_inst_source (proc_inst_id, file_name, file_path, is_process)
VALUES (
    'e2e-pifc-inst-001',
    'completed.txt',
    'http://kong:8000/storage/v1/object/public/files/pifc/completed.txt',
    false
);

COMMIT;
