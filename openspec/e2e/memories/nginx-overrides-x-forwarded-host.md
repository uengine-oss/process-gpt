---
name: nginx-overrides-x-forwarded-host
description: 공유 E2E nginx 게이트웨이가 인바운드 X-Forwarded-Host 헤더를 무조건 자신의 $host로 덮어쓰므로 멀티-테넌트(subdomain) 분기 검증은 게이트웨이를 우회해 백엔드 직접 포트로 호출해야 함.
applies-to:
  - completion
  - nginx-gateway
  - multi-tenant
  - subdomain-routing
  - playwright-request
last-verified: 2026-05-27
metadata:
  type: pitfall
---

# 공유 nginx 게이트웨이의 X-Forwarded-Host 덮어쓰기

`openspec/specs/completion_agent-memory-chat/e2e/docker/nginx.e2e.conf` 는 모든 스위트가
공유하는 게이트웨이이며, `/completion/` location 블록에서 다음과 같이 헤더를 설정한다:

```
proxy_set_header X-Forwarded-Host $host;
```

`$host` 는 nginx 가 인식한 자신의 호스트(예: `localhost`)이므로, 클라이언트가
보낸 `X-Forwarded-Host` 는 **항상 폐기**되고 백엔드 `services/completion/main.py`
의 subdomain 미들웨어는 언제나 `localhost` 테넌트로 해석한다.

따라서 게이트웨이를 통해서는 멀티-테넌트(subdomain) 분기를 검증할 수 없다.

## What works

테넌트 분기 검증이 필요한 보조 프로토콜 시나리오는 **completion 의 직접 노출 포트(`localhost:8000`)**
로 호출한다. `docker-compose.e2e.yml` 의 completion 서비스는 8000 을 호스트에 노출한다.

```js
// Playwright 보조 프로토콜 패턴
const COMPLETION_DIRECT = process.env.COMPLETION_DIRECT_URL || 'http://127.0.0.1:8000';
const ctx = await pwRequest.newContext({ baseURL: COMPLETION_DIRECT });
const resp = await ctx.post('/process-search', {
  headers: {
    'Content-Type': 'application/json',
    'X-Forwarded-Host': 'empty-tenant.process-gpt.io',
  },
  data: { query: '...' },
});
```

127.0.0.1 권장 — Windows + Node 18+ 에서 `localhost` 가 IPv6 로 해석되면서
간헐적으로 `socket hang up` 이 발생하는 사례를 보았음.

대안(권장하지 않음): 공유 nginx 설정을 `proxy_set_header X-Forwarded-Host
$http_x_forwarded_host;` 로 변경하면 클라이언트 헤더가 통과되지만, 기존 다른
스위트의 가정을 깰 수 있어 영향 범위 분석이 필요하다.

## Why

- nginx 의 `proxy_set_header X-Forwarded-Host $host;` 는 인바운드 헤더와
  무관하게 매 요청에서 헤더를 새로 설정한다 (덮어쓰기).
- 게이트웨이가 단일 스택의 공유 자원이라 한 스위트가 nginx 설정을 바꾸면
  다른 스위트의 가정이 같이 깨질 수 있어, 게이트웨이 우회가 가장 안전한 회피.

## How to apply

- Triggered when:
  - 멀티-테넌트/subdomain 라우팅 분기를 E2E 로 검증해야 할 때
  - 게이트웨이를 거친 요청에서 백엔드가 항상 `localhost` 테넌트로 동작할 때
  - 사용자 워크플로(시나리오 01)는 게이트웨이를 그대로 사용하고, 보조 프로토콜
    시나리오(02/03)만 직접 백엔드 포트로 격리해야 할 때
- Skip if:
  - 모든 시나리오가 단일 테넌트(localhost) 만 사용하는 경우
  - 공유 nginx 설정을 변경할 권한이 있고 영향 범위가 분석된 경우

Related: [[completion-coverage-override-workdir]], [[coverage-py-usr2-flush]], [[shared-auth-user-password-rotation]]
