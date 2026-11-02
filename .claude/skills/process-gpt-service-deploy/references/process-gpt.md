# ProcessGPT 서비스와 공용 설정

## 1. 저장소별 배포 경로

푸시 전에 **기본 브랜치**를 본다. deepagents 는 master 다.

| 서비스 | 저장소 / 워크플로 | 푸시 브랜치 | 고치는 매니페스트 |
|---|---|---|---|
| 프론트 + 게이트웨이 | `process-gpt-vue3` `deploy.yaml` | main | `frontend-deployment.yaml`, `gateway.yaml` |
| deepagents | `process-gpt-deepagents` `deploy.yml` | **master** | `process-gpt-deepagents.yaml`, `agent-runner-templates.yaml` |
| completion | `process-gpt-completion` `deploy.yaml` | main | `completion-deployment.yaml` |
| polling | 같은 저장소 `polling-service.yaml` | main | `polling-service-deployment.yaml` |
| memento | `process-gpt-memento` `deploy.yml` | main | `memento-deployment.yaml` |
| office-mcp | `process-gpt-office-mcp` `deploy.yaml` | main, master | `process-gpt-office-mcp-deployment.yaml` |
| agent-feedback | `process-gpt-agent-feedback` `deploy.yml` | main | `agent-feedback.yaml` |

다른 서비스는 그 저장소의 `.github/workflows` 를 먼저 읽는다. `deploy-prod.yaml` 은 release 생성으로 도는 별도 경로다. `mcp-validator` 저장소에는 워크플로가 없다.

- **공용 서비스 재배포는 Lite 와 모든 테넌트에 함께 영향이 있다.** 기능 브랜치를 Lite 때문에 합치면 운영 deepagents 가 재배포된다. 2026-10-28 에는 Lite 가 master 기준 deepagents 로 통과했고 재배포가 불필요해 합치지 않았다. 꼭 필요한지 사용자에게 확인한다.
- 푸시 뒤 CI 성공과 k8s 의 `Update ... image to <sha>` 커밋을 본다.
- 운영 태그와 소스 차이를 보고한다: `git log <매니페스트 태그>..origin/<기본 브랜치>`.

## 2. vue3(프론트·게이트웨이)

- 푸시는 **프론트·게이트웨이 전체 재배포**다. 게이트웨이 라우트 한 줄도 그동안 쌓인 프론트 커밋을 함께 내보낸다. 실패하면 `.deploy/last-good-*` 로 되돌리는 잡이 돈다.
- 푸시 전에 파이프라인이 살아 있는지 본다: `gh run list -R uengine-oss/process-gpt-vue3 --workflow deploy.yaml -L 5`. 오래 실패해 왔다면 운영이 main 보다 한참 뒤에 있다. 2026-10-28 에는 그 상태로 36개 커밋이 한꺼번에 나갔다. 개수를 말하고 사용자가 정하게 한다.
- 2026-10-28 에 막혔던 것(같은 증상이면 먼저 본다):
  - "Run Vue SAST report" 의 `semgrep-core exited with -11` → semgrep 을 `scripts/security/scan.sh` 와 같은 버전으로 고정, Python 3.12
  - vue-tsc `heap out of memory` → `NODE_OPTIONS=--max-old-space-size=6144` (`package.json` 의 `build` 도)
  - "Build Gateway JAR" 의 `release version 17 not supported` → `setup-java` 를 17 로(게이트웨이는 Spring Boot 4)

**이미지 패키지는 공개여야 한다.** 클러스터 매니페스트에는 imagePullSecrets 가 없어 공개 패키지만 받는다. `GHCR_PAT` 로 처음 올린 패키지는 비공개로 생겼고(`process-gpt-lite-*`), 공개 저장소의 `GITHUB_TOKEN` 으로 올린 패키지는 공개로 생겼다(`process-miner`). 어느 쪽이든 첫 CI 뒤 `gh api /orgs/uengine-oss/packages/container/<image> --jq .visibility` 로 보고, `private` 이면 사용자에게 패키지 화면(Package settings → Danger Zone → Change visibility → Public)에서 바꿔 달라고 한다. API 로는 바꿀 수 없고, 이미지마다 따로 바꾼다.

## 3. 공용 설정

| 바꿀 것 | 어디서 | 주의 |
|---|---|---|
| deepagents 설정 | k8s `process-gpt-deepagents-config.yaml` | 채팅 Deployment 와 세션 런너 PodTemplate 이 함께 쓴다. env 를 어느 한쪽에만 넣지 않는다. 파드가 다시 떠야 반영되므로, 재시작이 일어나는지 확인한다 |
| deepagents 비밀값 | `process-gpt-deepagents-env` Secret | 사람이 클러스터에 만든다 |
| LLM 모델·제공사 키 | LiteLLM UI | 키 갱신과 모델 추가를 프록시 한 곳에서 하고 사용량도 거기 남긴다. 서비스는 `litellm-proxy:4000` 과 `litellm-proxy-secret` 을 쓴다 |
| 공용 `openai-secret` | 사람이 클러스터에서 교체 | 프론트·completion·polling·office-mcp 등 여러 서비스가 함께 쓴다. 바꾼 뒤 ProcessGPT 채팅·에이전트 답까지 확인한다 |
| 게이트웨이 라우트 | vue3 `application.yml` | 2장의 전체 재배포 |
| 메일 발송 | 운영 Supabase 대시보드 SMTP | 사용자가 고친다. `Error sending magic link email` 이면 Logs → Auth 에서 error_id 로 찾는다. Gmail 의 `535 BadCredentials` 는 앱 비밀번호가 필요하다는 뜻이다 |
| 공용 Secret·ConfigMap | 클러스터 | 사람이 한다. 값을 Git 에 두지 않는다 |

Codex 워크로드를 건드리면 k8s `AGENTS.md` 와 `docs/PROCESS_GPT_CODEX_RUNBOOK.md` 를 따른다.
