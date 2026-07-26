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
| 15 | 프론트(또는 다른 자체 개발 서비스)가 "옛날 버전" | compose가 `image:`(GHCR 고정 태그)를 `build:`보다 우선 사용 → 로컬 개발 모드는 항상 `--build`로 띄울 것 (#15-b) |
| 15-b | 로컬 개발 모드에서 서브모듈을 최신으로 받아도 앱 서비스가 계속 옛 버전 | 위 #15와 동일 원인, 근본 해결책 → 아래 상세 |
| 16 | dev 서버 충돌 (5173, :8000) | 다른 vite/python 프로젝트 선점 → `--port 5199 --strictPort`, vite 프록시 타깃을 :8088(nginx)로 |
| 17 | Docker VM 디스크 부족 중 pull → 이후 `content digest ... not found` / `apply layer error` (nginx, deepagents 등), kong이 `Cannot mkdir /tmp/resty_...: No space left on device`로 unhealthy | Docker Desktop VM 디스크 풀 상태에서 pull이 진행되며 containerd content store가 손상 → 아래 상세 |
| 18 | `no matching manifest for linux/arm64/v8` 또는 compose가 pull 대신 "Building"으로 전환 후 `unable to prepare context: ... no such file or directory` | 일부 이미지(`process-gpt-base-agent-langchain-react`, `process-gpt-glossary-backend`, `process-gpt-deepagents`, `process-gpt-office-mcp` 등)가 amd64 전용이라 Apple Silicon에서 자동 pull 실패 → compose가 `build:`로 폴백하는데 서브모듈 미체크아웃이라 재실패 → 아래 상세 |
| 19 | supabase-auth가 "password authentication failed" / "has no password assigned"로 무한 재시작 (신규 설치, `process-gpt-infra-docker`) | `volumes/db/roles.sql`이 `supabase_functions_admin`(조건부 생성 role, arm64에선 미존재 가능)에서 `ON_ERROR_STOP`으로 abort → 뒤의 `supabase_storage_admin` 패스워드 설정과 `migrations/*.sql` 전체가 미실행. 컨테이너 재시작해도 PGDATA 존재라 init 스크립트가 스킵되어 저절로 복구 안 됨 → 아래 상세 |
| 20 | auth가 "must be owner of function uid" / "must be owner of table identities" | `20211124212715_update-auth-owner.sql` 등 auth 스키마 소유권 이전 마이그레이션이 #19 abort로 미실행 → auth 스키마 객체가 여전히 `postgres` 소유 → 아래 상세 |
| 21 | GoTrue 특정 버전(예 `20221208132122_backfill_email_last_sign_in_at`)에서 `operator does not exist: uuid = text` | 부트스트랩 스키마가 이미 최신 타입인데 옛날 데이터-백필 마이그레이션이 구버전 타입을 가정 → 아래 상세 |
| 22 | 컨테이너는 `Up`인데 응답 없음/504, 로그 끝에 `qemu: uncaught target signal 11 (Segmentation fault)` (주로 supabase-rest) | 무관한 다른 도커 스택과 동시 실행으로 메모리 고갈 → amd64→arm64 QEMU 에뮬레이션 중인 프로세스가 세그폴트로 죽고 컨테이너는 재시작 안 됨 → 무관 스택 정리 + `docker restart <service>` |
| 23 | frontend가 vendor TS 에러로 소스 빌드 실패, 또는 `image:`만 있는 서비스가 "No such image" | 서브모듈 체크아웃 커밋 자체의 버그이거나 compose가 요구하는 태그가 로컬에 없음 → `build:`가 없는 서비스만 `docker tag`로 우회, `build:`가 있는 서비스(frontend 등)는 재태깅 대신 `--build`로 실제 재빌드할 것 (#15-b) |
| 24 | 컨테이너 삭제 후에도 재기동 시 "ports are not available" (동일 포트) | Docker Desktop이 host-side 포트 포워딩을 즉시 해제하지 못함 (macOS) → compose 파일에서 해당 서비스 포트만 remap |
| 25 | 채팅에서 "휴가 신청 프로세스 만들어줘" 전송 시 `/agent/chat/stream` 502, nginx 로그에 `base-agent-langchain-react could not be resolved` | `nginx/nginx.conf`의 `$upstream_agent`가 옛 네이밍(`process-gpt-base-agent-langchain-react`)을 하드코딩 — 실제 compose 서비스명은 `base-agent-langchain-react` → 아래 상세 |
| 28 | 프론트의 `DeepAgentRouterService.js`가 사용하는 `/process-gpt-deepagents/*`가 항상 SPA HTML을 반환 (deepagents가 응답 안 함) | nginx는 `/deepagents/*`만 정의돼 있고 `/process-gpt-deepagents/*`는 없음 → `location /`(frontend catch-all)로 떨어짐 → 아래 상세 |
| 30 | deepagents 채팅이 `DockerException: Error while fetching server API version: ... FileNotFoundError` | deepagents 컨테이너가 자체 코드 실행을 위해 내부에서 Docker(사촌 컨테이너)를 띄우는데 `/var/run/docker.sock`이 마운트 안 됨 → 아래 상세 |
| 31 | docker.sock 마운트 후에도 `mounts denied: The path /app/workspace(또는 /app/skills/...) is not shared from the host` | Docker-outside-of-Docker 패턴에서 컨테이너 내부 경로(`/app/workspace`, `SKILLS_HOST=/app/skills`)를 그대로 사촌 컨테이너의 bind mount source로 써서 실패 — 호스트 Docker 데몬은 그 경로를 컨테이너가 아니라 **맥(호스트) 파일시스템 경로**로 해석함 → 아래 상세 |
| 26 | base-agent/bpmn-extractor 로그에 `Could not find the function public.fetch_pending_task(...)`/`record_events_bulk(...)` in the schema cache 반복 (폴링 실패) | **근본원인**: `volumes/db/init.sql` 자체가 `type "public.agent_orch" does not exist` 에러로 중간에(3560줄 중 2698줄에서) 완전히 중단되어 그 뒤 800줄 이상(fetch_pending_task, record_events_bulk, tenant_skills 등)이 통째로 미실행 상태였음 → 아래 상세 |
| 32 | 채팅에 파일(PDF 등) 첨부 시 `POST /memento/save-to-storage` 500, "파일 업로드 실패: 알 수 없는 오류" | Supabase Storage에 `files`/`chat-images` 버킷 자체가 생성된 적 없음(`Bucket not found`) → 아래 상세 |
| 33 | 버킷 생성 후에도 같은 요청이 `The file system does not support extended attributes or has the feature disabled` 500 | `storage`/`imgproxy` 서비스가 `./volumes/storage`를 **bind mount**로 씀 — macOS Docker Desktop의 gRPC-FUSE/virtiofs 공유 파일시스템은 xattr(확장 속성)을 지원하지 않아 storage-api의 file 백엔드가 실패 → 아래 상세 (named volume으로 교체) |
| 34 | memento `/retrieve`가 `Client error '401 Unauthorized' for url 'http://litellm-proxy:4000/v1/embeddings'` | memento의 `LLM_BASE_URL`/`EMBEDDING_BASE_URL`이 OpenAI 직결 설정과 무관하게 항상 `http://litellm-proxy:4000/v1`로 하드코딩돼 있고, `OPENAI_EMBEDDING_MODEL` 기본값도 litellm 전용 로컬모델명(`qwen/qwen3-embedding-4b`)이라 OpenAI에 없는 모델 → 아래 상세 |
| 35 | bpmn-extractor가 파일 업로드 기반 요청에서 `메멘토에 사전 처리된 청크가 없습니다` (memento는 실제로 청크/임베딩 저장에 성공했는데도) | bpmn-extractor 서비스에 `MEMENTO_BASE_URL` env가 아예 없어 코드 기본값(`http://host.docker.internal:8005`)으로 접속 → 다른 모든 서비스가 쓰는 내부 도커 네트워크 이름 `memento:8005`가 아니라서 실패/404 → 아래 상세 |
| 36 | (해결됨 → #37) pdf2bpmn이 `Neo4j 선삭제 실패로 작업을 중단합니다: ... port 5432 ... Connection refused`로 항상 실패 | pdf2bpmn의 그래프 저장 계층("Neo4jClient")은 실제로는 실제 Neo4j가 아니라 **PostgreSQL의 Apache AGE 확장**을 쓰는데, `supabase/postgres` 기본 이미지엔 AGE가 컴파일돼 있지 않음 → age-postgres 전용 컨테이너로 해결 (#37) |
| 37 | AGE 미설치 (위 #36의 해결책) | 전용 `age-postgres`(apache/age 이미지) 컨테이너 + `AGE_DSN`/`GRAPH_DB_*` 와이어링 → 아래 상세 |
| 38 | AGE 설치 후에도 그래프는 구축되는데 추출 프로세스가 0건 저장, 로그에 `syntax error at or near "{"` `RETURN p {.*} as process` | AGE의 openCypher는 Neo4j 맵 프로젝션 문법(`x {.*}`)을 지원 안 함 → `properties(x)`로 치환 → 아래 상세 |
| 39 | HITL(스킬/DMN 승인) 단계에서 `record_events_bulk`가 `invalid input value for enum event_type_enum: "waiting_for_user"`로 재시도 실패 반복 | `event_type_enum`에 pdf2bpmn HITL 이벤트용 값(`waiting_for_user`/`task_cancelled`/`human_feedback_submitted`)이 없음 → 아래 상세 |
| 40 | HITL 스킬 승인 카드에서 "승인"을 눌러도 최종 `proc_def`의 스킬/에이전트 오케스트레이션이 비어서 저장됨 | 프론트가 `select_items`(체크박스) 질문을 승인/반려 2버튼 카드로 잘못 렌더링해 `selected_ids` 없이 제출 → 백엔드가 "0개 선택하고 승인"으로 정확히 해석해 스킵 → 아래 상세 (프론트 미수정, SQL 우회 있음) |
| 41 | PDF 샘플 문서에서 스킬은 생성되는데 에이전트 후보는 0개(`agents:{}` 질문 자체가 안 옴) | 스킬 클러스터링(지침 유사도)과 에이전트 후보 생성(같은 역할+같은 스킬 ≥2개 activity)의 조건이 어긋나거나, activity 이름이 너무 비슷해 스킬 클러스터링 전 단계에서 같은 역할 내 두 activity가 먼저 병합돼버림 → 아래 상세 |
| 42 | `proc_def`엔 스킬이 저장됐고 채팅에도 "생성됨"으로 뜨는데 실제 `SKILL.md` 파일이 `volumes/deepagents-skills/`에 없음, 스킬 카드 클릭해도 무반응 | ① `CLAUDE_SKILLS_BASE_URL` 기본값이 존재하지 않는 nginx 경로(`/claude-skills`)를 가리켜 SPA catch-all의 가짜 200을 성공으로 오인 ② `skill_docs` dict 키를 한글 표시명으로 만들어 영문 slug 기반 승인 키와 항상 불일치 → 조용히 스킵 ③ 두 실패 모두 로그/UI에 안 남음(3중 silent-failure) → 코드 수정 완료, 아래 상세 |
| 43 | 프로세스 생성 시 단 한 번만 쓰이는 분기(게이트웨이)에 대해서도 "DMN 의사결정 테이블을 만들까요?" HITL 질문이 매번 뜸 | `_collect_dmn_candidates_from_proc_json`의 DMN 후보 자격 조건이 "ExclusiveGateway + 분기 2개 이상"뿐이라 재사용 여부와 무관하게 모든 분기가 후보가 됨(DMN은 원래 여러 곳에서 재사용되는 규칙을 위한 것) → 같은 이름의 게이트웨이가 이 프로세스 안에 1개뿐이면(재사용 정황 없음) 후보에서 제외하도록 수정 완료, 아래 상세 |
| 44 | 채팅에서 "OO 프로세스 실행해줘"라고 하면 몇 단계 진행 후 "시스템 오류가 발생했습니다(API 오류: 'NoneType' object has no attribute 'get')"로 실패 | `process-gpt-mcp`(PyPI 패키지, work-assistant MCP)의 `get_api_base_url()`이 멀티테넌트 SaaS 도메인(`https://<tenant>.process-gpt.io`)을 하드코딩 — 자체 호스팅 설치엔 이 도메인이 없어 `execute_process`가 completion 서비스에 아예 도달 못 함 → `PROCESS_GPT_API_BASE_URL` env override 추가로 해결, 아래 상세 |
| 45 | 프로세스 인스턴스 실행 중 워크아이템 제출(`/completion/complete`)이 500 `'NoneType' object has no attribute 'get'`로 실패 | `submit_workitem()`이 `email`(`user_email`)이 요청에 없으면 `user_info=None`인 채로 `user_info.get('id')`를 무조건 호출 — null 가드 없음. `task_id`만으로 기존 워크아이템을 제출하는 모든 호출(이메일 생략)이 크래시함 → null-safe로 수정 완료, 아래 상세. **별개로, 같은 조사 중 게이트웨이 분기 선택 자체가 승인/반려 입력값과 무관하게 항상 "승인" 쪽으로만 가는 것도 관찰됨 — 이건 아직 원인 미확정(코드 수정 안 함), 아래 상세 참고** |
| 46 | Playwright로 로그인 자동화 시 `input[type="text"]` 로케이터가 간헐적으로 타임아웃되거나, 로그인 폼 자체가 안 보임 | 루트(`/`)가 이제 앱이 아니라 별도 마케팅 랜딩 페이지 — 백그라운드 활동이 계속 있어 `waitUntil: 'networkidle'`이 안정적으로 안 끝남 → 아래 상세 |
| 47 | proc_def에 스킬+에이전트가 정상 연결돼 있고 워크아이템도 무인으로 SUBMITTED→DONE 처리되는데, deepagents 로그엔 "스킬 설정 없음"만 뜨고 실제로 스킬이 전혀 안 쓰임 | 원인 A: 에이전트로 지정된 `users` 행의 `skills` 컬럼이 애초에 비어 있음(bpmn-extractor의 `_sync_skills_to_supabase`가 이 에이전트 생성 시점엔 안 붙었거나 실행 안 됨) → 아래 상세 |
| 48 | 위 #47의 `users.skills`를 채워도 여전히 `Cannot load skills from '/app/skills/...': path_not_found` | 원인 B: deepagents의 Docker-outside-of-Docker 샌드박스는 스킬을 `/skills/<name>`에 개별 마운트하는데, `_get_skills()`가 반환하는 경로는 이 API 컨테이너 자신의 뷰(`/app/skills/...`) 그대로라 샌드박스 backend로 ls()하면 항상 path_not_found — 게다가 마운트 여부 자체를 판단하는 `_skill_volumes()`도 호스트 절대경로(`SKILLS_HOST`)로 `.exists()`를 호출해 이 컨테이너 안에서는 절대 참이 될 수 없어 스킬 볼륨이 통째로 스킵됨 → 코드 3곳 수정, 아래 상세 |
| 49 | proc_def 활동에 `orchestration`을 명시적으로 지정 안 했는데도 담당자가 에이전트라서 자동으로 `agent_mode=COMPLETE`가 되는 활동이, 워크아이템 생성 직후 `IN_PROGRESS`에서 영원히 안 끝남 | `agent_orch`가 `crewai-deep-research`로 기본 폴백되는데, Core/Standard 프로파일엔 그 서비스 자체가 설치돼 있지 않아 아무도 이 워크아이템을 집어가지 않음(에러도 안 남) → 아래 상세 |
| 50 | 에이전트와 1:1 채팅에서 "기본 에이전트" 모드로 전송하면 항상 "(에이전트 준비 실패)"만 뜨고 응답이 안 옴(딥 에이전트 모드는 정상) | **버그 아님, 아키텍처 한계** — `agent-router`의 `/warmup`이 에이전트별 K8s 파드를 띄우는 구조라 `config.load_kube_config()`를 호출하는데, 이 설치엔 진짜 Kubernetes 클러스터가 없어 항상 500 → 아래 상세 |

## 상세 레시피

### #12 로그인 "가입된 이메일주소가 아닙니다" — 테넌트 불일치

프론트 `signIn`은 로그인 전에 `public.users`를
`{email, tenant_id: 접속호스트명}`으로 조회한다. `localhost:8088` 접속이면
tenant는 **`localhost`** 여야 한다.

```sql
-- auth uid 확인: select id from auth.users where email='<email>';
-- 주의: public.users의 PK는 (id, tenant_id) 복합키다. on conflict (id)만
-- 쓰면 "no unique or exclusion constraint matching" 에러가 난다(직접 재현
-- 확인함 — 데모 계정 스크립트 작성 중 발견, verification.md 4 참고).
insert into public.users (id, email, username, is_admin, role, tenant_id)
values ('<auth-uid>', '<email>', '<name>', true, 'superAdmin', '<접속호스트>')
on conflict (id, tenant_id) do update set role='superAdmin', is_admin=true;

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

`process-gpt-infra-docker`의 `nginx/nginx.conf`에는 이 라우트가 반영되어 있다 —
새 설치에서 증상이 재발하면 이미지/설정 버전 불일치를 의심하고 라우트 존재부터 grep.

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

### #19–21 supabase-db init 부분 실패 → auth 소유권/마이그레이션 연쇄 장애 (신규 설치)

`process-gpt-infra-docker`의 `volumes/db/roles.sql`은 기본적으로:

```sql
ALTER USER authenticator WITH PASSWORD :'pgpass';
ALTER USER pgbouncer WITH PASSWORD :'pgpass';
ALTER USER supabase_auth_admin WITH PASSWORD :'pgpass';
ALTER USER supabase_functions_admin WITH PASSWORD :'pgpass';  -- 조건부 생성 role
ALTER USER supabase_storage_admin WITH PASSWORD :'pgpass';
```

`supabase_functions_admin`은 `98-webhooks.sql`이 pg_net 확장/스키마 상태에
따라 조건부로만 만든다 — 없으면 `ON_ERROR_STOP=1` 때문에 스크립트 전체가
abort되고, 뒤에 있는 `supabase_storage_admin` 패스워드 설정도 이어지는
`migrations/*.sql`(auth 스키마 소유권 이전 포함)도 실행되지 않는다. 컨테이너를
재시작해도 `PGDATA`가 이미 있어 init 스크립트를 통째로 스킵하므로 저절로
복구되지 않는다.

**예방(레포 파일 수정)**: `volumes/db/roles.sql`에서 순서를 바꾸고 문제 role만
`ON_ERROR_STOP`을 잠깐 끈다:

```sql
ALTER USER authenticator WITH PASSWORD :'pgpass';
ALTER USER pgbouncer WITH PASSWORD :'pgpass';
ALTER USER supabase_auth_admin WITH PASSWORD :'pgpass';
ALTER USER supabase_storage_admin WITH PASSWORD :'pgpass';
\set ON_ERROR_STOP off
ALTER USER supabase_functions_admin WITH PASSWORD :'pgpass';
\set ON_ERROR_STOP on
```

**이미 이 상태로 떠버린 DB 복구(볼륨 유지, 재초기화 없이)**:

```bash
# 1) roles.sql 재실행 (수정본으로)
docker exec -u postgres supabase-db psql -v ON_ERROR_STOP=1 --no-password \
  --no-psqlrc -U postgres -f /docker-entrypoint-initdb.d/init-scripts/99-roles.sql

# 2) migrations/*.sql 순서대로 재실행 (대부분 idempotent — IF NOT EXISTS/예외처리)
docker exec -u postgres supabase-db bash -c '
for f in $(ls /docker-entrypoint-initdb.d/migrations/*.sql | sort); do
  psql -v ON_ERROR_STOP=1 --no-password --no-psqlrc -U supabase_admin -f "$f"
done'

# 3) 그래도 auth가 "must be owner of ..."로 실패하면 auth 스키마 전체 소유권 이전
#    (postgres는 demote-postgres.sql로 superuser 박탈된 상태라 -U supabase_admin으로 실행)
docker exec -i -u postgres supabase-db psql -v ON_ERROR_STOP=1 --no-password \
  --no-psqlrc -U supabase_admin -d postgres <<'SQL'
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
SQL

# 4) 특정 GoTrue 버전이 "이미 최신 타입인데 옛날 마이그레이션이 실패"하면
#    (예: 20221208132122, uuid=text 캐스팅 에러) 데이터 없는 신규 설치에 한해
#    완료 처리만 (실질적 부작용 없음):
docker exec -u postgres supabase-db psql -U postgres -d postgres -c \
  "insert into auth.schema_migrations (version) values ('<실패한 버전>');"

docker restart supabase-auth
```

전체 버전 목록과 diff하려면:
`docker run --rm --entrypoint sh supabase/gotrue:<tag> -c 'ls /usr/local/etc/auth/migrations'`

### #22 컨테이너는 Up인데 응답 없음 — QEMU 세그폴트 (메모리 고갈)

무관한 다른 프로젝트 스택이 동시에 떠 있어 메모리가 고갈되면, amd64 바이너리를
arm64에서 에뮬레이션 중인 프로세스(특히 Haskell로 컴파일된 PostgREST)가
세그폴트로 죽는다. 컨테이너 자체(PID 1 wrapper)는 안 죽고 `Up`으로 남아있어
`docker ps`만으로는 정상처럼 보이므로 반드시 로그로 확인:

```bash
docker logs -t <service> | tail -10   # 마지막 줄이 "qemu: uncaught target signal 11"인지 확인
docker inspect <service> --format 'StartedAt={{.State.StartedAt}} RestartCount={{.RestartCount}}'
```

해결: `docker run --rm busybox free -h`로 Docker VM 메모리 확인 →
부족하면 무관 스택을 `docker stop`(사용자 승인 후) → `docker restart <service>`.

### #23 로컬 캐시 이미지 재태깅으로 빌드/pull 실패 우회

```bash
docker images ghcr.io/uengine-oss/<name>   # 로컬에 어떤 태그가 있는지 확인
docker tag ghcr.io/uengine-oss/<name>:<로컬태그> ghcr.io/uengine-oss/<name>:<compose가 요구하는 태그>
```

`polling-service`처럼 `build:` 없이 `image:`만 있는 서비스는 GHCR 로그인이
없을 때 이 방법이 유일한 우회책이다.

⚠️ **frontend처럼 `image:`+`build:`가 둘 다 있는 서비스에는 이 방법을 쓰지
말 것** — 재태깅은 `services/frontend`의 **현재 소스**를 빌드하는 게
아니라 로컬에 있던 **다른(대개 훨씬 오래된) 빌드 결과물**을 요구 태그로
관재로 라벨만 바꿔 붙이는 것이라, 겉보기엔 `docker compose up`이 성공해도
실제로는 옛날 코드가 계속 돈다(이 우회로 인해 "프론트가 몇 달 전
버전"으로 보이는 사고가 실제 발생 — #15, INSTALL_MEMORY.md #23 참고).
`image:`+`build:`가 둘 다 있는 서비스는 **반드시 #15/아래 "로컬 개발
환경에서는 --build 필수" 절**대로 `docker compose up -d --build` (또는
`start-all-services.sh --build`)로 실제 재빌드해야 한다.

### #15-b 로컬 개발 환경에서는 앱 서비스에 반드시 `--build`를 붙일 것

`docker-compose.yml`의 모든 자체 개발 서비스(frontend, completion,
base-agent-langchain-react, memento, polling-service, deepagents,
bpmn-extractor, strategy, agent-router 등 `services/` 아래 서브모듈로
관리되는 것 전부)는 `image:`(GHCR에 고정된 옛 태그)와
`build:`(`./services/<name>` 현재 소스) **둘 다** 정의돼 있다. Docker
Compose는 `--build`를 명시하지 않으면 **항상 `image:`를 우선**하므로,
`git submodule update`로 최신 소스를 받아놔도 `docker compose up -d`나
`start-all-services.sh`(플래그 없이)를 실행하면 조용히 GHCR의 옛 이미지가
뜬다 — 서브모듈 커밋 시각과 무관하게 매번 같은 결과.

**로컬 개발용(local-dev) 설치 모드에서는 이게 기본값이면 안 된다** — 개발
중인 서비스를 실제로 개발 중인 소스로 띄우는 게 이 모드의 목적이므로.
`start-all-services.sh`에 `-b`/`--build` 플래그를 추가해뒀다:

```bash
./start-all-services.sh --build all              # 전체를 소스 빌드
./start-all-services.sh --build frontend memento  # 특정 서비스만
```

`--build`는 인프라(Supabase 전 서비스, age-postgres, neo4j, litellm)에는
영향 없다 — 이 컨테이너들은 애초에 `build:` 블록이 없는 서드파티 이미지라
`--build`를 줘도 그냥 pull된 이미지를 그대로 쓴다. `nginx`(게이트웨이)는
`depends_on`으로 앱 서비스들을 물고 있어서 `start_gateway()`가
`--build`로 nginx를 올리면 그 의존 서비스들도 함께 재빌드된다 — 의도된
동작이다.

검증: `docker inspect <image> --format '{{.Created}}'`가 해당
서브모듈의 `git log -1 --format=%ci` 이후 시각이면 정상 반영된 것.
`docker tag`로 재태깅된 옛 이미지는 태그의 겉보기 `CreatedAt`(docker
images 목록)은 최신으로 보여도 `docker inspect`의 실제 빌드 시각은 그대로
과거이므로 구분된다.

### #25 nginx `$upstream_agent` 호스트명 불일치

`nginx/nginx.conf`의 `/agent/chat/stream` 라우트만 다른 라우트(`frontend`,
`completion`, `memento`, `deepagents` 등은 전부 plain 서비스명 사용)와 다르게
`process-gpt-base-agent-langchain-react:8000`처럼 옛 컨테이너명 접두사가 붙어
있다. compose 서비스명은 `base-agent-langchain-react`이므로 nginx의 내장
DNS(127.0.0.11)가 이 호스트를 못 찾아 502.

```nginx
# 수정 전
set $upstream_agent process-gpt-base-agent-langchain-react:8000;
# 수정 후
set $upstream_agent base-agent-langchain-react:8000;
```

수정 후 `docker restart <nginx 컨테이너>` (바인드마운트라 reload로는 부족,
#13-b와 동일 이유).

### #26 `fetch_pending_task` 함수 없음 — 레포 이원화로 마이그레이션 누락

`process-gpt-infra-docker`(compose용 `volumes/db/init.sql`)와
`services/frontend/supabase/migrations/*.sql`(프론트 서브모듈 자체 마이그레이션)
이 스키마 관리 경로가 분리되어 있어, `init.sql`에 없는 함수/테이블이 프론트
마이그레이션에만 존재하는 경우가 있다. `fetch_pending_task(p_agent_orch,
p_consumer[, p_env], p_limit)`가 대표 사례 — base-agent/completion의 폴링
루프가 이 함수를 호출하는데 `init.sql`엔 `openai_deep_fetch_pending_task`만
있고 범용 버전이 없다.

`services/frontend/supabase/migrations/202602230001_recreate_fetch_pending_task_with_query.sql`에
정의는 있지만, RETURNS TABLE의 `agent_orch agent_orch`(enum 타입 가정)가 현재
`init.sql` 스키마의 실제 컬럼 타입(`agent_orch text`, enum 타입 자체가 없음)과
안 맞아 그대로 적용하면 타입 에러가 난다 — `agent_orch agent_orch` →
`agent_orch text`로 바꿔 만들어야 한다 (다른 컬럼은 그대로: `todo_status`/
`agent_mode`/`draft_status` enum은 이미 존재). 적용 후
`docker exec ... psql -c "NOTIFY pgrst, 'reload schema';"`와 base-agent
재시작 필요.

**교훈**: 프론트 서브모듈의 `supabase/migrations/`에 새 마이그레이션이 있는데
`init.sql`에 없는 함수/테이블 404·PGRST202 에러가 나면, 그 마이그레이션 파일을
찾아 (필요시 현재 스키마에 맞게 타입을 보정해) 직접 적용하는 패턴을 우선
시도한다. 아직 미확인이나 같은 원인(아래 #27)일 가능성 있는 것(설치 중 관찰된
404/406, Core 데모엔 영향 없어 보류): `get_credit_balance` RPC, `configuration`
테이블, `org_chart_groups` 테이블.

### #27 (근본원인) `init.sql`이 `agent_orch` enum 타입 누락으로 2698줄에서 통째로 중단

`docker exec -u postgres supabase-db psql ... -f .../100-init.sql`은
`migrate.sh`가 `ON_ERROR_STOP=1`로 실행하므로, 파일 중간의 에러 하나가 **그
뒤 전체(수백~수천 줄)를 통째로 미실행 상태로 만든다**. 이번 설치에서 실제로
`volumes/db/init.sql`(총 3560줄) 이 2598번째 줄 근처
(`deep_research_fetch_pending_task` 함수의 `t.agent_orch::public.agent_orch`
캐스팅)에서 `ERROR: type "public.agent_orch" does not exist`로 죽어, 그 뒤에
정의된 `fetch_pending_task`, `record_events_bulk`, `tenant_skills` 등이 전부
없는 상태였다. `public.agent_orch`는 `services/frontend/supabase/migrations/
20260101_base_schema.sql`엔 enum으로 정의돼 있지만 `process-gpt-infra-docker`
쪽 `init.sql`엔 그 `CREATE TYPE` 자체가 없고, 실제 `todolist.agent_orch`
컬럼도 `text`다 (enum 아님, 게다가 현재 데이터엔 `pdf2bpmn` 처럼 그 enum
정의에도 없는 값이 들어감) — 즉 enum을 새로 만드는 대신 **해당 캐스팅
2곳(값 캐스트 1곳 + RETURNS TABLE 선언 1곳)을 text로 고치는 게 맞는 수정**.

**진단 방법** — postgres 로그에서 최초 부팅 시점의 에러를 찾는다:
```bash
docker logs supabase-db 2>&1 | grep -n "ERROR" | head -20
# 예: "psql:/docker-entrypoint-initdb.d/init-scripts/100-init.sql:2698: ERROR: ..."
```
이 줄 번호가 파일 중간이면(끝이 아니면) 그 뒤로 전체가 안 만들어졌다고 의심.

**복구(볼륨 재생성 없이, 실행 중인 DB에 바로 적용)**:
```bash
# 1) 호스트의 init.sql에서 문제의 캐스팅을 text로 수정 (::public.agent_orch 제거,
#    RETURNS TABLE의 `agent_orch public.agent_orch` -> `agent_orch text`)
# 2) 에러 지점 이후(안 만들어진 부분)만 잘라서 재실행
PGPW=$(grep -E '^POSTGRES_PASSWORD=' .env | cut -d= -f2-)
tail -n +2598 volumes/db/init.sql | \
  docker exec -i -e PGPASSWORD="$PGPW" supabase-db psql -v ON_ERROR_STOP=1 -U supabase_admin -d postgres
```
`CREATE OR REPLACE FUNCTION`/`CREATE TABLE IF NOT EXISTS`/`DROP ... IF EXISTS`
패턴이 대부분이라 중단 지점부터 EOF까지 통째로 재실행해도 안전하다(이미 있는
객체는 NOTICE만 뜨고 스킵). 이 재실행이 **다른 새 에러**(예: 파일 맨 끝
`skill_feedback_proposals` — 실제 테이블명은 `feedback_proposals`인데
함수가 옛 이름을 참조하는 오탈자, Core 데모와 무관해 미수정)에 또 부딪히면
그 지점까지만 반영되고 넘어간 것이니 같은 방식으로 추가 확인.

**주의(중요)**: init.sql 자체에도 `fetch_pending_task(p_agent_orch, p_consumer,
p_limit, p_env)` (SETOF todolist, enum 문제 없음) 정의가 있다 — #26에서 급히
만든 임시 버전과 파라미터 이름이 같고 순서만 달라 **PostgREST가 두 오버로드
중 하나를 못 골라 PGRST203("Could not choose the best candidate function")**
에러가 난다. init.sql 재생 후에는 임시로 만든 버전을 반드시 `DROP FUNCTION`
하고 init.sql의 정식 버전만 남겨야 한다:
```sql
DROP FUNCTION public.fetch_pending_task(p_agent_orch text, p_consumer text, p_env text, p_limit integer);
NOTIFY pgrst, 'reload schema';
```
수정 후 `base-agent-langchain-react`/`bpmn-extractor`/`completion`/
`polling-service` 전부 재시작해 스키마 캐시를 새로 받게 한다.

### #28 `/process-gpt-deepagents/*` — nginx에 없는 프론트 전용 경로

프론트 소스 `services/frontend/src/services/DeepAgentRouterService.js`의
`baseUrl`은 `/process-gpt-deepagents`인데, `nginx/nginx.conf`엔 `/deepagents/`
(및 `/deepagents/chat/stream`)만 정의돼 있다. 없는 경로라 404가 아니라 맨 아래
`location /`(frontend catch-all)로 떨어져 **SPA index.html을 200으로 반환** —
겉보기엔 "에러 없음"이라 딥에이전트 채팅이 조용히 실패한다(응답이 그냥 안
옴). frontend는 이미지로 pull해서 쓰므로(troubleshooting #23 참고) 소스를
고칠 수 없어, nginx 쪽에 동일한 별칭(alias) 라우트를 추가하는 게 실질적인
해결책이다:

```nginx
# /deepagents/chat/stream 블록 바로 뒤에 추가
location = /process-gpt-deepagents/chat/stream {
  set $upstream_deepagents deepagents:8888;
  proxy_pass http://$upstream_deepagents/chat/stream;
  proxy_http_version 1.1;
  proxy_buffering off;
  proxy_read_timeout 3600s;
  proxy_set_header Host $host;
  proxy_set_header X-Real-IP $remote_addr;
  proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
  proxy_set_header X-Forwarded-Proto $scheme;
}

# /deepagents/ 블록 바로 뒤에 추가
location /process-gpt-deepagents/ {
  set $upstream_deepagents_root deepagents:8888;
  rewrite ^/process-gpt-deepagents/(.*)$ /$1 break;
  proxy_pass http://$upstream_deepagents_root;
  proxy_set_header Host $host;
  proxy_set_header X-Real-IP $remote_addr;
  proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
  proxy_set_header X-Forwarded-Proto $scheme;
}
```

`docker restart <nginx 컨테이너>` 후 `curl .../process-gpt-deepagents/health`가
`{"status":"ok"}`를 반환하는지 확인.

### deepagents 오케스트레이션 UI를 못 찾을 때

`AgentSelectField.vue`의 `orchestration: 'deepagents'` 옵션은 **에이전트
동료(사이드바) 프로필 편집기에는 없다** — 신규/A2A/ProcessGPT 에이전트 생성
모달 3개 탭 전부 확인했지만 오케스트레이션 선택지가 없었다. 이 필드는 BPMN
디자이너에서 개별 액티비티(태스크)에 에이전트를 배정할 때만 노출되는 것으로
보인다. 즉 "이 프로세스를 deepagents로 실행"을 UI로 시연하려면 **먼저 해당
프로세스의 BPMN 다이어그램이 정상 렌더링되어야** 액티비티 속성 패널에
접근할 수 있다 — proc_def_version 스냅샷이 없는 프로세스(#29 참고)는 이
경로 자체가 막힌다.

### #29 채팅으로 생성된 프로세스가 "정의된 프로세스 모델이 없습니다"

pdf2bpmn/bpmn-extractor 에이전트가 프로세스를 생성하면 `proc_def.definition`
(jsonb)엔 구조화된 내용이 제대로 들어가지만, `proc_def.bpmn`(raw XML 텍스트)과
`proc_def_version` 스냅샷 행은 채워주지 않는다. BPMN 디자이너/뷰어는 이 중
하나가 있어야 다이어그램을 그리므로, `/definition-map/sub/<id>`로 들어가면
"정의된 프로세스 모델이 없습니다"만 보인다 — `proc_def`에 데이터가 없는 게
아니라(실제로 있음, `select * from proc_def` 확인됨) **뷰어가 기대하는
다른 컬럼/테이블이 비어있는 것**. 채팅 완료 메시지("프로세스 정의가
저장되었습니다")와 실제 DB persist(`proc_def` 1행 생성, 이번 검증 통과
기준)는 정상이므로 설치 검증 자체엔 영향 없다 — BPMN 시각 편집만 막힌다.
근본 수정은 bpmn-extractor 에이전트의 저장 로직(벤더 서비스 코드) 쪽이라
인프라 설치 범위 밖으로 보류.

### #32 Storage 버킷 누락 — 채팅 파일 첨부/PDF 업로드 500

프론트가 `/memento/save-to-storage`로 파일을 올리면 memento는
`supabase.storage.from_("files").upload(...)`(또는 프론트 직접 업로드 시
`from('chat-images')`)를 호출하는데, **Supabase Storage에 이 버킷들이
존재한 적이 없다**(`select * from storage.buckets` → 0 rows). `init.sql`도
버킷을 만들지 않는다 — Storage API는 버킷을 애플리케이션 코드가 아니라
관리자가 별도로 생성해줘야 하는 리소스다.

```sql
insert into storage.buckets (id, name, public) values ('files', 'files', true)
  on conflict (id) do nothing;
insert into storage.buckets (id, name, public) values ('chat-images', 'chat-images', true)
  on conflict (id) do nothing;
```

memento/frontend 모두 `SUPABASE_KEY`로 `SERVICE_ROLE_KEY`를 쓰므로 RLS는
우회된다 — 버킷 존재 여부만 문제였다.

### #33 storage/imgproxy — macOS bind mount는 xattr 미지원

버킷을 만든 후에도 같은 업로드가 `The file system does not support extended
attributes or has the feature disabled`로 500이 나면, `storage`(및 그 파일을
읽는 `imgproxy`) 서비스의 볼륨이 호스트 bind mount
(`./volumes/storage:/var/lib/storage:z`)인지 확인한다. Docker Desktop for
Mac의 gRPC-FUSE/virtiofs 공유 파일시스템은 xattr을 지원하지 않는데,
`storage-api`의 `STORAGE_BACKEND=file` 모드는 메타데이터 저장에 xattr을 쓴다.

해결: **named volume으로 교체**(Docker Desktop VM 내부 진짜 리눅스
파일시스템이라 xattr 지원). `storage`와 `imgproxy` 둘 다 같은 볼륨을 봐야
하므로 함께 바꾼다:

```yaml
# docker-compose.yml
storage:
  volumes:
    - storage-data:/var/lib/storage   # 기존: ./volumes/storage:/var/lib/storage:z
imgproxy:
  volumes:
    - storage-data:/var/lib/storage   # 기존: ./volumes/storage:/var/lib/storage:z
volumes:
  storage-data:   # 최상단 volumes: 섹션에 추가
```

`./volumes/storage`에 기존 데이터가 있었다면 전환 전에 `du -sh`로 확인 —
비어있으면(모든 업로드가 이미 실패해왔다면 거의 확실히 비어있음) 그냥
바꿔도 안전하다.

### #34 memento 임베딩 401 — LLM_BASE_URL/EMBEDDING_BASE_URL이 litellm-proxy 하드코딩

`docker-compose.yml`의 `memento` 서비스는 OpenAI 직결(local-dev.md 권장) 여부와
무관하게 `LLM_BASE_URL`/`EMBEDDING_BASE_URL`을 **항상**
`http://litellm-proxy:4000/v1`로 하드코딩해뒀다. OpenAI 직결 구성에서는
litellm-proxy가 제대로 라우팅되지 않아(모델 미등록 등) `401 Unauthorized`가
난다. 게다가 `OPENAI_EMBEDDING_MODEL` 기본값(`qwen/qwen3-embedding-4b`)도
litellm 전용 로컬 모델명이라 OpenAI API엔 존재하지 않는 모델이다.

```yaml
# 수정 전
LLM_BASE_URL: http://litellm-proxy:4000/v1
EMBEDDING_BASE_URL: http://litellm-proxy:4000/v1
OPENAI_EMBEDDING_MODEL: ${OPENAI_EMBEDDING_MODEL:-qwen/qwen3-embedding-4b}
# 수정 후 (.env의 LLM_PROXY_URL을 그대로 재사용 — OpenAI 직결이면 https://api.openai.com/v1)
LLM_BASE_URL: ${LLM_PROXY_URL}
EMBEDDING_BASE_URL: ${LLM_PROXY_URL}
OPENAI_EMBEDDING_MODEL: ${OPENAI_EMBEDDING_MODEL:-text-embedding-3-small}
```

`.env`의 `OPENAI_EMBEDDING_MODEL=qwen/qwen3-embedding-4b`도
`text-embedding-3-small`(실제 OpenAI 임베딩 모델)로 바꿔야 한다. 수정 후
`docker compose up -d memento`로 재기동.

### #35 bpmn-extractor `MEMENTO_BASE_URL` 누락 — host.docker.internal로 잘못 폴백

`docker-compose.yml`의 `bpmn-extractor` 서비스 environment 블록엔
`MEMENTO_BASE_URL`이 아예 없다. 코드 기본값(`services/bpmn-extractor/src/
pdf2bpmn/config.py`)은 `http://host.docker.internal:8005`인데, 이건 다른
로컬 프로세스가 호스트 8005 포트를 점유하고 있으면(흔함 — 다른 프로젝트들이
자주 씀) 그쪽으로 라우팅되어 엉뚱한 응답(404 등)을 받는다. 반드시 다른
서비스들(`deepagents`의 `MEMENTO_BASE_URL: "http://memento:8005"` 등)과
동일하게 **내부 도커 네트워크 이름**을 써야 한다:

```yaml
# bpmn-extractor environment 블록에 추가
MEMENTO_BASE_URL: http://memento:8005
```

증상 진단 팁: memento 로그에 `[vector_store] add_documents done`(업로드/임베딩
성공)이 보이는데도 bpmn-extractor가 "청크가 없다"고 하면, 컨테이너 내부에서
직접 연결 테스트:
```bash
docker exec <bpmn-extractor 컨테이너> python3 -c "
import urllib.request
print(urllib.request.urlopen('http://host.docker.internal:8005/documents/chunks-with-embeddings?tenant_id=<tenant>', timeout=5).status)"
```
404/타임아웃이면 `MEMENTO_BASE_URL`부터 확인.

### #36 (해결됨 → #37 참고) pdf2bpmn의 Apache AGE 의존성 — supabase/postgres 이미지엔 없음

파일(PDF 등) 첨부 기반 프로세스 생성은 #32~#35를 전부 고쳐도 마지막에
`Neo4j 선삭제 실패로 작업을 중단합니다: ... port 5432 ... Connection refused`
(또는 AGE_DSN을 고치면 `could not open extension control file ... No such
file or directory`)로 실패한다.

**원인**: `services/bpmn-extractor/src/pdf2bpmn/graph/neo4j_client.py`의
`Neo4jClient`는 이름과 달리 실제로는 **PostgreSQL Apache AGE 확장**을
씁니다(`psycopg.connect(AGE_DSN)` 후 `CREATE EXTENSION IF NOT EXISTS age`).
컴포즈가 함께 띄우는 진짜 Neo4j(`neo4j:7687`, `NEO4J_URI` 등)는 이 경로에서
전혀 쓰이지 않는다 — 이름만 같을 뿐 별개의 두 그래프 백엔드다. AGE는
프로세스 추출 파이프라인 전체(에이전트/역할 생성, 시퀀스, 그래프 스냅샷,
프로세스 상세 조회 등 6곳 이상)의 **핵심 저장소**로 쓰이는데,
`supabase/postgres:15.8.1.060` 이미지엔 AGE가 컴파일돼 있지 않다
(`select * from pg_available_extensions where name='age'` → 0 rows).

**최종 해결책**: `strategy` 서비스(온톨로지 그래프)도 어차피 AGE가 필요해
이미 같은 패턴(`services/strategy/docker-compose.age.yml`)을 쓰고 있었다 —
Supabase의 postgres 이미지를 건드리는 대신, `apache/age:release_PG16_1.5.0`
공식 이미지로 **별도 전용 Postgres 인스턴스**(`age-postgres`)를 띄우고
`bpmn-extractor`(`AGE_DSN`)와 `strategy`(`GRAPH_DB_*`)가 이를 공유하도록
와이어링했다. 자세한 내용과 자동화는 #37 참고. 이 해결로 그래프 자체는
정상 구축되지만(노드/엣지 생성 성공), 실제 프로세스 추출 결과가 0건으로
저장되는 후속 문제가 있었다 — #38(Cypher 문법 비호환) 참고.

**시도했으나 불충분했던 것**: 초기 정리 단계(`_clear_process_core_labels`)의
"fail fast" 예외를 경고+계속으로 완화(`pdf2bpmn_agent_executor.py` 9022줄
부근) — AGE 자체가 없던 시점에는 이후 단계에서 결국 같은 AGE 연결로 또
실패했다. AGE를 실제로 설치한 지금은 이 완화가 실질적으로 필요 없어졌지만
부작용이 없어 코드에는 남겨두었다.

### #37 Apache AGE 설치 — `age-postgres` 전용 컨테이너 + `AGE_DSN`/`GRAPH_DB_*` 와이어링

#36의 최종 해결책. `docker-compose.yml`에 아래 서비스를 추가한다(전체
반영 사항은 `post-clone-fixes.sh` 9번 항목이 자동으로 해준다):

```yaml
age-postgres:
  image: apache/age:release_PG16_1.5.0
  platform: linux/amd64   # Apple Silicon에서도 필요 (arm64 네이티브 이미지 없음)
  environment:
    POSTGRES_USER: postgres
    POSTGRES_PASSWORD: postgres
    POSTGRES_DB: postgres
  ports:
    - "55433:5432"
  volumes:
    - age-postgres-data:/var/lib/postgresql/data
  healthcheck:
    test: [ "CMD-SHELL", "pg_isready -U postgres -d postgres" ]
    interval: 10s
    timeout: 5s
    retries: 5
    start_period: 20s
```

`bpmn-extractor` environment에 `AGE_DSN: postgresql://postgres:postgres@age-postgres:5432/postgres`,
`strategy` environment에 `GRAPH_DB_HOST: age-postgres` / `GRAPH_DB_PORT: "5432"` /
`GRAPH_DB_NAME: postgres` / `GRAPH_DB_USER: postgres` / `GRAPH_DB_PASSWORD: postgres`를
추가하고 두 서비스 모두 `depends_on: age-postgres: condition: service_healthy`를 건다.

**주의 — `container_name`을 고정하지 말 것**: `services/strategy/docker-compose.age.yml`을
과거에 한 번이라도 별도로 띄워본 적이 있는 환경이면 `process-gpt-age-postgres`라는
이름의(데이터가 이미 들어있는) 컨테이너가 남아있을 수 있다. 새 서비스에
같은 `container_name`을 박아두면 `docker compose up`이
`Conflict... container name ... already in use`로 실패한다. 이런 컨테이너를
발견하면 **삭제하지 말고**(기존 그래프 데이터가 있을 수 있음)
`docker network connect --alias age-postgres <프로젝트>_default process-gpt-age-postgres`로
기존 컨테이너를 이 compose 프로젝트 네트워크에 별칭으로 연결해 재사용하거나,
사용자에게 삭제 여부를 확인한다.

검증:
```bash
docker exec <bpmn-extractor 컨테이너> python3 -c "
import psycopg
conn = psycopg.connect('postgresql://postgres:postgres@age-postgres:5432/postgres', autocommit=True)
conn.execute('CREATE EXTENSION IF NOT EXISTS age')
print('AGE connect+load OK')"
```

### #38 AGE Cypher가 Neo4j 맵 프로젝션 문법(`node {.*}`)을 지원하지 않음

AGE 설치(#37) 후에도 그래프는 정상 구축되는데(로그에 `nodes=21, edges=30` 등
정상 카운트) 실제 추출된 프로세스가 **0건**으로 저장된다. bpmn-extractor
로그에 다음 경고가 남는다:
```
[WARN] process detail 조회 중 예외: proc_id=..., err=syntax error at or near "{"
LINE 10: RETURN p {.*} as process,
```

**원인**: `RETURN p {.*} as x` / `RETURN p {.name, .id} as x`는 Neo4j 전용 맵
프로젝션 문법으로, AGE의 openCypher 서브셋은 이를 지원하지 않는다. AGE에서는
반드시 `properties(p)` 함수를 써야 한다. 같은 코드베이스의 다른 정상 동작
쿼리들이 이미 `properties()`를 쓰고 있어 확인된 패턴이다.

**해결**: 아래 3개 파일에서 `<var> {.*}` 및 `<var> {.field1, .field2, ...}`
패턴을 전부 `properties(<var>)`로 치환한다 (post-clone-fixes.sh 10번 항목이
정규식으로 자동 처리):
- `services/bpmn-extractor/src/pdf2bpmn/graph/neo4j_client.py`
  (`get_all_processes`, `get_process_with_details`, `get_open_ambiguities`)
- `services/bpmn-extractor/src/pdf2bpmn/api/main.py` (5곳)
- `services/bpmn-extractor/src/pdf2bpmn/graph/vector_search.py` (2곳)

수정 후 확인:
```bash
grep -rn '{\.\*}\|[a-zA-Z_][a-zA-Z0-9_]* {\.[a-zA-Z_]' services/bpmn-extractor/src/pdf2bpmn/
# 아무 결과도 없어야 함
```
이 수정 후에는 실제로 프로세스가 추출·저장되고, 활동 지침 텍스트가 반복되는
패턴에 대한 스킬 클러스터링(`[SKILL][CLUSTER] ... clusters=N`)도 정상 동작해
`agentMode=complete`/`orchestration=deepagents`가 붙는 것까지 확인했다.

### #39 `event_type_enum`에 없는 값 — HITL 이벤트가 조용히 유실됨

PDF 첨부 프로세스 생성이 스킬/에이전트/DMN 승인을 묻는 HITL(human-in-the-loop)
단계에서 멈춘 채 진행이 안 될 때, bpmn-extractor 로그에 이런 에러가 반복된다:
```
FATAL: retry failed: name=record_events_bulk retries=3 error={'message':
  'invalid input value for enum event_type_enum: "waiting_for_user"', 'code': '22P02', ...}
❌ record_events_bulk failed: events not persisted count=N
```
같은 패턴으로 `"task_cancelled"`, `"human_feedback_submitted"`도 발생할 수 있다.

**원인**: `volumes/db/init.sql`의 `event_type_enum`은 초기 값 목록
(`task_started`, `task_completed`, `tool_usage_started`, `tool_usage_finished`,
`crew_completed`, `human_asked`, `human_response`, `human_checked`,
`task_working`, `error`)만 갖고 있는데, pdf2bpmn의 HITL 진행 상태 이벤트가
이 목록에 없는 값(`waiting_for_user`, `task_cancelled`,
`human_feedback_submitted`)을 기록하려다 매 재시도마다 실패한다. 이벤트가
DB에 안 남으니 프론트가 질문 카드를 못 그리거나 진행률이 멈춘 것처럼 보인다.

**해결**(post-clone-fixes.sh 9번 항목이 `init.sql`의 enum 정의 자체에
자동으로 반영한다 — 새로 클론하는 설치는 아예 이 문제를 겪지 않는다):
```sql
-- 이미 떠 있는 환경에서 즉시 고치려면:
ALTER TYPE event_type_enum ADD VALUE IF NOT EXISTS 'waiting_for_user';
ALTER TYPE event_type_enum ADD VALUE IF NOT EXISTS 'task_cancelled';
ALTER TYPE event_type_enum ADD VALUE IF NOT EXISTS 'human_feedback_submitted';
NOTIFY pgrst, 'reload schema';
-- 그 후 bpmn-extractor 컨테이너 재시작
```

### #40 HITL "스킬 승인" 카드에서 승인해도 스킬/deepagents 오케스트레이션이 비어서 저장됨

PDF 첨부로 생성된 프로세스가 스킬 클러스터링까지는 성공하고(`[SKILL][CLUSTER]
... clusters=N`) HITL 질문("어떤 스킬을 생성할까요?")도 뜨는데, 채팅 UI에서
"승인" 버튼을 누르고 제출해도 최종 `proc_def.definition.skills`가 빈 배열로,
관련 activity들의 `agentMode`가 `"none"`(기대값: `"complete"`/`orchestration:
"deepagents"`)으로 저장된다.

**원인**: 이 질문은 백엔드가 `feedback_type: "select_items"`(체크박스로 개별
스킬 항목을 선택하는 UI)로 보내는데, 프론트(`ChatRoomPage.vue`
`addPdf2BpmnHumanQuestionMessage`/`Chat.vue`)가 실제로는 `승인`/`반려` 두
버튼짜리 `approve_reject_with_edit` 카드로 렌더링하는 경우가 있다(정확한
분기 조건은 미확정 — 라이브 이벤트 경로와 `loadExistingEvents`를 통한
재구성 경로 둘 다 코드상으로는 `question.feedback_type`을 그대로 따르게
되어 있어 재현 조건을 특정하지 못했다). 이 카드에서 "승인"을 누르면
`selected_ids` 없이 `{"action":"approve","answer":"승인",...}`만 제출되고,
백엔드(`pdf2bpmn_agent_executor.py` 부근 `hitl_selected_ids(sk_entry)`)는
이를 "사용자가 스킬을 0개 선택하고 승인함" = **스킬 생성 스킵**으로
정확하게 해석한다. 즉 백엔드는 정상 동작하고 있고, 사용자가 뭘 골랐는지와
무관하게 프론트가 선택 정보를 안 실어 보내는 게 문제다.

**증상 재현/확인 방법**: 응답 제출 후 `todolist.output.hitl_feedbacks`를
직접 조회해서 `selected_ids` 필드가 있는지 확인한다:
```sql
select jsonb_pretty(output->'hitl_feedbacks') from todolist where id='<task_id>';
```
`selected_ids`가 없거나 빈 배열이면 이 버그에 해당한다.

**임시 우회(데모/검증용)**: 프론트를 거치지 않고 `todolist.output`에 직접
올바른 페이로드를 넣고 재개시키면 정상적으로 스킬/DMN이 반영된다:
```sql
UPDATE todolist
SET output = jsonb_set(
  output, '{hitl_feedbacks}',
  COALESCE(output->'hitl_feedbacks', '[]'::jsonb) ||
  jsonb_build_array(jsonb_build_object(
    'action', 'approve',
    'selected_ids', jsonb_build_array('<questions[].items[].id 값>'),
    'target_id', '<task_id>',
    'question_id', '<questions[].question_id 값>',
    'target_type', '<questions[].target_type 값>',
    'submitted_at', to_char(now() at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
  ))
)
WHERE id = '<task_id>';

UPDATE todolist SET draft_status = 'FB_REQUESTED' WHERE id = '<task_id>';
-- (draft_status를 HUMAN_ASKED→FB_REQUESTED로 직접 바꿔줘야 폴링이 재개된다.
--  프론트가 정상 동작할 때는 requestPdf2BpmnWorkerResume()이 이걸 자동으로
--  해준다 — fetch_pending_task의 WHERE절이 FB_REQUESTED만 보고
--  HUMAN_ASKED는 안 보기 때문에, output만 패치하고 draft_status를 안
--  바꾸면 워커가 이 태스크를 영원히 폴링에서 걸러낸다.)
```
`<questions[].items[].id>`, `<question_id>`, `<target_type>`은 해당
`waiting_for_user` 이벤트(`events` 테이블, `event_type='waiting_for_user'`,
`todo_id=<task_id>`)의 `data.questions[]`에서 그대로 읽어오면 된다.

**아직 수정 안 함**: 이 항목은 설치 스킬 범위를 넘는 프론트(`ChatRoomPage.vue`/
`Chat.vue`) 벤더 소스 버그라 `post-clone-fixes.sh`에는 반영하지 않았다.
데모/검증이 급하면 위 SQL 우회로 충분하다.

### #41 샘플 문서에서 스킬은 생성되는데 에이전트 후보가 0개

pdf2bpmn은 스킬과 에이전트를 **서로 다른 조건**으로 판단한다 — 하나만
설계하고 나머지를 안 챙기면 둘 중 하나만(주로 스킬만) 생긴다.

**스킬 클러스터링** (`ProcessPostProcessor.build_skill_clusters`): activity의
**지침(instruction) 본문**을 문장 단위로 쪼개 토큰 Jaccard 유사도
(`SKILL_CLUSTER_SIMILARITY`, 기본 0.55)로 비교 — **역할(role)은 안 본다.**
같은 역할이든 다른 역할이든 지침 문장이 비슷하면 묶인다.

**에이전트 후보 생성** (`ProcessPostProcessor.collect_lane_skill_candidates`):
`(role, skill_id)` 쌍이 **동일 역할** 안에서 같은 스킬로 ≥
`AGENT_CREATION_MIN_TASKS_PER_SKILL_PER_LANE`개(기본 2) activity에 걸쳐
나타나야 후보가 된다. 스킬이 이미 만들어졌어도 그 스킬을 가진 activity들이
**서로 다른 역할**에 흩어져 있으면(예: 재무팀이 하나, 컴플라이언스팀이
하나) 후보가 0개다 — `[ASSIGN][LANE] ... candidates=0` 로그로 확인 가능.

**여기까지만 맞추면(같은 역할 + 유사 지침) 끝날 줄 알았는데, 세 번째 함정이
있다**: `PDF2BPMNWorkflow._merge_tasks_by_similarity`(`workflow/graph.py`)가
스킬 클러스터링보다 **먼저** 실행되면서, 같은 역할(role_tasks 그룹) 안에서
**activity 이름**이 비슷한 두 activity를 하나로 합쳐버린다(로그: `🔀 병합:
[...] → ...`). 판정 기준은 이름을 공백 기준으로 쪼갠 단어 집합의 교집합이
전체 단어의 50% 이상이면 병합(`_have_same_core_words`) — 지침 본문이
아니라 **activity 이름만** 본다. "재무 리스크 평가 리포트 생성" vs
"컴플라이언스 리스크 평가 리포트 생성"은 5단어 중 4단어("리스크 평가
리포트 생성")가 겹쳐 병합 대상이 되고, 병합되면 activity가 1개로 줄어
`AGENT_CREATION_MIN_TASKS_PER_SKILL_PER_LANE=2` 조건을 영원히 못 채운다.

**해결(세 조건을 동시에 만족시켜야 함)** — `assets/vendor-onboarding.pdf`에
적용된 실제 예:
1. 두 activity를 **같은 역할**로 배정 (에이전트 후보 조건).
2. 지침 **본문**은 기존 템플릿을 유지해 유사도 0.55 이상 확보 (스킬 클러스터링).
3. activity **이름**은 공유 단어가 전체의 50% 미만이 되도록 다르게 작성 —
   원본 HTML에 `<b>재무 건전성 스코어링.</b>` / `<b>제재·위규 이력
   스코어링.</b>` 같은 짧고 구분되는 소제목을 지침 문장 앞에 붙여 LLM이
   그 표현을 activity 이름으로 채택하도록 유도했다. 두 이름은 "스코어링"
   1단어만 공유(4~5단어 중 1개, 50% 미만)해 병합을 피한다.

디버깅 시 `docker logs <bpmn-extractor> | grep -E "🔀 병합|SKILL\]\[CLUSTER|ASSIGN\]\[LANE"`
로 세 단계(병합 → 스킬 클러스터링 → 에이전트 후보) 로그를 순서대로 보면
어느 단계에서 원하는 activity가 사라지는지 바로 보인다.

### #42 스킬이 proc_def엔 저장됐는데 실제 스킬 파일(SKILL.md)은 어디에도 없음 — 3중 원인, 전부 조용히 실패

`proc_def.definition.skills`엔 스킬이 들어있고 채팅 결과 카드에도 "생성된
스킬 1개"로 표시되는데, `volumes/deepagents-skills/<tenant>/`를 아무리
찾아봐도 실제 `SKILL.md` 파일이 없다. 프론트에서 스킬 카드를 클릭해도
아무 반응이 없다(팝업이 안 뜸). 이 데모/설치 스킬 자체 버그이며, 아래 세
가지가 겹쳐서 어디에도 에러가 안 남는 채로 실패했다 — 각각 독립적으로
"조용한 실패"였다.

**원인 1 — 잘못된 base URL이 게이트웨이 SPA catch-all에서 가짜 200을 받음**:
`pdf2bpmn_agent_executor.py`의 `_upload_skill_to_claude_skills()`는
`CLAUDE_SKILLS_BASE_URL`(기본값 `http://localhost:8088/claude-skills`)로
`POST {base}/skills/upload`를 호출하는데, `nginx.conf`엔 `/claude-skills`
라우트가 아예 없다(`/process-gpt-deepagents/*`만 있음 — 프론트 자신의
업로드 UI는 이 올바른 경로를 쓴다). 존재하지 않는 경로 요청은 nginx의
프론트 catch-all(`location /`)로 떨어져 **SPA index.html을 200으로
반환**하고, 예전 코드는 `2xx면 성공`으로만 판단해 실제로는 아무것도
업로드 안 됐는데 "성공"으로 기록했다.

**원인 2 — 승인 여부 판단 키와 업로드용 dict 키가 서로 다른 필드였음**:
HITL 스킬 승인 질문의 `items[].id`(및 사용자가 고르는 `selected_ids`)는
스킬의 **영문 slug**(`safe_name`/`id`, 예: `partner-risk-score-report`)인데,
`skill_docs` dict를 만드는 루프는 스킬의 **한글 표시명**(`name`)을
`_normalize_skill_key()`에 넣어 키로 썼다. 두 키가 절대 같을 수 없으니
`approved_keys`에 있는 항목이 매번 "일치하는 게 없음"으로 조용히
스킵됐다 — 승인/거부와 무관하게 항상 0개 업로드. 원인 1을 고쳐도 이 버그가
남아있으면 여전히 아무것도 안 올라간다.

**원인 3 — 위 실패들이 로그에 전혀 안 남음**: `_upload_skill_to_claude_skills`는
status code만 보고 성공/실패를 반환했고(응답 바디 검증 없음), 실패해도
호출부는 `logger.warning` 한 줄만 남기고 최종 완료 메시지·채팅 결과 카드엔
아무 표시가 없었다. 사용자가 "완료됐다"는 메시지만 보고 실제로는 스킬이
하나도 안 올라간 걸 알 방법이 없었다.

**해결** (전부 이 세션에서 코드 수정, 이미지 재빌드 후 실제 업로드까지
검증 완료):
1. `docker-compose.yml`의 bpmn-extractor 환경변수에
   `CLAUDE_SKILLS_BASE_URL: http://deepagents:8888` 추가 — 게이트웨이를
   거치지 않고 deepagents 컨테이너에 직접 붙는다 (`post-clone-fixes.sh`
   10번 항목이 자동 반영).
2. `pdf2bpmn_agent_executor.py`의 `skill_docs` 키 생성을
   `sm.get("safe_name") or sm.get("id")` 기준으로 수정(한글 `name` 기준 →
   영문 slug 기준). 업로드 시 스킬명도 마크다운에서 재추출하지 않고 이
   키를 그대로 재사용하도록 통일(재추출 시 또 다른 정규화 불일치가 생길
   수 있어서).
3. `_upload_skill_to_claude_skills()`가 응답 JSON의 `registered: true`
   여부까지 확인하도록 수정(상태코드만 보지 않음), 409(이미 존재)는
   성공으로 취급.
4. 업로드 실패 시(개별 스킬 단위, 또는 단계 전체가 예외로 죽은 경우 모두)
   `skill_upload_errors` 리스트에 사유를 쌓고, 진행 카드에 별도 경고
   이벤트를 쏘고, 최종 완료 메시지에도 `⚠️ 스킬 N건 업로드 실패: ...`를
   덧붙이도록 수정 — "완료됐다"는 문구만 보고 전부 정상인 줄 오해하지
   않게 함. `saved_skills[]`에도 `uploaded`/`error` 필드를 채워 프론트가
   그대로 렌더링할 수 있게 함.
5. 프론트(`Chat.vue`의 pdf2bpmn 결과 카드, `ProcessArtifactViewer.vue`의
   스킬 목록)에서 `uploaded === false`인 스킬을 경고 아이콘 + 빨간
   테두리 + "업로드 실패: <사유>" 캡션으로 표시하고, 클릭해도 깨진 링크로
   이동하지 않도록(no-op) 수정.

**검증 방법**: 업로드 성공 여부는 채팅 UI만 보지 말고 반드시 파일시스템과
DB를 직접 확인한다.
```bash
# 실제 파일이 생겼는지 (호스트 bind-mount 경로)
find volumes/deepagents-skills/<tenant_id> -maxdepth 3

# 최종 완료 이벤트의 saved_skills[].uploaded 필드
docker exec -i supabase-db psql -U postgres -d postgres -t -A \
  -c "select jsonb_pretty(data->'saved_skills') from events where todo_id='<task_id>' and event_type='task_completed';"
```

**교훈**: 이 세 버그는 전부 "예외를 안 던지고 조용히 잘못된 성공을 반환"
하는 패턴이었다 — 상태코드만 보고 성공 판정, 키 불일치로 조용히 스킵,
실패해도 로그 한 줄. pdf2bpmn 파이프라인의 다른 단계(에이전트 생성/동기화,
DMN 적용 등)에도 비슷한 `try/except: logger.warning` 패턴이 더 있을 수
있으니, 유사한 "성공한 것처럼 보이는데 실제로는 아무 일도 안 일어남"
증상을 마주치면 이 항목의 세 가지 원인 유형(잘못된 엔드포인트가 catch-all에서
가짜 성공을 받는 경우 / 두 코드 경로가 서로 다른 키 체계를 쓰는 경우 /
실패가 로그 한 줄로만 남고 사용자에게 전달 안 되는 경우)부터 의심해볼 것.

### #43 단 한 번만 쓰이는 분기까지 DMN HITL 질문이 뜸 — 재사용 여부를 안 보고 판단

텍스트 대화("휴가 신청 프로세스 만들어줘")로 생성하든 PDF 업로드로 생성하든,
프로세스 안에 승인/반려 같은 배타적 게이트웨이(분기 2개 이상)가 하나만
있어도 "DMN 의사결정 테이블을 어떤 게이트웨이에 만들까요?" HITL 질문이 뜬다.
DMN(의사결정 테이블)의 존재 이유는 **여러 곳에서 재사용되는 비즈니스 규칙**을
한 곳에 모아 관리하기 위함인데, 프로세스 안에서 딱 한 번만 등장하는 분기는
DMN으로 뽑아낼 실익이 없다 — 이런 경우까지 매번 HITL로 물어보는 건 사용자
관점에서 불필요한 확인 단계다.

**원인**: `pdf2bpmn_agent_executor.py`의 `_collect_dmn_candidates_from_proc_json`이
DMN 후보 자격을 "ExclusiveGateway이고 분기(outgoing sequence)가 2개
이상"으로만 판단했다 — 같은 의사결정이 프로세스 안에서 몇 번이나
등장하는지는 전혀 보지 않았다. 이 함수는 같은 이름의 게이트웨이가 여러 개
있으면 하나로 병합하는 로직(`by_name` 그룹핑, `gids` 리스트)을 이미
갖고 있었는데, 그 병합 결과(`len(gids)`, 즉 이 프로세스 안에서 같은
게이트웨이가 실제로 몇 번 등장했는지)를 후보 채택 여부에는 반영하지
않고 있었다.

**해결**: 같은 이름의 게이트웨이 그룹을 병합한 뒤, `len(gids) <= 1`
(=이 프로세스 안에서 재사용되는 정황이 없는 단발성 분기)이면 DMN 후보
목록에서 아예 제외하도록 수정했다 — `len(gids) > 1`(동일 게이트웨이가
프로세스 내 여러 지점에서 재사용됨)일 때만 사용자에게 DMN 변환 여부를
묻는다. DMN을 실제로 적용하는 `_augment_runtime_with_gateway_dmn`은
이미 승인된 게이트웨이 id만 처리하므로(`approved_gateway_ids` 필터)
별도 수정이 필요 없다 — 후보를 안 물어보면 애초에 승인 대상에도 안
들어가기 때문이다.

디버깅 시 `docker logs <bpmn-extractor> | grep "\[DMN\]\[CAND\]"`로
어떤 게이트웨이가 단발성으로 판단돼 후보에서 빠졌는지 확인할 수 있다.

### #44 채팅으로 "프로세스 실행해줘"가 항상 실패 — work-assistant MCP의 하드코딩된 SaaS 도메인

`process-gpt-demo` 스킬의 시나리오 1(휴가 신청 인스턴스 실행)을 만들며
처음 발견. 채팅에서 "OO 프로세스 실행해줘" → 필요 정보 입력 →
`work-assistant.execute_process` MCP 도구까지 성공적으로 호출되는데,
최종적으로 "휴가 신청 프로세스 실행 중 시스템 오류가 발생했습니다(API
오류: 'NoneType' object has no attribute 'get')"로 실패한다.
`completion` 서비스 로그(`docker logs <completion>`)엔 `/complete`
요청이 **아예 찍히지 않는다** — 즉 요청이 completion에 도달하지도
못했다.

**원인**: `base-agent-langchain-react`가 pip으로 설치하는 별도 PyPI
패키지 `process-gpt-mcp==0.3.0`(GitHub: uengine-oss/process-gpt-mcp,
이 레포의 `services/base-agent-langchain-react/process-gpt-mcp/` 폴더는
**참고용 사본일 뿐 실제 빌드에 안 쓰인다** — Dockerfile이
`pip install process-gpt-mcp==0.3.0`로 PyPI에서 직접 설치)의
`get_api_base_url(tenant_id)`가 무조건
`f"https://{tenant_id}.process-gpt.io"`를 반환한다. 이건 실제로 그
도메인을 운영하는 멀티테넌트 SaaS 환경 전용이고, 자체 호스팅(Docker
Compose) 설치엔 이 도메인이 존재하지 않는다 — `execute_process`가
`{base}/completion/complete`로 POST를 보내지만 그 호스트 자체가 없으니
completion에 도달할 수조차 없다.

이 MCP 서버는 자체 로그 파일(`mcp_debug.log`, `os.path.dirname(__file__)`
기준 경로)에 로그를 남기는데, 이건 컨테이너 안에 설치된 site-packages
경로 밑이라 `docker logs`로는 안 보인다 — 이 문제를 디버깅할 때
`docker exec <container> find / -iname mcp_debug.log`로 찾아 직접
읽어야 한다(단, `process_gpt_mcp` 패키지 자체가 별도 로그 설정 없이
그냥 print()만 쓰는 빌드라면 그마저도 안 남을 수 있다 — 이번엔 실제로
못 찾았고, 대신 completion 서비스에 `/completion/complete`가 아예 안
찍히는 것으로 "요청이 라우팅부터 실패했다"를 역으로 추론했다).

**해결**: `PROCESS_GPT_API_BASE_URL` 환경변수로 override할 수 있게
`services/base-agent-langchain-react/patch_mcp_server.py`를 추가하고
Dockerfile에서 `pip install process-gpt-mcp==0.3.0` 직후
`COPY patch_mcp_server.py /tmp/ && RUN python3 /tmp/patch_mcp_server.py`로
**빌드 시점에** site-packages의 `server.py`를 in-place 수정하도록
했다(원본 함수 텍스트가 바뀌면 `assert`가 실패해 빌드가 멈추므로,
업스트림이 바뀌어도 조용히 무효화되지 않는다). 그리고
`docker-compose.yml`의 `base-agent-langchain-react` 서비스에
`PROCESS_GPT_API_BASE_URL: http://nginx:8088`를 추가했다. **주의**:
`http://completion:8000`(서비스 직결)이 아니라 **게이트웨이(nginx)
주소**를 줘야 한다 — completion 서비스 자체엔 `/complete`만 있고
`/completion` 접두사가 없다(`nginx.conf`의 `location /completion/`
블록이 그 접두사를 벗겨서 completion에 전달하는 구조). MCP 코드는
항상 `{base}/completion/complete`를 호출하므로 `base`는 그 접두사를
그대로 받아줄 수 있는 게이트웨이여야 한다.

이 패치는 `docker compose build --no-cache base-agent-langchain-react`로
재빌드해도 유지되는 것을 확인했다(이미지 빌드 로그에 `patched
get_api_base_url() ...` 출력이 찍히고, 컨테이너 안에서
`get_api_base_url('localhost')`를 직접 호출하면 `http://nginx:8088`을
반환) — 더 이상 컨테이너 writable layer에만 의존하는 임시 패치가
아니다. 향후 `process-gpt-mcp` PyPI 패키지 자체에 이 env override가
업스트림으로 반영되면 `patch_mcp_server.py`와 Dockerfile의 관련 두 줄을
제거해도 된다.

### #45 워크아이템 제출이 500 `'NoneType' object has no attribute 'get'`로 실패 — 그리고 게이트웨이 분기 선택 신뢰성 문제

**버그 1 (수정 완료)**: `services/completion/process_engine.py`의
`submit_workitem()`이 요청에 `email`이 없으면 `user_email`이 빈 문자열이
되고, 그러면 `user_info = None`으로 남는데, 바로 다음 줄에서
`workitem_data['user_id'] = user_info.get('id')`를 **가드 없이**
호출해 크래시한다. `task_id`만으로 기존 워크아이템을 제출하는 모든
호출(담당자 재배정 의도 없이 그냥 폼만 제출하는 경우)이 이 경로를
탄다. 프론트의 `putWorkItemComplete()`가 항상 `email`을 채워 보내는지는
호출 지점마다 다를 수 있어, UI로는 안 걸리다가 API를 직접 호출하거나
새 연동을 만들 때 걸리기 쉽다.

```python
# 수정 전 (크래시)
workitem_data['user_id'] = user_info.get('id')
workitem_data['username'] = user_info.get('name')
# 수정 후
if user_info:
    workitem_data['user_id'] = user_info.get('id')
    workitem_data['username'] = user_info.get('name')
```
`user_info`가 없으면 기존 워크아이템에 이미 배정된 `user_id`/`username`을
그대로 둔다(강제로 지우지 않음). `completion` 서비스 재빌드로 반영됨.

**버그 2 (미확정, 코드 수정 안 함)**: 위 버그 1을 고친 뒤 실제로 승인
경로("휴가 신청" → "상사 검토·승인" → "인사팀 등록" → "사원 승인 통보")를
끝까지 실행해 `bpm_proc_inst.status='COMPLETED'`까지 확인했다. 그런데
**같은 게이트웨이에서 반려(`approval_status: "rejected"`)를 제출해도
승인 브랜치(`task_register`)가 활성화되고 반려 브랜치
(`task_notify_reject`)는 계속 `TODO`로 남아있는 것**을 관찰했다 — 2회
재현(자연 실행 1회 + API 직접 호출 1회) 모두 동일.

조사 결과: 게이트웨이 분기 자체를 결정하는 게 어떤 함수/프롬프트인지
명확히 특정하지 못했다.
- `prompt_completed`(LLM, `workitem_processor.py`)는 **현재
  액티비티가 DONE인지 PENDING인지만** 판단하고 다음 브랜치는 결정하지
  않는다 — 여기가 원인이 아님을 확인.
- `run_completed_determination`(결정론적 사전 체크)은 "다음으로 진행
  가능한 경로가 있는지"만 보고 어느 특정 분기인지는 안 정한다
  (`sequence_conditions`에 `conditionEval`이 없으면 게이트웨이 엣지를
  전부 "unknown"으로 취급 → LLM 폴백으로 넘어가는 구조로 보임).
- `get_gateway_condition_data`가 정확한 `conditionData` 필드
  (`..._task_review_form.approval_status`)를 조회해 값("rejected")을
  제대로 가져오는 것까지는 로그로 확인했다 — 즉 **데이터 자체는 맞게
  조회되는데, 그 값이 최종적으로 어떻게 분기 선택에 반영되는지를
  코드 레벨에서 못 찾았다** (별도 LLM 호출 프롬프트가 더 있을 가능성,
  또는 단순 문자열 비교인데 조건 문자열이 "승인인 경우"/"반려인 경우"
  같은 한국어 자연어라 실제 매칭 로직이 애매할 가능성 등 — 미확정).

**데모 시 권장 대응**: 승인(approve) 경로는 이번 세션에서 완전히
검증됨(2회 성공). 반려(reject) 경로는 구조적으로 존재하지만(별도
`task_notify_reject` 워크아이템이 미리 생성돼 있음) 실제로 그 분기가
선택되는지는 매번 DB로 확인해야 한다:
```sql
select activity_id, status from todolist where proc_inst_id='<inst_id>' order by start_date;
```
`task_register`가 활성화됐다면 반려 의도와 무관하게 승인 경로로 간
것이니, 데모에서는 이 한계를 있는 그대로 설명하거나 승인 경로 위주로
시연할 것.

### #46 Playwright 로그인 자동화가 루트(`/`)에서 불안정 — 새 마케팅 랜딩 페이지

`process-gpt-demo` 스킬 작업 중 발견. 프론트엔드에 `/` 마케팅 랜딩
페이지가 추가되면서, 기존에 `page.goto(BASE)` 후 `waitUntil:
'networkidle'`로 로그인 폼을 기다리던 스크립트들이 간헐적으로
타임아웃되거나 `input[type="text"]` 로케이터를 못 찾는다. 랜딩
페이지에 계속되는 백그라운드 활동(애니메이션 등)이 있어
`networkidle`이 안정적으로 안 끝나는 것으로 보인다.

**해결**: 로그인이 목적이면 랜딩 페이지를 거치지 말고 `/auth/login`으로
바로 이동하고, `waitUntil: 'load'` + 명시적 `waitForSelector`를 쓴다.

```javascript
await page.goto('http://localhost:8088/auth/login', { waitUntil: 'load', timeout: 30000 });
await page.waitForSelector('input[type="text"]', { timeout: 15000 });
await page.locator('input[type="text"]').first().fill('demo@localhost');
await page.locator('input[type="password"]').first().fill('Demo1234!');
await page.locator('button:has-text("로그인")').click();
```

`process-gpt-demo/references/demo-account.md`와
`process-gpt-install/references/demo-playwright.md`의 로그인 스니펫에
반영해뒀다 — 새 Playwright 스크립트를 짤 때도 이 패턴을 그대로 쓸 것.

### #47/#48 deepagents가 proc_def에 연결된 스킬을 실제로는 전혀 안 씀 — 2개의 독립된 원인

`process-gpt-demo` 시나리오 2(협력사 온보딩: 스코어링 활동을 deepagents가
무인으로 처리하며 실제로 스킬을 참조하는지 검증)를 실행하며 발견. 워크아이템은
분명 SUBMITTED→DONE으로 자동 처리됐지만, 응답 내용이 스킬의 절차를 따르는지
의심스러워 `docker logs deepagents`를 직접 열어보고서야 스킬이 아예 로드되지
않는 것을 확인했다. 서로 독립적인 2개의 버그가 겹쳐 있었다.

**버그 A — 에이전트 생성 시 `users.skills`가 비어있음**

```sql
select id, username, skills from users where id='<agent-uuid>';  -- skills가 빈 문자열
```
`services/deepagents/core/agents/subagents.py`가 서브에이전트를 만들 때
`skill_names = _parse_csv(agent.get("skills"))`이고, 여기서 `agent`는
`processgpt_agent_sdk`의 `fetch_users_grouped()`가 **`users` 테이블에서 그대로
읽어온 행**이다(proc_def 활동에 선언된 `skills` 배열과는 무관 — 그건 생성 당시
안내문 정도로만 쓰이고 런타임엔 다시 안 읽는다). 즉 실제로 스킬을 쓰려면
해당 에이전트의 `users.skills` 컬럼에 스킬 slug가 들어있어야 하는데,
`bpmn-extractor`의 `_sync_skills_to_supabase()`가 이 값을 채우도록 이미
구현돼 있음에도(`pdf2bpmn_agent_executor.py:629`) 이번에 재사용한 기존
데모 에이전트(이전 세션에서 생성됨)는 이 컬럼이 비어 있었다 — 그 코드가
언제부터 존재했는지, 매 생성마다 항상 정확히 채우는지는 이번에 별도로
검증하지 못했다(아래 "미확정" 참고).

로그로 바로 확인 가능: 로드 시도조차 안 하면
`서브에이전트 '<이름>': skills 설정 없음 (스킬 없이 빌드)`가 찍힌다(이름/스킬
목록이 있는데도 이 로그가 뜨면 `users.skills`부터 의심).

**해결(즉시 조치)**: 기존 에이전트는 SQL로 직접 채워 넣으면 된다(멱등,
콤마구분 slug):
```sql
update users set skills='partner-risk-score-report' where id='<agent-uuid>';
```

**버그 B — 샌드박스가 컨테이너 내부 스킬 경로를 못 찾음(path_not_found), 그리고 애초에 마운트도 안 됨**

버그 A를 고쳐도 여전히 다음 경고가 반복됐다:
```
WARNING:deepagents.middleware.skills:Cannot load skills from '/app/skills/localhost/local': Path '/app/skills/localhost/local': path_not_found
```
deepagents는 실제 실행을 **Docker-outside-of-Docker 샌드박스**(사촌 컨테이너
`deepagent-sandbox-<tenant>`, `docker.sock`으로 별도 기동)에서 하고,
`core/sandbox/docker_sandbox.py`의 `_skill_volumes()`가 테넌트별/전역
스킬 디렉터리를 화이트리스트 단위로 `/skills/<name>`에 개별 bind-mount한다
(전체를 한 번에 마운트하면 다른 테넌트 스킬까지 노출되므로 의도적으로
이렇게 설계됨). 이 안에서 서로 다른 2가지 하위 버그가 겹쳐 있었다:

1. **경로 변환 누락(`core/agents/subagents.py`)**: `_get_skills()`가 반환하는
   경로는 이 API 컨테이너 자신의 파일시스템 기준(`/app/skills/...`, `SKILLS_DIRS`
   env)인데, `FilteredSkillsMiddleware(backend=<샌드박스>, sources=<이 경로 그대로>)`로
   넘겨서 샌드박스 backend가 `ls()`할 때 항상 path_not_found — 샌드박스 안에서
   실제로 유효한 경로는 `/skills/<name>`(prefix 자체가 다름)이다.
   `core/agents/agent.py`의 **루트 에이전트** 경로는 이미 `container_skills` 변환을
   하고 있어서 "이건 이미 고쳐져 있구나" 하고 넘어갈 뻔했는데, 그 변환 코드도
   사실 **동일한 버그를 갖고 있었다** — 아래 2번.
2. **변환 기준 경로가 틀림(`core/agents/agent.py`, 잠재 버그)**: 위 1번을 고치며
   `core/agents/agent.py`의 기존 `container_skills` 변환 로직을 그대로 따라
   했더니 여전히 안 됐다. 원인: 그 변환이 `Path(p).relative_to(_SKILLS_DIR)`를
   쓰는데 `_SKILLS_DIR = Path(os.getenv("SKILLS_HOST", ...))`는 **실제 호스트
   절대경로**(예: `/Users/.../deepagents-skills`, docker.sock으로 사촌 컨테이너를
   띄울 때 bind-mount *source*로만 써야 하는 값)라서, `/app/skills/...`로
   시작하는 어떤 경로와도 절대 매치되지 않아 매번 `ValueError`로 원본 경로를
   그대로 반환하는 조용한 no-op이었다 — 즉 **루트 에이전트(1:1 채팅 딥에이전트)
   경로도 이번 조사 전까지는 스킬을 하나도 못 읽고 있었을 가능성이 높다**
   (시나리오 3의 "딥 에이전트가 직접 채팅에서 스킬을 참조" 데모 포인트와
   직결되므로 중요).
3. **마운트 여부 판정 자체가 항상 실패(`core/sandbox/docker_sandbox.py`
   `_skill_volumes()`)**: `if not self._skills_host.exists(): return {}` 를
   `self._skills_host`(호스트 절대경로)로 호출 — 이 역시 API 컨테이너 자신의
   파일시스템에서 존재 여부를 물어보는 거라 항상 `False` → 샌드박스가 뜰 때마다
   스킬 볼륨이 통째로 스킵됨(`docker inspect deepagent-sandbox-<tenant>`로
   `/skills/*` 마운트가 하나도 없는 것으로 직접 확인).

**해결**: 세 곳 모두 "존재 여부/화이트리스트 판정은 이 컨테이너 자신의 뷰
(`SKILLS_DIRS`, 기본값 `/app/skills`) 기준, 실제 bind-mount source는 호스트
절대경로(`SKILLS_HOST`) 기준"으로 명확히 분리:
- `core/skills/skills.py`에 `to_sandbox_skill_paths()` 추가(컨테이너 뷰 경로 →
  `/skills/...` 샌드박스 뷰로 변환) + `core/agents/subagents.py`가
  `FilteredSkillsMiddleware(sources=...)`에 넘기기 전에 이 함수를 통과시키도록 수정.
- `core/agents/agent.py`의 기존 변환 기준을 `SKILLS_HOST`가 아니라 새
  `_SKILLS_CONTAINER_ROOT`(`SKILLS_DIRS` 기준)로 교체.
- `core/sandbox/docker_sandbox.py`의 `DockerSandboxBackend`/`get_or_create_sandbox`에
  `skills_container_root` 파라미터를 추가하고, `_skill_volumes()`가 존재 여부/
  `iterdir()`는 이 컨테이너 뷰 경로로 하되 실제 볼륨 딕셔너리의 키(bind-mount
  source)는 `self._skills_host / entry.name`(호스트 절대경로)로 만들도록 수정.

**⚠️ 사촌 컨테이너 재사용 주의**: `deepagents`를 재빌드/재시작해도
`deepagent-sandbox-<tenant>` 컨테이너는 실행 중이면 그대로 재사용된다
(`_start_container`가 이름으로 기존 running 컨테이너를 찾아 반환) — 마운트
구성을 바꾸는 수정을 했다면 `docker rm -f deepagent-sandbox-<tenant>`로
**반드시 지워서** 다음 실행 시 새 마운트로 재생성되게 해야 한다. 안 지우면
고쳤는데도 여전히 옛 컨테이너의 옛 마운트(스킬 없음)로 계속 실패한다.

재빌드 + 사촌 컨테이너 제거 후 실제로 `/skills/localhost/local/...../SKILL.md`가
샌드박스 안에서 보이는 것, `Skills load errors`가 더 이상 안 뜨는 것,
"Skill '...' in /skills/.../SKILL.md does not follow Agent Skills specification"
(이름 규칙 경고일 뿐 로드 자체는 성공)까지 확인했다.

**미확정(추가 확인 필요)**: 버그 A(`users.skills` 비어있음)가 **현재 코드
기준으로 새로 PDF를 업로드해 처음부터 에이전트를 생성해도 재현되는지**는
이번 세션에서 별도로 검증하지 못했다 — 재사용한 기존 데모 에이전트가
이 동기화 로직이 존재하기 전에 만들어졌을 가능성도 있다. 데모/설치 후에는
매번 아래로 확인할 것:
```sql
select id, username, skills from users where is_agent=true and skills is null or skills='';
```
비어있는 행이 있으면 위 SQL로 직접 채우거나, 해당 활동을 담당하는 스킬의
`proc_def.definition.activities[].skills`를 참고해 매핑한다.

**스킬 이름 규칙 경고(참고, 블로킹 아님)**: `SKILL.md`의 frontmatter `name:`이
한글 표시명이면 "does not follow Agent Skills specification: name must be
lowercase alphanumeric with single hyphens only" 경고가 뜬다 — 로드는
정상적으로 되고 기능에 영향 없음. 다만 스펙 준수를 원하면 `name:`을
영문 slug(예: `partner-risk-score-report`)로 바꾸는 게 좋다.

### #49 활동에 `orchestration`을 지정 안 했는데 담당자가 에이전트라서 무인 처리 시도 → 영원히 IN_PROGRESS

proc_def 활동에 `agentMode`/`orchestration`을 명시적으로 안 넣어도, 담당
역할이 이미 에이전트(`is_agent=true`)로 해석(role resolution)되면
`completion/polling_service/database.py`의 `determine_agent_mode()`가
자동으로 `agent_mode='COMPLETE'`를 부여하고, `agent_orch`가 없으면
**`crewai-deep-research`로 기본 폴백**한다(`database.py:1370-1371`,
`1417-1420`, `1723-1726`). 문제는 이 process-gpt-install의 Core/Standard
프로파일에는 그 서비스 자체가 설치돼 있지 않다는 것 — 워크아이템은
`IN_PROGRESS`로 바뀐 채 아무도 집어가지 않아 영원히 멈춰있고, 에러 로그도
전혀 안 남는다(폴링 대상 자체가 없으니 실패할 기회도 없음).

**확인 방법**:
```bash
docker ps --format '{{.Names}}' | grep -i "crewai\|deep-research"   # 없으면 원인 확정
```
```sql
select activity_id, status, agent_mode, agent_orch from todolist where proc_inst_id='<id>' order by start_date;
```
`agent_orch='crewai-deep-research'`인 행이 `IN_PROGRESS`에 멈춰있으면 이 문제다.

**데모 진행 시 우회**: 해당 활동을 `/completion/complete`로 `task_id`+`email`과
함께 직접 완료 처리해서 다음 단계로 넘긴다(사람이 사후 검토한 것으로 간주).
근본 해결은 둘 중 하나: (a) Full 프로파일로 `crewai-deep-research` 서비스를
같이 설치하거나, (b) proc_def 생성/승인 단계에서 에이전트가 담당하는 모든
활동에 `orchestration`을 명시적으로 `deepagents`(또는 의도한 엔진)로 채워
넣어 암묵적 폴백에 의존하지 않게 한다.

### #50 "기본 에이전트" 1:1 채팅 모드가 self-host docker-compose에선 원천적으로 동작 불가

`process-gpt-demo` 시나리오 3(에이전트와 1:1 채팅, 기본 에이전트 vs
딥 에이전트 비교) 작업 중 발견. 에이전트 채팅(`/agent-chat/<id>`)에서
"기본 에이전트"를 선택한 채 메시지를 보내면 화면에 "(에이전트 준비 실패)"만
뜨고 응답이 오지 않는다. 같은 화면에서 "딥 에이전트"로 바꿔 보내면 정상
동작한다(troubleshooting과 무관하게 그냥 잘 됨).

**원인**: 프론트가 기본 에이전트 모드로 보낼 때 먼저
`POST /agent-router/<agent_id>/warmup`를 호출한다
(`services/frontend/src/services/AgentRouterService.js:38-45`). 이 요청은
게이트웨이(nginx) 레벨에서도 라우트가 없어 405가 나지만(정적 파일 서버
폴백), **게이트웨이를 우회해 `agent-router` 컨테이너에 직접 요청해도
500**이 난다:
```
kubernetes.config.config_exception.ConfigException: Invalid kube-config
file. No configuration found.
  File "/app/agent_router/app.py", line 523, in _load_k8s
    config.load_kube_config()
```
`agent-router`는 에이전트마다 **전용 Kubernetes 파드**(`TARGET_BASE_URL_TEMPLATE:
"http://agent-{agent_id}:8000"`, `AGENT_RUNTIME_IMAGE`, `K8S_NAMESPACE` 등
compose env가 이를 뒷받침)를 온디맨드로 띄우는 구조로 설계되어 있다 — 즉
이 기능은 **진짜 Kubernetes 클러스터가 있는 배포(K8s/EKS/GKE/AKS 프로덕션
모드)를 전제로 하며, 단일 Docker Compose 설치에서는 애초에 성립할 수 없는
전제**다(`mcp-proxy`가 K8s 전용이라 로컬에서 무시 가능한 것과 같은 종류의
제약 — 항목 10 참고. 다만 `mcp-proxy`와 달리 `agent-router`는 로컬에서도
정상 기동·헬스체크되고 "route"(에이전트 자동 선택) 기능 자체는 되므로
"K8s 전용 서비스라 아예 빼도 되는 것"으로 착각하기 쉽다 — 실제로는
`/warmup`(=기본 에이전트 1:1 채팅 한정)만 K8s가 필요하고 나머지 기능은
로컬에서도 동작한다).

**해결/우회**: 코드를 고쳐서 될 문제가 아니다(진짜 K8s 클러스터가
필요). 자체 호스팅(Core/Standard/단일서버) 설치에서는:
- 데모/사용 시 **딥 에이전트 모드만** 실사용 경로로 안내한다. "기본
  에이전트"는 UI에 선택지로 남아 있지만 self-host에서는 기능하지
  않는다는 점을 사용자에게 명확히 알릴 것.
- 데모 관점에서는 오히려 이 실패 자체를 "왜 딥 에이전트가 기본값이어야
  하는지"를 보여주는 대비 자료로 활용할 수 있다(단, "버그가 있다"가
  아니라 "이 배포 방식의 구조적 한계"라고 정확히 설명할 것).
- 실제로 기본 에이전트(langchain-react) 1:1 채팅까지 필요하면 K8s 기반
  프로덕션 배포(`references/production-k8s.md`)로 가야 한다.

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

### #51 에이전트 "지식 관리" 탭이 항상 "메모리가 없습니다" — mem0 RPC(get_memories)가 DB에 없음

튜토리얼 Lv2(에이전트 학습) 데모 작업 중 발견. `/agent-chat/<id>`의
**학습 모드**로 지식을 가르치면 `vecs.memories`에는 실제로 저장되고(에이전트도
"학습했습니다"라고 답함), 런타임 제안서에도 반영되는데, 화면의 **"지식 관리"
탭만 "메모리가 없습니다"로 비어 보인다.**

**원인**: 프론트 `getVecsDocuments`(`ProcessGPTBackend.ts:7110`)가 호출하는
Postgres RPC `public.get_memories(agent text, lim int)`(및 `delete_memory`,
`delete_memories_by_agent`)가 이 설치의 DB에 **존재하지 않는다**. 이 함수들은
`docker-infra/volumes/db/vecs.sql`에 정의돼 DB 초기화 때 만들어져야 하지만,
`vecs.memories` 테이블은 mem0(Memory.from_config)가 **첫 학습 시점에 지연
생성**하므로 — DB 초기화 시점엔 테이블이 없어 `RETURNS SETOF vecs.memories`
함수 생성이 스킵/실패한다. 그래서 테이블은 나중에 생기고 함수는 영영 없다.

**해결**: mem0로 한 번이라도 학습해 `vecs.memories` 테이블이 생긴 뒤,
`vecs.sql`을 재적용한다.
```bash
docker cp docker-infra/volumes/db/vecs.sql supabase-db:/tmp/vecs.sql
docker exec -e PGPASSWORD="$PGPW" supabase-db psql -U supabase_admin -d postgres -f /tmp/vecs.sql
docker exec -e PGPASSWORD="$PGPW" supabase-db psql -U supabase_admin -d postgres -c \
  "GRANT EXECUTE ON FUNCTION public.get_memories(text,int) TO anon, authenticated, service_role;
   GRANT EXECUTE ON FUNCTION public.delete_memory(text) TO anon, authenticated, service_role;
   GRANT EXECUTE ON FUNCTION public.delete_memories_by_agent(text) TO anon, authenticated, service_role;
   NOTIFY pgrst, 'reload schema';"
```
검증: `select count(*) from public.get_memories('<agent_uuid>',100);` → 저장된
메모리 수가 나오면 OK. 이후 "지식 관리" 탭에 학습 지식이 보인다.

### #52 게이트웨이 뒤(activity→gateway→endEvent)로 종료하는 인스턴스가 COMPLETED로 전이 안 됨 — 배포 이미지의 오래된 `find_end_activity`

튜토리얼 Lv3(조건 분기 + 피드백 루프) 데모 작업 중 발견. 마지막 사람 태스크
뒤에 배타 게이트웨이를 두고 그 분기 하나가 endEvent로 가는 구조
(예: `task3 → gw_revision → end_event`)에서, 승인 분기를 제출하면 **모든
활동이 DONE이고 `current_activity_ids`가 비었는데도 `bpm_proc_inst.status`가
영원히 `RUNNING`**으로 남는다. (게이트웨이 라우팅·조건 평가·반려 루프백은 정상.)

**원인**: 배포된 `polling-service` 이미지의
`process_definition.find_end_activity()`가 **게이트웨이를 거슬러 올라가지
못한다**. 이 stale 버전은 `endEvent`로 들어오는 시퀀스의 source를 한 홉만
보고 `find_activity_by_id(source)`를 반환하는데, source가 게이트웨이면
`None`이 되어 종료 활동을 못 찾는다 → `upsert_process_instance`
(`database.py`)가 COMPLETED 판정을 못 한다. 즉 **직전 노드가 활동이 아니라
게이트웨이인 종료 경로**를 처리 못 함.

**현재 소스는 이미 고쳐져 있음**: 로컬 소스
`services/completion/polling_service/process_definition.py`에는 게이트웨이를
재귀적으로 거슬러 올라가는 `find_end_activities()`(복수형)가 있고,
`find_end_activity()`(단수)는 그것에 위임하며, `database.py`도 복수형을 쓴다.
**배포 컨테이너 이미지가 그 커밋 이전**이라 증상이 난다. → **해당 서비스
이미지를 현재 소스로 재빌드/재배포하면 해소**된다. (데모 중에는 컨테이너
소스를 건드리지 않고, 논리적으로 완료된 인스턴스의 status만 데이터로 반영해
쇼케이스했다 — 게이트웨이 라우팅/루프백/전 활동 완료는 in-container
`resolve_next_activity_payloads` 단위 실행으로 별도 입증.)

**빠른 진단**:
```bash
# 배포 이미지가 stale인지: 복수형 함수가 없으면 stale
docker exec <polling-svc> sh -lc "grep -c 'def find_end_activities' /usr/src/app/process_definition.py"  # 0이면 stale
```
