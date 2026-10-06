# E2E 시나리오 — 에이전트 SDK 워크아이템 점유 만료·회수

## 목적
워크아이템을 점유한 워커가 죽어도 작업이 유실되지 않고(만료 뒤 회수), 살아 있는 워커의
작업은 빼앗기지 않는지를 **실제 에이전트 서비스 워커**로 검증한다(spec: `../spec.md`).

점유 수명 자체는 인프라 저장소의 lease 벤치(`process-gpt-infra-docker/tests/lease/`)가
범용 워커로 검증한다(`LEASE-BENCH-*`). 이 suite 는 같은 계약이 각 서비스의 실행기·컨텍스트
조립·결과 저장을 거친 상태에서도 지켜지는지 본다(`SVC-LEASE-*`). 서비스가 SDK 버전을
올리거나 실행기를 바꿀 때 돌린다.

lease 도입 전에는 점유에 만료가 없어, 작업을 집은 워커가 죽으면 그 작업이 `STARTED`로
영구히 남았다.

## 구성 (mock 없음)
| 구성요소 | 실물 |
|---|---|
| DB | 로컬 Supabase(`supabase_db_process-gpt-vue3`). lease 버전 `fetch_pending_task`·`renew_task_lease`·`release_task_lease` 배포 상태(`process-gpt-infra-docker/tests/lease/apply-lease-local.sql`) |
| 워크아이템 폴링 런타임 | `process-gpt-agent-sdk` ≥ 0.10.0 (각 서비스 venv 에 설치된 것) |
| 워커 | 각 서비스 작업 트리를 자기 진입점으로 소스 실행 — deepagents `server.py`, cli-agent `server.py`, codex `main.py` |
| LLM | litellm proxy `LLM_PROXY_URL`. cli-agent 의 claude CLI 와 codex 가 이 프록시를 쓴다 |
| codex CLI | Dockerfile 이 고정한 버전을 `.tools/`에 설치해 네이티브로 실행 |

판정은 전부 DB 상태(`todolist`, `events`)로 한다. 워커 로그(`.logs/`)는 실패 원인을 볼 때만 쓴다.

테스트용 lease 는 8초(heartbeat 2초)다. 운영(120초/30초)과 비율은 같고 길이만 줄였다 —
LLM 수행이 4초만 넘어도 연장이 두 번 관찰된다.

## 사전 조건
- 로컬 Supabase 에 lease 마이그레이션이 적용되어 있다.
- 틀로 복제할 워크아이템(`LEASE_SVC_TEMPLATE_TODO`)이 있다. 컨텍스트 조립이 실제로 성공하는 행이어야 한다(프로세스 인스턴스·폼·에이전트가 있는 작업).
- 각 서비스 저장소에 SDK 가 설치된 `.venv`가 있다. cli-agent 는 `uv venv && uv pip install -r requirements.txt`.
- codex CLI: `npm install --prefix .tools "@openai/codex@<CODEX_VERSION>"`(버전은 codex Dockerfile 의 `CODEX_VERSION`).
- 같은 `agent_orch`로 DB 를 폴링하는 다른 워커가 없다.

## 실행
```bash
cp services.env.example services.env   # 값을 채운다(커밋하지 않는다)
uv run --no-project --with pytest pytest -v -p no:cacheprovider                     # 세 서비스 전부
uv run --no-project --with pytest pytest -v -p no:cacheprovider --service codex     # 하나만
```

## 시나리오
테스트 함수 이름이 시나리오 ID 로 시작하고, docstring 이 spec 의 GIVEN/WHEN/THEN 원문이다.
서비스마다 같은 6개를 돈다.

