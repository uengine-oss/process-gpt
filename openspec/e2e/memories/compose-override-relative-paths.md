---
name: compose-override-relative-paths
description: docker compose override 파일의 상대 경로 volume은 override 파일 위치가 아니라 compose를 호출한 프로젝트 디렉터리(보통 repo 루트) 기준으로 해석된다. e2e/docker 안에서 ../results/... 식으로 쓰면 엉뚱한 곳으로 마운트됨.
applies-to:
  - docker-compose
  - compose-override
  - backend-coverage
  - spec-local-overrides
last-verified: 2026-05-27
metadata:
  type: pitfall
---

# Compose override 상대 경로는 프로젝트 디렉터리 기준

스위트별 coverage override를 `openspec/specs/<spec-name>/e2e/docker/coverage.override.yml`에
두고 backend coverage를 컨테이너 `/coverage`에 마운트할 때, 상대 경로를 override 파일
디렉터리 기준으로 적으면 의도와 다른 경로가 마운트된다.

## What works

override 파일 안의 volume 경로는 **프로젝트 디렉터리(=`docker compose -f ...` 호출
디렉터리, 보통 저장소 루트)** 기준으로 적는다:

```yaml
# openspec/specs/<spec-name>/e2e/docker/coverage.override.yml
services:
  completion:
    volumes:
      # Repo 루트 기준 절대 경로(./로 시작)
      - ./openspec/specs/<spec-name>/e2e/results/backend-coverage:/coverage
```

검증 방법:

```bash
docker compose -f docker-compose.e2e.yml \
  -f openspec/specs/<spec-name>/e2e/docker/coverage.override.yml \
  up -d --force-recreate --no-deps completion
docker inspect process-gpt-e2e-completion --format '{{json .Mounts}}'
# Source 경로가 의도한 e2e/results/backend-coverage인지 확인
```

함정 사례 — 다음은 **모두 잘못된 경로로 마운트됨**:

```yaml
# ❌ override 파일 기준이라고 착각한 경우 (`../results/...`)
volumes:
  - ../results/backend-coverage:/coverage
# → repo 루트의 ../results/backend-coverage (= 저장소 바깥)로 마운트됨

# ❌ "openspec" 접두어를 두 번 적은 경우
volumes:
  - ../../openspec/specs/<spec-name>/e2e/results/backend-coverage:/coverage
# → repo 루트의 ../../openspec/... (= 저장소 위의 두 단계 위)로 마운트됨
```

## Why

Docker Compose v2 사양상 override 파일에서 정의된 **bind mount 상대 경로는
"project directory" 기준으로 해석**된다(`COMPOSE_PROJECT_DIR` 또는 첫 번째
compose 파일이 있는 디렉터리). override 파일 자신의 위치는 무시된다. 이는
명시적으로 문서화되어 있지만, 보통의 파일 경로 직관(자기 파일 기준)과
충돌하므로 디버깅에 시간이 들어간다.

조용한 실패가 더 위험하다 — 잘못된 경로가 새 디렉터리로 자동 생성되면서
mount는 성공하고, 컨테이너 안에서는 `/coverage`가 비어 있는 듯 동작하지만
실제 데이터는 저장소 바깥 어딘가에 쌓인다. `coverage combine`이 통과해도
산출물이 spec-local results 디렉터리에 보이지 않으면 거의 이 문제다.

기존 `completion_agent-memory-chat/e2e/docker/coverage.override.yml`에도 동일한
패턴(`../../openspec/specs/...`)이 남아 있어, 적용해도 의도한 위치로
마운트되지 않을 수 있다. 새 스위트는 항상 프로젝트 디렉터리 기준 경로로
작성하고, override 적용 직후 `docker inspect ... .Mounts`로 마운트 위치를
검증한다.

## How to apply

- Triggered when:
  - 새 스위트의 backend coverage override를 만들 때
  - override를 적용했는데 `e2e/results/backend-coverage/`가 비어 있을 때
  - `docker exec ... ls /coverage`가 비어 보이거나 권한 오류가 날 때
- Skip if:
  - override를 사용하지 않고 메인 compose 파일에 직접 volume을 정의하는 경우
    (그쪽도 동일한 규칙이지만 경로 직관이 깨질 일이 적음)

Related: [[coverage-py-usr2-flush]], [[playwright-node-modules-junction]]
