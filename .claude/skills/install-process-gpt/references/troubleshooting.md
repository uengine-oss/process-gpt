# 트러블슈팅 플레이북

실전 설치(INSTALL_MEMORY.md)에서 겪은 이슈의 증상→원인→해결 색인.
새 이슈를 해결하면 여기와 레포 루트 INSTALL_MEMORY.md에 모두 추가할 것.

## 증상별 빠른 색인

| # | 증상 | 원인 한줄 |
|---|---|---|
| 1 | `git submodule update --init --recursive` 실패 "No url found ... .claude/worktrees" | 중첩 worktree 잔재를 서브모듈로 오인 → `--recursive` 빼고 실행 |
| 2 | `./start-all-services.sh` exit 126 permission denied | 실행비트 없음 → `chmod +x` |
| 3 | `compose pull` 중 `denied` 로 전체 중단 | GHCR private 이미지 + 미로그인 → 로그인하거나 `up -d --pull never` |
| 4/7 | 포트 bind 실패 (8010, 8021 등) | 다른 컨테이너/프로세스 선점 → `lsof -nP -iTCP:<port>`, kind 클러스터·root 프로세스 확인, 안 되면 compose ports remap |
| 5 | `Conflict. The container name "/supabase-imgproxy" is already in use` | 옛 compose 프로젝트 잔재가 고정 container_name 선점 → `docker rm -f <이름들>` (사용자 승인) |
| 6 | platform linux/amd64 ≠ arm64 경고 | Apple Silicon 에뮬레이션 — 경고일 뿐 동작함. 성능·메모리 오버헤드 유의 |
| 8 | litellm-proxy unhealthy | model_list 빈 값 → LLM 직결 구성이면 우회되므로 무해 |
| 9 | LLM 호출 무응답/에러 | .env가 placeholder(dream-flow) → 실제 키·URL로 교체 후 관련 컨테이너 recreate |
| 10 | agent-feedback 크래시 "DB 연결 환경 변수" / office-mcp "OPENROUTER_API_KEY" | env 누락 → office-mcp는 compose에 `LLM_PROVIDER: openai` 추가. mcp-proxy는 K8s 전용이라 로컬 무시 |
| 11 | 가입 후 확인 메일 안 옴 → 로그인 불가 | SMTP 미설정 + autoconfirm=false → dev는 `ENABLE_EMAIL_AUTOCONFIRM=true` + auth recreate; 기가입자는 `update auth.users set email_confirmed_at=now() where email_confirmed_at is null;` |
| 12 | 로그인 시 "가입된 이메일주소가 아닙니다" | `public.users`에 (email, tenant_id=접속호스트) 행이 없음 → 아래 상세 |
| 13 | 메인 채팅 무반응, `chat_rooms` 400 | JWT에 `app_metadata.tenant_id` 없음(RLS 위반) + `chat_rooms.context` 컬럼 누락 → 아래 상세 |
| 13-b | "생각 중..."에서 멈춤, 답변 미렌더 | nginx `/completion/*` 라우트 부재로 sanity-check가 HTML 수신 → prefix-strip 라우트 추가; 근본은 프론트·nginx·서비스 버전 불일치 |
| 14 | postgres 반복 크래시 "recovery mode", auth 500 | Docker VM 메모리 고갈(OOM) → 무관 컨테이너 정리, Docker 메모리 상향(24GB+), 무거운 옵션 서비스 중지 |
| 15 | 프론트가 "옛날 버전" | compose frontend는 pull 이미지 사용 → 소스 빌드 `docker build -t process-gpt-frontend:local services/frontend` 후 image 교체 |
| 16 | dev 서버 충돌 (5173, :8000) | 다른 vite/python 프로젝트 선점 → `--port 5199 --strictPort`, vite 프록시 타깃을 :8088(nginx)로 |

## 상세 레시피

### #12 로그인 "가입된 이메일주소가 아닙니다" — 테넌트 불일치

프론트 `signIn`은 로그인 전에 `public.users`를
`{email, tenant_id: 접속호스트명}`으로 조회한다. `localhost:8088` 접속이면
tenant는 **`localhost`** 여야 한다.

```sql
-- auth uid 확인: select id from auth.users where email='<email>';
insert into public.users (id, email, username, is_admin, role, tenant_id)
values ('<auth-uid>', '<email>', '<name>', true, 'superAdmin', '<접속호스트>')
on conflict (id) do update set tenant_id='<접속호스트>', role='superAdmin', is_admin=true;

insert into public.tenants (id, owner) values ('<접속호스트>', '<auth-uid>')
on conflict (id) do update set owner='<auth-uid>';
```

### #13 채팅 무반응 — JWT 테넌트 클레임 + 스키마 컬럼

```sql
-- 1) RLS용 JWT 클레임 주입 (적용 후 재로그인 필요)
update auth.users
  set raw_app_meta_data = coalesce(raw_app_meta_data,'{}'::jsonb)
      || '{"tenant_id":"<접속호스트>"}'::jsonb
  where id='<auth-uid>';

-- 2) 스키마 구버전 컬럼 보정 (PGRST204 에러 시)
alter table public.chat_rooms add column if not exists context jsonb;
alter table public.proc_def  add column if not exists agent_id text;
notify pgrst, 'reload schema';
```

원래는 로그인 후 `POST /completion/set-tenant`가 클레임을 자동 세팅한다 —
이게 405/404면 #13-b의 nginx 라우트 문제.

### #13-b nginx `/completion/*` prefix-strip 라우트

프론트는 completion 호출에 전부 `/completion` prefix를 붙인다. nginx에 다음이
있어야 한다 (치환이 아니라 **strip**):

```nginx
location /completion/ {
  set $u completion:8000;
  rewrite ^/completion/(.*)$ /$1 break;
  proxy_pass http://$u;
  proxy_http_version 1.1; proxy_buffering off; proxy_read_timeout 3600s;
}
```

macOS에서 nginx.conf 수정 후에는 `nginx -s reload`가 아니라
`docker restart process-gpt-nginx` (바인드마운트 동기화 이슈).

현재 레포 gateway/nginx/nginx.conf에는 이 라우트가 반영되어 있다 — 새 설치에서
증상이 재발하면 이미지/설정 버전 불일치를 의심하고 라우트 존재부터 grep.

### DB 접속 원라이너

```bash
PGPW=$(grep -E '^POSTGRES_PASSWORD=' .env | cut -d= -f2-)
docker exec -e PGPASSWORD="$PGPW" supabase-db psql -U supabase_admin -d postgres -c "<SQL>"
```

### 컨테이너 이름 충돌 탐지 (#5)

```bash
docker ps -a --format '{{.Names}}\t{{.Label "com.docker.compose.project"}}'
# project 라벨이 비었거나 다른 프로젝트인데 supabase-*/neo4j/deepagents 이름을
# 쥐고 있으면 충돌 → 사용자 승인 후 docker rm -f
```

## 설계상 정상인 것들 (버그 아님)

- `agent-router/route` 503: 로컬 nginx가 의도적으로 503 반환 → 프론트 폴백 사용.
- litellm-proxy unhealthy: LLM 직결 구성에서는 우회되므로 무해.
- 프로세스 생성 후 `proc_def` 0건: 자동저장 안 함(보안 정책) — 사용자가 저장
  버튼을 눌러야 영속화.
- mcp-proxy 크래시(로컬): kubeconfig 요구 — K8s 전용 서비스.
