# 로컬 개발용 설치 (Docker Compose)

개인 PC(macOS/Linux/Windows+WSL2)에서 개발·체험 목적으로 설치하는 경로.
Apple Silicon은 대부분 이미지가 amd64라 에뮬레이션으로 돌아간다(느리지만 동작).

> **이 문서는 로컬 개발 경로만 다룬다.** single-server.md/production-k8s.md는
> 여기와 무관하게 `process-gpt-infra-docker`(별도 저장소)를 독립적으로
> 클론해서 쓰는 기존 방식 그대로다 — 바뀐 게 없다.
>
> 로컬 개발은 구조가 다르다: `process-gpt`(이 모노레포) 루트의
> **`docker-infra/`**가 순수 인프라(Supabase 전체 스택 + Apache AGE + neo4j +
> LiteLLM)만 담당하는 고정 폴더로 들어와 있고, `process-gpt-infra-docker`를
> 서브모듈로 받을 필요가 없다. frontend/completion/memento/deepagents 같은
> **앱 서비스는 이제 공유 compose에 없다** — 각자 `services/<name>` 서브모듈에서
> 개별적으로 (`npm run dev`, 자체 `docker build` 등으로) 띄운다.

## 1. 소스 준비

```bash
git clone https://github.com/uengine-oss/process-gpt.git
cd process-gpt
# 건드릴 앱 서비스의 서브모듈만 받으면 된다 — 전부 받을 필요 없음
git submodule update --init services/frontend
# 예: completion도 볼 거면 추가로
# git submodule update --init services/completion
```

`docker-infra/`는 서브모듈이 아니라 이 저장소에 이미 커밋돼 있는 일반
폴더다 — clone만 하면 바로 쓸 수 있다.

## 2. docker-infra .env 구성

```bash
cd docker-infra
cp .env.example .env
```

수정 필수 항목은 거의 없다 — JWT 세트(`JWT_SECRET`/`ANON_KEY`/
`SERVICE_ROLE_KEY`)와 Supabase URL들은 dev 기본값 그대로 로컬에서 바로
동작한다. 이메일 인증 없이 즉시 가입 테스트하려면:

```dotenv
ENABLE_EMAIL_AUTOCONFIRM=true
```

LLM 관련 키(`OPENAI_API_KEY`, `ANTHROPIC_API_KEY` 등)는 여기서 다루지
않는다 — 그건 각 앱 서비스(completion, deepagents, ...)의 개별 `.env`에
넣는다. `docker-infra`의 `.env`에서 LLM 관련 항목은 `OPENROUTER_API_KEY`
(LiteLLM 프록시용, 선택)뿐이다.

