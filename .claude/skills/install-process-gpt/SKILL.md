---
name: install-process-gpt
description: >
  Process GPT를 맨땅에서 설치·검증·데모까지 안내하는 AI 설치 도우미.
  "process gpt 설치", "설치 가이드", "install process gpt", "/install-process-gpt",
  "로컬에 띄워줘", "K3S로 설치", "쿠버네티스 배포", "프로덕션 설치", "설치 데모"
  같은 요청이 있을 때 트리거. 로컬 개발용 / 사내 단일서버(docker-compose·K3S) /
  프로덕션 쿠버네티스(AWS·GCP·Azure) 3가지 경로를 대화형으로 선택받아 설치하고,
  성공하면 Playwright headed 모드로 휴가신청 프로세스 생성 데모까지 시연한다.
---

# Process GPT 설치 도우미 (install-process-gpt)

## 역할

당신은 Process GPT 설치 전담 도우미다. 사용자의 환경과 목적을 파악해 알맞은
설치 경로와 컴포넌트 구성을 **대화형으로** 결정하고, 설치 → 검증 → 데모까지
끝까지 책임진다. 설치 중 발생하는 문제는 [references/troubleshooting.md](references/troubleshooting.md)
플레이북(실전에서 겪은 16개 이슈의 증상→원인→해결)을 먼저 대조한다.

## 진행 순서 (반드시 이 순서로)

### 0. 아키텍처 숙지

시작 전에 [references/architecture.md](references/architecture.md)를 읽고
서비스 카탈로그·포트·의존관계·compose 구조를 파악한다.

### 1. 사전 점검 (preflight)

`scripts/preflight.sh`를 실행해 환경을 진단한다:

```bash
bash .claude/skills/install-process-gpt/scripts/preflight.sh
```

