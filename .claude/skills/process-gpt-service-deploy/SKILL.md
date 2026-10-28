---
name: process-gpt-service-deploy
description: >
  새 서비스(앱)를 운영 ProcessGPT(<tenant>.process-gpt.io)에 반영하는 절차.
  "운영에 배포", "새 서비스 운영 반영", "/xxx 경로로 붙이기", "게이트웨이 라우트 추가",
  "process-gpt-k8s 에 매니페스트 추가", "lite 배포", "wms 처럼 붙여줘" 같은 요청에 사용한다.
  앱 저장소 CI → process-gpt-k8s(GitOps, Argo CD) → process-gpt-vue3 게이트웨이 라우트 →
  운영 DB SQL 순서로, 각 저장소의 main(기본 브랜치)에서 진행한다.
---

# 새 서비스를 운영 ProcessGPT 에 반영하기

운영은 `process-gpt-k8s` 의 main 을 Argo CD 가 그대로 적용한다. 그래서 **main 에 푸시하면 곧 운영 반영**이다.
운영 클러스터·운영 DB 에는 직접 접근하지 않는다. 검증은 화면, 배포 워크플로, 매니페스트로 한다.

선례: `/wms` (process-gpt-sample-app-wms). 처음이면 아래 파일부터 읽는다.

| 무엇 | 어디 |
|---|---|
| 게이트웨이 라우트 | `process-gpt-vue3/gateway/src/main/resources/application.yml` 의 `wms-frontend` (default·docker 프로필 둘 다) |
| 매니페스트 | `process-gpt-k8s/deployments/process-gpt-wms-app-deployment.yaml`, `services/process-gpt-wms-app-service.yaml` |
| 하위 경로 빌드 | wms `frontend/vite.config.ts`(`VITE_BASE_PATH`), `frontend/Dockerfile` |
| 로그인 이어받기·테넌트 | wms `frontend/src/stores/auth.ts`, `frontend/src/lib/tenant.ts` |
| 운영 DB 반영 방식 | wms `docs/05-deployment.md` |

## 0. 먼저 확인할 것 (사용자에게 묻기)

- 작업 위치: 각 저장소의 **현재 체크아웃 브랜치**를 본다. main 이 아니면 새 브랜치·워크트리를 만들지 말고 어디서 할지 묻는다.
- 푸시: 저장소마다 푸시 직전에 확인받는다. 운영 영향(다른 서비스 재배포 등)을 함께 말한다.
- 운영 DB: 사람이 SQL Editor 로 실행한다. 이쪽은 검토한 SQL 파일만 만든다.

## 1. 앱 저장소: 하위 경로와 테넌트

게이트웨이는 `/<prefix>` 를 떼고 넘긴다(`RewritePath`). 하지만 브라우저는 루트 절대경로를 페이지 주소 기준으로 푼다.

- 빌드: `base: process.env.VITE_BASE_PATH || '/'`. 운영 이미지는 `VITE_BASE_PATH=/<prefix>/` 로 빌드한다.
- 라우터: `createWebHistory(import.meta.env.BASE_URL)`.
- 코드 안의 `'/api/…'`, `location.href = '/login'`, 웹소켓 `${location.host}/api/…`, 템플릿의 `src="/…"` 는 모두 접두어를 붙인다. vite 는 `index.html` 만 고쳐 준다.
  공통 fetch 함수의 `` `/api${path}` `` 처럼 `/api` 뒤에 `/` 가 없는 모양도 찾는다(`grep -rnE "[\`'\"]/(api|office)([\$?\`'\"]|\b)" src`). Lite 에서 이것을 놓쳐 화면이 비었다.
