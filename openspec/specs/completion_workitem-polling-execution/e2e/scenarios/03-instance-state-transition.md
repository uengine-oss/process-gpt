# E2E 시나리오 03: 프로세스 인스턴스 상태 전이

## 메타데이터
- 스위트 슬러그: `completion_workitem-polling-execution`
- 원본 명세 ID: `completion_workitem-polling-execution`
- 시나리오 ID: `03`
- Playwright 테스트 제목: `종료 활동이 완료되면 인스턴스가 COMPLETED 로 전이되고 종료 시각이 기록된다`
- 원본 명세:
  - `openspec/specs/completion_workitem-polling-execution/spec.md`
- 상태: **보류** (시나리오 02 의존)

## 목적
종료 활동(`endEvent` 와 연결된 활동) 의 워크아이템이 완료되면 폴링 워커가 `bpm_proc_inst.status` 를 `COMPLETED` 로 전이하고 `end_date` 를 기록한다. 진행 중인 인스턴스는 `RUNNING` 상태를 유지한다. 직접 구현체는 `workitem_processor.py` 의 `update_instance_status_on_error` 및 `execute_next_activity` 내부의 last-activity 분기(line 1414 인근)이다.

## 사전 조건
- 시나리오 02 의 사전 조건이 모두 충족되어야 합니다.
- 시드 BPMN 정의에 `startEvent` 와 `endEvent` 가 명시되어 있어야 하며, `process_definition.find_end_activity()` 가 종료 활동을 식별할 수 있어야 합니다.
- `mock-llm-ate` 의 `prompt_completed` 응답이 마지막 활동(`act_step_2`)을 완료로 판정하는 분기를 포함해야 합니다.

## 테스트 데이터 및 Stub
| 이름 | 유형 | 경로 또는 route | 목적 |
| --- | --- | --- | --- |
| `e2e_seed.sql` | seed | `openspec/specs/completion_workitem-polling-execution/e2e/seed_files/e2e_seed.sql` | 시나리오 02 와 동일 BPMN 재사용 |
| `mock_llm.py` (확장) | stub | `openspec/specs/completion_automated-task-execution/e2e/scripts/mock_llm.py` | 마지막 활동 완료 판정 분기 |

## 절차
1. 시나리오 02 완료 직후 사용자가 `/process-instances` 또는 인스턴스 상세 화면으로 이동합니다.
2. 사용자가 `act_step_2` 워크아이템을 제출하고 폴링 워커의 다음 사이클을 대기합니다.
3. 사용자가 인스턴스 상세에서 상태 배지가 RUNNING → COMPLETED 로 변경되고 종료 시각이 표시되는지 확인합니다.

## 기대 결과
- 인스턴스 상태 배지가 `COMPLETED` 로 표시됩니다 (DB: `bpm_proc_inst.status = 'COMPLETED'`, `end_date IS NOT NULL`).
- 진행 중 분기에서는 인스턴스 상태가 `RUNNING` 으로 유지됨이 인스턴스 상세 화면에서 확인됩니다.

## 커버하는 요구사항
| 명세 | 요구사항 | 시나리오 |
| --- | --- | --- |
| `completion_workitem-polling-execution` | 프로세스 인스턴스 상태 전이 | 종료 활동 완료 시 인스턴스 완료 / 진행 중 인스턴스 유지 |

## 산출물
- 스크린샷 체크포인트:
  | 체크포인트 | 캡처할 UI 상태 | 예상 파일 | 매뉴얼용 캡션 |
  | --- | --- | --- | --- |
  | `03-instance-running` | 인스턴스 상세에서 RUNNING 배지 노출 | `process-gpt-completion_workitem-polling-execution-03-instance-running.png` | 진행 중 인스턴스 상태 |
  | `03-instance-completed` | 인스턴스 상세에서 COMPLETED 배지 + 종료 시각 표시 | `process-gpt-completion_workitem-polling-execution-03-instance-completed.png` | 종료 활동 완료 후 인스턴스 완료 상태 |
- Trace/video: Playwright 실패 시 보존됩니다.
- 결과 JSON: `openspec/specs/completion_workitem-polling-execution/e2e/results/results.json`.

## 보류 사유
시나리오 02 와 동일한 mock-llm 확장 의존성을 가지며, 추가로 인스턴스 상세 화면의 정확한 셀렉터(상태 배지·종료 시각 요소) 식별이 필요하다. 본 스위트 활성화 시 시나리오 02 와 동일 turn 에서 활성화하는 것이 비용 효율적이다.
