# 로컬 개발용 설치 (Docker Compose)

개인 PC(macOS/Linux/Windows+WSL2)에서 개발·체험 목적으로 설치하는 경로.
Apple Silicon은 대부분 이미지가 amd64라 에뮬레이션으로 돌아간다(느리지만 동작).

> compose yaml과 설정 파일은 [process-gpt-infra-docker](https://github.com/uengine-oss/process-gpt-infra-docker)
> 레포에 있다. **이 레포 자체가 `build:` 지정된 서비스 소스의 서브모듈
> (`.gitmodules`)을 전부 갖고 있다** — frontend, completion, memento,
> deepagents, instance-classifier, strategy, base-agent-langchain-react 등.
> `process-gpt` 본체(모노레포)도 동일한 서브모듈 세트를 갖고 있지만, 도커
> 설치만 목적이면 `process-gpt-infra-docker` 하나만 클론하면 되고
> `process-gpt`를 별도로 클론할 필요는 없다. compose 파일과 `start-all-services.*`
> 스크립트는 `process-gpt-infra-docker`에만 있다.

## 1. 소스 준비

```bash
git clone https://github.com/uengine-oss/process-gpt-infra-docker.git
cd process-gpt-infra-docker
# 서브모듈: --recursive 금지 (중첩 worktree 오인 이슈 — troubleshooting #1)
git submodule update --init
```

서브모듈이 필요한 경우는 (a) frontend를 소스 빌드/dev 서버로 돌릴 때,
(b) instance-classifier·strategy·deepagents처럼 `build:` 지정된 서비스를 쓸
때뿐이다(`docker-compose.yml`의 `build: context: ./services/*`가 이 레포
기준 상대경로). 전부 GHCR 이미지로만 돌리면 서브모듈 없이도 가능.

## 2. .env 구성

```bash
cp .env.example .env
```

수정 필수 항목 (사용자에게 직접 입력받기):

```dotenv
# LLM — OpenAI 직결 권장 (dream-flow placeholder는 동작 안 함)
OPENAI_API_KEY=sk-...
LLM_MODEL=gpt-4.1
LLM_PROXY_URL=https://api.openai.com/v1
LLM_PROXY_API_KEY=sk-...        # OPENAI_API_KEY와 동일하게
OPENAI_BASE_URL=https://api.openai.com/v1
LLM_BASE_URL=https://api.openai.com/v1   # bpmn-extractor용

# 개발기: 메일 확인 없이 즉시 가입 허용
ENABLE_EMAIL_AUTOCONFIRM=true
```

JWT 세트(`JWT_SECRET`/`ANON_KEY`/`SERVICE_ROLE_KEY`)는 dev 기본값 그대로 사용
가능(로컬 한정). Supabase URL들도 localhost 기본값 유지.

## 3. 기동

레포에 이미 이 순서(infra `--wait` → 선택 서비스 → gateway)를 구현한
`./start-all-services.sh`(Windows는 `.ps1`)가 있다 — 대화형 체크박스로
서비스를 고르거나 `./start-all-services.sh frontend completion memento ...`
처럼 인자로 바로 넘길 수 있고, `.env` 없으면 자동으로 `.env.example`을
복사해준다. 가능하면 raw compose 커맨드보다 이 스크립트를 우선 사용한다.

수동으로 할 경우(GHCR 미로그인 + 로컬 이미지 존재 시 `--pull never`):

```bash
docker compose up -d --wait \
  db analytics kong auth rest realtime storage imgproxy meta studio
docker compose up -d --pull never \
  frontend completion base-agent-langchain-react memento polling-service nginx
```

- 전체 기동(`docker compose up -d`)은 `pull`을 먼저 도는데 GHCR private 이미지에서
  `denied`로 전체 중단될 수 있다 → GHCR 로그인하거나 `--pull never` 사용.
- supabase-db는 첫 부팅에 init.sql 시드로 30–60초 걸린다. `--wait`가 처리.
- **주의**: `nginx` 서비스는 `depends_on`으로 agent-router·
  robo-data-glossary-backend·deepagents를 물고 있다. 위 예시처럼 Core 구성만
  고르더라도 `nginx`를 포함해 기동하면 이 세 서비스(+ deepagents가 의존하는
  process-gpt-office-mcp)가 compose에 의해 자동으로 같이 뜬다. 정말 최소로
  띄우려면 nginx를 빼고 각 서비스 포트로 직접 접속하거나, 늘어난 컨테이너
  수만큼 메모리 여유를 더 잡아야 한다.

## 4. frontend를 이미지 대신 dev 서버로 (코드 수정 이터레이션용)

도커 이미지 재빌드는 ~3분/회 — 프론트 개발 시엔 vite dev 서버가 낫다:

```bash
cd services/frontend
# .env: VITE_SUPABASE_URL=http://localhost:54321, VITE_SUPABASE_KEY=<ANON_KEY>, VITE_MODE=ProcessGPT
npm install --legacy-peer-deps
npm run dev -- --port 5199 --strictPort   # 5173은 다른 vite 프로젝트와 충돌 이력
# 접속: http://localhost:5199
```

- vite 프록시(`vite.config.ts`)의 `/langchain-chat` 타깃은 `http://127.0.0.1:8088`
  (nginx)로 두는 것이 안전 — 호스트 :8000이 다른 프로세스에 선점될 수 있음
  (troubleshooting #16).
- 프론트 이미지를 소스로 굳히려면:
  `docker build -t process-gpt-frontend:local services/frontend` 후
  compose의 `frontend.image`를 그 태그로.

## 5. 부분 설치에서 빠진 컴포넌트의 영향

| 뺀 것 | 잃는 기능 |
|---|---|
| memento | RAG/문서 검색, deepagents의 retrieve |
| polling-service | 프로세스 인스턴스 실행(워크아이템 처리) |
| agent-router | 동적 에이전트 라우팅 — 로컬 nginx는 어차피 `/agent-router/route`에 503 반환(의도된 폴백 설계) |
| neo4j + bpmn-extractor | PDF→BPMN 추출 |
| analytic | 실행 분석 대시보드 |
| deep-research 계열, voice(react-voice-agent) 등 | 해당 에이전트 기능만 |

> `browser-use`는 `start-all-services.sh` 메뉴엔 있지만 현재
> `docker-compose.yml`에 서비스 정의가 없다 — 선택해도 "no such service"로
> 실패한다. 고쳐질 때까지는 안내하지 않는다.

## 6. 다음 단계

verification.md 체크리스트 → 통과 시 demo-playwright.md 데모 실행.
