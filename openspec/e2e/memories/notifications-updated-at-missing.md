---
name: notifications-updated-at-missing
description: init.sql 의 notifications 테이블에 updated_at 컬럼이 없는데 fcm_service / 다른 워커는 update 시 updated_at 를 항상 동봉함. 새 E2E 환경에서는 시드로 ALTER ADD COLUMN 한 뒤 PostgREST 를 재시작해 schema cache 를 새로 고쳐야 함.
applies-to:
  - completion-fcm-service
  - completion-polling
  - supabase-postgrest
  - notifications-table
last-verified: 2026-05-27
metadata:
  type: pitfall
---

# notifications 테이블에 updated_at 컬럼이 없음

새로 `docker-compose.e2e.yml` 로 db 를 부팅하면 `init.sql` 의
`public.notifications` 정의에 `updated_at` 컬럼이 없습니다. 그런데
`services/completion/fcm_service/database.py:fetch_unprocessed_notifications`
는 배치/개별 update 시 항상 `{'consumer': pod_id, 'updated_at': now}` 를
보내서 PostgREST 가 `PGRST204 Could not find the 'updated_at' column of
'notifications' in the schema cache` 로 거부합니다. 결과적으로 폴링
워커가 어떤 알림도 클레임하지 못하고 FCM 도 발송되지 않습니다.

(운영/스테이징은 migration_script 가 이 컬럼을 추가했을 가능성이
높지만 init.sql 단독 부팅에서는 누락됨.)

## What works

E2E 시드 파일 최상단에서 멱등 ALTER 로 보강:

```sql
ALTER TABLE public.notifications
    ADD COLUMN IF NOT EXISTS updated_at timestamp with time zone NULL DEFAULT now();
```

그리고 `db-seed-*` 가 ALTER 한 뒤에는 PostgREST 가 캐시한 스키마가
오래된 상태이므로, `fcm-service` (또는 다른 supabase-py 컨슈머) 가
실제로 update 를 발행하기 전에 **rest 컨테이너를 재시작** 합니다.

```bash
docker compose -f docker-compose.e2e.yml restart rest fcm-service
```

대안: PostgREST 에 `NOTIFY pgrst, 'reload schema'` 를 보내거나, kong/rest
설정에서 schema reload 엔드포인트를 호출할 수도 있지만 컨테이너 재시작이
가장 단순합니다.

## Why

- PostgREST 는 부팅 시점에 테이블 스키마를 캐시하며, 새로 추가된 컬럼은
  자동으로 인식되지 않습니다.
- supabase-py 의 `.update({...})` 는 fields 를 그대로 PostgREST 에
  올려보내므로 캐시에 없는 컬럼은 `PGRST204` 로 거부됩니다.
- 코드 쪽 fix (updated_at 를 보내지 않음) 는 별도 PR 영역. E2E 워크플로는
  운영과 동일한 코드를 검증해야 하므로 시드로 컬럼을 보강하는 방향이
  안전합니다.

## How to apply

- Triggered when:
  - 폴링 워커 로그에 `Could not find the 'updated_at' column of
    'notifications' in the schema cache` 가 반복적으로 나타날 때
  - `notifications.consumer` 가 시드 후에도 NULL 로 유지될 때
- Skip if:
  - 이미 운영용 migration 으로 컬럼이 추가되어 있는 환경 (`\d notifications`
    출력에 컬럼이 보임)
  - PostgREST 재시작 없이도 schema 가 최신인 환경 (NOTIFY 로 reload 한 경우)

Related: [[playwright-node-modules-junction]]
