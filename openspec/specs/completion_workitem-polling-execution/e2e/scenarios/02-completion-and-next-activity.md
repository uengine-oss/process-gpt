# E2E 시나리오 02: 완료 판정과 다음 활동 진행

## 메타데이터
- 스위트 슬러그: `completion_workitem-polling-execution`
- 원본 명세 ID: `completion_workitem-polling-execution`
- 시나리오 ID: `02`
- Playwright 테스트 제목: `완료 조건을 만족한 활동이 DONE 으로 전이되고 다음 활동 워크아이템이 IN_PROGRESS 로 생성된다`
- 원본 명세:
  - `openspec/specs/completion_workitem-polling-execution/spec.md`
- 상태: **보류** (`handle_workitem` LangChain mock 확장 의존)

## 목적
사용자가 `userTask` 워크아이템을 제출하면 폴링 워커가 `handle_workitem` 의 LangChain 완료 판정 파이프라인(`prompt_completed`)으로 활동을 `DONE` 으로 전이하고, `execute_next_activity` 가 다음 활동 워크아이템을 `IN_PROGRESS` 상태로 생성한다. 본 시나리오는 동시에 완료 조건 미충족 시 `PENDING` 전이(원본 명세의 두 번째 OpenSpec Scenario)와 LLM 출력 파싱 실패 시 `PENDING` 전이(세 번째 OpenSpec Scenario)도 분기로 커버한다.

## 사전 조건
- 본 스위트 고유 시드(`db-seed-workitem-polling-execution`)가 적용되어 있어야 합니다.
- 시드 내용:
  - `proc_def` 정의: 두 개의 사용자 활동 시퀀스 (`act_step_1` userTask → `act_step_2` userTask). `sequences` 와 `startEvent`/`endEvent` 가 명시되어 있어야 함.
  - `bpm_proc_inst` 인스턴스, `current_activity_ids = ARRAY['act_step_1']`, `status = 'RUNNING'`.
  - `todolist` 행 1건: `act_step_1` 의 SUBMITTED 워크아이템 (`user_id` = 로그인 사용자 UUID).
- `mock-llm-ate` 의 `mock_llm.py` 확장: `prompt_completed` 응답으로 `{"completedActivities":[{"completedActivityId":"act_step_1","result":"DONE"}]}` JSON 을 반환하고, `prompt_next_activity` 응답으로 `{"nextActivities":[{"nextActivityId":"act_step_2","result":"IN_PROGRESS"}]}` 를 반환하도록 prompt detection 분기 추가.

## 테스트 데이터 및 Stub
| 이름 | 유형 | 경로 또는 route | 목적 |
| --- | --- | --- | --- |
| `e2e_seed.sql` | seed | `openspec/specs/completion_workitem-polling-execution/e2e/seed_files/e2e_seed.sql` | userTask 시퀀스 BPMN + SUBMITTED 워크아이템 시드 |
| `mock_llm.py` (확장) | stub | `openspec/specs/completion_automated-task-execution/e2e/scripts/mock_llm.py` | `prompt_completed` / `prompt_next_activity` JSON 응답 추가 |

## 절차
1. 사용자가 `/auth/login` 에서 로그인합니다.
2. 사용자가 `/todolist` 로 이동해 SUBMITTED 컬럼의 `act_step_1` 카드를 확인합니다.
3. 사용자가 카드를 열어 폼을 입력하고 "제출" 버튼을 누릅니다(또는 시드 시점에 이미 SUBMITTED 상태이면 폴링 워커의 다음 사이클을 대기합니다).
4. 사용자가 5–10초 후 화면을 새로고침하며 카드가 DONE 컬럼으로 이동하고, IN_PROGRESS 컬럼에 `act_step_2` 카드가 새로 등장하는지 확인합니다.

## 기대 결과
- `act_step_1` 워크아이템이 DONE 컬럼에 표시됩니다 (DB: `todolist.status = 'DONE'`, `end_date IS NOT NULL`).
- `act_step_2` 워크아이템이 신규로 생성되어 IN_PROGRESS 컬럼에 표시됩니다 (DB: `todolist.status = 'IN_PROGRESS'`).
- 인스턴스의 `current_activity_ids` 가 `['act_step_2']` 로 갱신됩니다.
- (분기) 완료 조건 미충족 mock 시: 카드 상태가 `PENDING` 으로 표시되고 사유 로그가 노출됩니다.
- (분기) LLM 출력 파싱 실패 mock 시: 카드 상태가 `PENDING` 으로 표시되고 시스템 메시지 로그가 노출됩니다.

## 커버하는 요구사항
| 명세 | 요구사항 | 시나리오 |
| --- | --- | --- |
| `completion_workitem-polling-execution` | 완료 판정과 다음 활동 진행 | 워크아이템 완료 후 다음 활동 생성 / 완료 조건 미충족 / LLM 출력 파싱 실패 |

## 산출물
- 스크린샷 체크포인트:
  | 체크포인트 | 캡처할 UI 상태 | 예상 파일 | 매뉴얼용 캡션 |
  | --- | --- | --- | --- |
  | `02-submit-form` | act_step_1 폼 입력 직후 제출 직전 | `process-gpt-completion_workitem-polling-execution-02-submit-form.png` | 사용자 활동 제출 직전 |
  | `02-next-activity-shown` | DONE 컬럼의 act_step_1 + IN_PROGRESS 컬럼의 act_step_2 | `process-gpt-completion_workitem-polling-execution-02-next-activity-shown.png` | 완료 판정 직후 다음 활동 카드 노출 |
  | `02-pending-on-mismatch` | (분기) 완료 조건 미충족 시 PENDING 상태 + 사유 로그 | `process-gpt-completion_workitem-polling-execution-02-pending-on-mismatch.png` | 완료 조건 미충족으로 PENDING 전이된 상태 |
- Trace/video: Playwright 실패 시 보존됩니다.
- 결과 JSON: `openspec/specs/completion_workitem-polling-execution/e2e/results/results.json`.

## 보류 사유
`handle_workitem` 은 4000+ 라인의 LangChain 파이프라인으로, `prompt_completed`/`prompt_next_activity`/`prompt_role_resolution` 등 다단계 prompt 응답을 모두 결정적으로 mock 해야 한다. 기존 `mock-llm-ate` 의 `mock_llm.py` 는 react agent 의 tool_calls 응답만 처리하며, 본 시나리오를 위해서는 prompt 본문 패턴 매칭과 활동 ID 별 응답 매핑이 추가로 필요하다 ([[completion-script-task-execution-path]]). 이 mock-llm 확장 작업은 본 스위트의 별도 사전 작업으로 분리되어야 한다.
