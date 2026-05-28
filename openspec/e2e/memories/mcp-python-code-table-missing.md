---
name: mcp-python-code-table-missing
description: public.mcp_python_code 테이블이 루트 init.sql/마이그레이션에 없어 compensation_handler.generate_compensation 이 호출되는 모든 흐름(특히 rework-complete)이 PostgREST 404 → 500으로 실패.
applies-to:
  - completion
  - compensation-handler
  - rework
  - supabase
  - postgrest
last-verified: 2026-05-27
metadata:
  type: pitfall
---

# `public.mcp_python_code` 테이블이 init.sql에 없음

`services/completion/database.py::fetch_mcp_python_code` 는 `supabase.table('mcp_python_code')` 를 PostgREST로 호출한다. 그러나 E2E 스택의 `init.sql`/`infra/volumes/db/*` 어디에도 해당 테이블 DDL이 없어, 호출 시 PostgREST가 `42P01 relation "public.mcp_python_code" does not exist`로 응답하고 그 안의 `try/except`가 `HTTPException(404, ...)` 으로 재포장한다.

문제는 호출 위치들이다. 특히 `compensation_handler.generate_compensation` 의 첫 줄이 이 함수를 호출하므로, `rework-complete` 핸들러가 호출하는 흐름 전체가 실패한다. 사용자에게 보이는 에러:

```
{"detail":"Compensation handling failed: 404: {'message': 'relation \"public.mcp_python_code\" does not exist', ...}"}
HTTP 500
```

`get-rework-activities` 는 이 함수를 부르지 않으므로 문제없이 동작 → 디버깅 초기에는 "왜 한쪽만 실패하지" 로 혼란스럽다.

## What works

스위트 시드 SQL에 임시 DDL을 추가한다:

```sql
create table if not exists public.mcp_python_code (
    id           uuid primary key default gen_random_uuid(),
    proc_def_id  text not null,
    activity_id  text not null,
    tenant_id    text not null,
    compensation text,
    created_at   timestamp with time zone default now(),
    updated_at   timestamp with time zone default now()
);
grant all on public.mcp_python_code to anon, authenticated, service_role, supabase_admin;
notify pgrst, 'reload schema';
```

`notify pgrst, 'reload schema'` 는 이미 떠 있는 PostgREST가 새 테이블을 인식하게 한다. 시드 후 즉시 효과 발생.

근본 해결: infra 또는 completion 서비스 자체 마이그레이션에 정식 DDL을 추가하고, 그 후 시드의 임시 DDL을 제거.

## Why

`mcp_python_code` 는 completion 서비스 런타임에서 보상(undo) Python 코드를 cache하기 위해 도입된 테이블인데, repository 차원의 init.sql/마이그레이션에 반영되지 않은 채 코드만 머지되었다. 보상 처리를 실행하지 않는 일반적 흐름에서는 드러나지 않다가, rework 처럼 `generate_compensation` 을 명시적으로 호출하는 경로에서만 폭발한다.

## How to apply

- Triggered when:
  - rework-complete, compensation, 또는 보상 처리 관련 새 E2E 스위트가 500으로 실패하고 detail에 `mcp_python_code` 가 등장.
  - 또는 completion 컨테이너 로그에 `relation "public.mcp_python_code" does not exist` 가 보임.
- Skip if:
  - 이미 infra 마이그레이션이 갱신되어 `mcp_python_code` 가 존재하는 환경.

Related: [[coverage-py-usr2-flush]], [[completion-coverage-override-workdir]]
