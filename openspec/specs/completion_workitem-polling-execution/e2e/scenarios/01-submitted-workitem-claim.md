# E2E 시나리오 01: 제출된 워크아이템 자동 폴링

## 메타데이터
- 스위트 슬러그: `completion_workitem-polling-execution`
- 원본 명세 ID: `completion_workitem-polling-execution`
- 시나리오 ID: `01`
- Playwright 테스트 제목: `폴링 워커가 SUBMITTED 워크아이템을 클레임해 처리한다`
- 원본 명세:
  - `openspec/specs/completion_workitem-polling-execution/spec.md`
- 상태: **보류** (활성화 시 ATE 스위트와 연계 또는 본 스펙 고유 데이터로 보강)

## 목적
폴링 워커가 `status='SUBMITTED'` 이고 `consumer IS NULL` 인 워크아이템을 주기적으로(5초) 감지해 자신의 pod_id 로 `consumer` 를 설정하고 `safe_handle_workitem` 으로 처리를 시작하는 동작을 사용자 화면에서 검증한다. 본 시나리오의 핵심 경로(`fetch_workitem_with_submitted_status` → `safe_handle_workitem` → `handle_service_workitem` 또는 `handle_workitem`) 는 이미 `completion_automated-task-execution` 스위트가 결정적으로 검증한다.

## 사전 조건
- `docker-compose.e2e.yml` 의 `db`, `kong`, `auth`, `rest`, `mock-llm-ate`, `completion-polling`, `frontend`, `gateway` 가 healthy 상태.
- `db-seed-automated-task-execution` (또는 본 스위트 고유 시드) 가 `localhost` 테넌트, 로그인 사용자, agent 사용자, MCP 설정, SUBMITTED 워크아이템을 적재 완료.
- 본 스위트 활성화 시: `db-seed-workitem-polling-execution` 시드를 추가하여 ATE 데이터와 충돌하지 않는 별도 `proc_inst_id`/`activity_id` 사용.

## 테스트 데이터 및 Stub
| 이름 | 유형 | 경로 또는 route | 목적 |
| --- | --- | --- | --- |
| `e2e_seed.sql` | seed | `openspec/specs/completion_workitem-polling-execution/e2e/seed_files/e2e_seed.sql` (본 스위트 활성화 시 작성) | 본 스펙 고유 SUBMITTED 워크아이템 시드. `user_id='<agent_uuid>,<human_uuid>'` 형식 유지 |
| `mock_llm.py` | stub | `openspec/specs/completion_automated-task-execution/e2e/scripts/mock_llm.py` (재사용) | LangChain react agent 호출 결정성 확보 |
| `mock_mcp_server.py` | stub | `openspec/specs/completion_automated-task-execution/e2e/scripts/mock_mcp_server.py` (재사용) | MCP 도구 응답 결정성 확보 |

## 절차
1. 사용자가 `/auth/login` 으로 이동해 `ate-e2e@uengine.org` / `ate-password` 로 로그인합니다.
2. 사용자가 `/todolist` 로 이동해 KanbanBoard 의 SUBMITTED 컬럼에 워크아이템 카드가 노출됨을 확인합니다.
3. 사용자가 페이지를 새로고침하며(폴링 워커가 5초 간격으로 처리하므로) 카드가 IN_PROGRESS 또는 DONE 컬럼으로 이동할 때까지 대기합니다.
4. 사용자가 DONE 컬럼의 카드를 클릭해 상세를 확인합니다.

## 기대 결과
- 워크아이템 카드가 SUBMITTED → IN_PROGRESS(또는 DONE 직접 전이) 컬럼으로 이동합니다.
- DB 레벨에서 처리 진행 중 `todolist.consumer` 가 폴링 워커의 pod_id 값으로 설정되고 처리 완료 후 `NULL` 로 해제됩니다 (직접 검증은 `docker exec` SQL 보조).
- 카드의 로그/결과 영역에 처리 결과가 표시됩니다.

## 커버하는 요구사항
| 명세 | 요구사항 | 시나리오 |
| --- | --- | --- |
| `completion_workitem-polling-execution` | 제출된 워크아이템 자동 폴링 | 제출 워크아이템 클레임 |

## 산출물
- 스크린샷 체크포인트:
  | 체크포인트 | 캡처할 UI 상태 | 예상 파일 | 매뉴얼용 캡션 |
  | --- | --- | --- | --- |
  | `01-login` | 로그인 완료 직후 첫 진입 화면 | `process-gpt-completion_workitem-polling-execution-01-login.png` | 폴링 검증용 사용자 로그인 직후 화면 |
  | `01-submitted-initial` | KanbanBoard SUBMITTED 컬럼에 워크아이템 카드가 보이는 초기 상태 | `process-gpt-completion_workitem-polling-execution-01-submitted-initial.png` | 폴링 시작 전 SUBMITTED 워크아이템 |
  | `01-claimed-or-done` | 폴링 워커가 처리해 카드가 다른 컬럼으로 이동한 상태 | `process-gpt-completion_workitem-polling-execution-01-claimed-or-done.png` | 폴링 워커가 클레임/완료 처리한 상태 |
- Trace/video: Playwright 실패 시 보존됩니다 (활성화 시).
- 결과 JSON: `openspec/specs/completion_workitem-polling-execution/e2e/results/results.json` (활성화 시).

## 보류 사유
Req 1 의 동선은 `completion_automated-task-execution` 스위트가 동일한 폴링 워커·시드 패턴·UI 셀렉터로 이미 결정적으로 검증한다. 본 스위트에서 별도 검증할 가치는 (a) 본 스펙 고유의 `PENDING` 상태 폴링 경로(`fetch_workitem_with_pending_status` + `handle_pending_workitem`) 또는 (b) 동시 polling tick 에서의 `consumer` race 케이스 정도이며, 둘 다 별도 시나리오로 분리하는 것이 더 명확하다.
