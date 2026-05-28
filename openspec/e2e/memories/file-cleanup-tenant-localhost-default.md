---
name: file-cleanup-tenant-localhost-default
description: services/completion/polling_service/file_cleanup_service.py 의 cleanup_completed_process_files 는 subdomain_var=='localhost' 일 때 fetch_completed_process_instances 에 tenant_id=None 을 넘기지만, 그 함수가 다시 'localhost' 로 fallback 하므로 시드 tenant_id 가 'localhost' 가 아니면 인스턴스를 절대 못 찾는다.
applies-to:
  - completion-polling
  - file_cleanup_service
  - bpm_proc_inst
  - subdomain_var
last-verified: 2026-05-27
metadata:
  type: pitfall
---

# file_cleanup_service tenant filter 가 항상 'localhost' 로 fallback

`services/completion/polling_service/file_cleanup_service.py` 의
`cleanup_completed_process_files()` 는 다음과 같이 시작한다:

```python
tenant_id = subdomain_var.get() if subdomain_var.get() != 'localhost' else None
completed_instances = fetch_completed_process_instances(tenant_id)
```

겉으로는 "localhost 면 tenant 필터링을 끈다" 처럼 보이지만,
`fetch_completed_process_instances` 의 첫 줄은:

```python
if not tenant_id:
    tenant_id = subdomain_var.get()  # 'localhost'
result = supabase.table('bpm_proc_inst').select(...).eq('tenant_id', tenant_id)...
```

따라서 워커가 기본 컨텍스트에서 실행되면 SQL 은 **항상 `tenant_id='localhost'`** 로
필터링된다. E2E 시드에서 `tenant_id='e2e-something'` 처럼 의미 있는 이름을
넣으면 워커 로그에 `No completed process instances found` 만 찍히고 행복
경로가 한 번도 실행되지 않는다.

## What works

- E2E 시드의 `tenants.id` 와 `bpm_proc_inst.tenant_id` 를 **모두 `'localhost'`** 로
  맞춘다. 시드 SQL 예:

```sql
INSERT INTO public.tenants (id, owner) VALUES ('localhost', null)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.bpm_proc_inst (..., tenant_id, ...) VALUES (..., 'localhost', ...);
```

- 대안으로 워커 컨테이너에서 `subdomain_var.set(...)` 를 호출하는 별도
  엔트리포인트를 만들 수 있지만, 본 정리 작업은 HTTP 요청 컨텍스트가 없는
  asyncio 루프이므로 ContextVar 를 따로 set 해줘야 하며 추가 복잡도가 든다.
  단일 테넌트 회귀라면 시드 쪽을 'localhost' 로 맞추는 게 가장 간단하다.

## Why

- 운영 환경에서는 FastAPI 미들웨어가 Subdomain 헤더로 `subdomain_var.set(...)`
  를 채우지만, 폴링 워커는 그 미들웨어를 거치지 않는다.
- 함수 시그니처의 fallback 두 번이 서로 다른 방향(상위 None → 하위 'localhost')
  으로 동작해 코드만 봐선 "None 이 전달되면 필터링이 꺼진다" 고 잘못
  읽기 쉽다.

## How to apply

- Triggered when:
  - completion polling 기반 E2E 에서 워커가 시드된 인스턴스를 못 찾고
    `No completed process instances found` 만 반복할 때
  - 다른 `*_polling_task` (예: stale consumer cleanup) 도 동일 패턴을 쓰므로
    동일 증상이 보이면 본 메모리를 먼저 점검
- Skip if:
  - 워커 진입점에서 명시적으로 `subdomain_var.set('your-tenant')` 를 호출하는 경우

Related: [[polling-mcp-processor-quirks]], [[coverage-py-usr2-flush]]
