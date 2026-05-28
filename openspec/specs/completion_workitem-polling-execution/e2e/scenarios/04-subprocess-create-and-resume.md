# E2E 시나리오 04: 서브프로세스 생성과 부모 재개

## 메타데이터
- 스위트 슬러그: `completion_workitem-polling-execution`
- 원본 명세 ID: `completion_workitem-polling-execution`
- 시나리오 ID: `04`
- Playwright 테스트 제목: `서브프로세스 활동 시 자식 인스턴스가 생성되고 자식 완료 후 부모 워크아이템이 다시 진행 대상으로 전이된다`
- 원본 명세:
  - `openspec/specs/completion_workitem-polling-execution/spec.md`
- 상태: **보류** (`subProcesses` BPMN 구조 + `handle_pending_workitem` 시드 필요)

## 목적
폴링 워커가 서브프로세스 활동을 처리할 때 자식 프로세스 인스턴스와 초기 워크아이템을 생성하고, 부모 워크아이템을 `PENDING` 으로 전이한다. 이후 자식 인스턴스가 모두 `COMPLETED` 되면 `handle_pending_workitem` (workitem_processor.py:4196–) 이 부모 PENDING 워크아이템을 `DONE` 으로 전환하여 다시 진행 대상으로 만든다.

## 사전 조건
- 본 스위트 고유 시드에 다음 BPMN 구조가 포함되어야 합니다:
  - 부모 `proc_def`: `act_setup_parent` (userTask) → `act_call_sub` (subProcess) → `act_after_sub` (userTask) → endEvent. `subProcesses` 필드에 자식 정의 ID 참조.
  - 자식 `proc_def`: `act_child_step` (userTask) → endEvent.
- 부모 `bpm_proc_inst` 가 `RUNNING` 상태로 시드되어 있고, `act_call_sub` 워크아이템이 SUBMITTED 또는 PENDING 으로 시드되어 있어야 합니다.
- `mock-llm-ate` 가 부모/자식 prompt 응답을 모두 결정적으로 처리해야 합니다.

## 테스트 데이터 및 Stub
| 이름 | 유형 | 경로 또는 route | 목적 |
| --- | --- | --- | --- |
| `e2e_seed.sql` | seed | `openspec/specs/completion_workitem-polling-execution/e2e/seed_files/e2e_seed.sql` | 부모/자식 BPMN 정의 + 인스턴스 시드 |
| `mock_llm.py` (확장) | stub | `openspec/specs/completion_automated-task-execution/e2e/scripts/mock_llm.py` | 부모/자식 prompt_completed/prompt_next_activity 분기 |

## 절차
1. 사용자가 로그인 후 `/todolist` 에서 `act_setup_parent` 카드를 제출합니다.
2. 폴링 워커가 `act_setup_parent` 를 DONE 처리하고 `act_call_sub` 를 진행시킵니다.
3. 자식 인스턴스가 생성되고 `act_child_step` 워크아이템이 IN_PROGRESS 컬럼에 등장합니다.
4. 사용자가 `act_child_step` 카드를 제출하고 자식 인스턴스가 COMPLETED 됩니다.
5. 사용자가 부모 인스턴스 상세로 이동해 PENDING 이었던 부모 워크아이템이 `act_after_sub` 로 전이된 것을 확인합니다.

## 기대 결과
- 자식 인스턴스(`bpm_proc_inst` 신규 행)가 `RUNNING` 으로 생성됩니다.
- 부모 워크아이템 `act_call_sub` 가 자식 처리 중에는 `PENDING` 상태로 유지됩니다.
- 자식 인스턴스가 `COMPLETED` 된 후 부모 `act_call_sub` 워크아이템이 `DONE` 으로 전이되고 후속 `act_after_sub` 워크아이템이 생성됩니다.

## 커버하는 요구사항
| 명세 | 요구사항 | 시나리오 |
| --- | --- | --- |
| `completion_workitem-polling-execution` | 서브프로세스 생성과 부모 재개 | 서브프로세스 자식 인스턴스 생성 / 자식 완료 시 부모 재개 |

## 산출물
- 스크린샷 체크포인트:
  | 체크포인트 | 캡처할 UI 상태 | 예상 파일 | 매뉴얼용 캡션 |
  | --- | --- | --- | --- |
  | `04-child-instance-created` | 자식 인스턴스의 첫 워크아이템이 IN_PROGRESS 에 등장한 상태 | `process-gpt-completion_workitem-polling-execution-04-child-instance-created.png` | 자식 인스턴스 생성 직후 |
  | `04-parent-resumed` | 자식 COMPLETED 후 부모의 `act_after_sub` 워크아이템 등장 | `process-gpt-completion_workitem-polling-execution-04-parent-resumed.png` | 부모 인스턴스 재개 직후 |
- Trace/video: Playwright 실패 시 보존됩니다.
- 결과 JSON: `openspec/specs/completion_workitem-polling-execution/e2e/results/results.json`.

## 보류 사유
서브프로세스 검증은 (a) BPMN 정의에 `subProcesses` 와 자식 정의 참조를 포함시키는 BPMN 모델링 작업, (b) 자식 인스턴스 자동 생성 로직(`handle_workitem` 의 subProcess 분기)이 mock-llm 응답에 의존하는 LangChain 경로를 다시 통과해야 하는 점, (c) 부모/자식 UI 표면(자식 인스턴스 화면 진입 셀렉터)을 모두 식별해야 하는 점에서 단일 turn 작업으로 적합하지 않다. 별도 작업으로 분리하여 BPMN 시드 → 자식 자동 생성 검증 → 자식 완료 후 부모 재개 검증의 3단계로 활성화하는 것이 권장된다.
