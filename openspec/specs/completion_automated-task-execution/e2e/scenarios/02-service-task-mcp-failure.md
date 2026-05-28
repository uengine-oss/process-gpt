# E2E 시나리오 02: 서비스 작업 MCP 도구 실패 기록

## 메타데이터
- 스위트 슬러그: `completion_automated-task-execution`
- 원본 명세 ID: `completion_automated-task-execution`
- 시나리오 ID: `02`
- Playwright 테스트 제목: `MCP 도구가 실패하면 워크아이템 로그에 실패 내역이 기록된다`
- 원본 명세:
  - `openspec/specs/completion_automated-task-execution/spec.md`

## 목적
폴링 워커가 `serviceTask` 워크아이템을 실행하다가 일부 또는 전체 MCP 도구가 실패했을 때, 사용자가 todolist 화면에서 어떤 도구가 어떤 오류로 실패했는지 확인할 수 있어야 한다. 이는 자동 실행 결과의 추적 가능성을 보장한다.

## 사전 조건
- 시나리오 01 과 동일한 stack.
- mock-mcp 가 특정 도구에 대해 결정적으로 실패 응답을 반환하도록 두 번째 도구를 시드한다. 응답 예: `{"status":"error","connection_type":"stdio","error":"simulated tool failure"}`.
- 시드: `serviceTask` 활동의 `tools` 에 두 개 이상의 도구를 등록하고 두 번째 도구를 실패하도록 mock-mcp 설정.

## 테스트 데이터 및 Stub
| 이름 | 유형 | 경로 또는 route | 목적 |
| --- | --- | --- | --- |
| `e2e_seed.sql` (재사용) | seed | `openspec/specs/completion_automated-task-execution/e2e/seed_files/e2e_seed.sql` | 실패 도구를 포함한 활동 정의 |
| `mock_mcp.py` | stub server | `openspec/specs/completion_automated-task-execution/e2e/scripts/mock_mcp.py` | 도구별 분기 응답 (성공/실패) |

## 절차
1. 사용자는 E2E 계정으로 로그인하고 todolist 화면에 진입한다.
2. 사용자는 실패 도구를 포함한 자동 실행 데모 프로세스 인스턴스를 연다.
3. 사용자는 `serviceTask` 워크아이템이 자동 실행되어 결과 로그가 표시될 때까지 대기한다.
4. 사용자는 워크아이템 카드의 로그 영역을 열어 실패한 도구와 오류 메시지를 확인한다.

## 기대 결과
- 워크아이템 `log` 에 `일부 MCP 도구 실행 완료: ...` 또는 `모든 MCP 도구 실행 실패: ...` 형태의 메시지가 표시되고, 실패한 도구 이름과 `simulated tool failure` 오류가 포함되어 있다.
- 워크아이템 `output` 에 실패한 도구의 오류 정보가 포함된다.
- 사용자 UI 에서 실패 도구를 식별할 수 있는 형태로 로그가 노출된다.

## 커버하는 요구사항
| 명세 | 요구사항 | 시나리오 |
| --- | --- | --- |
| `completion_automated-task-execution` | 서비스 작업의 MCP 도구 실행 | 도구 실행 실패 기록 |

## 산출물
- 스크린샷 체크포인트:
  | 체크포인트 | 캡처할 UI 상태 | 예상 파일 | 매뉴얼용 캡션 |
  | --- | --- | --- | --- |
  | `02-failure-log` | 실패한 MCP 도구 이름과 오류 메시지가 표시된 워크아이템 로그 | `process-gpt-completion_automated-task-execution-02-failure-log.png` | MCP 도구 실패 시 사용자 화면에서 확인할 수 있는 오류 기록 |
- Trace/video: Playwright 실패 시 보존됩니다.
- 결과 JSON: `openspec/specs/completion_automated-task-execution/e2e/results/results.json`
