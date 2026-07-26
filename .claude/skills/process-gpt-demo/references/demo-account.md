# 고정 데모 계정

모든 데모 시나리오는 매번 새로 회원가입하지 않고 **항상 아래 고정 계정**을
쓴다. 로컬 개발(`localhost:8088`) 기준:

- 이메일: `demo@localhost` (tenant_id가 `localhost`여야 하므로 — 이메일
  로컬파트만 봐도 어느 테넌트인지 바로 알 수 있게 이 패턴을 쓴다)
- 비밀번호: `Demo1234!`
- 역할: `superAdmin` / `is_admin=true`

원격/다른 호스트에 설치했다면 이메일의 `@` 뒷부분만 접속 호스트명으로
바꾼다(예: `demo@my-server.local`) — tenant_id는 접속 호스트명과 반드시
일치해야 한다.

## idempotent 생성 스크립트

이미 있으면 조용히 건너뛰고, 없으면 Admin API로 즉시 이메일 확인 상태로
생성한다(UI 회원가입+메일확인 절차를 전부 우회). 재실행해도 안전하다.

```bash
BASE=http://localhost:8088
KONG=http://localhost:54321
cd /path/to/process-gpt-infra-docker   # .env가 있는 레포 루트
PGPW=$(grep -E '^POSTGRES_PASSWORD=' .env | cut -d= -f2-)
PSQL(){ docker exec -e PGPASSWORD="$PGPW" supabase-db psql -U supabase_admin -d postgres -tAc "$1"; }

SERVICE_ROLE_KEY=$(grep -E '^SERVICE_ROLE_KEY=' .env | cut -d= -f2-)
DEMO_EMAIL="demo@localhost"
DEMO_PW="Demo1234!"
DEMO_TENANT="localhost"

# 1) auth.users에 없으면 Admin API로 생성 (email_confirm=true → 메일확인 스킵)
AUTH_UID=$(PSQL "select id from auth.users where email='$DEMO_EMAIL';")
if [ -z "$AUTH_UID" ]; then
  RESP=$(curl -s -X POST "$KONG/auth/v1/admin/users" \
    -H "apikey: $SERVICE_ROLE_KEY" -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$DEMO_EMAIL\",\"password\":\"$DEMO_PW\",\"email_confirm\":true}")
  AUTH_UID=$(echo "$RESP" | python3 -c "import json,sys; print(json.load(sys.stdin).get('id',''))")
fi

# 2) JWT 테넌트 클레임 + public.users/tenants 매핑 (멱등)
PSQL "update auth.users set raw_app_meta_data = coalesce(raw_app_meta_data,'{}'::jsonb) || '{\"tenant_id\":\"$DEMO_TENANT\"}'::jsonb where id='$AUTH_UID';"
PSQL "insert into public.tenants (id, owner) values ('$DEMO_TENANT', '$AUTH_UID') on conflict (id) do update set owner='$AUTH_UID';"
PSQL "insert into public.users (id, email, username, is_admin, role, tenant_id) values ('$AUTH_UID','$DEMO_EMAIL','demo',true,'superAdmin','$DEMO_TENANT') on conflict (id, tenant_id) do update set role='superAdmin', is_admin=true;"
# 주의: public.users의 PK는 (id, tenant_id) 복합키다 — on conflict (id)만 쓰면
# "no unique or exclusion constraint matching" 에러가 난다(직접 재현/확인함).
```

## Playwright 로그인 스니펫

루트(`/`)는 이제 별도의 마케팅 랜딩 페이지라 앱 화면이 아니다 — 항상
`/auth/login`으로 직접 이동한다. 이 페이지는 백그라운드 활동이 계속 있어
`waitUntil: 'networkidle'`이 타임아웃되거나 불안정하게 동작하므로
`waitUntil: 'load'` + 명시적 `waitForSelector`를 쓴다.

```javascript
await page.goto('http://localhost:8088/auth/login', { waitUntil: 'load', timeout: 30000 });
await page.waitForSelector('input[type="text"]', { timeout: 15000 });
await page.locator('input[type="text"]').first().fill('demo@localhost');
await page.locator('input[type="password"]').first().fill('Demo1234!');
await page.locator('button:has-text("로그인")').click();
await page.waitForTimeout(3000);
```

## 참고

이 계정 설계와 idempotent 스크립트는 `process-gpt-install` 스킬의
`references/verification.md` §4에도 동일한 내용이 있다 — 두 스킬이
독립적으로 동작할 수 있도록 의도적으로 복제해뒀다. 계정 정책을 바꾸면
양쪽 다 갱신할 것.
