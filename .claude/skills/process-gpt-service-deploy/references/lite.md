# Process GPT Lite 운영 배포

저장소 `uengine-oss/process-gpt-lite`. **main 푸시가 곧 운영 배포다.** 서버 1대가 모든 테넌트를 받고, 주소의 테넌트로 요청을 나눈다. 계정과 데이터는 ProcessGPT 의 Supabase 를 함께 쓴다.

## 1. 무엇이 어디서 만들어지는가

| 구성요소 | 이미지 | 만드는 곳 | 태그 |
|---|---|---|---|
| 화면(nginx + SPA) | `process-gpt-lite-web` | `.github/workflows/deploy.yml`, `install/docker/pgpt.Dockerfile` target `web`, `VITE_BASE_PATH=/lite/` | Lite 커밋 |
| 서버(Node BFF) | `process-gpt-lite-server` | 같은 워크플로, target `server` | Lite 커밋 |
| 이음오피스 편집기 | `process-gpt-lite-office-host` | `.github/workflows/office-host-image.yml`. `backends/office-host` 서브모듈이 움직일 때만 돈다 | 편집기 커밋 |

매니페스트는 k8s `deployments/process-gpt-lite.yaml`, `services/process-gpt-lite-service.yaml` 이다. 게이트웨이 라우트는 vue3 `application.yml` 의 `lite-web` 이다.
CI 가 태그를 고치므로 image 줄은 손으로 고치지 않는다. 파일 머리 주석에 현재 구성과 아직 없는 기능이 적혀 있으니 먼저 읽는다.

Lite 는 deepagents·completion·office-mcp·memento 의 운영 이미지를 그대로 쓴다. `backends/process-gpt` 서브모듈은 로컬 개발용이고 운영 이미지에 들어가지 않는다. **백엔드 수정이 필요한 기능은 Lite 만 올려서는 운영에서 돌지 않는다.** [process-gpt.md](process-gpt.md) 의 경로로 그 서비스를 따로 낸다. 백엔드의 기능 브랜치에 있는 코드도 운영에 없는 것으로 본다.

## 2. 운영 설정

값을 바꾸는 곳은 k8s 의 `process-gpt-lite-server` env 다. 공용 값은 기존 Secret 에서 받고, 새 Secret 을 만들지 않아도 뜬다.

| 값 | 운영 설정 | 이유 |
|---|---|---|
| `PRO_TENANT_FROM_HEADER` | `1` | 게이트웨이의 `X-Tenant-Id` 로 요청별 테넌트를 정하고 `public.users` 소속을 확인한다 |
| `PRO_PUBLIC_URL` | `https://www.process-gpt.io/lite` | |
| `PRO_DEMO_LOGIN` | `0` | 코드 `000000` 데모 로그인을 끈다. **반드시 끈다** |
| `PRO_BROWSER_GATES` | `off` | |
| `PRO_CRON_MODE` | `server` | 서버가 1분마다 예약을 본다. 그래서 `replicas: 1`, `Recreate` 를 유지한다 |
| `PRO_SUPABASE_URL`, `ANON_KEY`, `SERVICE_ROLE_KEY` | `my-config`, `my-secrets` | |
| `PRO_DB_*`, `POSTGRES_PASSWORD` | `my-secrets` 의 `DB_*` | |
| `PRO_LLM_*` | `litellm-proxy:4000/v1`, `frentis-ai-model`, `litellm-proxy-secret` | |
| `PRO_TRANSCRIBE_*` | litellm-proxy | 프록시가 `gpt-4o-mini-transcribe` 를 이 키에 제공해야 회의록이 나온다. 모델 추가는 LiteLLM UI 에서 한다 |
| `PRO_DEEPAGENTS_URL`, `PRO_COMPLETION_URL`, `PRO_OFFICE_MCP_URL`, `PRO_MEMENTO_URL` | Service 이름 | |
| `PRO_FOLDERS_ROOT`, `PRO_VAULT_KEYRING`, `PRO_CLI_WORKSPACE_ROOT` | `/data/...` | PVC 위. **PVC 를 잃으면 보관함을 잃는다** |

- 명시한 `env` 가 `envFrom` 의 `process-gpt-lite-env`(optional, 사람이 클러스터에 만듦)보다 우선한다. 키를 그쪽으로 옮기려면 여기 env 항목을 지운다. 값이 든 Secret 은 커밋하지 않는다.
- 화면 nginx 는 업스트림을 요청마다 푼다. `LITE_RESOLVER=kube-dns.kube-system.svc.cluster.local` 이고 업스트림은 FQDN 이다. `/api/cron/` 은 nginx 에서 막혀 있으니 유지한다.
- 게이트웨이 `lite-web` 라우트의 `AddResponseHeader=X-Accel-Buffering, no` 는 SSE 때문이다. 지우지 않는다.
- 메일 코드 로그인은 운영 Supabase SMTP 를 쓴다. [process-gpt.md](process-gpt.md) 3장을 본다. 쿠키가 있으면 ProcessGPT 로그인을 넘겨받는다.

