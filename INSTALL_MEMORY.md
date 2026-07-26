# Process-GPT 설치/기동 기록 (INSTALL_MEMORY)

> 로컬(macOS, Apple Silicon) 개발기에 Process-GPT 전체 스택을 Docker Compose로
> 기동하면서 겪은 문제와 해결책을 시간 순으로 기록. 이후 작업도 계속 여기에 추가.

> **참고**: compose 설치 파일은 이후
> [process-gpt-infra-docker](https://github.com/uengine-oss/process-gpt-infra-docker)
> 레포로 이전되었다. 아래 기록은 이전 `docker-compose.yml` + `infra/` + `compose/`
> + `gateway/` 4계층 구조 기준이며, 컨테이너명/증상 진단 등은 여전히 참고 가치가
> 있지만 파일 경로는 새 레포 기준으로 다시 확인해야 한다.

- 환경: macOS (darwin 25.0), Apple Silicon(arm64), Docker Desktop
- 레포: `/Users/uengine/process-gpt` (main 브랜치, 서브모듈 다수)
- 기동 스크립트: `./start-all-services.sh`
- compose 레이어: `docker-compose.yml` + `infra/` + `compose/` + `gateway/`
- 이미지: 대부분 `ghcr.io/uengine-oss/*` (private) + supabase/기타 public

---

## 1. 서브모듈 pull — nested worktree로 `--recursive` 실패

- **증상**: `git submodule update --init --recursive` 실행 시
  `fatal: No url found for submodule path 'services/bpmn-extractor/.claude/worktrees/...'`
- **원인**: `services/bpmn-extractor` 안에 `.claude/worktrees/dreamy-diffie-32f099`
  라는 중첩 git worktree 잔재가 있어 재귀 초기화가 그걸 서브모듈로 오인.
- **해결**: `--recursive` 없이 최상위 서브모듈만 각자 브랜치에서 pull.
  - 대부분 `main`, `services/deep-research`만 `master`.
  - 23개 서브모듈 전부 정상 pull (본체엔 영향 없음).
- **미정리**: 위 임시 worktree는 그대로 남아있음(정리해도 무방).

## 2. `start-all-services.sh` 실행 권한 없음

- **증상**: `./start-all-services.sh all` → exit 126, `permission denied`.
- **원인**: 파일 권한 `-rw-r--r--` (실행 비트 없음).
- **해결**: `chmod +x start-all-services.sh`.

## 3. `all` 모드의 `compose pull`이 private 이미지에서 `denied`

- **증상**: `all` 모드는 먼저 `compose pull`을 도는데
  `Error response from daemon: error from registry: denied` 로 전체 중단
  (`set -e`라 이후 단계 진행 안 됨 → 컨테이너 0개 기동).
- **원인**: `ghcr.io/uengine-oss/*` 패키지들이 **private**. 로컬 Docker에
  GHCR 로그인이 없어서 pull 단계에서 막힘.
- **해결**: **필요한 이미지가 전부 로컬에 이미 존재**했음.
  → pull을 건너뛰고 스크립트와 동일한 compose 구성으로 직접 기동:
  ```bash
  CF=(-f docker-compose.yml -f infra/docker-compose.yml -f compose/docker-compose.yml -f gateway/docker-compose.yml)
  docker compose --env-file .env "${CF[@]}" up -d --pull never <services...>
  ```
  `up -d`는 기본적으로 로컬에 없는 이미지만 pull하므로 private denial을 회피.
- **참고**: 이미지를 새로 받아야 하는 상황이면 GHCR 로그인 필요
  (`echo $GITHUB_PAT | docker login ghcr.io -u <user> --password-stdin`, PAT에 `read:packages`).

## 4. 포트 8010 충돌 — 기존 kind 클러스터

- **증상**: `polling-service`가 8010 바인드 실패.
- **원인**: 기존에 떠 있던 `rag-service-control-plane`(kind 클러스터)가
  `0.0.0.0:8010->30800` 매핑으로 점유.
- **해결**: `docker stop rag-service-control-plane` (사용자 승인 하에).

## 5. 고정 컨테이너명 충돌 — 2개월 전 옛 `docker-compose` 프로젝트 잔재

- **증상**: `Conflict. The container name "/supabase-imgproxy" is already in use...`
  (이후 `/deepagents` 등도 동일).
- **원인**: compose가 `container_name:`으로 고정 이름을 쓰는데
  (`supabase-*`, `neo4j`, `deepagents`, `litellm-*`), 예전 `docker-compose`
  프로젝트의 exited 컨테이너들이 같은 이름을 선점.
- **해결**: 충돌 컨테이너 제거:
  ```bash
  docker rm -f docker-compose-litellm-db-1 docker-compose-litellm-proxy-1 \
    neo4j realtime-dev.supabase-realtime supabase-analytics supabase-auth \
    supabase-db supabase-edge-functions supabase-imgproxy supabase-kong \
    supabase-meta supabase-rest supabase-storage supabase-studio deepagents
  ```
- **탐지 팁**: `docker ps -a --format '{{.Names}}\t{{.Label "com.docker.compose.project"}}'`
  로 다른 프로젝트/무프로젝트 컨테이너가 원하는 이름을 쥐고 있는지 확인.
  (standalone `docker run` 컨테이너는 project 라벨이 비어 있어 필터에서 놓치기 쉬움.)

## 6. 플랫폼 경고 amd64 vs arm64 (Apple Silicon)

- **증상**: `The requested image's platform (linux/amd64) does not match the
  detected host platform (linux/arm64/v8)`.
- **원인**: 이미지가 amd64 전용. Apple Silicon에서 에뮬레이션(Rosetta/qemu)으로 실행.
- **영향**: 경고일 뿐 기동은 됨. 다만 성능 저하 가능.

## 7. 포트 8021 점유 — 정체불명 root loopback 프로세스 (deepagents 미기동)

- **증상**: `deepagents` 기동 시
  `ports are not available: ... 0.0.0.0:8021 ... bind: address already in use`.
- **원인**: `netstat -an`에는 `127.0.0.1.8021 LISTEN`이 보이는데
  `lsof`로는 소유자가 안 보임 → **root 소유 loopback 리스너**. `sudo` 없이 식별 불가.
  (docker 컨테이너는 아님 — `docker ps -a | grep 8021` 무결과.)
- **상태**: **미해결(OPEN)**. deepagents만 이 포트에 막혀 있음.
- **해결 후보**:
  1. `sudo lsof -nP -iTCP:8021` 로 점유 프로세스 찾아 종료, 또는
  2. `compose/docker-compose.yml`의 deepagents `ports`를 `8022:8888`로 변경.

## 8. litellm-proxy unhealthy (기능엔 영향 없음)

- **증상**: `process-gpt-litellm-proxy`가 `running`이지만 `unhealthy`.
- **원인**: `infra/litellm_config.yaml`의 `model_list: []`(빈 목록, 모델은 DB 저장 방식)
  → `/health` 체크가 통과 못 함. 초기엔 upstream이 dream-flow였던 것도 겹침.
- **결론**: `LLM_PROXY_URL`을 OpenAI로 직결하도록 바꾼 뒤(항목 9),
  서비스들은 litellm-proxy를 우회 → **unhealthy여도 기능 영향 없음**.

## 9. `.env` placeholder / 커스텀 LLM 프록시 → 실제 OpenAI로 전환

- **증상**: `.env`가 커스텀 LLM 서버(dream-flow)를 향하고 placeholder 키(`dream-flow`)
  사용. 사용자가 실제 OpenAI 키(`sk-proj-...`) 제공.
- **조치** (사용자 선택: "실제 OpenAI로 전환"):
  - `OPENAI_API_KEY=sk-proj-...`
  - `LLM_MODEL=gpt-4.1` (기존 `openai/gpt-oss-120b`는 실제 OpenAI 모델 아님)
  - `LLM_PROXY_URL=https://api.openai.com/v1` (기존 dream-flow)
  - `LLM_PROXY_API_KEY=sk-proj-...`
  - `OPENAI_BASE_URL=https://api.openai.com/v1`
  - 변경 후 `docker compose ... up -d --pull never` 로 관련 컨테이너 recreate.
- **주의**: `.env`에 실제 시크릿이 들어가 있으므로 커밋/공유 금지.

## 10. 일부 서비스 크래시 — 포트가 아니라 설정/시크릿 문제

- `agent-feedback`: `knowledge_retriever.py`가 요구하는 **DB 연결 환경변수 미설정**
  → `ValueError: DB 연결 환경 변수가 설정되지 않았습니다`. (OPEN — 어떤 var명인지 추적 필요)
- `office-mcp`: 이미지 기본값 `LLM_PROVIDER=openrouter`인데 compose가 이 변수를 안 넘김
  → `OPENROUTER_API_KEY` 없다며 종료. (OPEN — compose env에 `LLM_PROVIDER: openai` 추가 필요)
- `mcp-proxy`: Kubernetes kubeconfig 필요(`/root/.kube/config` 없음).
  로컬 docker 단독 실행 대상이 아님 → **무시 가능**.

## 11. 회원가입 후 로그인 — 확인 메일 안 옴 (SMTP 미설정)

- **증상**: 가입은 되는데 확인 메일이 오지 않아 로그인 불가.
- **원인**: `.env`의 SMTP 값이 비어 있고(`SMTP_HOST=` 등),
  `ENABLE_EMAIL_AUTOCONFIRM=false` → GoTrue가 이메일 확인을 필수로 요구.
- **해결** (개발기용):
  - `.env` `ENABLE_EMAIL_AUTOCONFIRM=true` → auth 컨테이너 recreate
    (`GOTRUE_MAILER_AUTOCONFIRM=true`) → **이후 신규 가입은 메일 확인 없이 즉시 사용**.
  - 이미 가입된 미확인 계정은 DB에서 직접 확인 처리:
    ```sql
    update auth.users set email_confirmed_at = now() where email_confirmed_at is null;
    ```
- **운영 전환 시**: `ENABLE_EMAIL_AUTOCONFIRM=false`로 되돌리고 실제 SMTP 설정.

## 12. 로그인 "가입된 이메일 아님" — 앱 사용자 테이블(`public.users`) + 테넌트 불일치

- **증상**: auth는 통과했는데 로그인 시 "가입된 이메일주소가 아닙니다".
- **핵심 원인 (멀티테넌트 + 접속 호스트)**:
  프론트엔드 `signIn(t)`는 `signInWithPassword` **전에** `public.users`를
  `{email, tenant_id: window.$tenantName}`로 조회하고, 결과가 없으면
  `notRegisteredEmail`("가입된 이메일주소가 아닙니다") 에러를 냄.
  - `window.$tenantName`은 **접속 호스트에서 파생** — `http://localhost:8088`로
    접속하면 **`$tenantName === "localhost"`** (빌드 JS에 `window.$tenantName!=="localhost"`
    특수처리가 있는 것으로 확인).
  - 즉 로그인하려면 사용자의 `public.users.tenant_id`가 **`"localhost"`** 여야 함.
- **삽질 기록 (중요)**:
  1) 처음엔 `public.users`가 **0건**이라(가입 후처리가 메일확인 막힘으로 안 돎),
     레코드를 만들어야 했음. → auth uid와 동일 id로 insert.
  2) 이때 기존에 있던 `process-gpt` 테넌트를 보고 `tenant_id='process-gpt'`로 넣었는데
     **이게 오답**. localhost 접속의 `$tenantName`("localhost")과 안 맞아 여전히 실패.
  3) 빌드된 프론트 JS(`/opt/www/assets/index-*.js`)를 디컴파일/grep 해서
     `signIn` 로직과 `$tenantName` 파생을 확인 → `tenant_id`를 `'localhost'`로 교정.
