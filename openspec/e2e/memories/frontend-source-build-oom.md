---
name: frontend-source-build-oom
description: services/frontend을 Docker 안에서 vite build로 빌드하면 Vuetify+Monaco CSS 처리 중 Docker 데몬이 OOM-killed 됨. 호스트에서 빌드 후 thin 이미지로 패키징하는 우회 경로가 필요.
applies-to:
  - vue
  - vite
  - vuetify
  - monaco
  - in-docker-build
  - frontend-coverage
last-verified: 2026-05-27
metadata:
  type: pitfall
---

# Frontend source build OOMs in Docker

`completion_agent-memory-chat` 스위트에서 소스맵 기반 프론트엔드 coverage를
얻기 위해 `services/frontend`을 in-docker 빌드(`docker compose build frontend`)
했을 때, Vite CSS 단계에서 Docker 데몬 자체가 반복적으로 OOM-killed 됨.
`build:e2e` 스크립트로 `vue-tsc` 생략, `--minify=false`로 메모리 절감 시도
모두 실패함.

## What works

호스트에서 dist를 만들고 thin 이미지로 패키징:

```bash
# 1) 호스트에서 빌드
cd services/frontend
NODE_OPTIONS="--max-old-space-size=8192" npx vite build --minify=false

# 2) thin Dockerfile이 dist를 spa-http-server 이미지에 복사
#    예: services/frontend/Dockerfile.coverage-prebuilt
#    FROM sanghoon01/spa-http-server:v1
#    COPY dist /opt/www
docker build -f services/frontend/Dockerfile.coverage-prebuilt -t process-gpt-e2e-frontend:coverage services/frontend

# 3) 스위트 로컬 compose override로 이 이미지 참조
#    openspec/specs/<spec-name>/e2e/docker/frontend-coverage.override.yml
```

참고 구현: `openspec/specs/completion_agent-memory-chat/e2e/docker/frontend-coverage.override.yml`
와 `services/frontend/Dockerfile.coverage-prebuilt`.

## Why

- `vite build`의 피크 RSS가 WSL2 Docker 기본 메모리 한도를 초과함.
- Vuetify(스타일 변환)와 Monaco(거대한 워커 번들)가 같이 들어가면 더 심함.
- `--minify=false`로 압축 단계는 줄일 수 있지만 CSS 변환 단계의 피크를
  못 낮춤. `vue-tsc` 생략도 코드 생성 단계의 피크와 무관.
- 호스트 Node는 16GB 머신 기준으로 8GB heap을 잡아도 안정적으로 통과.

## How to apply

- Triggered when:
  - source-mapped frontend coverage가 필요한데 운영 이미지가 prebuilt/minified임
  - frontend 스택이 Vue + Vite + Vuetify (또는 Monaco 등 대형 의존성) 조합
  - Docker Desktop / WSL2 환경에서 작업 중
- Skip if:
  - 프론트엔드 번들이 작고(예: Vuetify/Monaco 없음) in-docker 빌드가 안정적임
  - 개발 머신의 Docker에 16GB 이상이 할당되어 있고 데몬 OOM이 재현되지 않음

Related: [[spa-http-server-port-8080]]
