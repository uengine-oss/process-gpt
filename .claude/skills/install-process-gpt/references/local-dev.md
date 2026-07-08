# 로컬 개발용 설치 (Docker Compose)

개인 PC(macOS/Linux/Windows+WSL2)에서 개발·체험 목적으로 설치하는 경로.
Apple Silicon은 대부분 이미지가 amd64라 에뮬레이션으로 돌아간다(느리지만 동작).

## 1. 소스 준비

```bash
git clone https://github.com/uengine-oss/process-gpt.git && cd process-gpt
# 서브모듈: --recursive 금지 (중첩 worktree 오인 이슈 — troubleshooting #1)
git submodule update --init
```

서브모듈이 필요한 경우는 (a) frontend를 소스 빌드/dev 서버로 돌릴 때,
(b) instance-classifier처럼 `build:` 지정된 서비스뿐이다. 이미지로만 돌리면
서브모듈 없이도 가능.

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

프로파일(architecture.md)을 선택받은 뒤:

```bash
chmod +x start-all-services.sh    # 실행권한 없을 수 있음 (troubleshooting #2)

# 방법 A — 헬퍼 스크립트 (interactive 체크박스 or 명시)
./start-all-services.sh frontend completion base-agent-langchain-react memento polling-service

# 방법 B — compose 직접 (GHCR 미로그인 + 로컬 이미지 존재 시 --pull never)
CF=(-f docker-compose.yml -f infra/docker-compose.yml -f compose/docker-compose.yml -f gateway/docker-compose.yml)
docker compose --env-file .env "${CF[@]}" up -d --wait \
  db analytics kong auth rest realtime storage imgproxy meta studio
docker compose --env-file .env "${CF[@]}" up -d --pull never \
  frontend completion base-agent-langchain-react memento polling-service nginx
```

- `all` 모드는 `compose pull`을 먼저 도는데 GHCR private 이미지에서 `denied`로
  전체 중단될 수 있다 → GHCR 로그인하거나 방법 B의 `--pull never` 사용.
- supabase-db는 첫 부팅에 init.sql 시드로 30–60초 걸린다. `--wait`가 처리.

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
| deep-research 계열, browser-use, voice 등 | 해당 에이전트 기능만 |

## 6. 다음 단계

verification.md 체크리스트 → 통과 시 demo-playwright.md 데모 실행.