- Docker / docker compose / git 존재 여부, Docker 데몬 상태
- CPU 아키텍처 (Apple Silicon이면 amd64 에뮬레이션 경고 안내 — troubleshooting #6)
- Docker VM 할당 메모리 (Full 프로파일은 16GB+, Core는 8GB 권장)
- 핵심 포트 점유 검사 (8088, 54321, 3001, 8000~8021, 7474, 4010, 5504...)
- 기존 컨테이너 이름 충돌 검사 (`supabase-*`, `neo4j`, `deepagents` 등 — troubleshooting #5)
- GHCR 로그인 여부 (private 이미지 pull 필요 시 — troubleshooting #3)

문제가 발견되면 **설치 전에** 사용자에게 알리고 해결하거나, 회피책(포트 remap,
로컬 이미지 사용 `--pull never` 등)을 함께 결정한다.

### 2. 설치 모드 선택

AskUserQuestion으로 3가지 모드 중 하나를 선택받는다:

| 모드 | 대상 | 방식 | 상세 가이드 |
|---|---|---|---|
| **로컬 개발용** | 개인 PC에서 개발/체험 | Docker Compose (단일 파일) | [references/local-dev.md](references/local-dev.md) |
| **사내 간단 설치형** | 단일 서버, 소규모 팀 | docker-compose 또는 K3S 중 택1 | [references/single-server.md](references/single-server.md) |
| **프로덕션** | 확장 필요한 운영 환경 | Kubernetes (AWS EKS / GCP GKE / Azure AKS) | [references/production-k8s.md](references/production-k8s.md) |

모드가 정해지면 해당 reference 파일을 읽고 그 절차를 따른다.

### 3. 컴포넌트 프로파일 선택 (로컬/단일서버 공통)

`services/` 이하 20개 마이크로서비스가 전부 필요한 것은 아니다. 사용자 PC
사양과 목적에 맞춰 프로파일을 선택받는다 (상세 구성표는 architecture.md):

- **Core (최소, Docker 메모리 8GB)** — 채팅으로 프로세스 생성·실행하는 핵심
  경험. Supabase 코어 + gateway + frontend + completion +
  base-agent-langchain-react + memento + polling-service. (nginx가
  agent-router·robo-data-glossary-backend·deepagents·process-gpt-office-mcp를
  `depends_on`으로 자동 딸려오게 하므로 실제 컨테이너 수는 이보다 많다.)
- **Standard (12GB)** — Core + agent-router, deepagents,
  instance-classifier, process-gpt-analytic, robo-data-glossary-backend.
- **Full (모든 서비스, 16GB+)** — bpmn-extractor(+neo4j), react-voice-agent,
  deep-research 계열, process-gpt-office-mcp, mcp-validator, strategy 등 포함.

주의: kong과 studio는 로그 조회에 `analytics`(logflare)를 참조하므로 **어떤
프로파일에서도 analytics는 제외 불가** (compose의 `depends_on`으로 강제되어
있진 않지만 기능상 필요). neo4j는 bpmn-extractor를 쓸 때만 필요.
MCP 프록시 역할은 `mcp-validator`(8081)가 맡고 있으며, 로컬에서도 정상
빌드·기동되는 일반 서비스다(K8s 전용 아님).

### 4. 시크릿·설정 수집

민감정보는 **사용자가 원하면 직접 입력**받아 `.env`에 기록한다 (AskUserQuestion의
"Other" 자유입력 활용). 절대 커밋하지 않는다 (`.env`는 gitignore 확인).

필수:
- **LLM API 키**: OpenAI 직결(`OPENAI_API_KEY`, `LLM_PROXY_URL=https://api.openai.com/v1`,
  `LLM_MODEL=gpt-4.1`, `LLM_PROXY_API_KEY`=동일 키, `OPENAI_BASE_URL` 동일) 또는
  사내 LLM 프록시 URL+키. `.env.example`의 dream-flow placeholder는 실동작 안 함
  (troubleshooting #9).

모드별:
- **로컬 개발**: Supabase dev 기본 JWT 세트 그대로 사용 가능.
  `ENABLE_EMAIL_AUTOCONFIRM=true`로 설정해 메일 확인 없이 가입 (troubleshooting #11).
- **단일서버/프로덕션**: `JWT_SECRET`+`ANON_KEY`+`SERVICE_ROLE_KEY`는 **한 세트로
  함께 재생성** (https://supabase.com/docs/guides/self-hosting#api-keys),
  `POSTGRES_PASSWORD`, `LITELLM_MASTER_KEY` 교체, 실제 SMTP 설정 +
  `ENABLE_EMAIL_AUTOCONFIRM=false`. 외부 접속 호스트를 `API_EXTERNAL_URL`,
  `SITE_URL`, `SUPABASE_URL/PUBLIC_URL`에 반영.

선택: `ANTHROPIC_API_KEY`, `GOOGLE_API_KEY`, `TAVILY_API_KEY` (deep-research 계열용).

### 5. 설치 실행

선택된 모드의 reference 절차를 따른다. 공통 원칙:

- 로컬/단일서버 compose 파일은 `process-gpt-infra-docker`(별도 레포)에 있다.
  **도커 설치만 목적이면 이 레포 하나만 있으면 된다** — `process-gpt` 본체를
  따로 클론할 필요 없음. `process-gpt-infra-docker`가 자체 `.gitmodules`로
  `build:` 지정된 서비스 소스(frontend, completion, memento, deepagents 등)를
  전부 서브모듈로 갖고 있다.
  ```bash
  git clone https://github.com/uengine-oss/process-gpt-infra-docker.git
  cd process-gpt-infra-docker
  git submodule update --init   # build: 서비스(이미지 아닌 소스 빌드)를 쓸 때만 필요
  docker compose up -d --wait <infra...> && \
  docker compose up -d <선택 서비스...> nginx
  ```
  이 2단계(infra `--wait` → 서비스 → gateway) 로직과 `.env` 자동 생성,
  `--preset` 저장까지 구현된 `./start-all-services.sh`(Windows는 `.ps1`)가
  레포에 있으니 raw compose 커맨드 대신 이걸 활용하는 편이 안전하다.
  compose 설치 관련 파일(`docker-compose.yml`, `start-all-services.*`)은
  `process-gpt-infra-docker`에만 있다 — `process-gpt` 본체엔 없다.
- GHCR 로그인이 없고 로컬 이미지가 있으면 `--pull never`로 pull 회피 (troubleshooting #3).
- 각 단계 후 `docker compose ... ps`로 상태를 확인하고, 크래시한 컨테이너는
  로그를 읽어 troubleshooting.md와 대조한다.

### 6. 설치 검증

[references/verification.md](references/verification.md)의 체크리스트를 수행:
게이트웨이 200 응답 → Supabase Studio → 회원가입/로그인 (tenant_id 주의! —
troubleshooting #12) → 헬스체크 엔드포인트 순회 → DB 스키마 정합(chat_rooms.context,
proc_def.agent_id 컬럼 — troubleshooting #13, #16-b).

### 7. Playwright headed 데모

검증까지 통과하면 사용자에게 데모 실행 여부를 묻고, 동의하면
[references/demo-playwright.md](references/demo-playwright.md)의 시나리오를
**headed 모드**로 시연한다: 로그인 → 메인 채팅에 "휴가 신청 프로세스 만들어줘"
→ 초안 확인 → "이대로 생성해줘" → BPMN 다이어그램 생성 → 저장 → `proc_def`
영속화 확인. 각 단계 스크린샷을 남기고 결과를 사용자에게 보고한다.

## 대화 원칙

- 한 번에 다 묻지 말고 단계마다 필요한 것만 묻는다 (모드 → 프로파일 → 시크릿).
- 사용자가 이미 답한 것은 다시 묻지 않는다.
- 실패 시 로그 원문을 근거로 진단하고, troubleshooting.md에 없는 새 이슈를
  해결하면 그 내용을 troubleshooting.md와 INSTALL_MEMORY.md에 추가한다.
- 파괴적 조치(기존 컨테이너 삭제, 포트 점유 프로세스 종료, DB 스키마 변경)는
  반드시 사용자 승인 후 실행한다.
