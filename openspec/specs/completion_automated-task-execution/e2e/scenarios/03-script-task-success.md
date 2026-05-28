# E2E 시나리오 03: 스크립트 작업 코드 실행 성공

## 메타데이터
- 스위트 슬러그: `completion_automated-task-execution`
- 원본 명세 ID: `completion_automated-task-execution`
- 시나리오 ID: `03`
- Playwright 테스트 제목: `스크립트 작업이 정상 종료되면 stdout 이 결과로 기록되고 트리거 워크아이템이 DONE 으로 전이된다`
- 원본 명세:
  - `openspec/specs/completion_automated-task-execution/spec.md`

## 목적
사용자가 자동 실행 활동을 포함한 프로세스를 시작했을 때, 폴링 워커가 `userTask` 선행 활동을 처리한 직후 후속 `scriptTask` 의 파이썬 코드를 `_execute_script_tasks` 로 inline 실행하고 stdout 을 결과로 기록하는 동작을 검증한다. (`scriptTask` 는 `handle_workitem` 의 LangChain 완료 판정 파이프라인 뒤에서 다음 활동으로서만 실행되는 구조이므로, userTask 선행을 시드하여 자동 실행 경로를 트리거한다.)

## 사전 조건
- `db`, `kong`, `auth`, `rest`, `mock-llm-ate`, `completion-polling`, `frontend`, `gateway` 컨테이너가 정상.
- 시드: `proc_def ate_script_03_proc` (startEvent → `act_setup_03`(userTask) → `act_script_03`(scriptTask) → endEvent), `bpm_proc_inst` 의 role_bindings 에 `everyone` 역할이 사용자 UUID 와 매핑되어 있어 `check_role_binding` 의 LLM 폴백을 회피.
- `act_script_03` 의 pythonCode 는 결정적으로 stdout 에 `ate-script-03-result:E2E-1001` 를 출력하고 `/coverage/ate_script_03.out` 파일에 기록한 뒤 `sys.exit(0)`.
- `act_setup_03` workitem 은 `consumer='hold-test-03'` 으로 reservation 된 상태로 시드되며, 테스트 시작 시 docker exec 로 `consumer=null` 해제.

## 테스트 데이터 및 Stub
| 이름 | 유형 | 경로 또는 route | 목적 |
| --- | --- | --- | --- |
| `e2e_seed.sql` (확장) | seed | `openspec/specs/completion_automated-task-execution/e2e/seed_files/e2e_seed.sql` | proc_def 03 + bpm_proc_inst + userTask workitem 시드 |
| `mock_llm.py` (extended) | stub server | `openspec/specs/completion_automated-task-execution/e2e/scripts/mock_llm.py` | 도구 없는 chat completion 요청에 generic JSON 응답 반환 (CustomJsonOutputParser 호환) |
| `/coverage/ate_script_03.out` | 부수효과 파일 | `openspec/specs/completion_automated-task-execution/e2e/results/backend-coverage/ate_script_03.out` | pythonCode 실행 결정적 증거 |

## 절차
1. 사용자는 `/login` 화면에서 ATE 계정으로 로그인한다.
2. 사용자는 사이드바에서 `/todolist` 칸반 보드로 이동한다.
3. 사용자는 `진행 중` 컬럼에 `스크립트 03 트리거` 워크아이템이 노출되는 것을 확인한다.
4. 사용자는 잠시 대기 후 화면 새로고침으로 워크아이템이 `완료됨` 컬럼으로 이동한 것을 확인한다.
5. 사용자는 백엔드에서 자동 실행된 scriptTask 의 결과 파일(`/coverage/ate_script_03.out`) 이 stdout 마커를 담고 있는 것을 supplementary 검증으로 확인한다.

## 기대 결과
- `스크립트 03 트리거` workitem 이 `/todolist` 칸반의 `완료됨` 컬럼으로 이동한다.
- 폴링 워커 컨테이너에서 `_execute_script_tasks` 가 호출되어 pythonCode 가 실행된다.
- `/coverage/ate_script_03.out` 에 `ate-script-03-result:E2E-1001` 가 기록된다.
- polling worker 의 stdout 로그에 `ate-script-03-result:E2E-1001` 가 출력된다.

## 커버하는 요구사항
| 명세 | 요구사항 | 시나리오 |
| --- | --- | --- |
| `completion_automated-task-execution` | 스크립트 작업의 코드 실행 | 스크립트 작업 코드 실행 성공 |

## 산출물
- 스크린샷 체크포인트:
  | 체크포인트 | 캡처할 UI 상태 | 예상 파일 | 매뉴얼용 캡션 |
  | --- | --- | --- | --- |
  | `03-script-result` | `스크립트 03 트리거` 워크아이템이 `완료됨` 컬럼에 위치한 모습 | `process-gpt-completion_automated-task-execution-03-script-result.png` | 사용자 트리거 활동이 완료되어 scriptTask 가 백엔드에서 자동 실행된 모습 |
- Trace/video: Playwright 실패 시 보존됩니다.
- 결과 JSON: `openspec/specs/completion_automated-task-execution/e2e/results/results.json`
- 부수효과 파일: `openspec/specs/completion_automated-task-execution/e2e/results/backend-coverage/ate_script_03.out`
