---
name: nginx-gateway-dns-cache-after-restart
description: e2e gateway(nginx)의 upstream IP가 caching되어 completion 컨테이너가 재시작되면 게이트웨이가 옛 IP로 502를 계속 반환. docker restart process-gpt-e2e-gateway로 해소.
applies-to:
  - nginx-gateway
  - e2e-gateway
  - docker-compose
last-verified: 2026-05-27
metadata:
  type: pitfall
---

# Gateway DNS cache after upstream container restart

루트 `docker-compose.e2e.yml`의 `gateway` 서비스는 nginx 1.27 image를 사용하고 `upstream completion_upstream { server completion:8000; }` 같은 정적 upstream 블록을 가진다. Docker bridge 네트워크에서 `completion` 컨테이너가 재기동되면 IP가 바뀔 수 있는데, nginx는 시작 시 한 번만 DNS를 resolve하므로 옛 IP로 계속 연결 시도 → `502 Bad Gateway`를 반환한다. completion 컨테이너 자체는 healthy이지만 게이트웨이 경유 호출은 모두 실패한다.

## What works

게이트웨이를 재시작한다:

```bash
docker restart process-gpt-e2e-gateway
```

검증:

```bash
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:8088/completion/multi-agent/health-check
# 200 이어야 함. 502면 게이트웨이 재시작이 필요.
```

근본 해결책 (선택):

- `nginx.e2e.conf`에 `resolver 127.0.0.11 valid=10s;` 추가 (Docker embedded DNS) + upstream을 변수로 받아 동적 resolve
- 혹은 game day마다 `docker compose ... up -d` 직후 게이트웨이를 자동 재시작하는 helper script

## Why

nginx의 기본 동작은 startup시 1회 DNS resolve. Docker compose 네트워크에서 컨테이너 재시작/recreate는 IP를 바꿀 수 있고, 그 사이 gateway는 옛 IP에 stuck. completion 컨테이너만 healthy로 보이므로 원인 파악에 시간이 든다.

## How to apply

- Triggered when: completion(혹은 다른 upstream) 컨테이너를 재기동/recreate한 직후, gateway 경유 호출이 502/upstream unreachable로 실패.
- Skip if: 같은 라운드에서 gateway까지 함께 `docker compose ... up -d` 했다면 자동 갱신됨.

Related: [[spa-http-server-port-8080]], [[completion-coverage-override-workdir]]