- **최종 해결** (auth uid = `<auth.users.id>`):
  ```sql
  -- 1) 앱 사용자 레코드 (id는 auth uid와 동일)
  insert into public.users (id, email, username, is_admin, role, tenant_id)
  values ('<auth.users.id>', 'jyjang@uengine.org', 'jyjang', true, 'superAdmin', 'localhost')
  on conflict (id) do update set tenant_id='localhost', role='superAdmin', is_admin=true;
  -- 2) localhost 테넌트 생성 + owner 지정
  insert into public.tenants (id, owner) values ('localhost','<auth.users.id>')
    on conflict (id) do update set owner='<auth.users.id>';
  ```
  - `public.users`: `id`(uuid, auth uid와 동일)만 NOT NULL·default 없음.
    `tenant_id` 기본값은 `'process-gpt'`지만 **localhost 접속에선 반드시 `'localhost'`로**.
  - 검증: `set role anon; select ... where email=... and tenant_id='localhost';` 로
    앱과 동일 조회가 행을 반환하는지 확인(RLS `users_select_policy = USING(true)`라 anon도 조회 가능).
- **참고 — signIn 분기 요약** (빌드 JS 기준):
  - 사전조회 실패 → `notRegisteredEmail`
  - `signInWithPassword` 에러가 "Email not confirmed" → `emailNotConfirmed`
  - 그 외 에러 → `public.users`에 이메일 있으면 `wrongPassword`, 없으면 `wrongId`
- **후속 관찰 필요**: 신규 가입에서도 `public.users`가 자동 생성되는지,
  그때 `tenant_id`가 `$tenantName`(localhost)로 제대로 들어가는지 확인.
  (`setTenant(t)`가 `putObject("users",{...role:"superAdmin",tenant_id:t})`로 만드는 경로 존재.)

## 13. 메인 채팅 "휴가신청프로세스 만들어줘" 무반응 — chat_rooms RLS + JWT 테넌트 클레임

- **증상**: 메인 채팅(`/definition-map`의 textarea `#input-51`,
  placeholder "예: 휴가 신청 프로세스 만들어줘 …")에 입력해도 아무 반응 없음.
- **재현(Playwright)**: 로그인 → `/definition-map` → 메시지 전송 시
  `POST /rest/v1/chat_rooms` → **400** → `[Backend] 'putObject' threw ... error in putObject`
  → Vue 에러 → 채팅이 조용히 중단(AI/completion 단계까지 못 감).
- **근본 원인**: `public.chat_rooms` INSERT 정책이 `WITH CHECK (tenant_id = tenant_id())`,
  그리고 `tenant_id()` 함수는 **JWT의 `app_metadata.tenant_id`**를 읽음.
  사용자 `auth.users.raw_app_meta_data`에 `tenant_id`가 없어서 `tenant_id()`=null →
  RLS 위반(`new row violates row-level security policy`) → PostgREST 400.
  - psql 재현: JWT claims에 `app_metadata.tenant_id` 없으면 RLS 위반,
    있으면 `INSERT 0 1` 성공.
- **원래 자동 세팅돼야 하는 경로가 깨짐**: 프론트가 로그인 후
  `POST http://localhost:8088/completion/set-tenant` 로 app_metadata에 테넌트를
  넣어야 하는데 이게 **405 Method Not Allowed** → 자동 세팅 실패.
- **해결 1/2 — JWT 테넌트 클레임 주입**:
  ```sql
  update auth.users
    set raw_app_meta_data = coalesce(raw_app_meta_data,'{}'::jsonb) || '{"tenant_id":"localhost"}'::jsonb
    where id='<auth uid>';
  ```
  이후 **재로그인**하면 새 JWT에 `app_metadata.tenant_id=localhost`가 담김.
- **해결 2/2 — 진짜 원인은 `chat_rooms.context` 컬럼 누락(스키마 구버전)**:
  프론트가 채팅방 생성 시 `{id,name,participants,message,**context**}`를 보내는데
  DB `chat_rooms`에 `context`가 없어서 **PGRST204** (`Could not find the 'context' column`) → 400.
  ```sql
  alter table public.chat_rooms add column if not exists context jsonb;
  notify pgrst, 'reload schema';   -- PostgREST 스키마 캐시 리로드
  ```
  → 이후 Playwright 재현에서 `chat_rooms` **201 생성 성공**, Agent가 응답 시작("생각 중...").
- **검증(Playwright)**: 위 2개 적용 후 로그인→메인채팅→전송 시
  `chat_rooms 201` → `chats 201` → `agent-router/route 503(의도된 설계)` →
  `agent/chat/stream 200` 까지 진행. 백엔드(base-agent-langchain-react)에
  `/chat/stream` 직접 호출 시 **OpenAI(gpt-4.1)로 프로세스 컨설팅을 정상 토큰 스트리밍** 확인.

## 13-b. (OPEN) 채팅이 "생각 중..."에서 멈추고 AI 답변이 화면에 안 뜸

- **증상**: 위 수정 후 Agent가 "생각 중..." 말풍선까지는 뜨는데, 150초를 기다려도
  실제 답변으로 갱신되지 않음.
- **확인된 사실**:
  - 백엔드 `/chat/stream`은 정상 생성·스트리밍(직접 curl로 토큰 확인).
  - nginx `/agent/chat/stream`은 `proxy_buffering off`로 SSE 통과 정상(게이트웨이 경유 curl도 실시간 토큰 수신).
  - 브라우저도 유효 JWT+payload로 요청→200 수신.
  - **그러나 `public.chats`에 assistant 응답이 전혀 저장되지 않음**(row는 user 메시지 1건뿐).
  - `public.chats`는 `supabase_realtime` publication에 포함 → 프론트는 **Realtime로 chats 변경을 구독해 렌더**하는 구조.
  - 즉 **스트리밍된 AI 응답이 chats에 persist되지 않음 → Realtime 미발생 → UI 고착**.
- **연관 인프라 결함(가설/후속)**:
  - **`/autonomous` WebSocket 라우트가 nginx.conf에 아예 없음** → `ws://localhost:8088/autonomous`가
    기본 `location /`로 가서 200 반환 → WS 핸드셰이크 실패(101 업그레이드 안 됨).
    (nginx.conf에 `map $http_upgrade`/`Upgrade`/`autonomous` 설정 부재.)
  - `POST /completion/set-tenant` → **405** (nginx `= /completion/set-tenant` 라우팅 없음 or 메서드 불일치)
  - `POST /rest/v1/rpc/get_credit_balance` → **404** (`public.get_credit_balance(p_tenant_id)` 함수 없음; 힌트: `fetch_context_bundle`)
  - `configuration` 403(insert)/406/`org_chart_groups` 404 등
### 13-b 심층 추적 결과 (Playwright + 빌드 JS 디컴파일 + 백엔드 프로빙)

- **브라우저는 SSE 토큰을 정상 수신**함(fetch tee 로 확인: `STREAM DONE chunks=68`).
  백엔드 `/chat/stream`은 OpenAI(gpt-4.1)로 `tool_start→tool_end→token×N→done` 정상 스트리밍.
  nginx `/agent/chat/stream`도 `proxy_buffering off`로 실시간 통과. 프론트 SSE 파서(`ChatRoomPage`
  `sendMessageStream`)도 `type:token→onToken` 으로 맞음.
- **그런데 스트림 직후 프론트 콘솔에**:
  `Backend connection check failed: SyntaxError: Unexpected token '<', "<!DOCTYPE"... is not valid JSON`
  → `Failed to connect to the backend server for AI communication` → `Generator 에러` → 생성 중단.
- **근본 원인 = 게이트웨이 라우팅 누락(버전 불일치)**:
  프론트 `checkBackendConnection()`이 `${backendUrl}/sanity-check`(=`/completion/sanity-check`) 호출 →
  **nginx에 `/completion/` 라우트가 없어서**(오직 `/langchain-chat/`만 completion으로) `location /` 폴백 →
  SPA `index.html`(HTML) 반환 → `JSON.parse` 실패 → 연결 실패 판정 → Generator 중단.
  - completion 서비스 실제 경로: `sanity-check`=`/langchain-chat/sanity-check`(200 JSON),
    `set-tenant`=**root** `/set-tenant`(경로가 섞여 있음).
  - 프론트는 둘 다 `/completion/*`로 호출 → 3-way 불일치(프론트 `/completion/*` ↔ nginx `/langchain-chat/*` ↔ completion 혼합).
- **프론트의 실제 backendUrl (중요)**: 제너레이터 클래스의 `this.backendUrl="/completion/langchain-chat"`.
  즉 실제 호출은 **`/completion/langchain-chat/sanity-check`** 이고, set-tenant 는 `/completion/set-tenant`.
  → 프론트는 **모든 completion 호출에 `/completion` prefix**를 붙이고, completion 서비스는
    `/langchain-chat/*` 와 `/set-tenant`(root)에 마운트. 따라서 nginx는 **`/completion` prefix만 제거**하면 됨.
  - ⚠️ (첫 시도 오류) `/completion/*` → `/langchain-chat/*` 로 치환하면
    `/completion/langchain-chat/sanity-check` 가 `/langchain-chat/langchain-chat/sanity-check`(이중)→404 →
    "Failed to connect" 지속. **치환이 아니라 prefix strip 이어야 함.**
- **적용한 수정 (gateway/nginx/nginx.conf)** — `/completion/` prefix strip:
  ```nginx
  location /completion/ {
    set $u completion:8000;
    rewrite ^/completion/(.*)$ /$1 break;      # prefix STRIP (치환 아님!)
    proxy_pass http://$u;
    proxy_http_version 1.1; proxy_buffering off; proxy_read_timeout 3600s; ...
  }
  ```
  → `GET /completion/langchain-chat/sanity-check` **200 `{"is_sanity_check":true}`**,
    `POST /completion/set-tenant` **200** 확인. 자동 실행에서 `Backend connection check failed`/`Generator 에러` **0건**.
  → 수정 후 `chats`에 assistant 응답 저장 시작("프로세스 컨설팅을 시작합니다…").
  - ⚠️ macOS Docker 바인드마운트 동기화 이슈로 nginx.conf 편집 후 `nginx -s reload`가
    잘린 파일을 읽어 실패할 수 있음 → **`docker restart process-gpt-nginx`로 재적용**해야 함.
- **여전히 OPEN — 렌더/저장이 일관되지 않음**:
  수정 후에도 일부 대화는 assistant 응답이 안 뜨거나 "생각 중"에 멈춤(환경 flakiness + 잔여 불일치).
  남은 의심:
  - `ws://localhost:8088/autonomous` WS 라우트가 nginx에 없음(핸드셰이크 실패) — 실시간 갱신 경로.
  - `get_credit_balance(p_tenant_id)` RPC 404, `configuration` 403/406 등 잔여 API 불일치.
  - `agent-router/route`는 nginx가 의도적으로 `return 503` → 프론트 폴백 경로 사용(폴백에 렌더 레이스 의심).
- **결론/권장**: 이건 **프론트 이미지 ↔ 게이트웨이 nginx.conf ↔ completion/서비스 이미지의 버전 불일치**가
  누적된 문제. 엔드포인트별 nginx 패치는 두더지잡기 → **서브모듈 커밋/이미지 태그를 서로 호환되는 버전으로
  재정합**하는 것이 정공법. (프론트가 기대하는 라우팅 표: `/completion/*`, `/autonomous`(WS) 를
  nginx.conf 와 completion 라우트에 맞춰 정렬.)

