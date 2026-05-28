---
name: compose-force-recreate-stale-mount
description: docker compose -f base -f override up -d --force-recreate --no-deps 가 새 override 의 volumes 변경을 반영하지 않는 경우가 있어, docker rm -f 후 다시 up -d 가 필요.
applies-to:
  - docker-compose
  - compose-override
  - backend-coverage
  - windows-docker-desktop
last-verified: 2026-05-27
metadata:
  type: pitfall
---

# Compose --force-recreate 가 override 의 새 mount 를 반영하지 않음

여러 스위트가 동일 서비스(예: `completion`)에 서로 다른 `coverage.override.yml` 을 번갈아 적용할 때, 이전 스위트가 만들어 둔 컨테이너가 디스크에 남아 있는 상태에서:

```bash
docker compose -f docker-compose.e2e.yml \
  -f openspec/specs/<new-spec>/e2e/docker/coverage.override.yml \
  up -d --force-recreate --no-deps completion
```

를 실행하면 `docker compose ... config` 가 보여주는 merged config 는 새 override (`/coverage` 가 `<new-spec>/e2e/results/backend-coverage` 로 바인드) 가 맞지만, 실제 만들어진 컨테이너의 `docker inspect ... .Mounts` 는 이전 스위트의 경로(`<old-spec>/e2e/results/backend-coverage`) 를 그대로 가리킨다. Windows Docker Desktop 에서 재현됨.

결과적으로 USR2 flush 후 `coverage.xml` 이 호스트의 새 스펙 폴더에는 만들어지지 않고 이전 스펙 폴더에 떨어진다.

## What works

명시적으로 컨테이너를 제거한 뒤 다시 만든다:

```bash
docker rm -f process-gpt-e2e-completion
docker compose -f docker-compose.e2e.yml \
  -f openspec/specs/<new-spec>/e2e/docker/coverage.override.yml \
  up -d --no-deps completion
```

`docker inspect process-gpt-e2e-completion --format '{{json .Mounts}}'` 로 새 경로가 반영됐는지 즉시 확인할 것.

## Why

`--force-recreate` 는 컨테이너 spec hash 가 동일할 때 새 spec 으로 갈아엎지만, 일부 케이스에서 이전 컨테이너의 mount 메타데이터가 그대로 재사용되는 것으로 보임. 사용자 입장에서 가장 안전한 보장은 `docker rm -f` 후 `up -d` 다.

## How to apply

- Triggered when:
  - 같은 서비스(완료, 게이트웨이 등)에 대해 스위트별로 다른 coverage override 를 자주 갈아끼울 때
  - USR2 flush 후 호스트의 `e2e/results/backend-coverage/` 가 비어 있을 때
- Skip if:
  - override 가 변경 없이 그대로 재사용되는 경우 (force-recreate 만으로 충분)
  - 새로운 스택을 `docker compose down` 후 처음 띄우는 경우

Related: [[completion-coverage-override-workdir]], [[coverage-py-usr2-flush]], [[compose-override-relative-paths]]
