-- =====================================================================
-- completion_process-definition-search E2E seed
-- ---------------------------------------------------------------------
-- Creates the minimum, deterministic data the suite needs:
--   1. tenants: `localhost` (browser tenant) and `tenant-b` (isolation)
--   2. proc_def: 3 process definitions for `localhost`, 1 for `tenant-b`
--   3. documents: matching process-definition search-index rows
--      (metadata.type = 'process_definition'), so `match_documents`
--      vector search returns deterministic candidates per tenant
--
-- The frontend resolves its tenant from the host name; on localhost the
-- login user lives in the `localhost` tenant, so its search is scoped
-- there. The `tenant-b` rows exist only to prove tenant isolation: a
-- localhost search must never surface them.
--
-- This suite OWNS the process-definition search index in the E2E DB:
-- the seed first removes every existing `process_definition` document so
-- the suite stays deterministic regardless of prior runs. mem0 agent
-- memory uses a different store (vecs.memories) and is unaffected.
--
-- Embeddings: each document gets a fixed 1536-d unit-ish vector. With
-- only a handful of documents per tenant filter, `match_documents`
-- (no score threshold) returns them all, so the candidate set is
-- deterministic without depending on real embedding similarity.
--
-- Idempotent: safe to re-run.
-- =====================================================================
set search_path to public, extensions;

-- ---------------------------------------------------------------------
-- 1. Tenants
-- ---------------------------------------------------------------------
insert into public.tenants (id, owner) values ('localhost', null)
on conflict (id) do nothing;
insert into public.tenants (id, owner) values ('tenant-b', null)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------
-- 2. Process definitions (proc_def)
--    Delete-then-insert keeps the rows fully deterministic across runs.
--    Also clears any `e2e_search_*` orphans left by earlier attempts so
--    the search result set stays deterministic.
-- ---------------------------------------------------------------------
delete from public.proc_def
where id in (
    'e2e_pds_leave', 'e2e_pds_trip', 'e2e_pds_purchase', 'e2e_pds_competitor'
)
   or id like 'e2e_search_%';

insert into public.proc_def (id, name, tenant_id, isdeleted, bpmn) values
  ('e2e_pds_leave',     '휴가 신청 및 승인 프로세스', 'localhost', false,
   '휴가 신청서를 작성하고 팀장 승인을 거쳐 휴가를 확정하는 절차'),
  ('e2e_pds_trip',      '출장 경비 정산 프로세스',   'localhost', false,
   '출장 후 영수증을 등록하고 경비를 정산받는 절차'),
  ('e2e_pds_purchase',  '구매 요청 승인 프로세스',   'localhost', false,
   '필요 물품의 구매를 요청하고 승인받는 절차'),
  ('e2e_pds_competitor','외부 테넌트 전용 프로세스', 'tenant-b',  false,
   '다른 테넌트에만 등록된 격리 검증용 프로세스 정의');

-- ---------------------------------------------------------------------
-- 3. Search-index documents (public.documents)
--    content format matches what the frontend parser expects:
--      "process_definition: {\"processDefinitionId\":\"<id>\"}"
--    (compact JSON: no space after the colon inside the object).
--    This suite owns every process_definition document in the E2E DB.
-- ---------------------------------------------------------------------
delete from public.documents
where metadata->>'type' = 'process_definition';

with vec as (
    select ('[' || string_agg('0.0255', ',') || ']')::vector(1536) as e
    from generate_series(1, 1536)
)
insert into public.documents (id, content, metadata, embedding)
select d.id::uuid, d.content, d.metadata::jsonb, vec.e
from vec, (values
  ('a1d10000-0000-4000-8000-000000000001',
   'process_definition: {"processDefinitionId":"e2e_pds_leave"}',
   '{"tenant_id":"localhost","type":"process_definition"}'),
  ('a1d10000-0000-4000-8000-000000000002',
   'process_definition: {"processDefinitionId":"e2e_pds_trip"}',
   '{"tenant_id":"localhost","type":"process_definition"}'),
  ('a1d10000-0000-4000-8000-000000000003',
   'process_definition: {"processDefinitionId":"e2e_pds_purchase"}',
   '{"tenant_id":"localhost","type":"process_definition"}'),
  ('a1d10000-0000-4000-8000-0000000000b1',
   'process_definition: {"processDefinitionId":"e2e_pds_competitor"}',
   '{"tenant_id":"tenant-b","type":"process_definition"}')
) as d(id, content, metadata);