## 14. supabase-db(postgres) 반복 크래시 — Docker VM 메모리 압박(OOM)

- **증상**: 부하(특히 `/definition-map` 로드 시 수십 개 REST 쿼리 폭주)만 주면
  postgres가 `the database system is in recovery mode`로 빠짐(크래시→자동 복구 반복).
  이 복구 창에 걸린 요청은 GoTrue `POST /auth/v1/token` **500**
  (`error finding user: unexpected EOF`, `Database error querying schema`) 등으로 실패.
- **원인**: Docker Desktop VM 총 15.6GB 중 **~90% 사용**, 37개 컨테이너 실행.
  amd64 이미지들을 arm64에서 에뮬레이션(항목 6)하며 메모리 오버헤드 큼.
  부하 시 VM 내부 Linux OOM 킬러가 postgres 백엔드를 kill → 크래시 복구.
  - 컨테이너 본체 restarts=0 (컨테이너가 아니라 postgres 프로세스 내부 크래시).
  - 크래시 유발 시그널 라인은 docker logs에 안 남음(OOM kill 특성).
- **가장 큰 메모리 점유**: process-gpt와 **무관한** `oda-canvas-control-plane`(kind 클러스터) **~3.2GB**,
  그 외 supabase-kong ~1.3GB, supabase-analytics(logflare) ~1.3GB.
- **해결 방향(택1/병행)**:
  1. 무관 컨테이너 중지: `docker stop oda-canvas-control-plane` (~3.2GB 확보) — **사용자 승인 필요**(포트충돌 아님).
  2. Docker Desktop 할당 메모리 상향(예: 24GB+).
  3. 채팅 테스트에 불필요한 무거운 옵션 서비스(analytics/logflare, browser-use 등) 중지.
- **상태**: **OPEN** — 승인/설정 대기.

## 15. 프론트엔드 — 도커 이미지 실행 vs 로컬 소스 빌드

- **어디서 실행되나**: compose `frontend` 서비스는 `image:`만 있고 `build:` 없음 →
  **레지스트리 pull 이미지를 그대로 실행**. 원래 `ghcr.io/uengine-oss/process-gpt:e343845`
  (빌드일 **2026-04-23**, 약 2.5개월 전 = "옛날 버전"의 정체). 로컬 서브모듈 소스는 런타임에 안 씀.
- **서브모듈 클론 중단**: `services/frontend` 작업트리가 비어 있었음(`.git` gitlink만).
  `.git/modules/services/frontend`에 저장소는 있으나 체크아웃이 중단된 상태.
  → `git fetch` 후 `git checkout main` + `git pull --ff-only`로 최신 `1487a435`까지 복원(42+ 파일).
- **소스 빌드(옵션 B) 적용**:
  - Dockerfile: `node:22-bullseye`에서 `npm install --legacy-peer-deps` → `npm run build`
    (`vue-tsc --noEmit && vite build`) → `sanghoon01/spa-http-server:v1`에 `dist`를 `/opt/www`로.
  - 런타임 env: `run.sh`가 컨테이너 env(`VITE_SUPABASE_URL` 등)를 `window._env_`로 index.html에 주입 →
    **compose env 설정 그대로 두고 이미지만 교체하면 됨**.
  - 빌드: `docker build -t process-gpt-frontend:local services/frontend` (npm install 2m + vite build, 성공).
  - compose `frontend.image`을 `process-gpt-frontend:local`로 변경 후 recreate.
  - 검증: 메인 에셋 해시 `index-7bcee2cf.js`(구) → `index-9aa2318e.js`(신)로 바뀜, UI 레이아웃도 갱신 확인.
    로그인 정상, `/completion/*`·`/agent/chat/stream` 정상, **연결/Generator 에러 0건**, `chat_rooms` 400 없음.
- **그래도 남는 것**: 최신 프론트로도 AI 응답이 일관되게 렌더/완성되지 않음(이번엔 "생각 중" 말풍선조차 없이
  user 메시지만 표시되는 케이스). 프론트만 최신이고 **DB 스키마·게이트웨이·다른 서비스 이미지들은 여전히
  옛/혼합 버전**이라 정합이 안 맞음. → 완전 해결하려면 completion/base-agent/기타 이미지·DB 마이그레이션도
  프론트와 호환되는 버전으로 함께 맞춰야 함(전체 버전 재정합).

## 16. 최신 프론트에서 휴가처리프로세스 자동생성 복구 (✅ 해결) — dev 모드 + 트리거 재배선

- **목표**: 최신 프론트 기준으로 "휴가신청 프로세스 만들어줘" → 프로세스 초안 자동생성이 되게.
- **원인 1 — 프론트가 생성 트리거를 제거함**:
  최신 프론트는 `ChatRoomPage.handleAgentDirectiveToolCalls`에서 레거시
  `start_process_consulting` 후처리를 제거하고 "백엔드가 직접 생성"하도록 바꿈. 그러나 배포된
  base-agent(work-assistant-agent, `v0.0.7`)는 **분류/컨설팅 텍스트만** 스트리밍하고 BPMN을
  server-side로 생성하지 않음 → 아무 프로세스도 안 생김.
  - **수정**: `ChatRoomPage.vue`의 `handleAgentDirectiveToolCalls`에 `start_process_consulting`
    감지 시 `switchToConsultingMode(originalMessage)` 호출을 되살림
    (WorkAssistantChatPanel.vue:923-948 과 동일 패턴). 생성기/저장 콜백(`ProcessConsultingGenerator`,
    `AIGenerator`, `onModelCreated`)은 그대로 남아 있어 재배선만으로 클라이언트 사이드 생성이 부활.
- **원인 2 — dev 서버 포트/프록시 충돌**:
  - **도커 이미지 빌드는 이터레이션이 느림(매번 ~3분)** → `npm run dev`(vite + HMR)가 훨씬 나음.
    단, 이 레포엔 vite dev 프록시(`vite.config.ts`)가 이미 있음: `/agent`→:8008, `/langchain-chat`→:8000,
    `/agent-router`→:8001, `/memento`→:8005. dev 에선 `AIGenerator.backendUrl` 이
    `import.meta.env.DEV` 분기로 **`/langchain-chat`** (프로덕션은 `/completion/langchain-chat`).
  - **포트 5173 충돌**: 사용자 머신에 다른 vite 프로젝트들이 동시 실행중
    (`process-gpt-all/ontology-studio`, "Deep Agent Excel Generator"). 5173을 뺏겨 내 서버가
    엉뚱한 앱을 서빙 → **전용 포트로 고정**: `npm run dev -- --port 5199 --strictPort`.
  - **호스트 :8000 충돌**: ontology-studio 의 python 백엔드가 **IPv4 127.0.0.1:8000** 을 선점,
    docker completion 은 IPv6 로 밀림. vite 프록시 `/langchain-chat`→`127.0.0.1:8000` 이 ontology
    백엔드로 가서 404 → "Failed to connect".
    - **수정**: `vite.config.ts` 의 `/langchain-chat` 프록시 타깃을 **`http://127.0.0.1:8088`(nginx)** 로
      변경. nginx 가 `/langchain-chat/` 를 completion 으로 정확히 라우팅(항목 13 의 `/completion` prefix
      strip 과 별개로 `/langchain-chat/` 라우트는 원래 존재).
- **결과 (검증됨, Playwright + 스크린샷)**:
  `GET /langchain-chat/sanity-check 200` → `POST /langchain-chat/messages 200` → 에러 0건 →
  채팅에 **휴가신청 프로세스 초안(4단계 + 흐름도)** 렌더:
  `휴가 신청 → 상사 승인 요청 → 승인/반려 결정 → 결과 통보`. BPMN 프리뷰 아이콘도 표시됨.
- **재현 방법 (dev)**:
  ```bash
  cd services/frontend
  # .env: VITE_SUPABASE_URL=http://localhost:54321, VITE_SUPABASE_KEY=<ANON_KEY>, VITE_MODE=ProcessGPT
  npm install --legacy-peer-deps           # 최초 1회
  npm run dev -- --port 5199 --strictPort  # HMR dev 서버
  # 접속: http://localhost:5199  (로그인 jyjang@uengine.org / Test1234!)
  ```
  - 소스 수정(`ChatRoomPage.vue` 등)은 HMR 로 즉시 반영 → 도커 재빌드 불필요.
  - 도커 이미지로 굳히려면: `docker build -t process-gpt-frontend:local services/frontend` 후
    compose `frontend.image` 을 그걸로(이미 그렇게 바꿔둠). 단, **프론트 트리거 재배선(원인1)이
    이미지에도 반영되려면 재빌드 필요**. 프로덕션 이미지에선 backendUrl 이 `/completion/langchain-chat`
    이므로 항목 13 의 `/completion` prefix-strip nginx 라우트가 함께 있어야 함.

### 16-b. Stage 2 (초안 확정 → 실제 BPMN proc_def 생성)까지 복구 (✅)

- **stage 1**(초안)은 `start_process_consulting` → `switchToConsultingMode` 재배선으로 해결(위).
- **stage 2**(확정 생성): 사용자가 "이대로 생성해줘" 하면 base-agent 가 **`work-assistant__generate_process`**
  도구를 호출(직접 `/chat/stream` 프로빙으로 확인). 그런데 최신 프론트는 이 후처리도 제거했음
  → `ChatRoomPage.handleAgentDirectiveToolCalls` 에 **`generate_process` 감지 시
  `buildMessagesForDefinitionGeneration()` + `store.dispatch('updateMessages')` +
  `$router.push('/definitions/chat')`** 배선을 추가(WorkAssistantChatPanel:952-957 패턴).
- **결과 (Playwright + 스크린샷 검증)**: 확정 → `/definitions/chat` 이동 → `ProcessDefinitionChat`
  의 `ChatGenerator(genType='proc_def')` 가 `/langchain-chat/messages` 를 스트리밍(수 회) →
  **완성된 휴가신청 BPMN 다이어그램 + 폼 생성**:
  `휴가 신청(start) → 휴가 승인 요청 → 승인/반려 여부 결정(gateway) → 결과 통보(승인/반려) → 종료`,
  "요청하신 프로세스 생성을 모두 완료하였습니다 🎉" 메시지 표시(≈30초).
- **proc_def 저장은 "명시적 저장 클릭"이 필요(설계상 자동저장 안 함)**:
  소스 주석 "시스템이 자동 저장하지 않고, 사용자가 확인 후 클릭하면 저장"(보안 정책). 따라서
  자동생성 직후 `public.proc_def` 는 0 이 정상 — 화면의 저장 버튼(디자이너 💾 / 결과카드 "저장"
  = `ProcessArtifactViewer` `save-generated-process`, 아이콘 `mdi-content-save-outline`)을 눌러야
  영속화됨. 즉 **"자동생성"은 완결**되고, DB 반영만 1-클릭 사용자 액션.
- **proc_def 쓰기 경로 검증(✅)**: authenticated 역할 + JWT(app_metadata.tenant_id=localhost)로
  `insert into proc_def(...) → INSERT 0 1` 성공. RLS insert 정책은
  `tenant_id = tenant_id() AND (users.is_admin = true)` → jyjang 이 admin 이라 통과.
  즉 저장 버튼 클릭 시 proc_def 에 정상 저장됨(쓰기 계층 무결).
