---
name: spa-http-server-port-8080
description: services/frontend의 Dockerfile이 사용하는 sanghoon01/spa-http-server:v1 이미지는 80이 아니라 8080을 listen함. nginx 게이트웨이 upstream 포트를 8080으로 맞춰야 함.
applies-to:
  - spa-http-server
  - nginx-gateway
  - frontend
last-verified: 2026-05-27
metadata:
  type: quirk
---

# spa-http-server image listens on 8080, not 80

`docker-compose.e2e.yml`의 `frontend` 서비스가 prebuilt 이미지
(`ghcr.io/uengine-oss/process-gpt:e343845`)일 때는 nginx 게이트웨이가
`proxy_pass http://frontend:80`을 쓰면 동작함. 그러나 소스 빌드 이미지
(`services/frontend/Dockerfile`의 최종 단계인 `sanghoon01/spa-http-server:v1`)
로 바꾸면 80에서 응답이 안 오고, 게이트웨이가 502를 반환함.

## What works

`openspec/specs/<spec-name>/e2e/docker/nginx.e2e.conf`에서 upstream을 8080으로:

```nginx
upstream frontend_upstream {
    server frontend:8080;
}

server {
    listen 8088;

    location / {
        proxy_pass http://frontend_upstream;
        # ...
    }

    location /completion/ {
        rewrite ^/completion/(.*)$ /$1 break;
        proxy_pass http://completion:8000;
        # ...
    }
}
```

소스 빌드/coverage 시나리오에서만 8080으로 바꿔야 하는 경우, 스위트 로컬
override의 nginx conf만 8080으로 두고 root compose는 그대로 두는 방식도 가능.

## Why

- `sanghoon01/spa-http-server:v1` Dockerfile의 `EXPOSE 8080`과 `run.sh`가
  8080에 바인딩됨.
- 운영용 prebuilt 이미지(`ghcr.io/uengine-oss/process-gpt:*`)는 다른 정적
  서버를 쓰고 80에 바인딩되어 있어 게이트웨이 conf 기본값이 80으로 굳어
  있었음.

## How to apply

- Triggered when:
  - 소스 빌드 frontend 이미지로 교체할 때 (예: 소스맵 coverage용)
  - `services/frontend/Dockerfile`의 최종 베이스가 `spa-http-server:v1`일 때
  - 게이트웨이를 통해 frontend에 접근 시 502 또는 connection refused가 나는 경우
- Skip if:
  - 운영 prebuilt 이미지를 그대로 쓰는 일반 E2E 실행
  - frontend 컨테이너에 직접 접근하지 않고 다른 entrypoint를 쓰는 구성

Related: [[frontend-source-build-oom]]
