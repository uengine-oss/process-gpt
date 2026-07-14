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
