---
name: shared-auth-user-password-rotation
description: 여러 E2E 스위트가 같은 `e2e@uengine.org` Supabase auth 유저를 공유하므로, 다른 스위트가 비밀번호를 회전시킨 뒤 우리 스위트의 로그인이 갑자기 invalid_credentials 로 실패함. 매 실행 직전에 본 스위트의 seed 를 다시 적용해 비밀번호를 복구한다.
applies-to:
  - supabase-gotrue
  - shared-auth-user
  - e2e-seed
  - playwright-login
last-verified: 2026-05-27
metadata:
  type: pitfall
---

# 공유 e2e@uengine.org 사용자 비밀번호 회전

여러 OpenSpec E2E 스위트(`completion_agent-memory-chat`,
`completion_process-definition-search` 등)가 동일한 Supabase `auth.users` 행
(`id=11111111-1111-1111-1111-111111111111`, email=`e2e@uengine.org`)을 공유한다.
각 스위트의 `seed_files/e2e_seed.sql` 은 다음과 같이 비밀번호를 새로 설정한다:

```sql
on conflict (id) do update
  set encrypted_password = excluded.encrypted_password, ...
```

`encrypted_password = crypt('e2epassword', gen_salt('bf'))` 는 bcrypt salt 가
매번 새로 생성되므로 hash 값이 달라지지만 평문은 항상 `e2epassword` 다.
하지만 다른 스위트가 user_metadata 변경(`display_name = '갱신 사용자'` 등)
또는 비밀번호 회전을 수행한 직후에는 우리 스위트의 로그인 흐름이 즉시
`{"code":400,"error_code":"invalid_credentials"}` 로 실패하는 사례가 관찰됨.

가장 흔한 증상: Playwright 로그인 폼이 채워지고 `.cp-login` 클릭 후에도
URL 이 `/auth/login` 에서 벗어나지 않으며, 60~180 초 후 `not.toHaveURL`
타임아웃. 실제 Supabase REST 로 직접 password grant 를 호출하면 위 메시지가
반환됨.

## What works

각 실행(특히 coverage override 재기동 등 시간이 흐른 뒤 실행) 직전에 본
스위트의 db-seed 컨테이너를 다시 한 번 돌려 비밀번호를 평문 `e2epassword`
로 재고정한다:

```bash
docker compose -f docker-compose.e2e.yml run --rm db-seed-<our-suite>
# 즉시 검증
curl -s -X POST "http://localhost:54321/auth/v1/token?grant_type=password" \
  -H "apikey: $ANON_KEY" -H "Content-Type: application/json" \
  -d '{"email":"e2e@uengine.org","password":"e2epassword"}' \
  | jq -r '.access_token | .[0:20]'
```

`access_token` 이 반환되면 Playwright 재실행. 단순 재시도보다 훨씬 빠른
회복법이다.

## Why

- `auth.users` 행은 모든 스위트가 같은 PK 를 사용해 upsert 하므로 충돌 시
  마지막에 실행된 시드가 비밀번호 hash 를 결정한다.
- 평문이 동일하더라도, 다른 스위트가 의도치 않게 비밀번호 grant 흐름을
  변경(예: signInWithPassword 후 updatePassword)하면 hash 가 평문과 어긋날 수
  있다.
- 게다가 GoTrue 가 `failed_attempts` 카운터를 운영하므로, 짧은 시간 다수
  실패가 누적되면 일시적 잠금 가능성도 있다.

## How to apply

- Triggered when:
  - 직전까지 로그인 흐름이 정상이었다가 갑자기 `not.toHaveURL` 이 매번
    타임아웃되는 경우
  - 직접 Supabase password grant 가 `invalid_credentials` 로 응답하는 경우
- Skip if:
  - 본 스위트만 단독으로 돌리는 환경(다른 스위트가 같은 사용자 PK 를 건드릴
    가능성이 없음)
  - 매 실행마다 `docker compose down -v` 로 DB 자체를 초기화하는 워크플로

Related: [[nginx-overrides-x-forwarded-host]], [[playwright-node-modules-junction]]
