# 새 서비스 추가

## 1. 서비스 종류부터 정한다

필요한 파일과 절차는 **누가 이 서비스를 부르는가**로 정해진다.

| 종류 | 누가 부르나 | 운영 선례 | Deployment | CI | Service | 게이트웨이 라우트 | 화면 작업 |
|---|---|---|---|---|---|---|---|
| A. 워커 | 아무도 안 부른다. 스스로 일을 가져온다 | `polling-service` | 필수 | 필수 | 없음 | 없음 | 없음 |
| B. 내부 서버 | 클러스터 안의 다른 파드만 | `process-gpt-office-mcp` | 필수 | 필수 | 필수 | 없음 | 없음 |
| C. 외부 API 서버 | 브라우저나 외부에서도 | `memento`, `completion`, `agent-feedback` | 필수 | 필수 | 필수 | 필수 + **인증 등록** | 없음 |
| D. 화면 있는 앱 | 사람이 `/<prefix>` 로 접속 | `/wms`, `/lite` | 필수 | 필수 | 필수 | 필수 | 필수 |

- 모든 종류에 2장(파일 만들기)과 3장(CI/CD)이 공통이다.
- C 는 4장, D 는 4장과 5장을 더한다. A·B 는 게이트웨이를 건드리지 않는다. vue3 전체 재배포도 일어나지 않는다.
- 내부 서버로 시작해 나중에 외부로 열 수 있다. 외부에서 쓸 일이 정해지지 않았으면 B 로 둔다.

**종류는 README 가 아니라 실제 호출자로 정한다.** 서비스 이름과 경로를 호출할 만한 저장소의 코드에서 찾는다.

```bash
git -C process-gpt-vue3 grep -n '<service>' origin/main -- 'src/**' vite.config.ts
grep -rn '<service>\|<포트>' process-gpt-lite/server
```

process-miner 는 Lite 추천용 내부 서버로 보였지만 실제로는 ProcessGPT 화면이 브라우저에서 부르는 C 였다. 호출자마다 다음도 대조한다.

- 부르는 경로가 이 코드에 있는지. 같은 서비스도 브랜치마다 다르다. Lite 는 `feat/pgpt-lite-mining` 의 `/patterns`, `/discover` 를 불러 `main` 의 process-miner 로는 동작하지 않는다.
- 호출자가 토큰을 보내는지. 서비스가 JWT 를 요구하는데 호출자가 안 보내면 배포해도 401 이다.
- DB 를 쓰는지. 설명 문서가 아니라 `insert`·`update`·`delete` 를 코드에서 찾고, 이미지에 들어가지 않는 스크립트는 구분한다(`.dockerignore`).

어느 쪽인지 코드로 정할 수 없으면 사용자에게 묻는다.

## 2. 매니페스트 (공통)

새 서비스는 **템플릿으로 파일을 만들어 `process-gpt-k8s` 에 추가해야** 운영에 올라간다. main 의 `deployments/`, `services/` 에 파일이 있으면 Argo CD 가 적용한다(kustomization 같은 목록 파일은 없다).

```bash
bash .claude/skills/process-gpt-service-deploy/scripts/render-service.sh \
  --service <service> --repo <앱 저장소 이름> --port <포트> --health <확인 경로> \
  --app-dir <앱 저장소 경로> --k8s-dir <process-gpt-k8s 경로>
# A(워커)는 --worker 를 붙인다. Service 를 만들지 않고 포트와 HTTP 프로브를 뺀다
# 기본 브랜치가 main 이 아니면 --branch master
```

| 파일 | 위치 | 템플릿 |
|---|---|---|
| Deployment | `deployments/<service>.yaml` | `assets/deployment.yaml` |
| Service | `services/<service>-service.yaml` | `assets/service.yaml` |
| 워크플로 | 앱 저장소 `.github/workflows/deploy.yml` | `assets/deploy.yml` |

