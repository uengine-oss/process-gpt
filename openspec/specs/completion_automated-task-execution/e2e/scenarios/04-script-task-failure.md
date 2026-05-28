# E2E 시나리오 04: 스크립트 작업 코드 실행 실패

## 메타데이터
- 스위트 슬러그: `completion_automated-task-execution`
- 원본 명세 ID: `completion_automated-task-execution`
- 시나리오 ID: `04`
- Playwright 테스트 제목: `스크립트 작업이 비정상 종료되면 stderr 가 결과로 기록되고 트리거 워크아이템이 DONE 으로 전이된다`
- 원본 명세:
  - `openspec/specs/completion_automated-task-execution/spec.md`

## 목적
폴링 워커가 `userTask` 선행 직후 후속 `scriptTask` 의 파이썬 코드를 실행하다 비정상 종료(`sys.exit(1)`) 했을 때, `_execute_script_tasks` 가 `result.stderr` 를 결과로 기록하고 `find_next_activities` 로 다음(오류) 활동 ID 를 `current_activity_ids` 에 반영하는 동작을 검증한다.

## 사전 조건
- 시나리오 03 과 동일한 stack.
- 시드: `proc_def ate_script_04_proc` (startEvent → `act_setup_04`(userTask) → `act_script_04`(scriptTask, sys.exit(1)) → endEvent).
- `act_script_04` 의 pythonCode 는 stderr 에 `ate-script-04-error:boom` 를 출력하고 `/coverage/ate_script_04.err` 파일에 기록한 뒤 `sys.exit(1)`.

## 테스트 데이터 및 Stub
| 이름 | 유형 | 경로 또는 route | 목적 |
| --- | --- | --- | --- |
| `e2e_seed.sql` (확장) | seed | `openspec/specs/completion_automated-task-execution/e2e/seed_files/e2e_seed.sql` | proc_def 04 + bpm_proc_inst + userTask workitem 시드 |
| `/coverage/ate_script_04.err` | 부수효과 파일 | `openspec/specs/completion_automated-task-execution/e2e/results/backend-coverage/ate_script_04.err` | 비정상 종료 결정적 증거 |

## 절차
1. 사용자는 `/login` 으로 로그인한다.
2. 사용자는 `/todolist` 칸반 보드로 이동한다.
3. 사용자는 `스크립트 04 트리거` workitem 이 `완료됨` 으로 이동한 것을 확인한다.
4. 사용자는 백엔드 부수효과 파일(`/coverage/ate_script_04.err`) 이 stderr 마커를 담고 있는 것을 supplementary 검증으로 확인한다.

## 기대 결과
- `스크립트 04 트리거` workitem 이 `완료됨` 컬럼으로 이동한다.
- 폴링 워커가 `_execute_script_tasks` 의 `returncode != 0` 분기를 실행한다.
- `/coverage/ate_script_04.err` 에 `ate-script-04-error:boom` 가 기록된다.

## 커버하는 요구사항
| 명세 | 요구사항 | 시나리오 |
| --- | --- | --- |
| `completion_automated-task-execution` | 스크립트 작업의 코드 실행 | 스크립트 작업 코드 실행 실패 |

## 산출물
- 스크린샷 체크포인트:
  | 체크포인트 | 캡처할 UI 상태 | 예상 파일 | 매뉴얼용 캡션 |
  | --- | --- | --- | --- |
  | `04-script-error` | `스크립트 04 트리거` 워크아이템이 `완료됨` 컬럼에 위치한 모습 | `process-gpt-completion_automated-task-execution-04-script-error.png` | 사용자 트리거 활동이 완료되어 비정상 종료 scriptTask 가 백엔드에서 자동 실행된 모습 |
- Trace/video: Playwright 실패 시 보존됩니다.
- 결과 JSON: `openspec/specs/completion_automated-task-execution/e2e/results/results.json`
- 부수효과 파일: `openspec/specs/completion_automated-task-execution/e2e/results/backend-coverage/ate_script_04.err`
