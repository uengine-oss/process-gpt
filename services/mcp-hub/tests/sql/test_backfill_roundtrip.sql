-- ============================================================
-- 백필 왕복 동치성 테스트
-- 임의의 tenants.mcp 블롭을 백필한 뒤, mcp_servers_jsonb() 가
-- 만들어내는 결과가 원본과 의미적으로 동치인지 확인한다.
-- (enabled / is_default 는 백필이 명시값으로 채우므로 정규화 후 비교)
-- ============================================================
begin;

insert into public.tenants (id, owner) values ('__mcp_rt_test__', null)
  on conflict (id) do nothing;

update public.tenants set mcp = '{
  "mcpServers": {
    "rt-stdio":  {"command":"uvx","args":["some-mcp","--flag"],"env":{"K":"V"}},
    "rt-http":   {"type":"streamable-http","url":"http://example.test/mcp","headers":{"Authorization":"Bearer x"}},
    "rt-sse":    {"type":"sse","url":"http://example.test/sse"},
    "rt-off":    {"command":"node","args":["srv.js"],"enabled":false},
    "rt-legacy": {"type":"http","url":"http://example.test/legacy"}
  }
}'::jsonb
where id = '__mcp_rt_test__';

-- 원본 보관 (백필 트리거가 덮어쓰기 전에)
create temporary table _rt_orig as
select mcp as blob from public.tenants where id = '__mcp_rt_test__';

select public.mcp_backfill_from_tenants();

-- 정규화: 원본에 없는 enabled/is_default 기본값을 채워 넣어 비교 가능하게 만든다
create or replace function pg_temp.normalize(b jsonb) returns jsonb language sql immutable as $$
  select jsonb_build_object('mcpServers', jsonb_object_agg(
      k,
      (jsonb_build_object('enabled', true, 'is_default', false) || v)
      -- legacy 'http' 는 정본에서 streamable-http 로 정규화되므로 동일 취급
      || case when v->>'type' = 'http'
              then jsonb_build_object('type','streamable-http') else '{}'::jsonb end
  ))
  from jsonb_each((b -> 'mcpServers')) e(k, v);
$$;

\echo '--- 원본(정규화) vs 재생성 비교 ---'
select
  case when pg_temp.normalize(o.blob) = pg_temp.normalize(public.mcp_servers_jsonb('__mcp_rt_test__'))
       then 'PASS: 왕복 동치'
       else 'FAIL: 불일치'
  end as roundtrip,
  (select count(*) from public.mcp_server where tenant_id = '__mcp_rt_test__') as servers,
  (select count(*) from public.mcp_server_version where tenant_id = '__mcp_rt_test__') as versions
from _rt_orig o;

\echo '--- 불일치 시 상세 ---'
select k, o_val, n_val
from (
  select e.key as k, e.value as o_val,
         (public.mcp_servers_jsonb('__mcp_rt_test__') -> 'mcpServers' -> e.key) as n_val
  from _rt_orig o, jsonb_each(pg_temp.normalize(o.blob) -> 'mcpServers') e
) d
where o_val is distinct from (jsonb_build_object('enabled',true,'is_default',false) || n_val)
   and o_val <> n_val;

\echo '--- transport 매핑 확인 ---'
select s.name, v.transport, v.command, v.url, s.enabled
from public.mcp_server s join public.mcp_server_version v on v.id = s.current_version_id
where s.tenant_id = '__mcp_rt_test__' order by s.name;

\echo '--- enabled=false 가 보존되는가 ---'
select case when (public.mcp_servers_jsonb('__mcp_rt_test__') #>> '{mcpServers,rt-off,enabled}') = 'false'
            then 'PASS: enabled=false 보존' else 'FAIL' end;

rollback;
