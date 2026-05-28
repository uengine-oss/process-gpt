# OpenSpec E2E Memory Index

Cross-suite E2E knowledge — pitfalls, workarounds, and quirks discovered while
building suites under `openspec/specs/*/e2e/`. The E2E skill at
`.claude/skills/e2e-tests/SKILL.md` reads this index in Phase A and writes
back to it in Phase F.

## 사용 방법

1. Phase A에서 이 인덱스를 먼저 읽습니다. 각 항목의 `applies-to`가 현재 작업
   중인 스펙의 스택과 일치하면 해당 메모리 파일을 읽습니다.
2. 메모리를 적용하기 전에 항상 최신 여부를 확인합니다. 파일 경로, 이미지
   태그, 명령어는 코드 변경으로 부패할 수 있습니다. 확인할 수 없으면 사실이
   아니라 힌트로 취급하고 현재 코드 상태를 우선합니다.
3. 메모리는 단문, 의미 단위, 프로젝트 고유 지식만 담습니다. 스킬은 일반론을,
   메모리는 이 저장소에서만 통용되는 함정을 담는 분담입니다.

## 메모리 추가 기준 (Phase F)

다음 조건을 **모두** 만족할 때만 메모리를 추가합니다:

- 이번 스위트에서 약 30분 이상을 잡아먹은 함정/우회/환경 문제였음
- 미래의 작업자가 코드/`git log`를 읽어 유도할 수 없는 지식임
- 스킬의 일반 워크플로에 포함하기에는 프로젝트 특수성이 강함

다음은 메모리에 적지 않습니다:

- 코드를 보면 알 수 있는 사항 (파일 경로, 함수 구조)
- 잘 알려진 명령어/관용구
- 이미 SKILL.md, OUTPUT_CONTRACT.md, TEMPLATES.md에 적힌 내용
- 한 번 발생하고 다시 재현될 가능성이 낮은 일회성 이슈

## 메모리 파일 포맷

```markdown
---
name: <short-kebab-case>
description: <한 줄 요약 — 이 메모리가 어떤 상황에 적용되는지>
applies-to:
  - <stack-tag-1>
  - <stack-tag-2>
last-verified: YYYY-MM-DD
metadata:
  type: pitfall | quirk | workaround | reference
---

# <제목>

<상황 설명 — 어떤 작업 중에 발생했는지>

## What works

<해결책 — 명령어, 패치, 우회 절차>

## Why

<원인 — 가능하면 1~2 문장으로>

## How to apply

- Triggered when: <적용 조건>
- Skip if: <적용 제외 조건>

Related: [[other-memory-name]]
```

## Index

