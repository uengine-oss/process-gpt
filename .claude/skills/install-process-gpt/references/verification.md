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

## 4. 계정 준비 (데모용)

1. `$BASE` 접속 → 회원가입 (dev면 autoconfirm으로 즉시 활성).
2. 로그인 실패 시 troubleshooting #12(테넌트) → #11(메일확인) 순으로 점검.
3. 채팅 전 JWT 클레임 확인:
   ```bash
   PSQL "select raw_app_meta_data->>'tenant_id' from auth.users where email='<email>';"
   ```
   비어 있으면 #13 레시피 주입 후 **재로그인**.

## 5. nginx 라우트 존재 확인

`process-gpt-infra-docker` 레포 루트에서:

```bash
grep -c 'location /completion/' nginx/nginx.conf   # 1 이상
grep -c 'agent/chat/stream' nginx/nginx.conf       # 1 이상
```

## 통과 기준

위 1–5가 모두 녹색이면 "설치 검증 통과"로 보고하고 Playwright 데모
(demo-playwright.md)를 제안한다.