만든 뒤 서비스에 맞게 고친다. 서비스 이름, 이미지 이름, 파일 이름은 같게 둔다. 워크플로의 `yq` 가 이 이름으로 찾는다.

**스크립트는 저장소 하나에 서비스 하나를 전제로 한다.** 한 저장소의 하위 폴더에 있으면(`process-gpt` 의 `services/process-miner`) 만든 뒤 고친다. 워크플로 파일을 `<service>.yml` 로 바꾸고, `context` 를 그 폴더로, `on.push.paths` 에 그 폴더와 워크플로 파일을 넣는다. 저장소의 다른 변경으로 CI 가 돌지 않게 하기 위해서다. 선례: `process-gpt/.github/workflows/process-miner.yml`.

- **프로브:** `--health` 경로는 서비스가 실제로 200 을 줘야 한다. 없으면 readiness 가 실패해 트래픽을 받지 못한다. FastAPI 는 `/docs` 를 쓸 수 있다(`agent-feedback`). 워커의 생존 확인이 필요하면 `exec` 프로브를 넣는다(`polling-service`).
- **공용 값:** `my-config` 의 `SUPABASE_URL`, `my-secrets` 의 `SUPABASE_KEY`(anon)·`SERVICE_ROLE_KEY`·`JWT_SECRET`·`DB_*`. 쓰지 않는 키는 템플릿에서 지운다.
- **LLM:** `litellm-proxy:4000`, `litellm-proxy-secret/LLM_PROXY_API_KEY`. 제공사 키를 서비스에 직접 넣지 않는다.
- **전용 비밀값:** `<service>-env` Secret 을 `envFrom`(`optional: true`)으로 받는다. 사람이 클러스터에 만든다. **값이 든 Secret 은 커밋하지 않고** 필요한 키 목록만 주석으로 남긴다. 당장 없으면 공용 Secret 으로 시작한다. 명시한 `env` 가 `envFrom` 보다 우선한다.
- **디스크:** `local-path` PVC(RWO)는 `replicas: 1`, `strategy: Recreate` 로 둔다. 빈 볼륨이 붙으므로 필요한 폴더는 시작할 때 만든다.
- **주소:** 클러스터 안에서는 Service 이름으로 부른다. B·C 는 부르는 쪽 매니페스트에도 주소를 넣는다. 예: deepagents 는 `process-gpt-deepagents-config.yaml` 의 `MEMENTO_BASE_URL`, 다른 워크로드는 각자의 `env`. 서비스를 만들어도 부르는 쪽 설정이 없으면 아무도 쓰지 않는다.
- **테넌트:** 게이트웨이를 지나는 요청은 `X-Tenant-Id` 로 정한다. `X-Forwarded-Host` 는 게이트웨이를 지나며 사라진다(2026-11-02, completion 의 모든 요청이 `localhost` 테넌트가 됐다). 내부 호출에는 헤더가 없으니 검증한 JWT 의 `app_metadata.tenant_id` 를 쓰거나 호출하는 쪽이 넘긴다. 워커와 주기 작업은 요청이 없으니 테넌트마다 돈다.
- 검증: `yq eval '.' <file> >/dev/null`. namespace 는 default.

## 3. CI/CD (공통, 필수)

**운영 배포는 GitHub Actions 로 자동화한다.** 기본 브랜치 푸시 → 이미지 빌드 → k8s 태그 커밋 → Argo CD 적용까지 사람이 손대지 않는다. 손으로 이미지를 올리거나 태그를 고치지 않는다.

2장의 `render-service.sh` 가 만든 워크플로는 다음을 한다.

1. `ghcr.io/uengine-oss/<service>:<short-sha>` 로 빌드·푸시한다(`GITHUB_TOKEN` 의 `packages: write`, amd64). `GHCR_PAT` 는 필요 없다.
2. `process-gpt-k8s` 를 체크아웃해(`GITOPS_PAT`) `yq` 로 image 를 바꾸고 푸시한다. 매니페스트에는 `latest` 가 아니라 short SHA 가 남는다.

