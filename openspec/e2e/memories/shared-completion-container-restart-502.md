---
name: shared-completion-container-restart-502
description: 여러 completion 기반 스위트가 같은 process-gpt-e2e-completion 컨테이너를 coverage override로 교체하면 다른 스위트의 진행 중 Playwright가 502를 받는다. beforeAll 헬스 폴링이 견고한 우회.
applies-to:
  - completion
  - docker-compose-override
  - playwright
  - shared-services
last-verified: 2026-05-27
metadata:
  type: pitfall
---

# 공유 completion 컨테이너 재시작이 다른 스위트의 Playwright를 502로 끊는다

`docker-compose.e2e.yml`의 `completion` 서비스는 컨테이너 이름이 `process-gpt-e2e-completion`로 한 개뿐이다. 각 completion 기반 E2E 스위트가 자기 `coverage.override.yml`로 `up -d --force-recreate --no-deps completion`을 호출하면 동일한 컨테이너를 다른 mount/COMMAND로 다시 만든다. 다른 스위트의 Playwright 실행 중에 이 동작이 일어나면, gateway가 upstream(completion:8000)에 접속하지 못해 `502 Bad Gateway`로 떨어진다.

`completion_process-workitem-submission` 스위트의 초기 Playwright 실행에서 시나리오 01·02가 502로 실패했고, 동일한 스펙으로 재실행했더니 9/9 통과했다. 컨테이너 health-starting 윈도우 동안 들어간 요청만 502였다.

## What works

Playwright config에 `beforeAll`로 gateway → completion 헬스 폴링을 두어, 컨테이너가 healthy일 때까지 최대 120초 기다린다:

```javascript
test.beforeAll(async ({ request }) => {
  const deadline = Date.now() + 120_000;
  while (Date.now() < deadline) {
    try {
      const r = await request.get('/completion/multi-agent/health-check', { timeout: 5_000 });
      if (r.ok()) return;
    } catch (_) { /* retry */ }
    await new Promise((res) => setTimeout(res, 2_000));
  }
  throw new Error('gateway -> completion not healthy in 120s');
});
```

배경 작업으로 다른 스위트가 completion을 recreate해도, 본 스위트는 그 사이 health 윈도우를 기다리고 시작한다.

## Why

- compose의 `container_name: process-gpt-e2e-completion`가 고정 이름이라 두 스위트가 동시에 다른 mount/CMD를 시도하면 마지막 호출이 컨테이너를 통째로 교체한다.
- nginx gateway는 upstream healthcheck를 별도로 하지 않으므로 컨테이너가 starting인 동안 들어온 요청은 즉시 502로 회신된다.
- `depends_on`은 한 번 컨테이너가 올라간 시점만 본다 — 이후 recreate는 감지하지 못한다.

## How to apply

- Triggered when:
  - 두 개 이상의 completion 기반 스위트(`completion_*`)가 같은 머신/CI에서 시간차로 실행
  - "왜 Playwright 첫 1~2개 테스트만 간헐적으로 502인가?" 디버깅 중
- Skip if:
  - 본 스위트가 단독으로 실행되고 다른 작업자가 completion을 건드리지 않을 때
  - 스위트 전용 completion 컨테이너(예: `completion-wis`)를 따로 정의해 둔 경우

Related: [[completion-coverage-override-workdir]], [[coverage-py-usr2-flush]]