- **저장 → proc_def 영속화까지 검증 완료(✅)**:
  - 원인: 저장 시 프론트가 `proc_def` 에 **`agent_id`** 컬럼을 보내는데 배포 스키마에 없음
    → `POST /rest/v1/proc_def` **400 PGRST204** ("Could not find the 'agent_id' column of 'proc_def'").
    (chat_rooms.context 와 동일한 스키마 구버전 문제.)
  - 수정: `alter table public.proc_def add column if not exists agent_id text;` + `notify pgrst, 'reload schema';`
  - 결과: 저장 클릭 → `POST /rest/v1/proc_def` **201**, `public.proc_def` 에
    **`id=leave_request_process, name=휴가신청 프로세스, tenant_id=localhost, type=bpmn`** 1건 저장 확인.
  - 즉 **전체 end-to-end 완결**: 초안 → BPMN/폼 생성 → 저장 → proc_def 영속화까지 동작.
- **테스트 팁(headless)**: BPMN 디자이너 💾 는 아이콘 전용이라 selector 로 안 잡히고 bpmn-js 캔버스
  `layer` 초기화 경고가 있으나, 좌표 클릭(≈1216,189) + `Ctrl/Cmd+S` + 다이얼로그 "저장" 확인 조합으로
  저장 트리거 성공. 실제 브라우저(http://localhost:5199)에서는 💾 한 번으로 저장됨.

---

## 17. Docker VM 디스크 부족 → containerd content store 손상 (kong unhealthy, 이미지 레이어 유실)

- 증상: `docker system df`에서 여유 공간 거의 없음 → `supabase-kong`이
  `Cannot mkdir /tmp/resty_...: No space left on device`로 unhealthy. 이후
  다른 이미지(`deepagents`, `nginx` 등)를 pull/기동하면 `content digest
  sha256:... not found` 또는 `apply layer error ...: NotFound: failed to
  get reader from content store`로 컨테이너 생성 자체가 실패.
- 원인: 디스크가 빠듯한 상태에서 pull이 진행되며 일부 레이어만 기록된 채
  이미지 메타데이터가 로컬에 남음(`docker inspect <image>`의
  `RootFS.Layers`가 비어 있거나 존재하지 않는 blob을 가리킴).
- 해결:
  1. `docker image prune -f` — 미사용 dangling 이미지 정리(실행/중지 컨테이너
     안전, 승인 불필요). 우리 세션에서 ~3.7GB 회복.
  2. `docker restart supabase-kong` — 디스크 여유가 생기면 재시작만으로
     healthy 복귀(재설치 불필요했음).
  3. 그래도 특정 이미지가 "content digest not found"로 실패하면 해당 이미지만
     `docker rmi -f <image>:<tag>` 후 `docker pull --platform linux/amd64
     <image>@sha256:<digest>`(digest 지정 pull이 태그 pull보다 캐시 재사용
     문제를 덜 일으킴) → `docker tag`로 원래 태그 복원.
- 확인용: `docker run --rm busybox df -h /` — 호스트 `df -h`가 아니라 Docker
  Desktop VM 내부 디스크를 봐야 한다(호스트는 여유 충분해도 VM 디스크는
  꽉 찰 수 있음).

## 18. amd64 전용 이미지 — Apple Silicon에서 pull 실패 → build 폴백까지 실패

- 증상: `docker compose up`이 특정 서비스에서 `no matching manifest for
  linux/arm64/v8 in the manifest list entries`로 pull 실패 → 이미지가 없다고
  판단해 `build:`로 전환 → `unable to prepare context: unable to evaluate
  symlinks in Dockerfile path: ... no such file or directory`로 재실패
  (서브모듈 미체크아웃 상태라 `services/<name>/Dockerfile`이 없음).
- 확인된 대상: `process-gpt-base-agent-langchain-react`,
  `process-gpt-glossary-backend`, `process-gpt-deepagents`,
  `process-gpt-office-mcp`. (`image:`+`build:`를 동시에 갖는 서비스가
  대부분이라 태그 이미지가 로컬에 있으면 build는 건드리지 않는데, 애초에
  arm64용 매니페스트가 없어 pull 자체가 안 되는 게 문제.)
- 해결: 기동 전에 각 이미지를 명시적으로 amd64로 선pull.
  ```bash
  docker pull --platform linux/amd64 ghcr.io/uengine-oss/<image>:<tag>
  ```
  이렇게 로컬에 채워두면 `docker compose up`이 build를 시도하지 않고
  로컬 이미지를 그대로 사용한다.
- 참고: `start-all-services.sh`가 macOS 기본 bash(3.2, `/bin/bash`)에서
  `mapfile: command not found`로 죽는 문제도 같은 세션에서 발견 → 스크립트
  자체를 bash 3.2 호환(`mapfile` 대신 `while read` 루프)으로 수정해 해결.
  (`install-process-gpt` 스킬의 `preflight.sh`도 프로젝트명을 "process-gpt"로
  하드코딩해 정상 기동된 자기 컨테이너를 "이름 충돌"로 오탐하던 버그를
  함께 수정 — 실제 컴포즈 프로젝트명은 레포 디렉터리명인
  `process-gpt-infra-docker`.)

---

## 25. 위 19~24번 이슈 전부 자동 보정 스크립트로 고정 + deepagents DooD 샌드박스 수정

반복 재현되는 #19/#25/#27/#28 네 가지를 매번 손으로 진단하지 않도록
`.claude/skills/install-process-gpt/scripts/post-clone-fixes.sh`로 고정했다
(멱등적, 신규 클론 + `--pull never` 전에 실행). 프레시 클론에 실제 실행해
4개 패치가 정확히 적용되는 것까지 확인함.

추가로 deepagents의 "코드 실행 샌드박스"(Docker-outside-of-Docker — 자체
컨테이너 안에서 `docker.sock`으로 사촌 컨테이너를 띄우는 방식) 기능은 기본
설치에선 꺼져 있었는데, 실제로 채팅에서 deepagents 오케스트레이션으로
프로세스 조회/조작을 시키면 아래 순서로 3단계 에러가 난다:

1. `docker.sock` 미마운트 → `DockerException: fetching server API version`.
2. 마운트해도 `workspace_host`/`SKILLS_HOST`가 컨테이너 내부 경로
   (`/app/workspace`, `/app/skills`)를 그대로 사촌 컨테이너 bind mount
   source로 써서 `mounts denied: not shared from the host` (Docker Desktop
   특유의 DooD 경로 문제 — 사촌 컨테이너는 호스트 데몬이 만들기 때문에
   전달하는 경로 문자열이 반드시 **진짜 호스트 경로**여야 한다).
3. `services/deepagents/core/agents/agent.py`의 `get_or_create_sandbox(...)`
   호출부(200번째 줄 부근)가 `executor.py`와 별개로 **자기만의** 하드코딩된
   `_BASE_DIR / "workspace"`를 쓰고 있어서, executor.py 쪽만 고치면 놓친다.

해결(코드 3곳 + compose 볼륨/env 변경, `post-clone-fixes.sh --with-deepagents-sandbox`에
전부 반영됨):
- `agent.py`에 `_WORKSPACE_DIR = Path(os.getenv("WORKSPACE_HOST", ...))` 추가,
  `get_or_create_sandbox(..., workspace_host=_WORKSPACE_DIR, ...)`로 교체.
- `executor.py`의 4개 호출부도 동일하게 `_AGENT_WORKSPACE_DIR`(import alias)로 교체.
- `docker-compose.yml`: `skills-storage`(named volume) → `./volumes/deepagents-skills`
  (bind mount)로 교체 + 기존 시드 콘텐츠는 `docker cp deepagents:/app/skills/. ...`로
  먼저 빼둠. `SKILLS_HOST`/`WORKSPACE_HOST` env를 진짜 호스트 절대경로로 설정.
  `/var/run/docker.sock:/var/run/docker.sock` 마운트 추가.
- ⚠️ `docker.sock` 마운트는 그 컨테이너가 호스트 Docker를 통째로 제어할 수
  있게 되는 보안 민감 변경 — **사용자 승인 없이 적용하지 말 것** (이번
  세션에서도 AskUserQuestion으로 명시적 승인을 받은 뒤에만 적용함).

수정 후 실제로 deepagents에 "휴가 신청 프로세스 목록을 조회하고 활동 구성을
요약해줘"를 시켜서 `get_process_list`/`get_current_user`/`get_instance_list`/
`get_process_detail` 툴 호출이 실제 DB 데이터를 대상으로 성공하는 것까지 확인함.

## 현재 상태 요약 (기록 시점)

- **34개 컨테이너 running**, 게이트웨이 nginx `:8088` → HTTP 200.
- 접속: 게이트웨이 http://localhost:8088 · Supabase Studio http://localhost:3001 · Neo4j http://localhost:7474
- 로그인 계정: `jyjang@uengine.org` (superAdmin, **tenant=localhost**, auth 확인됨).
  ※ localhost:8088로 접속하므로 tenant는 반드시 `localhost` (항목 12 참조).

### OPEN 이슈 (남은 작업)
- [ ] `deepagents` — 포트 8021 점유 프로세스 정리 or 포트 remap (항목 7)
- [ ] `agent-feedback` — 필요한 DB 환경변수 채우기 (항목 10)
- [ ] `office-mcp` — compose env에 `LLM_PROVIDER: openai` 추가 (항목 10)
- [ ] `mcp-proxy` — k8s 전용, 로컬 제외 여부 결정 (항목 10)
- [ ] 신규 가입 시 `public.users` 자동 생성 경로 확인 (항목 12)
- [ ] `SITE_URL`(=http://localhost:8080)과 실제 게이트웨이(:8088) 불일치 여부 점검

## 19. 새 process-gpt-infra-docker 설치 — supabase-db init 스크립트 부분 실패 → 이후 재부팅마다 스킵

- **환경**: `/Users/uengine/process-gpt-infra-docker` (신규 클론, 이 레포가 표준
  compose 위치). `process-gpt` 본체 쪽엔 기존 레거시 설치가 있었으나
  `infra/volumes/db/*.sql`(8개 init 스크립트)이 빈 디렉터리로 깨져 있어 복구
  대신 새 레포로 재설치하기로 결정.
- **증상**: `docker compose up -d --wait db ...` 직후 `supabase-auth`가
  `password authentication failed for user "supabase_auth_admin"` /
  `"User has no password assigned"`로 무한 재시작.
- **원인**: `volumes/db/roles.sql`이
  ```sql
  ALTER USER authenticator WITH PASSWORD :'pgpass';
  ALTER USER pgbouncer WITH PASSWORD :'pgpass';
  ALTER USER supabase_auth_admin WITH PASSWORD :'pgpass';
  ALTER USER supabase_functions_admin WITH PASSWORD :'pgpass';  -- 이 시점에 role 미존재
  ALTER USER supabase_storage_admin WITH PASSWORD :'pgpass';
  ```
  순서로 되어 있는데, `supabase_functions_admin`은 `98-webhooks.sql`이 pg_net
  확장/스키마 존재 여부에 따라 **조건부**로만 생성한다 (arm64 에뮬레이션 환경 등
  에선 스킵될 수 있음). 이 role이 없으면 `ON_ERROR_STOP=1`이 걸린
  `migrate.sh`가 즉시 abort — 그 뒤에 있는 `supabase_storage_admin` 패스워드
  설정도, 이어지는 `migrations/*.sql` 전체(auth 스키마 소유권 이전 등)도 실행
  안 됨. 컨테이너 자체는 재부팅 후 `PGDATA`가 이미 존재해 초기화 스크립트를
  통째로 건너뛰므로 **재시작해도 저절로 복구되지 않는다.**
- **해결**: `volumes/db/roles.sql`에서 `supabase_storage_admin`을
  `supabase_functions_admin`보다 앞으로 옮기고, 없어도 되는 role 한 줄만
  `\set ON_ERROR_STOP off` / `on`으로 감싸기:
  ```sql
  ALTER USER authenticator WITH PASSWORD :'pgpass';
  ALTER USER pgbouncer WITH PASSWORD :'pgpass';
  ALTER USER supabase_auth_admin WITH PASSWORD :'pgpass';
  ALTER USER supabase_storage_admin WITH PASSWORD :'pgpass';
  \set ON_ERROR_STOP off
  ALTER USER supabase_functions_admin WITH PASSWORD :'pgpass';
  \set ON_ERROR_STOP on
  ```
  이미 떠 있는(초기화 중간에 멈춘) DB는 볼륨을 밀지 않고도 살릴 수 있다 —
  수정한 `roles.sql`을 그대로 재실행하고, `migrations/*.sql`도 순서대로
  재실행(대부분 `IF NOT EXISTS`/예외 처리로 idempotent)하면 된다:
  ```bash
  docker exec -u postgres supabase-db psql -v ON_ERROR_STOP=1 --no-password \
    --no-psqlrc -U postgres -f /docker-entrypoint-initdb.d/init-scripts/99-roles.sql
  docker exec -u postgres supabase-db bash -c \
    'for f in $(ls /docker-entrypoint-initdb.d/migrations/*.sql | sort); do
       psql -v ON_ERROR_STOP=1 --no-password --no-psqlrc -U supabase_admin -f "$f"; done'
  docker restart supabase-auth supabase-storage
  ```

## 20. GoTrue(auth) 스키마 소유권 불일치 — "must be owner of table/function ..."

- **증상**: 위 roles.sql 수정 후에도 auth가 `ERROR: must be owner of function
  uid (SQLSTATE 42501)`, 이어서 `must be owner of table identities`로 계속 실패.
- **원인**: `migrations/20211124212715_update-auth-owner.sql`(auth.uid/role/email
  함수 소유권을 `supabase_auth_admin`으로 이전)이 위 #19 abort 때문에 실행되지
  못해, 부트스트랩 스크립트가 만든 auth 스키마 객체들이 여전히 `postgres`
  소유였음. GoTrue는 `supabase_auth_admin`으로 접속해 `CREATE OR REPLACE
  FUNCTION`/테이블 마이그레이션을 실행하므로 소유자가 아니면 전부 실패.
- **해결**: auth 스키마 전체(스키마 자체 + 테이블 + 시퀀스 + 함수) 소유권을
  일괄 이전 (반드시 `supabase_admin`으로 접속 — `postgres`는
  `10000000000000_demote-postgres.sql`로 superuser 권한이 이미 박탈된 상태라
  `must be owner of schema auth`로 실패함):
  ```sql
  ALTER SCHEMA auth OWNER TO supabase_auth_admin;
  DO $$
  DECLARE r record;
  BEGIN
    FOR r IN SELECT tablename FROM pg_tables WHERE schemaname='auth' LOOP
      EXECUTE format('ALTER TABLE auth.%I OWNER TO supabase_auth_admin', r.tablename);
    END LOOP;
    FOR r IN SELECT sequencename FROM pg_sequences WHERE schemaname='auth' LOOP
      EXECUTE format('ALTER SEQUENCE auth.%I OWNER TO supabase_auth_admin', r.sequencename);
    END LOOP;
    FOR r IN SELECT p.proname, pg_get_function_identity_arguments(p.oid) as args
             FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
             WHERE n.nspname='auth' LOOP
      EXECUTE format('ALTER FUNCTION auth.%I(%s) OWNER TO supabase_auth_admin', r.proname, r.args);
    END LOOP;
  END $$;
  ```

## 21. GoTrue 개별 마이그레이션이 이미 최신인 부트스트랩 스키마와 안 맞음

- **증상**: 소유권 수정 후에도 `20221208132122_backfill_email_last_sign_in_at`
  단계에서 `ERROR: operator does not exist: uuid = text` (레거시 백필
  스크립트가 `identities.id`를 옛날 `text` 타입으로 가정하는데, 부트스트랩이
  이미 최신 `uuid` 타입으로 테이블을 만들어놔서 타입 불일치).
- **원인**: supabase-postgres 이미지의 부트스트랩 스크립트가 "최종 상태"
  스키마를 만들어두고 `auth.schema_migrations`에 일부 버전만 선반영해두는데,
  이 특정 데이터-백필 버전은 선반영 목록에서 빠져 있어 GoTrue가 옛날 가정으로
  다시 실행을 시도함. 신규 설치(빈 `auth.identities`)라 백필할 데이터도 없음.
- **해결**: 실제 효과가 없는(데이터 없음) 마이그레이션이므로 완료 처리만:
  ```sql
  insert into auth.schema_migrations (version) values ('20221208132122');
  ```
  이후 `docker restart supabase-auth`로 나머지 마이그레이션(26개)이 정상 적용됨.
  ⚠️ 다른 버전에서 비슷한 "이미 최신 스키마인데 옛날 마이그레이션이 실패"
  패턴을 만나면, `docker run --rm --entrypoint sh supabase/gotrue:<tag> -c
  'ls /usr/local/etc/auth/migrations'`로 전체 버전 목록을 뽑아
  `auth.schema_migrations`와 diff해서 판단.

## 22. 무관 도커 스택 동시 실행 → 메모리 고갈 → PostgREST(amd64/QEMU) 세그폴트

- **증상**: `docker run --rm busybox free -h` 기준 15.6GB 중 122MB만 여유,
  swap도 거의 다 참. `supabase-db`가 간헐적으로 "recovery mode"(#14와 동일
  패턴)를 겪었고, `supabase-rest` 로그 끝에 `qemu: uncaught target signal 11
  (Segmentation fault) - core dumped` 이후로 그 프로세스가 완전히 죽어
  응답을 멈춤 — 그런데 컨테이너 자체는 `Up`으로 남아있어 `docker ps`만 보면
  정상처럼 보임. Kong이 해당 요청에서 `upstream timed out`/504로 응답.
- **원인**: Process GPT와 무관한 다른 프로젝트 스택들(wazuh-docker ~2.9GB,
  oda-canvas-control-plane ~3.35GB, rag-service-control-plane ~2.13GB,
  infra 프로젝트의 robo-neo4j/mysql/mindsdb ~1.34GB, nkesa-mysql)이 동시에
  떠 있어 메모리를 다 써버림. amd64 바이너리(PostgREST 등)를 arm64에서 QEMU로
  에뮬레이션하는 상태에서 메모리 압박이 겹치면 세그폴트로 죽기 쉽다.
- **해결**: 사용자 승인 하에 무관 스택 전부 `docker stop`(삭제 아님, 나중에
  `docker start`로 복귀 가능) → 여유 메모리 10GB 확보. 이후
  `docker restart supabase-rest`로 깨끗하게 재기동하니 즉시 정상화
  (`Successfully connected to PostgreSQL ...`, `Schema cache loaded ...`).
  **진단 팁**: 컨테이너가 `Up`이어도 실제 프로세스가 죽어있을 수 있으니, 응답이
  없으면 `docker logs <name> -t | tail`로 마지막 로그 시각과 `qemu: uncaught
  target signal` 유무를 확인하고 `docker inspect --format
  '{{.State.StartedAt}}'`로 컨테이너 자체 재시작 여부까지 같이 봐야 한다
  (프로세스만 죽고 컨테이너는 안 재시작되는 경우가 있음).

## 23. frontend 소스 빌드 실패(vendor TS 에러) / 이미지 태그 불일치 → 로컬 캐시 재태깅으로 우회

- **증상 A**: `docker compose up ... frontend`가 소스 빌드로 전환되며
  `src/views/strategy/OntologyExplorer.vue(280,21): error TS2322: Type
  'number' is not assignable to type 'PropertyValueNode<string>'.`로 실패
  (서브모듈 체크아웃 커밋 자체의 vendor 버그, 인프라 설치 범위 밖).
- **증상 B**: `polling-service`는 `build:` 없이 `image:`만 있는데, compose가
  요구하는 태그(`a100ab6`)가 로컬에 없어 `No such image` 로 실패.
- **해결**: 로컬에 캐시된 **다른 태그**의 같은 이미지가 있으면(과거 다른
  설치에서 pull/build된 것) 앱 코드를 고치는 대신 재태깅으로 우회:
  ```bash
  docker tag ghcr.io/uengine-oss/process-gpt:e343845 ghcr.io/uengine-oss/process-gpt:1acd8a3
  docker tag ghcr.io/uengine-oss/process-gpt-polling-service:9b1055c ghcr.io/uengine-oss/process-gpt-polling-service:a100ab6
  ```
  `docker images ghcr.io/uengine-oss/<name>`로 로컬 캐시 태그 목록 확인 후
  compose가 요구하는 태그로 맞춰준다. GHCR 로그인이 없어 정확한 태그를 pull할
  수 없을 때 특히 유용 (버전 차이가 크지 않다면 핵심 데모 플로우엔 지장 없음).

## 24. deepagents 포트(8021) 바인드 실패 — Docker Desktop 프록시 지연 해제

- **증상**: `docker rm -f`로 기존 `deepagents` 컨테이너를 지운 뒤 재기동해도
  `Error response from daemon: ports are not available: exposing port TCP
  0.0.0.0:8021 -> 127.0.0.1:0: listen tcp 0.0.0.0:8021: bind: address already
  in use`. macOS `lsof -nP -iTCP:8021`로는 소유 프로세스가 안 잡히고
  (`netstat`로는 `127.0.0.1.8021 LISTEN` 확인됨, sudo 불가 환경이라 소유자
  특정 불가), Docker Desktop의 `com.docker.backend`가 host-side 포트 포워딩을
  즉시 해제하지 못하는 것으로 추정.
- **해결**: 근본 원인 추적 대신 `docker-compose.yml`의 `deepagents` 포트를
  `8021:8888` → `8022:8888`로 remap하고 재기동. 데모 핵심 경로(챗봇 프로세스
  생성/BPMN)엔 영향 없음. 재발 시 Docker Desktop 재시작으로도 해결 가능하지만
  실행 중인 다른 컨테이너에 영향 주므로 remap을 우선 시도할 것.

### 유용한 커맨드 모음
```bash
# compose 공통 (레포 루트에서)
CF=(-f docker-compose.yml -f infra/docker-compose.yml -f compose/docker-compose.yml -f gateway/docker-compose.yml)

# 상태 확인
docker compose --env-file .env "${CF[@]}" ps -a --format '{{.Service}}\t{{.State}}\t{{.Status}}'

# 기동(로컬 이미지만, private pull 회피)
docker compose --env-file .env "${CF[@]}" up -d --pull never

# DB 접속 (supabase-db)
PGPW=$(grep -E '^POSTGRES_PASSWORD=' .env | cut -d= -f2-)
docker exec -e PGPASSWORD="$PGPW" supabase-db psql -U supabase_admin -d postgres -c "<SQL>"
```

## 26. Apache AGE 설치 + PDF 첨부 프로세스 생성 end-to-end 완주 (✅ 해결, troubleshooting #37~#40)

트리거: `strategy`(온톨로지 그래프) 서비스도 어차피 Apache AGE가 필요하므로
설치 시점에 반영하라는 지시. 기존 #36(미해결로 기록됐던 AGE 부재)을 이번에
실제로 풀었고, 그 과정에서 PDF 첨부 → BPMN 생성 파이프라인 전체를 최초로
end-to-end 완주시켰다(스킬 클러스터링 + deepagents 오케스트레이션까지 확인).

- **AGE 설치**: `strategy`의 기존 패턴(`services/strategy/docker-compose.age.yml`)을
  그대로 채택 — Supabase의 postgres 이미지를 건드리지 않고
  `apache/age:release_PG16_1.5.0` 전용 컨테이너(`age-postgres`)를 추가해
  `bpmn-extractor`(`AGE_DSN`)와 `strategy`(`GRAPH_DB_*`)가 공유하도록 와이어링.
  기존에 데이터가 들어있는 동일 이름 컨테이너와 충돌하는 문제가 있어
  `container_name`은 고정하지 않기로 함 (troubleshooting #37).
- **Cypher 문법 비호환 발견**: AGE 설치 후 그래프는 정상 구축되는데 추출된
  프로세스가 0건 저장되는 문제 발견 → 원인은 Neo4j 전용 맵 프로젝션 문법
  (`node {.*}`)을 AGE openCypher가 지원하지 않는 것. `neo4j_client.py`,
  `api/main.py`, `vector_search.py` 3개 파일의 전 발생 지점을 `properties(node)`로
  치환해 해결 (troubleshooting #38). 이게 실질적으로 #36을 완전히 풀어준
  핵심 수정이었다 — AGE 컨테이너만 띄운 것으로는 부족했다.
- **`event_type_enum` 누락 값 2차 발견**: HITL(스킬/DMN 승인) 단계 진행
  중 `record_events_bulk`가 `waiting_for_user`/`task_cancelled`/
  `human_feedback_submitted` 값으로 계속 실패 — enum에 값 추가로 해결
  (troubleshooting #39).
- **HITL 재개 메커니즘 파악**: `todolist.draft_status='HUMAN_ASKED'`로 멈춘
  태스크는 `output.hitl_feedbacks`에 답을 채우는 것만으로는 재개되지 않는다
  — `fetch_pending_task` SQL 함수의 WHERE절이 `draft_status='FB_REQUESTED'`
  만 폴링 대상으로 보기 때문에, 프론트가 `draft_status`를 `FB_REQUESTED`로
  다시 PATCH해줘야 한다(정상 프론트 코드는 `requestPdf2BpmnWorkerResume()`가
  이걸 자동으로 함). 이 사실 자체는 버그가 아니라 설계된 2단계 계약이다.
- **실제로 걸린 프론트 버그 발견** (troubleshooting #40, 미수정 — 스킬
  범위 밖): 스킬 승인 질문이 백엔드에서 `feedback_type: "select_items"`
  (체크박스 UI, 항목별 선택)로 오는데 프론트가 이걸 `승인`/`반려` 2버튼
  카드로 렌더링하는 경우가 있었다. 이 카드에서 "승인"을 눌러도
  `selected_ids`가 없는 페이로드가 제출되고, 백엔드는 이를 "스킬 0개
  선택하고 승인함"으로 정확히 해석해 스킬 생성을 건너뛴다. 정확한 분기
  조건(어느 코드 경로가 이 카드를 만드는지)은 특정하지 못했다 — 라이브
  이벤트 경로와 재구성(`loadExistingEvents`) 경로 둘 다 코드상으로는
  `question.feedback_type`을 그대로 따르게 되어 있어 재현했지만 근본
  원인은 못 찾음. 데모 완주를 위해 `todolist.output.hitl_feedbacks`에
  `selected_ids`를 포함한 올바른 페이로드를 직접 넣고 `draft_status`를
  `FB_REQUESTED`로 바꾸는 SQL 우회로 프론트를 건너뛰어 검증했다.
- **최종 검증 결과**: 협력사 온보딩 PDF(재무/컴플라이언스 리스크 리포트
  생성 지침이 2개 activity에 걸쳐 반복되도록 의도적으로 설계한 샘플 문서)를
  업로드 → 표준 강도 선택 → 스킬/DMN 승인까지 전체 플로우를 완주시켜
  `proc_def`에 저장된 최종 프로세스 정의에서 두 리포트 생성 activity 모두
  `agentMode: "complete"`, `orchestration: "deepagents"`, 동일한
  `skills: ["partner-risk-assessment-report"]`가 붙은 것을 확인 — 스킬
  클러스터링(Jaccard 유사도 기반 중복 지침 탐지)과 deepagents 오케스트레이션
  자동 부여가 설계대로 동작함을 실증.
- **install-process-gpt 스킬에 반영**: `post-clone-fixes.sh`에 9~11번 항목으로
  (event_type_enum 값 추가 / age-postgres 서비스+와이어링 / Cypher
  `properties()` 치환) 자동화 추가, 원본 vendor 소스를 재현한 fixture로
  멱등성·YAML 유효성까지 검증 완료. `troubleshooting.md` #36을 해결됨으로
  갱신하고 #37~#40 신설.

## 27. PDF 샘플 문서 — 스킬은 생기는데 에이전트가 안 생기는 문제 (✅ 해결, troubleshooting #41)

트리거: "지금 예제가 생성한 프로세스는 스킬과 에이전트가 동반하여 생성되지
못했다"는 지적. pdf2bpmn은 스킬 클러스터링(지침 문장 유사도, 역할 무관)과
에이전트 후보 생성(같은 역할 안에서 같은 스킬을 가진 activity ≥2개)을
서로 다른 조건으로 판단한다는 걸 코드(`process_post_processor.py`)에서
확인. 처음 버전은 두 리포트 activity를 재무팀/컴플라이언스팀으로 역할을
나눠뒀어서 스킬은 묶여도 에이전트 후보 조건(같은 역할)을 못 채웠다. 역할을
하나로 합치자 이번엔 activity **이름**이 너무 비슷해서(`workflow/graph.py`
`_merge_tasks_by_similarity`, 스킬 클러스터링보다 먼저 실행됨) 같은 역할
안의 두 activity가 사전에 하나로 병합돼버려 여전히 에이전트 후보가 0개.
"같은 역할 + 유사한 지침 본문 + 겹치지 않는 activity 이름" 세 조건을 동시에
만족하도록(짧고 구분되는 소제목을 지침 앞에 붙여 LLM이 그 표현을 activity
이름으로 채택하도록 유도) `assets/vendor-onboarding.html`을 재설계 → 재업로드
검증 결과 두 activity 모두 `agentMode: complete`/`orchestration: deepagents`
+ 동일 스킬 + **동일한 신규 에이전트 id**(users 테이블에 `is_agent=true`로
실제 생성됨)가 붙는 것 확인. `troubleshooting.md` #41 신설,
`demo-playwright.md` 시나리오 B 검증 단계 업데이트.

## 28. 로컬 개발 모드에서 앱 서비스가 `--build` 없이 옛 GHCR 이미지로 뜨는 문제 (✅ 해결, troubleshooting #15-b)

트리거: "개발환경으로 설치하는 경우는 docker container 이미지로 실행하면
안 됨. 프론트엔드가 너무 옛날꺼임. 인프라(Supabase/Apache AGE 등) 제외하고는
`services/` 이하 신규 모듈로 설치돼야 함." — 원인 확인: `docker-compose.yml`의
자체 개발 서비스는 전부 `image:`(GHCR 고정 태그)와 `build:`(현재 소스) 둘
다 정의돼 있는데, Compose는 `--build`가 없으면 항상 `image:`를 우선한다.
`start-all-services.sh`는 애초에 `--build`를 지원하지 않아 이 스크립트로
설치하면 서브모듈을 최신으로 받아도 항상 옛 이미지가 떴다. 실제 확인:
`docker inspect ghcr.io/uengine-oss/process-gpt:1acd8a3`의 실제 빌드
시각이 2026-04-23(서브모듈 HEAD는 2026-07-20)이었음 — 이전 세션에서 태그
불일치를 `docker tag`로 우회했던 게(#23) 사실은 이 문제를 고치는 대신
숨기고 있었던 것.

**해결**: `start-all-services.sh`에 `-b`/`--build` CLI 플래그를 추가 —
`compose up -d`를 호출하는 모든 지점(`start_gateway`, `start_services`,
"all" 비대화형/대화형 경로)에 조건부로 `--build`를 삽입, 인프라
(`INFRA_STACK`: db/kong/auth/rest/realtime/storage/imgproxy/meta/functions/
analytics/studio/neo4j/litellm-db/litellm-proxy/age-postgres)는 애초에
`build:` 블록이 없어 영향 없음을 사전에 전수 확인. `--build frontend`로
실제 재빌드해 `docker inspect` 빌드 시각이 서브모듈 최신 커밋 이후로
찍히는 것까지 검증. `troubleshooting.md` #15-b 신설, #23 개정(재태깅은
`build:` 없는 서비스에만 쓰라고 명시), `local-dev.md`/`SKILL.md`에 로컬
개발 모드는 `--build`가 기본이라고 반영.

## 29. 스킬이 proc_def엔 저장되는데 실제 SKILL.md 파일은 안 생기는 3중 silent-failure (✅ 해결, troubleshooting #42)

트리거: 채팅 UI에서 "스킬 1개 생성됨"으로 표시된 프로세스를 보여줬더니
"이 스킬을 만든 PDF가 assets 폴더에 없다", "스킬/에이전트가 저장된 곳을
클릭해도 팝업이 안 뜬다"는 지적, 이어서 "업로드가 실패했는데 왜 화면엔
저장된 것처럼 표시되는가 — 오류 처리 없이 넘어간 부분을 전부 찾아 오류를
표시하도록 고쳐달라"는 명시적 요청.

조사 결과 서로 독립적인 3개의 "조용한 실패"가 겹쳐 있었다:
1. `CLAUDE_SKILLS_BASE_URL` 기본값이 nginx에 없는 `/claude-skills` 경로를
   가리켜, 요청이 프론트 SPA catch-all로 떨어지며 200 HTML을 "성공"으로
   오판(구 코드는 상태코드만 봄).
2. `skill_docs`(업로드 대상) dict의 키를 스킬의 **한글 표시명**으로
   만들었는데, HITL 승인 여부 판정은 **영문 slug**(`safe_name`/`id`) 기준
   이라 절대 안 맞음 — 승인해도 매번 "미승인"으로 스킵.
3. 위 두 실패 모두 로그 한 줄(`logger.warning`)로만 남고 채팅 완료
   메시지·결과 카드엔 아무 표시가 없었음.

**해결**:
- `docker-compose.yml`: bpmn-extractor에
  `CLAUDE_SKILLS_BASE_URL: http://deepagents:8888` 추가(게이트웨이
  우회, `post-clone-fixes.sh` 10번 항목에 반영).
- `pdf2bpmn_agent_executor.py`: skill_docs 키를 `safe_name`/`id` 기준으로
  수정, 업로드 시 스킬명도 마크다운 재추출 대신 이 키를 그대로 재사용,
  `_upload_skill_to_claude_skills()`가 응답 JSON의 `registered: true`까지
  검증(상태코드만으로 판단하지 않음), 실패 사유를
  `skill_upload_errors`로 수집해 진행 이벤트·완료 메시지·`saved_skills[]`에
  모두 노출.
- 프론트(`Chat.vue`, `ProcessArtifactViewer.vue`): `uploaded === false`인
  스킬을 빨간 경고 아이콘 + "업로드 실패: <사유>" 캡션으로 표시, 클릭해도
  깨진 링크로 안 넘어가게 수정.
- 재빌드(`docker compose up -d --build --no-deps bpmn-extractor frontend`)
  후 실제로 재업로드까지 재현·검증: 처음엔 여전히 실패(원인 1만 고친
  상태 — `skills_uploaded: []`, `skill_upload_errors: []`인 채로 조용히
  스킵되는 걸 보고 원인 2를 추가로 발견), 원인 2까지 고친 뒤에야
  `volumes/deepagents-skills/localhost/local/partner-risk-score-report/SKILL.md`
  가 실제로 생성되고 `saved_skills[].uploaded: true`가 찍히는 것을 확인.
- `troubleshooting.md` #42 신설(위 3원인 + 검증 커맨드 + 일반화된 교훈),
  `demo-playwright.md` 시나리오 B 검증 단계에 `saved_skills[].uploaded` +
  파일시스템 확인 절차 추가.

## 30. DMN HITL 질문이 단발성 분기에도 뜸 — 재사용 여부 미검토 (✅ 해결, troubleshooting #43)

트리거: process-gpt-demo 스킬용 "분기 있는 휴가 신청 프로세스" 데모를
텍스트 채팅으로 생성하는 중, 승인/반려 분기가 딱 하나뿐인데도 "DMN
의사결정 테이블을 어떤 게이트웨이에 만들까요?" HITL 질문이 뜬 것을 사용자가
지적: "DMN으로 분리할 대상은 비즈니스 규칙이 반복적으로 사용되는 것이
감지될 때다. 한 번만 쓰이는 분기는 HITL 대상이 아니다." 원인 확인:
`pdf2bpmn_agent_executor.py`의 `_collect_dmn_candidates_from_proc_json`이
"ExclusiveGateway + 분기 2개 이상"이라는 구조적 조건만 보고 후보를
채택했고, 같은 게이트웨이가 프로세스 안에서 몇 번 재사용되는지는 전혀
반영하지 않았다(이미 이름 기준 병합 로직은 있었는데 그 결과를 후보
채택 여부 판단에 안 썼을 뿐). 같은 이름 게이트웨이 그룹의 크기가 1개면
(=재사용 정황 없음) 후보에서 제외하도록 수정 — 실제로 DMN을 적용하는
`_augment_runtime_with_gateway_dmn`은 승인된 게이트웨이만 처리하므로
별도 수정 불필요. bpmn-extractor 재빌드로 반영, PDF/텍스트 채팅 생성
양쪽 다 같은 코드 경로를 타므로 둘 다 적용됨.

## 31. 프로세스 데모 시나리오 1 실인스턴스 실행 중 발견한 2개 버그 + 하나의 미해결 이슈 (✅✅⚠️, troubleshooting #44/#45)

`process-gpt-demo` 스킬 시나리오 1(휴가 신청 인스턴스를 채팅으로 실제
실행)을 처음 끝까지 검증하며 발견. 이전까지 이 레포의 어떤 데모도 프로세스
"생성"만 확인했지 실제 **인스턴스 실행**을 끝까지 밟아본 적이 없었다.

1. **(✅ 해결) work-assistant MCP의 하드코딩 SaaS 도메인**: 채팅에서
   "휴가 신청 프로세스 실행해줘"를 시켜보니 몇 단계 진행 후 "시스템
   오류가 발생했습니다('NoneType' object has no attribute 'get')"로 항상
   실패. `completion` 서비스 로그엔 `/complete` 요청이 아예 안 찍혀
   요청이 라우팅부터 실패한 것으로 추론. 원인 추적 결과
   `base-agent-langchain-react`가 pip으로 설치하는 **PyPI 패키지**
   `process-gpt-mcp==0.3.0`(레포 안의 `process-gpt-mcp/` 폴더는 참고용
   사본일 뿐 실제 빌드엔 안 쓰임)의 `get_api_base_url()`이 멀티테넌트
   SaaS 전용 도메인(`https://<tenant>.process-gpt.io`)을 무조건
   반환 — 자체 호스팅엔 이 도메인이 없어 `execute_process`가 completion에
   도달할 수조차 없었음.
   - **처음엔 컨테이너 안 site-packages 파일을 `docker exec`로 직접
     패치**했는데, 이건 다음 `--build`에 원복되는 임시방편이라는 걸
     바로 인지 → **`services/base-agent-langchain-react/`에
     `patch_mcp_server.py`를 추가하고 Dockerfile에서
     `pip install process-gpt-mcp==0.3.0` 직후 이 스크립트로 설치된
     패키지 파일을 빌드 시점에 in-place 패치**하도록 재작업(원본 함수
     텍스트가 바뀌면 `assert`로 빌드가 멈추게 해서, 업스트림이 바뀌어도
     이 패치가 조용히 무효화되지 않게 함). `docker compose build
     --no-cache base-agent-langchain-react`로 재빌드해도 패치가 남아있고
     `get_api_base_url('localhost')`가 올바르게 override되는 것까지 확인.
   - `docker-compose.yml`의 `base-agent-langchain-react` 서비스에
     `PROCESS_GPT_API_BASE_URL: http://nginx:8088` 추가 — **게이트웨이
     주소**여야 함(completion 서비스 자체엔 `/complete`만 있고
     `/completion` 접두사가 없음, nginx의 `location /completion/`이 그
     접두사를 벗겨서 전달하는 구조라 MCP가 항상 붙이는
     `{base}/completion/complete`를 받아줄 수 있는 쪽은 nginx뿐).
2. **(✅ 해결) `submit_workitem`이 `email` 없는 요청에서 크래시**:
   위 1번을 고친 뒤 `email` 없이 `task_id`만으로 직접 API를 호출해보니
   진짜 두 번째 버그를 만남 — `services/completion/process_engine.py`의
   `submit_workitem()`이 `user_info`가 `None`(=`email` 미포함 요청)이면
   `user_info.get('id')`를 무조건 호출해 크래시. `if user_info:` 가드
   추가로 수정, 기존 워크아이템에 이미 배정된 담당자는 그대로 보존되게
   함. `email` 포함해서 재시도 → 200 OK 확인.
3. **(⚠️ 미해결, 코드 수정 안 함) 게이트웨이 분기 선택이 승인/반려 입력값과
   무관하게 항상 "승인" 쪽으로 감**: `approval_status: "rejected"`로
   제출해도(자연어 채팅 실행 1회 + API 직접 호출 1회, 총 2번) 반려 분기
   (`task_notify_reject`)가 아니라 승인 분기(`task_register`)가 활성화됨.
   `prompt_completed`(현재 활동 DONE/PENDING만 결정, 다음 분기와 무관),
   `run_completed_determination`("진행 가능한 경로가 있는지"만 판정, 어느
   분기인지는 무관), `get_gateway_condition_data`(제출값 "rejected"를
   정확히 조회하는 것까지는 확인)까지 추적했지만, 그 값이 최종적으로
   어떻게 분기 선택에 반영되는지의 정확한 코드 경로는 이번 세션에서
   특정하지 못함 — 열린 이슈로 문서화(`troubleshooting.md` #45 "버그 2").
   데모에서는 승인 경로 위주로 시연하고, 반려를 보이려면 매번
   `select activity_id, status from todolist where proc_inst_id=...`로
   실제 어느 분기가 선택됐는지 확인할 것.

부가로, 프론트에 새 마케팅 랜딩 페이지(`/`)가 생기며 기존 Playwright
로그인 스니펫(`page.goto(BASE)` + `networkidle`)이 간헐적으로 깨지는 것도
발견 — `/auth/login`으로 바로 이동 + `waitUntil: 'load'` +
`waitForSelector`로 교체(`troubleshooting.md` #46, `demo-playwright.md`·
`process-gpt-demo/references/demo-account.md` 스니펫에 반영).

## 32. deepagents가 proc_def에 연결된 스킬을 실제로는 전혀 안 쓰는 2개의 독립 버그 (✅✅, troubleshooting #47/#48/#49)

`process-gpt-demo` 시나리오 2(협력사 온보딩 — 스코어링 활동을 deepagents가
무인으로 처리하며 실제로 스킬 절차를 따르는지 검증하는 것이 이 시나리오의
핵심 목적)를 실행하며 발견. 워크아이템은 SUBMITTED→DONE으로 자동 처리됐지만
`docker logs deepagents`를 직접 열어보니 매번 "서브에이전트 '...': skills
설정 없음 (스킬 없이 빌드)"만 찍히고 있었다 — 겉으로는 성공한 것처럼 보이는
데모가 사실은 핵심을 증명하지 못하고 있었던 케이스.

**버그 A**: 담당 에이전트의 `users.skills` 컬럼이 비어 있었음
(`select skills from users where id='<agent-uuid>'` → 빈 문자열).
deepagents는 활동에 선언된 스킬(`proc_def.definition.activities[].skills`)이
아니라 **런타임에 `users` 테이블에서 그 값을 다시 읽는다**
(`processgpt_agent_sdk.database.fetch_users_grouped()` → `select * from users`) —
즉 에이전트 자신의 프로필에 스킬이 박혀 있어야만 실제로 쓰인다.
`bpmn-extractor`에 이 값을 채우는 로직(`_sync_skills_to_supabase`)이 이미
있었지만, 재사용한 기존 데모 에이전트에는 왜인지 채워져 있지 않았다(그
동기화 로직이 언제부터 있었는지, 신규 생성 시 항상 채워지는지는 이번엔
검증 못 함 — 다음에 프레시 생성으로 재확인 필요). 즉시 조치: SQL로
`update users set skills='<skill-slug>' where id='<agent-uuid>';`.

**버그 B**: 버그 A를 고쳐도 여전히 로그에
`Cannot load skills from '/app/skills/...': path_not_found`가 반복됨.
deepagents는 실제 실행을 Docker-outside-of-Docker 샌드박스(사촌 컨테이너
`deepagent-sandbox-<tenant>`)에서 하는데, 그 샌드박스는 스킬을
`/skills/<name>`에 화이트리스트 단위로 개별 bind-mount한다(다른 테넌트
스킬이 통째로 노출되는 걸 막기 위한 의도적 설계). 그런데:
1. `core/agents/subagents.py`가 `_get_skills()`의 결과(이 API 컨테이너 자신의
   뷰 `/app/skills/...`)를 변환 없이 그대로 `FilteredSkillsMiddleware`에
   넘겨 샌드박스 backend의 ls()가 항상 path_not_found.
2. `core/agents/agent.py`의 **루트 에이전트**(1:1 채팅용) 경로는 이미
   "변환하는 것처럼 보이는" 코드가 있었지만, 그 변환 기준(`_SKILLS_DIR` =
   `SKILLS_HOST` env = 실제 호스트 절대경로, 예:
   `/Users/.../deepagents-skills`)이 애초에 `/app/skills/...`와 절대
   매치될 수 없는 값이라 매번 조용히 no-op — **시나리오 3(딥에이전트
   1:1 채팅에서 스킬 직접 참조)의 전제도 이번 조사 전까지는 깨져
   있었을 가능성이 높다**는 뜻.
3. `core/sandbox/docker_sandbox.py`의 `_skill_volumes()`도 마운트 여부
   판정을 호스트 절대경로(`self._skills_host.exists()`)로 해서 이 API
   컨테이너 안에서는 항상 `False` → 애초에 스킬 볼륨을 하나도 안 만듦
   (`docker inspect deepagent-sandbox-<tenant>`로 `/skills/*` 마운트가
   전무한 것을 직접 확인).
   해결: 세 곳 모두 "존재/화이트리스트 판정은 컨테이너 자신의 뷰
   (`SKILLS_DIRS` 기준) vs 실제 bind-mount source는 호스트 절대경로
   (`SKILLS_HOST` 기준)"을 명확히 분리하도록 수정
   (`core/skills/skills.py`에 `to_sandbox_skill_paths()` 추가,
   `agent.py`/`subagents.py`가 이걸 쓰도록, `docker_sandbox.py`에
   `skills_container_root` 파라미터 추가). **사촌 컨테이너는 재사용되므로
   마운트 구성을 고쳤으면 `docker rm -f deepagent-sandbox-<tenant>`로
   반드시 지워야** 다음 실행에 새 마운트가 적용된다(안 지우면 코드를
   고쳐도 여전히 실패).
3개 코드 수정 + 사촌 컨테이너 제거 후 재실행해 `Skills load errors`가
사라지고 스킬이 실제로 파싱되는 것(이름 규칙 경고만 남고 로드는 성공)까지
확인.

**추가로 발견(별도 원인, troubleshooting #49)**: proc_def 활동에
`orchestration`을 명시적으로 안 넣었는데 담당자가 에이전트로 해석되면
`agent_mode=COMPLETE`가 자동 부여되고 `agent_orch`는 `crewai-deep-research`로
기본 폴백되는데, 이 install-process-gpt 환경엔 그 서비스 자체가 없어
워크아이템이 `IN_PROGRESS`에서 에러도 없이 영원히 멈춘다. 데모에서는
해당 활동을 직접 API로 완료 처리해 우회(사람이 사후 검토한 것으로 간주).

## 33. "기본 에이전트" 1:1 채팅 모드는 self-host docker-compose에서 원천적으로 안 됨 — 버그 아닌 아키텍처 한계 (troubleshooting #50)

`process-gpt-demo` 시나리오 3(기본 에이전트 vs 딥 에이전트 1:1 채팅 비교)
작업 중 발견. "기본 에이전트"로 메시지를 보내면 항상 "(에이전트 준비
실패)"만 뜨는데, 원인을 끝까지 따라가 보니 `agent-router` 컨테이너에
직접 요청해도(게이트웨이 우회) 500이 나고, 로그에
`kubernetes.config.config_exception.ConfigException: Invalid kube-config
file. No configuration found.`가 찍혔다. `agent-router`의 `/warmup`은
에이전트마다 **전용 Kubernetes 파드**를 온디맨드로 띄우는 설계
(`TARGET_BASE_URL_TEMPLATE: "http://agent-{agent_id}:8000"` 등 compose env가
이를 뒷받침)라, 진짜 K8s 클러스터가 없는 Docker Compose 단일 설치에서는
애초에 성립할 수 없는 전제다 — 코드를 고쳐서 해결할 문제가 아니다. 항목 10의
`mcp-proxy`(K8s 전용, 로컬 무시 가능)와 같은 종류의 제약이지만, `agent-router`는
그 서비스 자체는 로컬에서도 정상 기동·헬스체크되고 "route"(에이전트 자동
선택) 기능도 되기 때문에 "이건 K8s 전용이라 아예 빼도 된다"로 오판하기
쉽다 — 실제로는 `/warmup`(=기본 에이전트 1:1 채팅 한정)만 K8s가 필요하고
나머지는 로컬에서도 동작한다. 결론: 자체 호스팅 설치에서는 **딥 에이전트
모드만 1:1 채팅의 실사용 경로**로 안내할 것.

## 34. 에이전트 "지식 관리" 탭이 항상 비어 보임 — mem0 RPC(get_memories)가 DB 초기화 때 누락 (troubleshooting #51)

튜토리얼 Lv2(에이전트 학습) 데모 작업 중 발견. 학습모드로 가르친 지식이
`vecs.memories`에는 실제로 저장되고 런타임 제안서에도 반영되는데, "지식 관리"
탭만 "메모리가 없습니다"로 비어 보였다. 원인은 프론트가 부르는 RPC
`public.get_memories`(+`delete_memory`/`delete_memories_by_agent`)가 DB에
아예 없어서였다. 이 함수들은 `docker-infra/volumes/db/vecs.sql`에 있지만
`RETURNS SETOF vecs.memories`라 초기화 시점에 `vecs.memories` 테이블이 없으면
생성되지 않는데, 그 테이블은 mem0가 **첫 학습 때 지연 생성**하므로 함수가
영영 누락된다. 한 번이라도 학습해 테이블이 생긴 뒤 `vecs.sql`을 재적용하고
`anon/authenticated/service_role`에 EXECUTE 부여 + PostgREST 스키마 리로드하면
해결. deepagents 런타임은 mem0를 안 읽으므로(서브에이전트 프롬프트는
role/goal/persona/tools/skills만으로 구성됨), 학습 지식이 **실행 결과에도**
반영되게 하려면 그 지식을 에이전트 **persona/goal**에도 넣어둬야 한다(학습
채팅은 사용자용 교육 UI, 실행 반영은 프로필 경유 — 두 경로를 함께 채울 것).

## 35. 게이트웨이→endEvent 종료 인스턴스가 COMPLETED 안 됨 — 배포 이미지 stale (troubleshooting #52)

튜토리얼 Lv3(조건 분기 + 피드백 루프) 데모 작업 중 발견. 마지막 사람 태스크
뒤에 배타 게이트웨이를 두고 한 분기가 endEvent로 가는 구조
(`task3 → gw_revision → end_event`)에서, 승인 분기를 제출하면 전 활동이 DONE이고
`current_activity_ids`가 비었는데도 `bpm_proc_inst.status`가 영원히 RUNNING에
남는다(게이트웨이 라우팅·조건 평가·반려 루프백은 정상). 원인은 배포된
`polling-service` 이미지의 `process_definition.find_end_activity()`(단수)가
**게이트웨이를 거슬러 올라가지 못해서** — endEvent 직전이 게이트웨이면 종료 활동을
`None`으로 판정, `upsert_process_instance`가 COMPLETED를 못 세운다. **현재 로컬
소스는 이미 수정됨**(`find_end_activities()` 복수형이 게이트웨이 재귀 traversal,
`database.py`가 이를 사용). **배포 이미지만 그 커밋 이전**이므로 polling-service
이미지를 현재 소스로 재빌드/재배포하면 해소된다. 빠른 진단:
`docker exec <polling-svc> grep -c 'def find_end_activities' /usr/src/app/process_definition.py`
→ 0이면 stale.

## 36. BPMN 편집기 저장이 conditionFunction을 저장하지 않음 — 결정론 분기는 DB 후보정 전제

Lv3 빌드타임(편집기 직접 조작)에서 확인. `/definitions/<id>` 편집기에서 분기
플로우에 자연어 조건만 입력하고 저장하면, `sequences[].properties`에 `condition`
(+`conditionMode:"text"`)만 남고 **`conditionFunction`이 없다**. 저장 시
`bpmnXmlToDefinition.buildSequence`가 패널이 쓴 uengine json을 그대로 복사할 뿐,
conditionFunction을 합성하지 않기 때문. conditionFunction을 편집기에서 넣으려면
조건 필드의 프리펜드 아이콘으로 **함수 모드** 전환 후 직접 입력하거나 **"결정론적
규칙화"** AI 버튼을 눌러야 한다. 자연어 조건만으로는 런타임이 불안정한 LLM 경로로
가므로(#45), 결정론 분기가 필요하면 **편집기 저장 후 `properties.conditionFunction`을
DB로 후보정**하는 것을 전제로 설계하라. 또한 편집기 저장은 캔버스에서 정의 전체를
재생성하므로 시퀀스 id가 bpmn 파생 id로 바뀐다(녹화 후 원본 정의 재적용으로 복구).

## 37. Lv4 ERP 데이터소스 연동 — 로컬 Supabase/Kong REST, 컨테이너 DB 도달, conditionFunction 제약

튜토리얼 4편(ERP 재고 관리) 제작 중 확정한 4가지.

1. **로컬 Supabase를 ERP로**: `public.product_table`을 만들고 Kong
   `/rest/v1/product_table`(anon 키, `apikey`+`Authorization: Bearer`)로 노출.
   새 테이블은 grant + (RLS면 정책) + **`NOTIFY pgrst,'reload schema'`** 필요
   (troubleshooting #53). `todolist` 등 테넌트 RLS 테이블은 anon 은 빈 배열 →
   **사용자 JWT(authenticated)** 로 조회해야 행이 보인다.
2. **데이터소스 = key/value 저장소**: `data_source.key`=이름 문자열,
   `value` jsonb=`{method,endpoint,headers:[{key,value}],parameters,auth}`. 폼 select
   연동은 **서버 리졸버 없이 프론트가 client-side fetch**(`SelectField.vue` dataBinding:
   `dynamic_data_source`=key, `dynamic_load_key_column`/`value_column`=옵션 value/label).
3. **컨테이너 에이전트 DB 도달**: deepagents 컨테이너는 `supabase-db`와 네트워크가
   분리돼 `localhost:54322`/`db:5432` 불가, **`host.docker.internal:54322`만** 도달
   (troubleshooting #54). tenant MCP DB URI를 이에 맞춰야 하고, host용(시나리오 7)과
   공존하면 서버명을 달리해 추가. **단, 이번 배포에선 에이전트 자율 MCP DB 쓰기가
   재현되지 않아**(agent-router 러너가 tenant MCP 도구 미바인딩 추정) 실데이터 변경은
   데이터소스 REST(anon) PATCH로 실증했다(PRODUCT_CHANGES #4).
4. **conditionFunction eval 제약**: `_evaluate_sequence_conditions`의 eval은
   `{"__builtins__":{}}`(→ `int()/float()` 불가) + **단일 dict 컨텍스트**(두 피연산자가
   같은 dict에 있어야 함). 그래서 "재고>=주문량" 수치 비교를 게이트웨이에서 직접 하지
   말고, **재고 확인 단계에서 판정한 boolean 필드(`stock_sufficient`='true'/'false')**를
   문자열 등가 비교(`== 'true'`)로 분기하라(Lv3 라디오 패턴과 동일, 검증됨).

## 튜토리얼 Lv5 — 확장된 서브프로세스 멀티 인스턴스 (병렬 자식 인스턴스)

1. **자식 수 자동 추론(결정론)**: subProcess `properties.determinationCode` 또는
   `forEachVariable`에 `"<수집폼id>:<section>"` 경로를 넣으면, 폴링 서비스
   (`check_subprocess_expression`)가 `all_workitem_input_data`에서 그 리스트를 찾아
   **길이만큼 자식 인스턴스를 병렬 생성**한다. 명시 `multiInstanceCount`도 LLM도 불필요
   (실측: 수집된 VIP 3명 → 자식 3개, 각 `execution_scope`=0/1/2, `proc_inst_name`에
   항목 요약 인코딩). 정본 shape는 `polling_service/tests/testSubprocess.json`.
2. **정의 shape 필수 조건**: subProcess는 `definition.subProcesses`에 + `children`에 중첩
   def(activities/sequences), **자식 start/end 이벤트·게이트웨이는 상위 `events`/`gateways`
   에 `process=<subId>`로 태깅**, **subProcess와 endEvent 사이에 실제 activity 1개 필수**
   (없으면 `find_end_activities`가 종료 활동 못 잡아 부모 미완료).
3. **자식 activity `agent` 유실(제품 갭)**: `build_subprocess_definition::act_to_dict`가
   `agent`를 미보존 → 자식 에이전트 태스크가 특정 persona 없이 deepagents 폴백 실행
   (`서브에이전트 미설정`). 개인화 완전 자동화엔 `act_to_dict`에 `agent` 보존 1줄 추가 +
   폴링 서비스 이미지 재빌드 필요(troubleshooting #55). Lv5는 소스 무수정, 뉴스레터는
   에이전트 persona+CRM LLM 생성으로 실증.
4. **자식 완료 판정 엣지**: 자식 마지막 사람 태스크 제출이 한 번에 안 될 수 있어 재제출
   필요, 전 워크아이템 DONE·`current_activity_ids={}`여도 status가 RUNNING 잔류(#52 동종)
   → status만 COMPLETED 데이터 보정.
