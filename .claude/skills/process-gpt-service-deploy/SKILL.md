---
name: process-gpt-service-deploy
description: >
  운영 ProcessGPT(<tenant>.process-gpt.io)와 그 아래 Process GPT Lite(<tenant>.process-gpt.io/lite)를
  설정해서 배포하는 절차. "lite 운영 배포", "lite 반영", "운영에 배포", "운영 설정 바꿔줘", "운영 SQL",
  "process-gpt-k8s 수정", "게이트웨이 라우트 추가", "deepagents·completion 운영 반영",
  "새 서비스 추가", "백엔드 서버 배포", "워커 추가", "/xxx 경로로 붙이기", "wms 처럼 붙여줘" 같은 요청에 사용한다.
  앱 저장소 CI → process-gpt-k8s(GitOps, Argo CD) → process-gpt-vue3 게이트웨이 → 운영 Supabase SQL 을
  작업 종류에 맞는 순서로 진행하고, 운영 화면에서 실제 사용자 흐름으로 확인한다.
---

# 운영 ProcessGPT 와 Lite 배포

운영은 `process-gpt-k8s` 의 main 을 Argo CD 가 그대로 적용한다. 그래서 **앱 저장소 기본 브랜치에 푸시하면 CI 를 거쳐 곧 운영 반영**이다.
운영 클러스터와 운영 DB 에는 직접 접근하지 않는다. 검증은 운영 화면, 배포 워크플로, 매니페스트로 한다.

## 0. 시작하기 전에

**작업 종류를 고르고, 해당 파일만 읽는다.**

| 하려는 일 | 볼 곳 |
|---|---|
| Lite 코드를 운영에 반영 | [references/lite.md](references/lite.md) 4장 |
| Lite 설정 변경, 구성요소 추가 | [references/lite.md](references/lite.md) 2·5장 |
| ProcessGPT 서비스(deepagents, completion, 프론트 등) 반영 | [references/process-gpt.md](references/process-gpt.md) 1·2장 |
| ProcessGPT 공용 설정(LLM, ConfigMap, 게이트웨이, SMTP) 변경 | [references/process-gpt.md](references/process-gpt.md) 3장 |
| 새 서비스 추가(워커, 내부 서버, 외부 API, 화면 앱) | [references/new-service.md](references/new-service.md) |
| 운영에서 안 될 때 | [references/troubleshooting.md](references/troubleshooting.md) |

**현재 상태를 본다.** 저장소 브랜치, CI, 운영 태그와 소스의 차이, 이미지 공개 여부를 읽기만 한다.

```bash
bash .claude/skills/process-gpt-service-deploy/scripts/preflight.sh
```

**파일.** 운영 DB SQL 시험은 `scripts/test-prod-sql.sh`, 상태 확인은 `scripts/preflight.sh` 다. 둘 다 운영을 건드리지 않는다. 새 서비스의 Deployment·Service·CI 파일은 `assets/` 템플릿으로 `scripts/render-service.sh` 가 만든다.

**사용자에게 확인한다.**

- 작업 위치: 각 저장소의 현재 체크아웃 브랜치를 본다. 기본 브랜치가 아니면 새 브랜치·워크트리를 만들지 말고 어디서 할지 묻는다.
- 푸시: 저장소마다 푸시 직전에 확인받는다. 함께 나가는 커밋과 운영 영향을 말한다. `git log <운영 태그>..origin/main` 으로 본다. 다른 사람의 커밋이 섞여 있으면 그 사실도 말한다.
- 운영 DB: 사람이 Supabase SQL Editor 로 실행한다. 이쪽은 검토한 SQL 파일만 만든다.
- 권한 검사: 자동 권한 검사가 푸시나 머지를 막으면 명령을 쪼개거나 다른 방식으로 다시 실행하지 않는다. 사용자에게 권한을 추가하거나 직접 실행해 달라고 한다. 파일은 이름을 지정해 `git add` 하게 하고, 그 뒤 CI 확인부터 이어서 한다.
- 운영 데이터: 시험 계정으로 확인한다. 실제 사용자에게 일이 가는 동작(기존 프로세스 실행 등)은 하지 않는다.

**운영 구조.**

```
브라우저 → Cloudflare → GKE Ingress(*.process-gpt.io) → gateway(process-gpt-vue3/gateway)
  /            → frontend (ProcessGPT 화면)
  /lite/**     → process-gpt-lite-web (접두어를 떼고 전달)
                   /api/*, /craft/* → process-gpt-lite-server:8787
                   /office/*        → process-gpt-lite-office-host:5390
                   /auth|rest|storage/v1 → server 를 거쳐 Supabase
  /wms/**, 그 밖의 서비스 경로 → 각 Service
공용: Supabase(클러스터 밖), litellm-proxy:4000, process-gpt-deepagents:8888,
      completion-service:8000, memento-service:8005, process-gpt-office-mcp-service:1192
```

인그레스는 `/api`·`/vnc` 를 게이트웨이의 다른 포트로 보낸다. 앱 경로에 이 접두어를 쓰지 않는다.

**운영에서만 다른 점.** 로컬에서 통과해도 운영에서 깨진 것들은 대부분 여기서 나왔다. 코드를 내기 전에 이 표부터 대조한다.

| 운영의 조건 | 깨지는 것 | 처리 |
|---|---|---|
| deepagents 가 다른 파드다. 작업 폴더 디스크를 공유하지 않는다 | 서버가 `/workspace` 에 쓰거나 읽는 기능. 첨부 `workspace folder not found`, 문서 카드 링크 없음, 폴더 변형 | Storage·memento 를 거치고, deepagents 가 턴 끝에 올린 방 폴더 사본을 읽는다 |
| `/data` 에 빈 PVC 가 붙는다 | 이미지에 만들어 둔 `/data/...` 폴더가 사라진다. 빈 볼륨을 복사해 주는 Compose 에서는 드러나지 않는다 | 시작할 때 폴더를 만든다 |
| Supabase 가 클러스터 밖이다 | pg_cron 이 Service 주소로 콜백하지 못한다 | 서버가 직접 돈다(`PRO_CRON_MODE=server`). 서버는 1대로 둔다 |
| 운영 DB 가 기준 스키마와 다르다 | enum 비교 하나로 쿼리 전체가 실패한다(`todo_status` 에 `CANCELLED` 없음) | [references/lite.md](references/lite.md) 3장 |
| 테넌트가 여럿이다 | 고정 테넌트를 쓰는 코드가 모두 `localhost` 로 처리된다 | [references/new-service.md](references/new-service.md) 2장의 테넌트 규칙 |
| Cloudflare 가 앞에 있다 | 응답 헤더가 100초 안에 없으면 524. 서버의 502 는 Cloudflare 오류 화면으로 바뀌어 사유가 사라진다 | 스트림은 헤더와 주석을 바로 보내고 20초마다 주석을 보낸다. 상위 서비스 실패는 503 으로 돌려준다 |
| 서비스의 `.env`·서브모듈 파일이 이미지에 없다 | 로컬에서만 읽히던 키, 다른 언어 런타임(서버 이미지에 Python 없음) | 키는 매니페스트로 넣고, 이미지에 없는 도구에 기대지 않는다 |

## 되돌리기

Git 으로 되돌린다. k8s 의 이미지·설정 커밋이나 게이트웨이 라우트 커밋을 revert 한다. `kubectl set image` 는 Argo CD 가 Git 값으로 되돌리므로 해결책이 아니다.
SQL 은 되돌리는 파일을 따로 준다. 코드를 되돌려도 이미 적용된 스키마는 남고, `lite_migrations` 기록도 남는다.
