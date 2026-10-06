# E2E 시나리오 — DeepAgents 워크아이템 사람 질문 대기·재개

## 목적
COMPLETE 모드 워크아이템에서 에이전트가 사람에게 물으면 질문이 산출물로 제출되지 않고
`HUMAN_ASKED`로 멈추는지, 질문 카드에 답하면 멈춘 지점에서 그 답으로 이어 실행해
결과를 제출하는지를 실물 구성요소로 검증한다(spec: `../spec.md`).

수정 전에는 질문 문구가 `output`으로 저장되며 `SUBMITTED`되어 프로세스가 다음 단계로
넘어갔다. 원인은 두 경로였다.
- 런타임이 질문 뒤의 마지막 결과를 완료로 저장했다.
- DeepAgents 워크아이템에 질문 도구가 없어 모델이 질문을 평문 답으로 냈다.

## 구성 (mock 없음 — sdk suite 의 실행기만 모의)
| 구성요소 | 실물 |
|---|---|
| DB | 로컬 Supabase(`supabase_db_process-gpt-vue3`). `fetch_pending_task`(lease 버전), `save_task_result`, `record_events_bulk` RPC 배포 상태 |
| 워크아이템 폴링 런타임 | `process-gpt-agent-sdk` ≥ 0.10.1 (실행 venv 에 설치된 것) |
| 에이전트 (live) | `process-gpt-deepagents` 작업 트리를 `server.py`로 소스 실행. 체크포인터는 공유 InMemory |
| LLM (live) | litellm proxy `LLM_PROXY_URL`, 모델 `LLM_MODEL` (검증 시 gpt-5) |
| 화면 (live) | `process-gpt-vue3` dev 서버 `APP_URL`(8088). Playwright 는 vue3 의 것을 빌려 쓴다 |

## 사전 조건
- 위 Supabase, LLM proxy, vue3 dev 서버가 떠 있다.
- live: 다른 deepagents 워커가 같은 DB 를 폴링하고 있지 않다. 러너는 워커가 집을 다른 deepagents 작업이 있으면 시작하지 않는다.
- live: 틀로 복제할 deepagents 프로세스 워크아이템이 하나 있다(자동 선택, 또는 `E2E_TEMPLATE_TODO_ID`). 정의 없는 작업은 화면이 자유입력으로 떠서 질문 카드가 없다.
- live: 화면 로그인 계정 `E2E_USER_EMAIL` / `E2E_USER_PASSWORD`.

## 실행 방법
```bash
cd openspec/specs/deepagents_workitem-human-input/e2e
PY=<ws>/process-gpt-deepagents/.venv/bin/python

$PY run_e2e.py sdk                         # LLM 없음, 약 20초 — 11 checks
E2E_USER_EMAIL=... E2E_USER_PASSWORD=... \
  $PY run_e2e.py live                      # 실제 LLM + 화면, 약 2~4분 — 13 checks
```
종료 코드는 전부 PASS 면 0 이다. 만든 todolist/events/notifications 행은 끝나면 지운다.
live 의 화면 캡처는 `screenshots/`, 워커 로그는 `worker.log`(git 제외)에 남는다.

## 시나리오별 검증 위치
| ID | 시나리오 | sdk | live | 단위 테스트 |
|---|---|---|---|---|
| HITL-01 | COMPLETE 가 질문하고 멈춘다 | ✓ | ✓ (실제 LLM) | SDK `TestProcessEventQueueHumanAsked` |
| HITL-02 | DRAFT 도 질문을 초안으로 저장하지 않는다 | ✓ | | |
| HITL-03 | 결과 없이 질문만 남겨도 대기 | ✓ | | SDK |
| HITL-04 | 같은 실행에서 이어 가면 결과로 제출 | ✓ | | SDK |
| HITL-05 | 답 전에는 폴링에 걸리지 않는다 | ✓ | ✓ (워커 가동 중 15초) | |
| HITL-06 | 대기 표시 전 취소는 유지 | ✓ | | |
| HITL-07 | 질문 카드에서 답한다 | | ✓ (Playwright) | vue3 `hitlFeedback.test.js` |
| HITL-08 | 대기 상태가 되면 진행 표시를 내린다 | | | **자동화 안 됨** — 수동 확인 |
| HITL-09 | 답을 반영해 결과를 제출한다 | 재클레임만 | ✓ | deepagents `test_hitl.py` (답 원문 재개) |
| HITL-10 | 재개 실행의 이벤트가 모두 저장된다 | | ✓ | deepagents `test_hitl.py` (`human_answered` 채팅 한정) |
| HITL-11 | COMPLETE 워크아이템에서 질문 도구로 묻는다 | | ✓ | deepagents `test_hitl.py` |
| HITL-12 | DRAFT 에는 질문 도구를 주지 않는다 | | | deepagents `test_hitl.py` |

## live 시나리오 흐름
1. 틀 워크아이템을 복제해 COMPLETE, `IN_PROGRESS`로 넣는다. `query`에 "진행 전에 반드시 request_human_input 으로 '이번 주 납기 지연 허용 기준이 며칠입니까?'를 물을 것"을 넣는다.
2. deepagents 워커를 띄운다. 에이전트가 질문 도구를 부르고 실행을 마치면 작업은 `HUMAN_ASKED`가 된다(HITL-11, 01).
3. 15초간 워커가 그 작업을 다시 집지 않는지 본다(HITL-05).
4. Playwright 로 `/todolist/<id>`를 열고, 질문 카드의 문구를 확인한 뒤 "5일까지 허용합니다"로 답한다(HITL-07).
5. 워커가 다시 집어 멈춘 지점에서 재개하고(`HITL 그래프 재개`), 결과를 `SUBMITTED`한다. 결과에 "5일"이 들어 있다(HITL-09).
6. events 에 `task_started`, `human_asked`, `human_response`, `task_completed`, `crew_completed`(1회)가 모두 있고, 워커 로그에 이벤트 저장 실패가 없다(HITL-10).

LLM 판단이 들어가므로 live 는 드물게 모델이 지시를 어기고 묻지 않을 수 있다. 이 경우 HITL-11 이 실패로 드러난다.
