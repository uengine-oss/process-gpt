---
name: completion-coverage-override-workdir
description: 기존 completion coverage override의 cd /app 경로가 Dockerfile WORKDIR /usr/src/app 과 불일치해 컨테이너가 즉시 종료됨
applies-to:
  - completion
  - coverage.py
  - docker-compose-override
last-verified: 2026-05-27
metadata:
  type: pitfall
---

# completion coverage override의 WORKDIR 불일치

`completion_agent-memory-chat` 및 `completion_mcp-server-config` 스위트의 `e2e/docker/coverage.override.yml`은 다음과 같이 시작한다:

```
command:
  - sh
  - -c
  - "pip install --quiet coverage && cd /app && coverage erase && ..."
```

그러나 실제 `services/completion/Dockerfile`은 `WORKDIR /usr/src/app`로 설정되어 있어 `cd /app`가 즉시 실패하고 컨테이너가 `Exited (2)`로 떨어진다. override를 켠 직후 다른 작업자가 `completion`을 정상 기동시키려 하면 그 사이 기간 동안 모든 의존 서비스(gateway, depends_on)도 같이 실패한다.

## What works

- 임시 우회: `docker compose -f docker-compose.e2e.yml up -d --build completion` 로 override 없이 재기동하면 정상 부팅된다 (Dockerfile의 정식 CMD가 회복됨).
- 정식 수정: 위 두 override 파일의 `cd /app` → `cd /usr/src/app` 으로 변경하거나, Dockerfile의 WORKDIR를 `/app`으로 통일.

## Why

override는 `cd /app`를 가정해 작성되었지만 본 저장소의 completion Dockerfile은 `/usr/src/app`을 사용한다. 두 사실이 한 곳에 적혀 있지 않아 발견까지 시간이 걸린다.

## How to apply

- Triggered when: 다른 completion 기반 스위트 빌드 중 `completion` 컨테이너가 `sh: 1: cd: can't cd to /app` 로 죽을 때.
- Skip if: coverage override를 사용하지 않는 단순 통합 테스트 (override 없이 `up -d --build completion` 으로 충분).

Related: [[coverage-py-usr2-flush]]
