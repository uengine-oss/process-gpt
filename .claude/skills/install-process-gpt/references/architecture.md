# Process GPT 아키텍처 요약 (설치 관점)

> **compose 파일 위치**: 로컬/단일서버 설치용 compose는
> [process-gpt-infra-docker](https://github.com/uengine-oss/process-gpt-infra-docker)
> 레포 루트의 **단일** `docker-compose.yml` 하나다. `process-gpt`(본체
> 모노레포)는 서비스 소스(서브모듈)와 앱 코드를 담당한다.
> `process-gpt-infra-docker`도 동일한 서비스 소스 서브모듈 세트를 자체
> `.gitmodules`로 갖고 있어(`build:` 서비스 빌드용), 도커 설치만 목적이면 이
> 레포 하나만 클론하면 된다.

## 전체 그림

```
브라우저 ──► nginx 게이트웨이 (:8088) ──┬──► frontend (Vue 3 SPA)
                                        ├──► completion (/completion/*, /langchain-chat/*)
                                        ├──► base-agent-langchain-react (/agent/chat/stream)
                                        ├──► memento (/memento/), deepagents (/deepagents/)
                                        ├──► robo-glossary (/robo/), instance-classifier (/instance-classifier/)
                                        ├──► strategy (/strategy-service/)
                                        └──► agent-router (/agent-router/route)
브라우저 ──► Supabase Kong (:54321) ──► auth(GoTrue)/rest(PostgREST)/realtime/storage
                                              │
                                    Postgres(db) + pgvector  ← init.sql로 스키마 시드
```

- 프론트는 Supabase(REST/Realtime/Auth)에 **직접** 붙고(멀티테넌트, RLS),
  AI/에이전트 호출만 nginx 게이트웨이를 경유한다.
- 채팅 응답 렌더는 **Realtime로 `public.chats` 변경 구독** 방식 — realtime
  컨테이너가 없으면 "생각 중"에서 멈춘다.
- 멀티테넌시: `tenant_id`가 **접속 호스트명에서 파생**된다
  (`localhost:8088` 접속 → tenant `localhost`). RLS는 JWT의
  `app_metadata.tenant_id` 클레임을 검사한다.

## Compose 구조

`process-gpt-infra-docker` 레포 루트의 `docker-compose.yml` 하나에 infra
(Supabase/Neo4j/LiteLLM), 마이크로서비스, nginx 게이트웨이가 전부 정의되어
있다. 헬퍼 스크립트 `./start-all-services.sh`(Windows는 `.ps1`)가 interactive
/ `all` / 서비스명 나열 / `--preset` / `--last` 모드를 지원하고, infra
`--wait` → 선택 서비스 → nginx 순서로 기동해준다.

## Infra 스택

| 서비스 | 역할 | 포트 | 비고 |
|---|---|---|---|
| db | Postgres 15 + pgvector | 5432(내부) | `init.sql` 스키마 시드. 첫 부팅 30–60초 |
| analytics | Logflare | 4000 | kong·studio가 로그 조회에 참조 — **어떤 프로파일에서도 제외 불가** (compose `depends_on`으로 강제되진 않음). 메모리 ~1.3GB |
| kong | Supabase API 게이트웨이 | **54321**(HTTP), 8443 | 메모리 ~1.3GB |
| auth | GoTrue (가입/로그인) | — | `ENABLE_EMAIL_AUTOCONFIRM` 중요 |
| rest | PostgREST | — | `notify pgrst, 'reload schema'`로 캐시 갱신 |
| realtime | Realtime (WS) | — | **채팅 렌더 필수** |
| storage + imgproxy | 파일 스토리지 | — | |
| meta | pg-meta | — | Studio용 |
| functions | Edge Functions | — | 선택적 |
| studio | Supabase Studio | **3001** | 관리 UI |
| neo4j | 그래프 DB | 7474/7687 | **bpmn-extractor 전용** — 그 외 프로파일에선 생략 가능 |
| litellm-db / litellm-proxy | LLM 프록시 | `.env.example` 기본값 4010 | OpenAI 직결 시 우회됨 — unhealthy여도 무해 (troubleshooting #8) |

`start-all-services.sh`의 `INFRA_STACK` 전체 = litellm-db litellm-proxy db kong
auth rest realtime storage imgproxy meta functions analytics studio neo4j.

**nginx의 `depends_on` 주의**: `nginx` 서비스는 agent-router·
robo-data-glossary-backend·deepagents를 `depends_on`으로 직접 물고 있다.
`docker compose up -d`로 nginx를 포함해 기동하면 이 세 서비스(및
deepagents가 의존하는 process-gpt-office-mcp)가 명시적으로 고르지 않아도
자동으로 같이 뜬다 — 아래 Core 프로파일도 이 cascade만큼 컨테이너가 늘어난다.

## 마이크로서비스 카탈로그

### Core — 핵심 경험(채팅→프로세스 생성/실행)에 필요

| 서비스 | 역할 | 호스트 포트 |
|---|---|---|
| frontend | Vue 3 SPA | (nginx 경유) |
| completion | LangChain 채팅/폼 생성 — 프론트의 메인 백엔드 | 8000 |
| base-agent-langchain-react | 프로세스 컨설팅 에이전트 (`/agent/chat/stream`) | 8008 |
| polling-service | 워크아이템 폴링/실행 | 8010 |
| memento | RAG / 벡터스토어 (Chroma) | 8005 |

### Standard 추가

| 서비스 | 역할 | 포트 |
|---|---|---|
| agent-router | 동적 에이전트 라우팅 (K8s에선 pod 스핀업) | (내부 8001) |
| deepagents | 딥에이전트 (스킬은 `skills-storage` 볼륨으로 컨테이너 내부에 마운트, 별도 컨테이너 아님) | 8021 |
| instance-classifier | 요청 자동분류·Top List (pgvector kNN) | 8013 |
| process-gpt-analytic | 실행 분석 ETL/대시보드 | 8009 |
| robo-data-glossary-backend | 용어집/카탈로그 | 5504 |

### Full 추가 (옵션·무거움)

| 서비스 | 역할 | 포트 | 비고 |
|---|---|---|---|
| openai-deep-research / process-gpt-deep-research | 딥리서치 | 8003, 8020 | TAVILY_API_KEY 선택 |
| a2a-orch | A2A 오케스트레이터 | 8006 | |
| react-voice-agent | 음성 에이전트 | 3000 | |
| computer-use | 컴퓨터 유즈 | 8007 | |
| agent-feedback | 에이전트 피드백 | 6789 | DB env 이슈 있음 (troubleshooting #10) |
| bpmn-extractor | PDF→BPMN | 8012 | **neo4j 필요** |
| process-gpt-office-mcp | 오피스 문서 MCP | 1192 | `LLM_PROVIDER: openai` env 필요 (#10) |
| mcp-validator | MCP 밸리데이터 | 8081 | 로컬에서 정상 빌드·기동되는 일반 서비스 |
| strategy | 전략 측정/설문(measure·survey) | 8014 | `/strategy-service/`로 nginx 라우팅됨 |

`start-all-services.sh`의 대화형 메뉴엔 `browser-use`도 있지만 현재
`docker-compose.yml`에는 서비스 정의가 없다 — 선택하면 "no such service"로
실패한다.

## 프로파일 → 기동 대상 매핑

```bash
# Core (Docker 메모리 8GB 권장; nginx를 포함하면 agent-router·
# robo-data-glossary-backend·deepagents·process-gpt-office-mcp가
# depends_on으로 자동 추가되므로 실제로는 더 늘어난다)
INFRA_CORE=(db analytics kong auth rest realtime storage imgproxy meta studio)
CORE=(frontend completion base-agent-langchain-react memento polling-service)

# Standard (12GB)
STANDARD=("${CORE[@]}" agent-router deepagents \
          instance-classifier process-gpt-analytic robo-data-glossary-backend)

# Full (16GB+): ./start-all-services.sh all
# (mcp-validator·strategy 포함, browser-use는 compose 미정의로 실패)
```

## 이미지 / 레지스트리

- 대부분 `ghcr.io/uengine-oss/*` — **private**. pull하려면
  `echo $GITHUB_PAT | docker login ghcr.io -u <user> --password-stdin`
  (PAT scope `read:packages`). 이미 로컬에 이미지가 있으면 `--pull never`.
- frontend는 소스 빌드 가능: `docker build -t process-gpt-frontend:local services/frontend`
  (서브모듈 체크아웃 필요, `process-gpt-infra-docker` 기준 상대경로).
  instance-classifier·strategy·deepagents 등도 `build:` 지정되어 로컬 빌드됨.
- 서브모듈 초기화는 `--recursive` 금지 (중첩 worktree 오인 — troubleshooting #1):
  `git submodule update --init` 후 각자 브랜치 pull (`deep-research`만 master).

## Kubernetes 자산 (프로덕션 경로)

- `deployments/*.yaml`: completion, frontend, memento, polling-service,
  crewai-action, crewai-deep-research, react-voice-agent, gateway, airbnb-agent
  — 네임스페이스 `dev`, `envFrom`: ConfigMap `my-config` + Secret.
- 루트: `configmap-example.yaml`, `secrets-example.yaml`, `rbac.yaml`
  (agent-router가 pod 생성할 권한), `pvc.yaml`, `*-service.yaml`.
- **K8s 매니페스트는 Supabase를 매니지드(cloud) 프로젝트로 가정**
  (`SUPABASE_URL: https://<project>.supabase.co`). 셀프호스팅 Supabase를 K8s에
  올리려면 별도 차트(공식 supabase-kubernetes) 필요 — production-k8s.md 참조.
- agent-router는 `K8S_NAMESPACE`에 agent runtime pod를 동적 생성
  (`agent-runtime-secrets` Secret 필요).

## 주요 URL (기본 포트)

- 게이트웨이(앱 진입점): http://localhost:8088
- Supabase API(Kong): http://localhost:54321 · Studio: http://localhost:3001
- Neo4j Browser: http://localhost:7474
