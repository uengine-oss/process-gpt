---
name: completion-bcrypt-seed-stability
description: Supabase auth.users 시드에서 `crypt('pw', gen_salt('bf'))` 를 그대로 두면 re-seed 시 가끔 GoTrue 가 인증 실패하는 케이스가 발생. 사전 계산된 bcrypt hash 를 시드에 embed 하는 것이 안전.
applies-to:
  - supabase
  - gotrue
  - e2e-seed
  - auth.users
last-verified: 2026-05-27
metadata:
  type: workaround
---

# auth.users seed: prefer precomputed bcrypt over gen_salt

E2E 시드의 일반적 패턴:

```sql
insert into auth.users (... encrypted_password ...) values (
    ..., crypt('mypw', gen_salt('bf')), ...
) on conflict (id) do update
    set encrypted_password = excluded.encrypted_password;
```

대부분 동작하지만, 같은 컨테이너 인스턴스에서 시드 SQL 을 여러 번 재실행하다 보면 종종 GoTrue
`/auth/v1/token?grant_type=password` 호출이 `{"code":400,"error_code":"invalid_credentials"}` 로 실패하는
순간이 관찰됨. `crypt('pw', encrypted_password) = encrypted_password` 비교가 `f` 를 반환.
한 번 더 시드를 돌리면 다시 정상으로 돌아오기도 함 → 안정성 낮음.

## What works

시드에 **사전 계산된 bcrypt hash 를 embed**:

```sql
insert into auth.users (..., encrypted_password, ...) values (
    ...,
    -- Precomputed bcrypt for 'ate-password'.
    '$2a$06$EdGznFMJOR.0cZcdULG5oOrfQ2hxYy3QZWY1Pp1rYjX9YH1SbC7oq',
    ...
) on conflict (id) do update set encrypted_password = excluded.encrypted_password;
```

Hash 는 한 번 생성해 두고 시드에 그대로 박는다. 비밀번호는 일반적 E2E 비밀번호(예: `'<email-prefix>-password'`)
면 충분. 보안이 필요한 시드가 아니므로 hash 노출은 문제 없음.

Hash 생성 (one-shot):
```sh
docker exec <db-container> psql -tA -U supabase_admin -d postgres \
  -c "select crypt('ate-password', gen_salt('bf'));"
```

## Why

- `crypt('pw', gen_salt('bf'))` 는 컨테이너에서 매 호출마다 다른 salt + hash 생성
- 같은 row 에 ON CONFLICT UPDATE 가 들어가도, GoTrue 가 캐시하거나 prior session 에 의해
  다른 hash 로 인증 시도하는 경우가 있어 보임 (정확한 원인은 GoTrue session 캐시 / shadow
  DB row 가능성)
- 사전 계산 hash 는 시드 재실행마다 동일 → 어떤 캐시 / shadow row 도 일치 보장

## How to apply

- Triggered when:
  - e2e_seed.sql 을 여러 번 재실행하는 중 GoTrue 인증이 invalid_credentials 로 실패
  - Playwright 로그인 테스트가 갑자기 실패하면서 화면에는 form 이 채워진 채 멈춰 있음
- Skip if:
  - 시드를 한 번만 실행하는 케이스 (drop-and-rebuild) 이고 인증 실패 관찰 없음

Related: [[playwright-node-modules-junction]]