## 3. 운영 DB

SQL 파일은 `install/db/prod-sql.sh` 로 만든다. `migrate.sh` 는 설치용 DB 전용이라 운영에 쓰지 않는다(스키마를 만들고 테넌트 MCP 를 등록한다).

```bash
# 사용자가 SQL Editor 에서 조회해 알려 준다
select name from lite_migrations order by 1;

install/db/prod-sql.sh <out-dir> 021_x.sql   # 그 파일부터 뒤를 뽑는다
install/db/prod-sql.sh <out-dir>             # 첫 배포 때만. compat 까지 포함한다
```

- 결과는 `lite-prod-core.sql` 이다. 첫 배포에는 조건부 `lite-prod-handover.sql` 도 나온다. 파일 머리의 확인 쿼리가 참일 때만 실행한다.
- **증분 실행은 `install/db/compat/` 를 넣지 않는다.** 새 기능이 compat 에 기대면(`04_artifact_worktree.sql` 처럼) 운영에 있는지 조회하는 쿼리와 함께 조건부 파일을 따로 만들어 넘긴다.
- 새 SQL 은 이미 적용된 파일 뒤에 정렬되는 번호를 준다. 앞에 끼면 증분으로 뽑히지 않는다.
- **기존 테이블·함수를 바꾸는 문장**(`alter table users`, `create or replace function tenant_id()`, 트리거)은 따로 짚어서 보고한다. ProcessGPT 도 함께 영향을 받는다.
- 코드가 새 열을 쓰면 SQL 을 **먼저** 적용받고 코드를 푸시한다.
- 일회용 DB 에서 시험한다. 기준 스키마를 적용한 뒤 넘긴 파일을 **두 번** 돌리고 컨테이너를 지운다.
  ```bash
  bash .claude/skills/process-gpt-service-deploy/scripts/test-prod-sql.sh \
    process-gpt-infra-docker/volumes/db <out-dir>/lite-prod-core.sql
  ```
  기준 스키마는 운영과 다를 수 있다. 통과해도 아래 enum 확인은 따로 한다.
- SQL Editor 는 psql 메타 명령(`\if`, `\gset`)을 못 쓴다. 단일 테넌트용 문장(`where id = 'localhost'`)은 뺀다.
- enum 값은 운영과 다를 수 있다. 서비스 SQL 이 enum 컬럼과 비교하는 글자 값을 모아(`grep -rhoE "status[^']*'[A-Z_]+'"`), 로그인한 세션으로 운영 PostgREST 에 `/<table>?select=<col>&<col>=eq.<값>&limit=1` 을 보낸다. 22P02 면 없는 값이고, 그런 곳은 `::text` 로 비교한다. 공개 주소와 anon 키는 ProcessGPT 첫 화면 HTML 의 `window._env_` 에 있다.

## 4. 코드 반영 순서

이슈 수정과 큰 기능은 나눠서, 단계마다 "로컬 확인 → 푸시 승인 → 운영 확인" 으로 낸다.

1. 원격 main 위로 다시 올린다. 다른 사람의 커밋이 들어와 있으면 그 위에서 다시 확인한다.
2. **로컬 8088/lite 에서 확인한다**(6장). 5180·5173 에서 통과한 결과는 근거로 쓰지 않는다.
3. [SKILL.md](../SKILL.md) 의 "운영에서만 다른 점" 표와 대조한다.
4. 새 SQL 이 있으면 파일을 넘기고, 적용됐다는 답을 받는다.
5. 매니페스트 변경이 있으면 **k8s 를 먼저** 푸시한다. Lite CI 가 그 파일의 태그를 고치므로 새 Deployment 가 먼저 있어야 한다.
6. Lite main 을 푸시한다. CI 성공과 k8s 의 `Update process-gpt-lite images to <sha>` 커밋을 본다.
   ```bash
   gh run list -R uengine-oss/process-gpt-lite -L 3
   git -C infra/process-gpt-k8s pull && grep -n 'lite-.*:' infra/process-gpt-k8s/deployments/process-gpt-lite.yaml
   ```
7. 운영에서 확인한다(7장). `Recreate` 라 교체하는 동안 잠깐 502 다.

새 파일 없는 일반 수정은 2·3·6·7 이다.

## 5. 구성요소를 운영에 더할 때

- 이미지가 없으면 CI 를 먼저 만든다. 태그 커밋은 다른 워크플로와 겹치므로 `git pull --rebase` 재시도를 넣는다(`office-host-image.yml`).
- 새 패키지는 비공개다. [process-gpt.md](process-gpt.md) 2장의 공개 절차를 거친다. 첫 실행은 `workflow_dispatch` 로 돌린다.
- `deployments/process-gpt-lite.yaml` 에 Deployment·PVC, `services/process-gpt-lite-service.yaml` 에 Service 를 더한다. 프로세스 안에 상태가 있고 디스크가 RWO 면 `replicas: 1`, `Recreate` 다.
- 머리 주석의 "Not here yet" 을 고친다.
- **ProcessGPT 에이전트까지 바뀌는 연결은 사용자가 정하게 한다.** `tenants.mcp` 등록이 그렇다. 2026-10-30 에 편집기 MCP(`PRO_OFFICE_HOST_URL`)도 에이전트 동작이 바뀌어 뺐다.

