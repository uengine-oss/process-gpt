---
name: kong-storage-route-hardcoded-hostname
description: infra/volumes/api/kong.yml 의 storage-v1 라우트가 upstream `http://storage:5000/` 로 하드코딩되어 있어, spec-local 에서 storage 컨테이너 이름을 바꿔 띄우면(예: `storage-pifc`) docker-compose `networks.aliases: [storage]` 를 추가하지 않는 한 kong 이 502 를 낸다.
applies-to:
  - supabase-storage
  - kong-gateway
  - spec-local-storage
last-verified: 2026-05-27
metadata:
  type: pitfall
---

# kong storage 라우트가 hostname `storage` 로 하드코딩됨

공유 kong 선언은 다음 라우트를 갖는다:

```yaml
- name: storage-v1
  url: http://storage:5000/
  routes:
    - paths: ['/storage/v1/']
```

스위트마다 별도의 supabase/storage-api 인스턴스(`storage-pifc`,
`storage-foo` 등) 를 띄우고 싶을 때 컨테이너 이름만 바꾸면 kong 은 여전히
hostname `storage` 를 찾기 때문에 502/Bad Gateway 또는 dns resolution
실패가 발생한다.

## What works

스위트별 storage 서비스에 docker compose `networks.aliases` 로 추가
hostname `storage` 를 부여한다:

```yaml
storage-pifc:
  image: supabase/storage-api:v1.25.7
  container_name: process-gpt-e2e-storage-pifc
  networks:
    default:
      aliases:
        - storage
  # ...
```

이 방법은 다른 스위트가 자기 자신의 storage 컨테이너를 띄우지 않을 때만
충돌 없이 동작한다. 두 스위트가 같은 compose 실행에서 각자 storage 를
띄우려 하면 alias 충돌이 난다 — 그 경우엔 kong override 도 함께 두어
라우트 upstream 자체를 바꾸는 것이 안전하다.

## Why

- 공유 kong.yml 은 production-like 인프라 한 세트(`storage` 한 개) 를
  가정해 만들어졌다.
- compose 네트워크는 한 컨테이너에 여러 hostname 을 부여할 수 있어서
  alias 추가만으로 우회가 가능하다.

## How to apply

- Triggered when:
  - 새 스위트가 자체 supabase/storage-api 인스턴스를 띄우고
  - 그 인스턴스에 kong 의 `/storage/v1/*` 라우트를 그대로 사용해야 하는 경우
  - 게이트웨이/curl/Playwright 가 `/storage/v1/...` 호출 시 502 또는
    "no route" 류 오류를 받을 때
- Skip if:
  - kong 라우트를 우회해 게이트웨이 nginx 가 storage 컨테이너로 직접
    프록시하는 구조라면 alias 없이도 동작 (단, public URL 의 일관성을 잃음)
  - 두 스위트가 동시에 storage 컨테이너를 띄워야 하는 경우 — 그때는 kong
    override 가 더 안전함

Related: [[compose-override-relative-paths]], [[spa-http-server-port-8080]]
