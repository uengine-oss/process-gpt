# 설치 검증 체크리스트

설치 직후 데모 전에 순서대로 수행한다. `BASE=http://localhost:8088`,
`KONG=http://localhost:54321` (원격 설치면 호스트 치환 — tenant_id도 그 호스트명!).

## 1. 컨테이너 상태

`process-gpt-infra-docker` 레포 루트에서(단일 `docker-compose.yml`):

```bash
docker compose --env-file .env ps -a --format '{{.Service}}\t{{.State}}\t{{.Status}}'
```

- 선택한 프로파일의 서비스가 모두 `running`인지. `restarting`/`exited`는 로그
  확인 후 troubleshooting.md 대조.
- unhealthy 허용 목록: litellm-proxy(LLM 직결 시).

## 2. 엔드포인트 순회

```bash
curl -sf -o /dev/null -w '%{http_code}\n' $BASE/                                  # 200 (SPA)
curl -sf $BASE/completion/langchain-chat/sanity-check                             # {"is_sanity_check":true}
curl -sf $KONG/auth/v1/health -H "apikey: $ANON_KEY"                              # GoTrue OK
curl -sf -o /dev/null -w '%{http_code}\n' $KONG/rest/v1/ -H "apikey: $ANON_KEY"   # 200
curl -sf http://localhost:8008/health          # base-agent (기동한 경우)
curl -sf http://localhost:8005/                # memento (기동한 경우, 404여도 응답이면 OK)
```

Studio http://localhost:3001 접속 → 테이블 목록이 보이면 DB/meta 정상.

## 3. DB 스키마 정합 (구버전 이미지 대비 선제 점검)

```bash
PGPW=$(grep -E '^POSTGRES_PASSWORD=' .env | cut -d= -f2-)
PSQL(){ docker exec -e PGPASSWORD="$PGPW" supabase-db psql -U supabase_admin -d postgres -tAc "$1"; }

PSQL "select count(*) from information_schema.columns where table_name='chat_rooms' and column_name='context';"   # 1이어야 함
PSQL "select count(*) from information_schema.columns where table_name='proc_def' and column_name='agent_id';"    # 1이어야 함
```

0이면 troubleshooting #13/#16-b 레시피로 컬럼 추가 + `notify pgrst, 'reload schema';`

## 4. 계정 준비 (데모용 — 고정 계정)

매번 새로 회원가입하지 말고 **항상 아래 고정 계정**을 쓴다 — Playwright
데모 스크립트(demo-playwright.md)와 트러블슈팅 레시피 전부 이 계정을
전제로 작성돼 있다. 로컬 개발(`localhost:8088`) 기준:

- 이메일: `demo@localhost` (tenant_id가 `localhost`여야 하므로 — troubleshooting #12 —
  이메일 로컬파트만 봐도 어느 테넌트인지 바로 알 수 있게 이 패턴을 쓴다)
- 비밀번호: `Demo1234!`
- 역할: `superAdmin` / `is_admin=true`

원격/다른 호스트에 설치했다면 이메일의 `@` 뒷부분만 접속 호스트명으로
바꾼다(예: `demo@my-server.local`) — tenant_id 규칙(#12)과 동일.

**idempotent 생성 스크립트** (이미 있으면 조용히 건너뛰고, 없으면
Admin API로 즉시 이메일 확인 상태로 생성 — UI 회원가입+메일확인 절차를
전부 우회):
```bash
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

# 2) JWT 테넌트 클레임 + public.users/tenants 매핑 (troubleshooting #12/#13과 동일 패턴, 멱등)
PSQL "update auth.users set raw_app_meta_data = coalesce(raw_app_meta_data,'{}'::jsonb) || '{\"tenant_id\":\"$DEMO_TENANT\"}'::jsonb where id='$AUTH_UID';"
PSQL "insert into public.tenants (id, owner) values ('$DEMO_TENANT', '$AUTH_UID') on conflict (id) do update set owner='$AUTH_UID';"
PSQL "insert into public.users (id, email, username, is_admin, role, tenant_id) values ('$AUTH_UID','$DEMO_EMAIL','demo',true,'superAdmin','$DEMO_TENANT') on conflict (id, tenant_id) do update set role='superAdmin', is_admin=true;"
# 주의: public.users의 PK는 (id, tenant_id) 복합키다 — on conflict (id)만 쓰면
# "no unique or exclusion constraint matching" 에러가 난다(직접 재현/확인함).
```
재실행해도 안전하다(계정이 이미 있으면 `AUTH_UID` 조회만 하고 2단계는
UPSERT라 값만 맞춰준다) — 매 설치 때마다 껐다 켜도 같은 계정/같은
비밀번호로 로그인된다.

1. 로그인 실패 시 troubleshooting #12(테넌트) → #11(메일확인) 순으로 점검.
2. 채팅 전 JWT 클레임 확인:
   ```bash
   PSQL "select raw_app_meta_data->>'tenant_id' from auth.users where email='demo@localhost';"
   ```
   비어 있으면 위 2단계를 재실행 후 **재로그인**.

## 5. nginx 라우트 존재 확인

`process-gpt-infra-docker` 레포 루트에서:

```bash
grep -c 'location /completion/' nginx/nginx.conf   # 1 이상
grep -c 'agent/chat/stream' nginx/nginx.conf       # 1 이상
```

## 통과 기준

위 1–5가 모두 녹색이면 "설치 검증 통과"로 보고하고 Playwright 데모
(demo-playwright.md)를 제안한다.