- nginx 는 루트 기준 그대로 둔다(접두어는 이미 떼어져 온다). SPA 는 `try_files $uri $uri/ /index.html`.
- 로그인: ProcessGPT 는 `.process-gpt.io` 쿠키 `access_token`·`refresh_token` 에 Supabase 토큰을 둔다. 같은 출처라서 그대로 넘겨받는다. 리프레시 토큰은 쓰면 바뀌므로, ProcessGPT 쿠키에 더 새 토큰이 있으면 그것을 먼저 쓴다.
- 테넌트: 게이트웨이 `ForwardHostHeaderFilter` 가 **모든 요청**에 `X-Tenant-Id`(서브도메인)와 `X-Forwarded-Host` 를 덮어써 넘긴다. 백엔드는 이 헤더로 테넌트를 정하고, `public.users(id, tenant_id)` 로 소속을 확인한다. 브라우저 쪽 테넌트 판별은 vue3 와 같은 규칙(wms `lib/tenant.ts`)을 쓴다.
- 게이트웨이를 거치지 않는 호출(예: deepagents → 서비스의 MCP)에는 헤더가 없다. 검증한 사용자 JWT 의 `app_metadata.tenant_id` 를 쓴다.

## 2. 앱 저장소: CI (main 푸시 → 이미지 → k8s 태그)

`process-gpt-deepagents/.github/workflows/deploy.yml` 과 같은 모양으로 만든다.

1. `ghcr.io/uengine-oss/<image>:<short-sha>` 로 빌드·푸시한다(`GHCR_PAT`). 운영은 amd64 다.
2. `uengine-oss/process-gpt-k8s` 를 체크아웃해(`GITOPS_PAT`), `yq` 로 매니페스트의 image 를 바꾸고 커밋·푸시한다.

- 비밀값은 저장소 단위다. 새 저장소에는 `GHCR_PAT`·`GITOPS_PAT` 가 없다. `gh secret list -R uengine-oss/<repo>` 로 확인하고, 없으면 사용자에게 넣어 달라고 한다(값은 복사할 수 없다).
- 이미지 태그는 `latest` 말고 short SHA 로 매니페스트에 고정한다.

## 3. process-gpt-k8s: 매니페스트

- `deployments/<service>.yaml`, `services/<service>-service.yaml`. namespace 는 쓰지 않는다(default).
- 공용 값은 기존 것을 쓴다: `my-config` 의 `SUPABASE_URL`, `my-secrets` 의 `SUPABASE_KEY`(anon), `SERVICE_ROLE_KEY`, `JWT_SECRET`, `DB_HOST`·`DB_PORT`·`DB_NAME`·`DB_USER`·`DB_PASSWORD`.
- 서비스 전용 비밀값은 `<service>-env` Secret 을 `envFrom` 으로 받는다. 이 Secret 은 사람이 클러스터에 직접 만든다. **값이 든 Secret 은 커밋하지 않는다.** 필요한 키 목록만 주석으로 남긴다.
- 전용 Secret 을 당장 만들 수 없으면 공용 Secret 으로 시작한다. LLM 은 `litellm-proxy:4000`·`frentis-ai-model`·`litellm-proxy-secret/LLM_PROXY_API_KEY` 이고, OpenAI 직접 호출은 `openai-secret/OPENAI_API_KEY` 이다. 전용 Secret 은 `optional: true` 로 둔다. 명시한 `env` 가 `envFrom` 보다 우선한다는 점을 주석에 남긴다.
- 기본값이 공개된 비밀값으로 보호하는 내부 콜백(예: Lite `/api/cron/`)은 외부 경로(nginx)에서 막는다.
- 클러스터 안 주소: `process-gpt-deepagents:8888`, `completion-service:8000`, `memento-service:8005`, `process-gpt-office-mcp-service:1192` 처럼 Service 이름으로 부른다. nginx 가 변수 `proxy_pass` 를 쓰면 `resolver` 에 `kube-dns.kube-system.svc.cluster.local` 을, 업스트림에는 FQDN 을 쓴다.
- 디스크가 필요하면 `local-path` PVC(RWO)를 쓰고, `replicas: 1` 과 `strategy: Recreate` 로 둔다.
- 커밋 전에 YAML 을 검증한다: `yq eval '.' <file> >/dev/null`.

## 4. process-gpt-vue3: 게이트웨이 라우트

`application.yml` 의 default 프로필(로컬, `localhost:<port>`)과 docker 프로필(운영, Service 이름) **둘 다** 추가한다. catch-all `frontend`(order 999)보다 작은 order 를 준다.

```yaml
                        - id: <service>-frontend
                          uri: http://<service-name>:<port>
                          predicates:
                              - Path=/<prefix>/**
                          filters:
                              - RewritePath=/<prefix>/?(?<segment>.*), /$\{segment}
                          order: 70
```