**배포하지 않은 것과 알려진 문제.** 2026-10-30 기준이다. 시작 전에 매니페스트 머리 주석과 코드에서 다시 확인한다.

| 항목 | 상태 |
|---|---|
| 편집기 MCP(`PRO_OFFICE_HOST_URL`), ArtCraft, 작업실 터미널(`PRO_CLI_AGENT_URL`) | 운영에 없다 |
| 커넥터 도구 | 운영에 mcp-hub 와 `PRO_MCP_HUB_URL` 이 없어 연결돼 보여도 에이전트에 안 붙는다. 사용자 결정 필요 |
| 구글 로그인·메일 | OAuth 값이 없다. 넣어도 여러 테넌트·하위 경로의 콜백을 고쳐야 한다 |
| 브라우저 에이전트 | 빈 PVC 에서 `/data/browser-profiles` 가 없어 시작하지 못한다 |
| 공유 폴더의 에이전트 작업(변형) | 서버 디스크에 펼쳐 에이전트 파드가 보지 못한다 |
| 프로세스 마이닝 추천 | 운영에 없다. `process-gpt` `feat/pgpt-lite-mining` 의 process-miner 가 필요하다. `main` 버전과 경로가 다르고, 인증 없이 DB 에 초안·PR 을 쓴다 |
| 대화로 만든 프로세스 저장 | 서버 이미지에 Python 이 없어 저장 브리지가 돌지 않는다. 방식 결정 보류 |
| deepagents 의 워크트리 지원 | 운영 반영 여부 미결정 |

## 6. 로컬 검증

운영과 같은 길로 띄운다. 게이트웨이를 거치지 않으면 하위 경로·테넌트 문제가 드러나지 않는다.

- 게이트웨이: `process-gpt-vue3/gateway` 에서 `mvn spring-boot:run`. default 프로필의 `lite-web` 이 `localhost:5181` 을 본다. 라우트를 바꾸면 그 PID 만 멈추고 다시 띄운다.
- 화면: `/lite/` 빌드 이미지를 5181 에 띄운다. nginx 가 변수 `proxy_pass` 를 쓰므로 사용자 정의 docker 네트워크(내장 DNS)에 둔다.
- 서버: 8787 을 게이트웨이 모드(`PRO_TENANT_FROM_HEADER=1`)로 띄운다. 이 모드에서는 새 시험 계정을 만들 수 없으니 기존 계정을 쓴다.
- 로그인: vue3 `/auth/login`(`.cp-id`·`.cp-pwd`·`.cp-login`). 계정은 `process-gpt-vue3/CLAUDE.md` 에 있다.
- e2e: `e2e/tests/deploy/lite-path.spec.js`. 다른 시험도 `PGPT_URL=http://localhost:8088/lite` 로 게이트웨이 아래에서 돈다.
- 판정은 "화면에 글자가 나왔다"로 끝내지 않는다. 요청 문장이 팀원에게 넘어가 안내 문장이 답처럼 보인 적이 있다. 실제 처리한 서비스(deepagents `/chat/stream` 호출 등)까지 본다.

## 7. 운영 확인

시험 계정으로 시험 테넌트의 `/lite` 에서 실제 사용자 흐름대로 한다. 로그인은 Playwright MCP 로 보이는 브라우저를 열어 두고 사용자에게 부탁한 뒤 이어서 한다. 첫 방문 생년월일 같은 개인 정보 입력도 사용자에게 맡긴다.

- 기본: `/lite/`·`/lite/chat`·`/lite/improve` 직접 열기와 새로고침 200, `/lite` 밖 경로는 그대로, 로그인 없이 오면 `/lite/login` 에 머문다.
- 채팅: 답이 오고, 새로고침해도 남고, 첫 글자가 오래 걸려도 끊기지 않는다.
- 테넌트: 그 테넌트 계정만 들어온다. 소속 밖 이메일은 코드 메일이 가지 않고 `auth.users` 도 늘지 않는다. 화면은 "보냈다"로 나오는 것이 정상이다.
- 이번에 고친 기능의 인수조건, 그리고 그 기능이 쓰는 파드 밖 경로(첨부, 문서 카드, 편집기 열기·저장, 공유·이어서 작업, 예약 제시각 실행, 회의 자막).
- 배포 전에 만든 데이터가 그대로 열리는지.
- 확인하지 못한 항목은 이유와 함께 보고한다. 시험하며 남긴 데이터도 알린다. 매일 도는 예약이면 특히 알린다.