- [Frontend source build OOMs in Docker](frontend-source-build-oom.md) — applies-to: `vue`, `vite`, `vuetify`, `in-docker-build`. 호스트 vite build + thin 이미지로 우회.
- [mem0 vecs.memories table reset after container restart](mem0-vecs-table-reinit.md) — applies-to: `mem0`, `supabase-pgvector`, `completion`. 컨테이너 재시작 시 vecs 스키마 재초기화가 필요할 수 있음.
- [spa-http-server image listens on 8080, not 80](spa-http-server-port-8080.md) — applies-to: `spa-http-server`, `nginx-gateway`. 게이트웨이 upstream 포트를 8080으로 맞춰야 함.
- [Backend coverage flush via USR2 for long-running FastAPI](coverage-py-usr2-flush.md) — applies-to: `fastapi`, `uvicorn`, `coverage.py`. uvicorn은 종료하지 않으므로 신호 기반 flush 필요.
- [Spec-local Playwright needs @playwright/test resolution](playwright-node-modules-junction.md) — applies-to: `spec-local-playwright`, `windows`. node_modules junction 또는 로컬 설치 패턴.
- [completion coverage override의 WORKDIR 불일치](completion-coverage-override-workdir.md) — applies-to: `completion`, `coverage.py`, `docker-compose-override`. `cd /app` vs Dockerfile WORKDIR `/usr/src/app` 함정.
- [form_def 시드 시 html NOT NULL 제약](form-def-html-not-null.md) — applies-to: `supabase`, `form_def`, `e2e-seed`. fields_json만 채우면 시드 실패, html placeholder 필수.
- [Compose override 상대 경로는 프로젝트 디렉터리 기준](compose-override-relative-paths.md) — applies-to: `docker-compose`, `compose-override`, `backend-coverage`. spec-local override의 volume 경로는 항상 repo 루트 기준으로 작성.
- [notifications.updated_at 컬럼이 init.sql에 없음](notifications-updated-at-missing.md) — applies-to: `completion-fcm-service`, `completion-polling`, `supabase-postgrest`. 시드에서 ALTER ADD + rest 컨테이너 재시작 필요.
- [completion polling MCP processor quirks](polling-mcp-processor-quirks.md) — applies-to: `completion-polling`, `mcp_processor`, `service-task`. sanitize_mcp_tools 의 dict-with-properties 드롭 + 전역 MCPProcessor race 우회.
- [completion scriptTask execution path](completion-script-task-execution-path.md) — applies-to: `completion-polling`, `script-task`. scriptTask 는 handle_workitem LangChain 파이프라인 뒤에서만 실행됨. userTask 선행 + role_bindings + generic-JSON mock-llm 패턴.
- [auth.users seed: precomputed bcrypt hash](completion-bcrypt-seed-stability.md) — applies-to: `supabase`, `gotrue`, `e2e-seed`. `crypt(..., gen_salt('bf'))` 대신 사전 계산된 hash 를 embed 하여 GoTrue invalid_credentials 산발적 실패 회피.
- [mcp_python_code 테이블이 init.sql에 없음](mcp-python-code-table-missing.md) — applies-to: `completion`, `compensation-handler`, `rework`, `supabase`. rework-complete/compensation 흐름이 500으로 폭발. 시드에서 임시 DDL + `notify pgrst, 'reload schema'`.
- [nginx 게이트웨이 upstream DNS 캐시](nginx-gateway-dns-cache-after-restart.md) — applies-to: `nginx-gateway`, `e2e-gateway`, `docker-compose`. completion 재시작 후 502가 계속 나면 `docker restart process-gpt-e2e-gateway`.
- [Compose --force-recreate 가 override 의 새 mount 를 반영하지 않음](compose-force-recreate-stale-mount.md) — applies-to: `docker-compose`, `compose-override`, `backend-coverage`. 다른 스위트가 만들어 둔 컨테이너가 있으면 `docker rm -f` 후 다시 `up -d` 해야 새 `/coverage` 바인드가 적용됨.
- [Shared completion 컨테이너 recreate가 다른 스위트 Playwright를 502로 끊는다](shared-completion-container-restart-502.md) — applies-to: `completion`, `docker-compose-override`, `playwright`, `shared-services`. test.beforeAll 헬스 폴링으로 우회.
- [공유 nginx 게이트웨이의 X-Forwarded-Host 덮어쓰기](nginx-overrides-x-forwarded-host.md) — applies-to: `completion`, `nginx-gateway`, `multi-tenant`. 멀티-테넌트 검증은 게이트웨이 우회 후 completion:8000 직접 호출.
- [공유 e2e@uengine.org 비밀번호 회전](shared-auth-user-password-rotation.md) — applies-to: `supabase-gotrue`, `shared-auth-user`, `playwright-login`. 로그인 갑자기 timeout 시 본 스위트 db-seed 재실행.
- [file_cleanup_service tenant filter 가 항상 'localhost' fallback](file-cleanup-tenant-localhost-default.md) — applies-to: `completion-polling`, `file_cleanup_service`, `bpm_proc_inst`. 시드 tenant_id 를 'localhost' 로 맞추지 않으면 worker 가 인스턴스를 못 찾음.
- [kong storage 라우트가 hostname `storage` 로 하드코딩됨](kong-storage-route-hardcoded-hostname.md) — applies-to: `supabase-storage`, `kong-gateway`, `spec-local-storage`. spec-local storage 컨테이너는 `networks.aliases: [storage]` 필수.
- [Tiptap BubbleMenu 입력이 viewport 바깥일 때 Playwright 우회](tiptap-bubble-menu-offscreen-input.md) — applies-to: `vue`, `vuetify`, `tiptap`, `bubble-menu`, `playwright`. `force:true` 도 viewport 검사로 막힘 → native value setter + dispatchEvent('keydown') 로 우회.
- [RTK 후크가 Playwright 리포터 출력을 잘라낸다](rtk-suppresses-playwright-reporters.md) — applies-to: `rtk`, `playwright`, `spec-local-playwright`, `windows`. `rtk proxy npx playwright test` 로 우회해야 results.json / html-report 가 정상 생성됨.
- [Vite dev cold-start 가 로그인 페이지를 Loading 스켈레톤에 묶는다](vite-dev-cold-start-login-suspense.md) — applies-to: `vite-dev`, `source-run-frontend`, `playwright`, `vuetify`. cold-start 시 `LoginForm` 의존 트리가 컴파일 전이라 `.cp-id input` 가 120s+ 안 보임. `vite build --sourcemap` + `vite preview` 또는 prebuilt 이미지로 fallback.
- [Windows source-run + Stop-Process -Force 는 coverage.py 데이터를 잃는다](coverage-flush-windows-force-stop.md) — applies-to: `windows`, `source-run-backend`, `coverage.py`, `uvicorn`. `TerminateProcess` 가 atexit 우회 → `.coverage.*` 미생성. Linux 컨테이너 source-run 또는 명시 `coverage save` 엔드포인트 필요.
