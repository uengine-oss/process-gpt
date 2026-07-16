
# Process-GPT 로컬 개발 환경 구축 공식 온보딩 가이드

> 이 문서는 Process-GPT를 처음 접하는 개발자가 **다시 위로 올라가서 확인할 필요 없이**
> 처음부터 끝까지 순차적으로 따라가며 로컬 개발 환경을 완성할 수 있도록 작성된
> 공식 온보딩 가이드입니다.
>
> **설치 자산(compose 파일, nginx 설정, env 템플릿, DB 초기화 SQL)은 모두
> [process-gpt-infra-docker](https://github.com/uengine-oss/process-gpt-infra-docker)
> 레포에 있으며, 이 레포(`process-gpt`)에는 `process-gpt-infra-docker/` 서브모듈로
> 포함되어 있습니다.** 게이트웨이는 nginx이고, 기본 경로는 개별 서비스를 각각
> 수동으로 띄우는 것이 아니라 Docker Compose로 전체 스택을 한 번에 기동하는
> 것입니다. 특정 서비스만 로컬 소스로 개발/반복하고 싶을 때는 그 서비스만
> Compose에서 빼고 dev 서버로 실행하면 됩니다.

---

## 0. 반드시 이 문서를 처음부터 끝까지 읽어야 하는 이유

Process-GPT는 단일 애플리케이션이 아닙니다.
다음과 같은 **다중 서비스 + 다중 기술 스택**이 정확한 순서와 설정으로 연결되어야 정상 동작합니다.

- Frontend (Vue 3 + Vite)
- Gateway (nginx, JWT 검증은 Supabase Auth 기준)
- Completion Service (Python + OpenAI)
- Polling Service (비동기 워크아이템 처리)
- Memento Service (RAG / 벡터스토어)
- Supabase (Auth + PostgreSQL + Realtime + Storage)
- 그 외 다수의 마이크로서비스 (`services/` 참조)

👉 **하나라도 누락되면** 로그인 실패, 401 오류, 채팅 무응답, 메모리 저장 실패가 발생할 수 있습니다.
정확한 서비스 카탈로그와 포트, 의존관계는
`.claude/skills/install-process-gpt/references/architecture.md`를 참조하세요.

---

## 1. 전체 아키텍처 개요

```
[Browser]
   ↓
[nginx 게이트웨이 :8088]  ← 모든 요청의 단일 진입점
   ├──► [Vue3 Frontend]
   ├──► [Completion Service] ←→ [Polling Service]
   ├──► [base-agent-langchain-react]
   └──► [Memento Service] 등
   ↓ (프론트는 Supabase에 직접 연결)
[Supabase (Auth + PostgreSQL + Realtime + Storage)]
```

- 게이트웨이(nginx)는 AI/에이전트 호출의 단일 진입점이고, 프론트는 Supabase(REST/
  Realtime/Auth)에 **직접** 접속합니다(멀티테넌트, RLS 기반).
- 멀티테넌시: `tenant_id`가 **접속 호스트명에서 파생**됩니다
  (`localhost:8088` 접속 → tenant `localhost`). RLS는 JWT의
  `app_metadata.tenant_id` 클레임을 검사합니다.

---

## 2. Repository 준비 (절대 생략 불가)

### 2-1. `process-gpt-infra-docker` 준비

이미 `process-gpt`를 클론했다면 서브모듈만 초기화하면 됩니다:

```bash
cd process-gpt
git submodule update --init process-gpt-infra-docker
cd process-gpt-infra-docker
```

`process-gpt` 소스가 필요 없고 Docker로 앱만 띄우면 된다면
`process-gpt-infra-docker`만 단독으로 클론해도 됩니다:

```bash
git clone https://github.com/uengine-oss/process-gpt-infra-docker.git
cd process-gpt-infra-docker
```

### 2-2. 서비스 소스 서브모듈 (소스 수정/dev 서버 실행 시에만 필요)

이미지 그대로 쓰지 않고 특정 서비스를 로컬 소스로 빌드/실행하려면 그 서비스의
서브모듈을 초기화합니다 (`--recursive`는 사용하지 않습니다 — 중첩 worktree를
서브모듈로 오인하는 문제가 있습니다):

```bash
git submodule update --init services/frontend services/completion services/memento
```

---

## 3. Docker Compose로 인프라 + 나머지 서비스 기동

로컬 소스로 반복 작업할 서비스를 제외한 나머지(인프라 + 다른 마이크로서비스 +
게이트웨이)는 Docker Compose로 띄워두는 것이 가장 간단합니다.
전체 절차는 [Local Installation Guide](docs/local-installation-guide.md)를 따르세요:

```bash
cp .env.example .env
# LLM API 키 등 채우기

./start-all-services.sh            # 대화형으로 서비스 선택
# 또는: ./start-all-services.sh completion memento base-agent-langchain-react
```

이 문서의 나머지는 **frontend를 로컬 dev 서버로 돌리는 경우**를 예로 듭니다.
같은 패턴(해당 서비스만 Compose에서 제외하고 로컬 실행)을 completion, memento
등 다른 서비스에도 적용할 수 있습니다 — 각 서비스의 정확한 실행 방법(가상환경,
의존성 설치, 실행 커맨드)은 해당 서비스 레포(`services/<name>/README.md`)를
따르세요.

---

## 4. Frontend를 dev 서버로 실행 (코드 수정 이터레이션용)

도커 이미지 재빌드는 매번 ~3분이 걸려 프론트 코드를 자주 수정할 때는 비효율적입니다.
Vite dev 서버(HMR)를 대신 사용하세요.

### 4-1. Node.js 버전 확인

```bash
node -v
```

버전 불일치 시 `nvm`으로 프로젝트가 요구하는 버전을 설치하세요
(`services/frontend/package.json`의 `engines` 참조).

### 4-2. 의존성 설치 및 실행

```bash
cd process-gpt-infra-docker/services/frontend
npm install --legacy-peer-deps
```

`.env`에 다음을 설정합니다 (Docker Compose로 띄운 Supabase 기준):

```env
VITE_SUPABASE_URL=http://localhost:54321
VITE_SUPABASE_KEY=<ANON_KEY>       # .env.example의 dev ANON_KEY
VITE_MODE=ProcessGPT
```

```bash
npm run dev -- --port 5199 --strictPort
```

- 5173 포트는 다른 Vite 프로젝트와 충돌한 이력이 있어 전용 포트(5199 등)로
  고정하는 것을 권장합니다.
- `vite.config.ts`의 `/langchain-chat` 프록시 타깃은 nginx 게이트웨이
  (`http://127.0.0.1:8088`)로 두는 것이 안전합니다 — 호스트 `:8000`이 다른
  프로세스에 선점될 수 있습니다.
- 접속: **http://localhost:5199**

프론트 이미지를 다시 빌드해 Compose에 고정하려면:

```bash
docker build -t process-gpt-frontend:local process-gpt-infra-docker/services/frontend
# docker-compose.yml의 frontend.image를 위 태그로 교체 후 재기동
```

---

## 5. 실행 순서 요약

1. Docker Desktop
2. `process-gpt-infra-docker`에서 인프라 + (로컬로 안 돌릴) 나머지 서비스 기동
3. (선택) 특정 서비스를 dev 서버로 별도 실행 — frontend 예시는 위 4번 참조

---

## 6. 최종 체크리스트

- [ ] `docker compose ps`로 인프라/서비스 컨테이너 상태 확인
- [ ] 게이트웨이(http://localhost:8088) 200 응답
- [ ] 로그인 성공, JWT `app_metadata.tenant_id` 정상 (접속 호스트명과 일치)
- [ ] Completion 응답, Memory 저장/조회 정상
- [ ] Supabase Studio에서 DB CRUD 정상

문제가 발생하면 `.claude/skills/install-process-gpt/references/troubleshooting.md`와
`INSTALL_MEMORY.md`를 먼저 확인하세요 — 실전에서 겪은 이슈의 증상→원인→해결이
정리되어 있습니다.

---

## 마무리

이 문서는 **Process-GPT 로컬 개발 환경 구축의 공식 기준 문서**입니다.
신규 개발자 온보딩, 사내 위키, 자동화 스크립트 작성의 기준으로 활용하십시오.
설치 파일 자체(compose/nginx/env/DB 스키마)의 최신 원본은 항상
[process-gpt-infra-docker](https://github.com/uengine-oss/process-gpt-infra-docker)
레포를 기준으로 삼습니다.