> `volumes/db/init.sql`에 예전부터 있던 `supabase_functions_admin` 미존재
> 가드, `agent_orch` enum 캐스팅 문제(troubleshooting.md #19, #27)는
> `docker-infra`로 옮기며 이미 고쳐진 상태로 복사해뒀다. 게다가
> `docker-infra`를 처음 실제로 완전 신규(fresh) 설치해보며 그동안 한 번도
> 안 걸렸던 버그 2개를 추가로 찾아 고쳤다 — 기존 `process-gpt-infra-docker`
> 스택은 이미 데이터가 있는 볼륨 위에서만 돌아 이 초기화 스크립트들이 최근에
> 실행된 적이 없었다:
> - `decide_feedback_proposal_target()` 함수가 실제로는 없는 타입
>   `public.skill_feedback_proposals`를 참조 — 올바른 테이블명
>   `public.feedback_proposals`로 고침.
> - `auth.identities` 테이블을 init.sql이 (신규 signup 대비용으로) 최종
>   형태로 미리 만들어 두면, GoTrue가 부팅하며 재생하는 자기 내장
>   마이그레이션 체인(구버전 스키마 → 최신 스키마로 단계적으로 진화하는
>   수십 개)이 "이미 최종 형태"인 테이블과 충돌해 auth 컨테이너가
>   기동 실패한다 — 이 사전 생성 로직을 제거하고 GoTrue 자신이 처음부터
>   만들게 뒀다.
>
> 이 두 개는 `docker-infra`에만 적용돼 있다 — `process-gpt-infra-docker`의
> 원본 `init.sql`(단일서버/K8s 경로가 계속 참조하는 파일)에는 아직 반영
> 안 됐으니, 그쪽에서 신규 볼륨으로 완전 새로 설치할 계획이 있다면 같은
> 수정을 포팅해야 한다.
>
> 별도로 `post-clone-fixes.sh`를 돌릴 필요는 없다 — 그 스크립트의 나머지
> 패치들은 `nginx.conf`·`services/deepagents`·`services/bpmn-extractor` 등
> 이 구성에 없는 파일을 대상으로 해서 여기선 해당 사항이 없다.

## 3. 인프라 기동

```bash
./up.sh      # .env 없으면 .env.example에서 자동 생성 후 15개 서비스 전부 기동 + healthy 대기
```

- Supabase 첫 부팅은 init.sql 시드로 30–60초 걸린다 — `up.sh`가 `--wait`로
  처리한다.
- 자세한 포트/서비스 목록은 [docker-infra/README.md](../../../../docker-infra/README.md) 참고.

## 4. 앱 서비스는 개별로 띄운다

### frontend (vite dev 서버, 코드 수정 이터레이션용)

```bash
cd services/frontend
# .env: VITE_SUPABASE_URL=http://localhost:54321 (docker-infra의 KONG_HTTP_PORT)
#       VITE_SUPABASE_KEY=<docker-infra .env의 ANON_KEY>
#       VITE_MODE=ProcessGPT
npm install --legacy-peer-deps
npm run dev -- --port 5199 --strictPort   # 5173은 다른 vite 프로젝트와 충돌 이력
# 접속: http://localhost:5199
```

`vite.config.ts`의 프록시들은 이미 각 백엔드 서비스의 로컬 published
포트(예: completion `:8000`, memento `:8005`)를 가리키도록 돼 있다 — 그
서비스를 어떻게 띄우든(개별 docker build, 직접 실행) 같은 포트로 로컬에
떠 있기만 하면 된다.

### 다른 앱 서비스 (completion, memento, deepagents, ...)

각 서비스는 자신의 `services/<name>` 서브모듈 안에 있는 README/Dockerfile을
참고해 개별적으로 띄운다(자체 `docker build && docker run`, 또는 언어별
dev 서버). 연결에 필요한 값은 `docker-infra/.env`의
`ANON_KEY`/`SERVICE_ROLE_KEY`/`JWT_SECRET`/`SUPABASE_INTERNAL_URL`
(=`http://localhost:54321` 형태로 호스트에서 접속)과 동일하게 맞춘다.

## 5. 안 띄운 앱 서비스의 영향

지금 구조에서는 앱 서비스를 아무것도 안 띄우면 인프라(Supabase/AGE/neo4j/
LiteLLM)만 뜬 상태가 된다. 필요한 만큼만 골라서 띄우면 되고, 대표적으로:

| 서비스 | 없으면 잃는 기능 |
|---|---|
| frontend | 웹 UI 자체 |
| completion | 프로세스 생성/개선 채팅(LLM 호출) |
| memento | RAG/문서 검색, deepagents의 retrieve |
| deepagents | 스킬 기반 에이전트 채팅 |
| bpmn-extractor (+ neo4j·age-postgres는 docker-infra에 이미 있음) | PDF→BPMN 추출 |
| strategy (+ age-postgres) | BSC 전략맵/KPI |
| polling-service | 프로세스 인스턴스 실행(워크아이템 처리) |
| agent-router | 동적 에이전트 라우팅 |

## 5.5. 채팅 파일 첨부(PDF 업로드)를 쓰려면 — Storage 버킷 생성 (필수)

인프라(`db`/`kong`)가 뜬 뒤 한 번 실행해야 한다:

```bash
cd docker-infra
PGPW=$(grep -E '^POSTGRES_PASSWORD=' .env | cut -d= -f2-)
docker exec -e PGPASSWORD="$PGPW" supabase-db psql -U supabase_admin -d postgres -c "
insert into storage.buckets (id, name, public) values ('files', 'files', true) on conflict (id) do nothing;
insert into storage.buckets (id, name, public) values ('chat-images', 'chat-images', true) on conflict (id) do nothing;
"
```

이걸 빼먹으면 채팅에 파일을 첨부할 때 `POST /memento/save-to-storage`가
500(`Bucket not found`)으로 조용히 실패한다 — 텍스트만으로 하는 채팅
흐름(휴가 신청 프로세스 데모 등)에는 영향 없음.

## 6. 다음 단계

verification.md 체크리스트 → 통과 시 demo-playwright.md 데모 실행.
(verification.md/troubleshooting.md/architecture.md는 아직 옛
`process-gpt-infra-docker` 단일 compose 구조 기준 설명이 섞여 있을 수
있다 — docker-infra 구조 반영은 별도 후속 작업.)