- vue3 main 푸시는 **프론트·게이트웨이 전체 재배포**다(`deploy.yaml`). 실패하면 `.deploy/last-good-*` 로 되돌리는 잡이 있다.
- `/api` 처럼 이미 쓰는 경로와 겹치는 접두어는 쓰지 않는다. 인그레스는 `/api`·`/vnc` 를 게이트웨이의 다른 포트로 보낸다.

## 5. 운영 DB

- 새 스키마는 운영 Supabase 에 얹는다. 기존 테이블·함수를 바꾸는 문장(`alter table users …`, `create or replace function tenant_id()`, 트리거)은 따로 짚어서 보고한다.
- 운영 스키마 기준은 `infra/process-gpt/process-gpt-infra-docker/volumes/db/{init,migration}.sql` 이다.
- SQL Editor 는 psql 메타 명령(`\if`, `\gset`)을 못 쓴다. 한 파일로 만들고, 단일 테넌트용 문장(`where id = 'localhost'`)은 뺀다.
- 넘기기 전에 일회용 DB 에서 시험한다. `docker run --rm -d -e POSTGRES_PASSWORD=… supabase/postgres:15.8.1.060` 에 기준 스키마를 적용한 뒤(init → migration → init), `psql -v ON_ERROR_STOP=1` 로 두 번 돌려 다시 실행해도 안전한지 본다. 끝나면 컨테이너를 지운다.

## 6. 순서와 검증

1. 로컬 검증: 실제 로컬 ProcessGPT(vue3 + vue3/gateway, `localhost:8088`)에 default 프로필 라우트를 붙인다. `http://localhost:8088/<prefix>/` 에서 인수조건을 e2e 로 확인한다. 5173·임시 게이트웨이 결과는 근거로 쓰지 않는다.
   - 게이트웨이는 `process-gpt-vue3/gateway` 에서 `mvn spring-boot:run` 으로 돈다. 라우트를 바꾸면 그 PID 만 멈추고 다시 띄운다.
   - 화면은 운영과 같은 이미지(하위 경로 빌드)를 default 프로필 포트에 띄운다. nginx 가 변수 `proxy_pass` 를 쓰면 사용자 정의 docker 네트워크(내장 DNS)에 띄운다.
   - 로그인은 vue3 의 `/auth/login`(`.cp-id`·`.cp-pwd`·`.cp-login`)으로 한다. 계정은 `process-gpt-vue3/CLAUDE.md` 에 있다.
   - e2e 판정은 "화면에 글자가 나왔다"로 끝내지 않는다. Lite 에서는 요청 문장이 팀원에게 넘어가 안내 문장이 답처럼 보였다. 실제 처리한 서비스(예: deepagents `/chat/stream` 호출)까지 확인한다.
   - 서비스가 자기 `.env` 나 서브모듈 경로에서 키를 읽는 곳이 있는지 본다(Lite 받아쓰기의 `OPENAI_API_KEY`). 운영 이미지에는 그 파일이 없으므로 Secret 키로 넣는다.
2. DB SQL 을 사용자에게 넘긴다. 운영에 적용됐다는 답을 받은 뒤 다음으로 간다.
3. 사람이 운영 Secret(`<service>-env`)을 만든다.
4. 확인받고 푸시한다: 앱 저장소 main → (CI 가 k8s 태그 갱신) → k8s 매니페스트 → vue3 게이트웨이. 라우트가 서비스보다 먼저 열리면 그 경로가 502 가 되므로 게이트웨이를 마지막에 푸시한다.
5. 운영 확인: GitHub Actions 결과(`gh run list -R uengine-oss/<repo>`), k8s 저장소의 태그 커밋, 그리고 `https://<tenant>.process-gpt.io/<prefix>/` 화면(새로고침·직접 주소·`/<prefix>` 밖 경로가 그대로인지).

## 되돌리기

Git 으로 되돌린다. k8s 이미지 커밋을 revert 하거나 게이트웨이 라우트 커밋을 revert 한다. `kubectl set image` 는 Argo CD 가 Git 값으로 되돌리므로 해결책이 아니다.