저장소 루트에 `Dockerfile` 이 있어야 한다. 위치가 다르면 `context`·`file` 을 고친다. 이미지가 둘 이상이면 `process-gpt-lite/.github/workflows/deploy.yml` 을 본다.

`GITOPS_PAT` 는 다른 저장소(`process-gpt-k8s`)에 푸시하므로 기본 토큰으로 대신할 수 없다. 비밀값은 저장소 단위다. `gh secret list -R uengine-oss/<repo>` 로 확인하고, 없으면 사용자에게 넣어 달라고 한다. 조직 Secret 은 조회 권한이 없을 수 있으니 사용자에게 묻는다.

첫 CI 뒤 이미지 공개 여부를 본다([process-gpt.md](process-gpt.md) 2장).

## 4. 게이트웨이 (C·D)

vue3 `gateway/src/main/resources/application.yml` 의 default(로컬 `localhost:<port>`)와 docker(운영 Service 이름) 프로필 **둘 다** 추가한다. catch-all `frontend`(order 999)보다 작은 order 를 준다. 푸시는 프론트·게이트웨이 전체 재배포다([process-gpt.md](process-gpt.md) 2장).

```yaml
                        - id: <service>
                          uri: http://<service>:<port>
                          predicates:
                              - Path=/<prefix>/**
                          filters:
                              - RewritePath=/<prefix>/?(?<segment>.*), /$\{segment}
                          order: 72
```

- 접두어는 서비스 이름으로 둔다(`/memento`, `/completion`). 인그레스가 `/api`·`/vnc` 를 게이트웨이의 다른 포트로 보내므로 그 아래에 새로 두지 않는다.
- SSE 를 쓰면 `AddResponseHeader=X-Accel-Buffering, no` 를 넣는다.

**C 는 인증을 반드시 정한다. 라우트만 추가하면 로그인 없이 호출된다.** 게이트웨이는 `gateway/src/main/java/shop/ForwardHostHeaderFilter.java` 의 `protectedPaths` 목록에 있는 경로만 토큰을 검사한다. 목록에 넣으면 토큰 서명과 테넌트 일치를 확인하고, 실패하면 401 을 돌려준다.

```java
List<String> protectedPaths = Arrays.asList(
        ...
        "/<prefix>/.*");
```

목록에 넣지 않는 경우는 서비스가 스스로 JWT 를 검증할 때뿐이다(Lite, 공개 웹훅 등). 그 이유를 사용자에게 알린다. 내부 전용 경로는 외부에서 막는다(Lite 의 `/api/cron/`).

## 5. 화면 앱의 하위 경로와 로그인 (D)

선례: `/lite`(웹·서버·편집기), `/wms`(단일 앱, `process-gpt-sample-app-wms`, `docs/05-deployment.md`).

게이트웨이는 `/<prefix>` 를 떼고 넘기지만, 브라우저는 루트 절대경로를 페이지 주소 기준으로 푼다.