| ID | 절차 | 판정 |
|---|---|---|
| SVC-LEASE-01 | 워커 A 기동 → 작업 1건 복제 | 첫 `STARTED`에서 `consumer`=A, `claim_count`=1, `lease_until`이 지금+lease 이내 |
| SVC-LEASE-02 | 01 의 작업을 끝까지 관찰 + 04 의 회수 뒤 B 구간 | 두 구간 모두 점유자·횟수 불변, 만료 시한이 지나지 않음. 판정 가능한 길이(heartbeat 2배 이상)의 구간에서 `lease_until`이 뒤로 밀림 |
| SVC-LEASE-03 | 01 의 작업이 끝날 때까지 | 종결 상태(`COMPLETED`/`FAILED`), `lease_until`·`consumer` 비어 있음. 점유만 풀린 `STARTED`가 lease 두 배 이상 이어지면 고아로 보고 실패 |
| SVC-LEASE-04 | 새 작업을 A 가 점유하는 즉시 A 의 프로세스 그룹에 SIGKILL → 워커 B 기동 | B 가 점유, `claim_count`=2, 회수 시각 ≥ A 의 `lease_until`, kill 부터 lease+폴링(10초)+기동 여유(60초) 이내, 이후 종결·점유 해제 |
| SVC-LEASE-05 | 01 과 04 의 작업 비교 | 04 의 `task_completed` 수 ≤ 01 의 수(둘 다 `COMPLETED`일 때만 판정) |
| SVC-LEASE-06 | 시작 전에 `lease_until` 없는 `STARTED` 행을 심어 둠 | 모든 시나리오가 끝난 뒤에도 점유자·상태·점유 횟수 그대로 |

SIGKILL 을 워커 프로세스 하나가 아니라 **프로세스 그룹 전체**에 보내는 이유: 파드가 죽는 것과
같게 만들기 위해서다. 프로세스 하나만 죽이면 CLI 자식 프로세스가 고아로 남아 계속 돈다.

05 의 기준이 "1건" 이 아닌 이유: 서비스마다 한 번의 실행에 남기는 `task_completed` 수가
다르다(deepagents 는 2건). 여기서 보는 것은 회수가 완료를 **더** 만들었는가이다.

## 안전장치
`todolist`에는 개발 데이터가 있다.
- 시작 전에 그 서비스가 집을 행이 DB 에 있는지 본다. 있으면 **시작하지 않는다** — 테스트 워커가 남의 작업을 실행하게 된다.
- 만드는 행은 `activity_name`이 `[lease-svc]`로 시작하고 DRAFT 모드다(초안만 저장, 프로세스 진행 없음).
- 지우는 것은 이 suite 가 만든 id 목록과, 트리거가 그 행에서 파생시킨 행(`events`, `task_execution_properties`, `notifications`)뿐이다. 실패해도 지운다.

## 설정(`services.env`, 괄호는 기본값)
| 키 | 뜻 |
|---|---|
| `SUPABASE_URL` (`http://127.0.0.1:54321`), `SUPABASE_KEY` | 워커가 붙을 Supabase |
| `LLM_PROXY_URL`, `LLM_PROXY_API_KEY` | codex 가 쓰는 프록시 |
| `ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_MODEL` | cli-agent 의 claude CLI 자격증명. cli-agent 는 실행마다 설정 폴더를 바꿔 로컬 로그인이 보이지 않는다 |
| `LEASE_SVC_CODEX_BIN` (`codex`) | codex CLI. 상대 경로는 이 폴더 기준 |
| `LEASE_SVC_CODEX_IMAGE` (빈 값) | 비우면 네이티브 실행. 로컬 이미지가 amd64 면 arm64 맥에서는 bwrap 이 실패한다 |
| `LEASE_SVC_TEMPLATE_TODO` | 틀로 복제할 워크아이템 id |
| `LEASE_SVC_LEASE_SECONDS` (8) | 테스트용 lease |
| `LEASE_SVC_*_DIR`, `LEASE_SVC_*_PYTHON` | 서비스 저장소와 python 경로(기본은 ws/ 아래 형제 디렉터리의 `.venv`) |
| `SB_DB_CONTAINER` (`supabase_db_process-gpt-vue3`) | 판정용 psql 을 실행할 DB 컨테이너 |
