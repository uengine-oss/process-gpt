# E2E 결과 — DeepAgents 워크아이템 사람 질문 대기·재개 — 2026-10-06

## 요약
| suite | 대상 버전 | 결과 |
|---|---|---|
| `run_e2e.py sdk` | SDK **0.10.1** | **11/11 PASS** |
| `run_e2e.py sdk` | SDK 0.10.0 (수정 전, 대조군) | 4/11 — 결함을 잡는다 |
| `run_e2e.py live` | SDK 0.10.1 + deepagents `075a7aa` 이후 작업 트리 + vue3 `5953158e` 이후 작업 트리, gpt-5 | **13/13 PASS** |

## 대조군: 수정 전 SDK 0.10.0 에서 실패한 항목
| ID | 관찰 |
|---|---|
| HITL-01 | `SUBMITTED / COMPLETED`, `output = "결재 금액 상한이 얼마입니까?"`, `crew_completed` 기록 |
| HITL-09 | 이미 SUBMITTED 라 답을 줘도 다시 집히지 않음 |
| HITL-02 | DRAFT 에서 질문이 `draft`로 저장되고 `COMPLETED` |
| HITL-03 | 결과 없이 질문만 낸 실행이 `STARTED`, `consumer` 남음, `lease_until` NULL → **아무도 다시 집지 않는 고아** |
| HITL-06 | 실행 중 취소한 작업이 질문 문구로 `SUBMITTED` |

## live 실측
- 틀: `de20244f…`(재고관리 프로세스 · 납기 모니터링, 폼 `inventory_mgmt_process_task_deliverymonitor_form`)
- 질문: 에이전트가 `request_human_input({"question": "이번 주 납기 지연 허용 기준이 며칠입니까?"})` 호출 → `IN_PROGRESS / HUMAN_ASKED`, `output` 없음
- 화면: 질문 카드에 질문 문구 표시(`screenshots/01-question-card.png`). "5일까지 허용합니다" 입력 후 확인(`02-answered.png`)
- 재개: `HITL 그래프 재개 | thread_id=<todo id>` → `SUBMITTED / COMPLETED`
- 결과: 폼의 `pending_receipt_report`·`expedite_draft`에 "허용 기준 5일" 반영
- events (12건, 유실 0): `task_started, tool_usage_started, human_asked, human_response, task_started, tool_usage_finished, tool_usage_started, tool_usage_finished, task_completed, task_started, task_completed, crew_completed`

## 이번 검증에서 드러난 것
1. **live 시드는 프로세스 정의에 붙은 작업이어야 한다.** 정의 없는 작업은 화면이 자유입력으로 떠서 질문 카드가 없다(첫 실행에서 HITL-07 실패). 그래서 기존 작업을 틀로 복제하도록 바꿨다.
2. **`events.event_type`은 이 DB 에서 NOT NULL 이다.** SDK README 는 "WORKING 은 자동 매핑하지 않고 NULL 허용"이라고 적고 있지만, `event_type` 없이 WORKING 상태를 보내면 그 이벤트가 든 묶음 저장(`record_events_bulk`)이 통째로 실패하고 같은 묶음의 `crew_completed`까지 사라진다. sdk suite 첫 실행의 HITL-04 실패가 이것이었다(실행기가 실제 에이전트처럼 `task_working`을 명시하도록 고쳐 통과). 이번 범위 밖의 기존 문제로, 묶음 저장이 한 건의 실패로 전부를 잃는 구조는 별도 과제다.
3. HITL-08(진행 표시 내림)은 자동화하지 못했다. 대기 중에도 에이전트 작업 카드에 "request_human_input 도구 사용 중" 진행 표시가 남는다(화면 표시만의 문제).