- 빌드: `base: process.env.VITE_BASE_PATH || '/'`. 운영 이미지는 `VITE_BASE_PATH=/<prefix>/` 로 빌드한다. 워크플로의 빌드 단계에 `build-args` 로 넣는다. 라우터는 `createWebHistory(import.meta.env.BASE_URL)`.
- 코드의 `'/api/…'`, `location.href = '/login'`, 웹소켓 `${location.host}/api/…`, 템플릿 `src="/…"` 에 모두 접두어를 붙인다. vite 는 `index.html` 만 고쳐 준다. `` `/api${path}` `` 처럼 `/api` 뒤에 `/` 가 없는 모양도 찾는다: `grep -rnE "[\`'\"]/(api|office)([\$?\`'\"]|\b)" src`
- nginx 는 루트 기준으로 둔다(접두어는 이미 떼어져 온다). SPA 는 `try_files $uri $uri/ /index.html`. 변수 `proxy_pass` 에는 `resolver kube-dns.kube-system.svc.cluster.local` 과 FQDN 을 쓴다.
- 로그인: ProcessGPT 는 `.process-gpt.io` 쿠키 `access_token`·`refresh_token` 에 Supabase 토큰을 둔다. 같은 출처라서 넘겨받는다. 리프레시 토큰은 쓰면 바뀌므로 쿠키에 더 새 토큰이 있으면 먼저 쓴다. 로그인이 안 됐다고 ProcessGPT 메인으로 보내지 않고 서비스 로그인 화면에 둔다.
- 메일 코드(`/auth/v1/otp`)는 `create_user: false` 로, 그 테넌트 계정(`public.users`)만 받는다. 아니면 아무 이메일이나 그 테넌트 사용자가 된다.
- 백엔드는 `public.users(id, tenant_id)` 로 소속을 확인한다. 브라우저의 테넌트 판별은 wms `lib/tenant.ts` 와 같은 규칙을 쓴다.

## 6. 순서와 확인

새 스키마가 있으면 코드보다 먼저 SQL 을 넘겨 적용받는다([lite.md](lite.md) 3장의 규칙).

**기존 테이블을 읽는 서비스도 운영에 그 열이 있는지 먼저 본다.** 운영 DB 에는 마이그레이션이 일부만 들어가 있을 수 있다. process-miner 는 `group_id` 는 있고 그보다 앞선 `closed_at` 만 없었다. 쿼리 하나가 고른 열 중 하나만 없어도 전부 500 이고, `/health` 는 `select 1` 만 봐서 드러나지 않는다. 서비스 SQL 이 읽는 열을 **전부** 모아 아래 모양으로 사용자에게 조회를 부탁하고, 빠진 열은 그 마이그레이션 원본에서 SQL 을 만든다.

```sql
select expected.column_name as missing_column
from unnest(array['col_a','col_b']) as expected(column_name)
where not exists (select 1 from information_schema.columns c
  where c.table_schema='public' and c.table_name='<table>' and c.column_name=expected.column_name);
```

앱 저장소 Secret 을 넣어 달라고 한 뒤, 확인받고 아래 순서로 푸시한다.

| 종류 | 푸시 순서 | 운영 확인 |
|---|---|---|
| A. 워커 | k8s → 앱 저장소 → 이미지 공개 | 일이 실제로 처리되는지 결과로 본다. 파드 상태를 볼 수 없으니 그 일의 화면이나 DB 조회로 확인한다 |
| B. 내부 서버 | k8s(서비스) → 앱 저장소 → 이미지 공개 → k8s(부르는 쪽 주소) | 부르는 서비스의 기능을 화면에서 끝까지 써 본다 |
| C. 외부 API | B 와 같음 → vue3 게이트웨이 | 토큰 없이 401, 다른 테넌트 요청 거부(서비스가 직접 검사하면 403, 게이트웨이 `protectedPaths` 면 401), 정상 토큰 200 |
| D. 화면 앱 | k8s → 앱 저장소 → 이미지 공개 → vue3 게이트웨이 | 새로고침·직접 주소, `/<prefix>` 밖 경로 그대로, 로그인 뒤 핵심 기능 |

- k8s 를 먼저 푸시하는 것은 앱 CI 가 그 파일의 태그를 고치기 때문이다.
- 게이트웨이를 마지막에 두는 것은 라우트가 서비스보다 먼저 열리면 그 경로가 5xx 이기 때문이다.
- 로컬 확인: C·D 는 로컬 8088 게이트웨이에 라우트를 붙여 확인한다([lite.md](lite.md) 6장과 같은 방식). A·B 는 실제로 부르는 서비스와 함께 띄워 확인한다.
