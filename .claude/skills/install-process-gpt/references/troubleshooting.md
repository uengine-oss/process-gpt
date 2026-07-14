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
| 17 | Docker VM 디스크 부족 중 pull → 이후 `content digest ... not found` / `apply layer error` (nginx, deepagents 등), kong이 `Cannot mkdir /tmp/resty_...: No space left on device`로 unhealthy | Docker Desktop VM 디스크 풀 상태에서 pull이 진행되며 containerd content store가 손상 → 아래 상세 |
| 18 | `no matching manifest for linux/arm64/v8` 또는 compose가 pull 대신 "Building"으로 전환 후 `unable to prepare context: ... no such file or directory` | 일부 이미지(`process-gpt-base-agent-langchain-react`, `process-gpt-glossary-backend`, `process-gpt-deepagents`, `process-gpt-office-mcp` 등)가 amd64 전용이라 Apple Silicon에서 자동 pull 실패 → compose가 `build:`로 폴백하는데 서브모듈 미체크아웃이라 재실패 → 아래 상세 |

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

### #17 Docker VM 디스크 부족 → containerd content store 손상

증상 진행 순서: `docker system df`로 여유 없음 확인 → kong이 `/tmp` mkdir 실패로
unhealthy(일시적, 재시작하면 회복되기도 함) → 이후 다른 이미지를 pull/기동할 때
`content digest sha256:... not found` 또는 `apply layer error ...: NotFound:
failed to get reader from content store`로 컨테이너 생성 자체가 실패. 디스크가
부족한 동안 받아지던 레이어가 일부만 기록되어 이미지 메타데이터가 로컬에는
남아있지만(예: `docker inspect <image>`의 `RootFS.Layers`가 비어있거나 실제
blob이 없음) 실체가 없는 상태가 된 것.

```bash
# 1) Docker VM 실디스크 여유공간 확인 (호스트 df -h가 아니라 VM 내부 기준)
docker run --rm busybox df -h /

# 2) 안전한 정리부터: 미사용 dangling 이미지 (실행/중지 컨테이너에는 영향 없음)
docker image prune -f
docker system df   # 회복량 확인, 그래도 여유공간 <10GB면 더 정리하거나
                    # Docker Desktop 설정에서 디스크 이미지 크기를 늘린다

# 3) kong 등 헬스체크 실패 컨테이너는 재시작만으로 회복되기도 함
docker restart supabase-kong

# 4) 특정 이미지가 "content digest not found"/"apply layer error"로 계속
#    실패하면 해당 이미지만 완전 삭제 후 재pull (재태그 없이 digest 기준으로
#    받으면 content store 캐시 재사용으로 인한 재발을 피할 수 있다)
docker rmi -f <image>:<tag>
docker pull --platform linux/amd64 <image>@<sha256-digest>   # docker manifest inspect로 digest 확인
docker tag <image>@<sha256-digest> <image>:<tag>
```

무관한 프로젝트(다른 앱의 exited 컨테이너 등)를 정리하는 것은 파괴적 조치이므로
사용자 승인 없이 임의 삭제하지 않는다 — dangling 이미지 prune만 승인 없이도 안전.

### #18 amd64 전용 이미지 — Apple Silicon에서 pull 실패 → build 폴백까지 실패

`docker-compose.yml`의 서비스 대부분은 `image:`와 `build:`를 동시에 갖고
있어서, 태그된 이미지가 있으면 pull만 하고 build는 건드리지 않는다. 문제는
일부 이미지가 amd64 매니페스트만 갖고 있어(`docker manifest inspect
<image>`로 `platform.architecture` 확인) arm64 호스트에서 plain
`docker pull`/`docker compose up`이 "no matching manifest" 로 즉시 실패하고,
Docker Compose가 이를 "이미지가 없다"고 판단해 `build:`로 자동 전환하는데,
`process-gpt-infra-docker`는 서브모듈을 초기화하지 않은 상태가 기본이라
`services/<name>/Dockerfile`이 없어 build도 즉시 실패한다.

```bash
# 실패한 서비스명은 compose 로그의 "Building"/"no matching manifest" 줄에서 확인.
# 확인된 사례: base-agent-langchain-react, glossary-backend, deepagents, office-mcp
# (버전이 바뀌면 다른 서비스도 해당될 수 있음 — 증상이 같으면 동일하게 처리)

docker pull --platform linux/amd64 ghcr.io/uengine-oss/<image>:<tag>
# 위가 매니페스트 자체 문제로 실패하면 amd64용 하위 digest를 직접 지정:
docker manifest inspect ghcr.io/uengine-oss/<image>:<tag>   # architecture:amd64 항목의 digest 확인
docker pull --platform linux/amd64 ghcr.io/uengine-oss/<image>@sha256:<amd64-digest>
docker tag ghcr.io/uengine-oss/<image>@sha256:<amd64-digest> ghcr.io/uengine-oss/<image>:<tag>

# 필요한 이미지를 모두 로컬에 채운 뒤 start-all-services.sh를 재실행하면
# compose가 로컬 이미지를 그대로 쓰고 build를 시도하지 않는다.
```

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
