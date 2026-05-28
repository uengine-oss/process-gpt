# E2E 시나리오 01: 서비스 작업 MCP 도구 자동 실행 성공

## 메타데이터
- 스위트 슬러그: `completion_automated-task-execution`
- 원본 명세 ID: `completion_automated-task-execution`
- 시나리오 ID: `01`
- Playwright 테스트 제목: `서비스 작업 워크아이템이 MCP 도구로 자동 실행되고 다음 활동으로 진행한다`
- 원본 명세:
  - `openspec/specs/completion_automated-task-execution/spec.md`

## 목적
사용자가 자동 실행 활동을 포함한 프로세스 인스턴스를 시작했을 때, 폴링 워커가 `serviceTask` 워크아이템을 자동으로 감지하여 테넌트에 설정된 MCP 도구를 호출하고 그 결과를 워크아이템 `output`/`log` 에 기록한 뒤 다음 활동으로 진행하는 사용자 경험을 검증한다.

## 사전 조건
- `db`, `kong`, `auth`, `rest`, `mock-llm`, `mock-mcp`, `completion`(FastAPI), `completion-polling`(폴링 워커), `frontend`, `gateway` 컨테이너가 모두 정상.
- 시드: `proc_def` 에 `serviceTask`(MCP 호출) + 후속 `userTask` 가 정의된 자동 실행 데모 프로세스, `configuration.mcpServers` 에 mock-mcp 도구 등록, `users`/`tenants` E2E 로그인 계정.
- mock-mcp 는 결정적 응답을 반환한다: `{"status":"success","connection_type":"stdio","data":{...}}`.
- 사용자는 frontend 로그인 후 todolist 화면에서 진행 중인 프로세스 인스턴스를 관찰할 수 있다.

## 테스트 데이터 및 Stub
| 이름 | 유형 | 경로 또는 route | 목적 |
| --- | --- | --- | --- |
| `e2e_seed.sql` | seed | `openspec/specs/completion_automated-task-execution/e2e/seed_files/e2e_seed.sql` | proc_def/tenant/mcpServers/proc_inst/workitem 시드 |
| `mock_mcp.py` | stub server | `openspec/specs/completion_automated-task-execution/e2e/scripts/mock_mcp.py` | MCP stdio/sse 결정적 응답 |
| `mock_llm.py` (재사용) | stub server | `openspec/specs/completion_agent-memory-chat/e2e/scripts/mock_llm.py` | LangChain agent LLM 호출 결정성 |

## 절차
1. 사용자는 `/login` 화면에서 E2E 계정으로 로그인한다.
2. 사용자는 메인 사이드바에서 todolist(또는 진행 중 프로세스) 화면으로 이동한다.
3. 사용자는 자동 실행 데모 프로세스 인스턴스 카드를 연다.
4. 사용자는 `serviceTask` 워크아이템 카드를 확인한다 (초기 상태 `SUBMITTED`/실행 중 메시지).
5. 사용자는 잠시 대기 후 화면 새로고침 또는 자동 갱신을 통해 상태 변화를 확인한다.
6. 사용자는 `DONE` 으로 전이된 워크아이템의 결과 로그와 다음 활동(`userTask` 등) 등장 여부를 확인한다.

## 기대 결과
- 워크아이템 상태가 `SUBMITTED` → `DONE` 으로 전이되어 UI 에 노출된다.
- 워크아이템 `log` 에 `모든 MCP 도구 실행 완료: <tool> (<connection_type>): 성공` 메시지가 표시된다.
- 워크아이템 `output` 에 mock-mcp 의 도구 결과가 JSON 으로 기록되어 있다 (UI 또는 supplementary API 검증).
- 다음 활동의 워크아이템이 todolist 에 노출되어 프로세스가 진행되었음을 확인할 수 있다.

## 커버하는 요구사항
| 명세 | 요구사항 | 시나리오 |
| --- | --- | --- |
| `completion_automated-task-execution` | 서비스 작업의 MCP 도구 실행 | 서비스 작업 도구 실행 성공 |

## 산출물
- 스크린샷 체크포인트:
  | 체크포인트 | 캡처할 UI 상태 | 예상 파일 | 매뉴얼용 캡션 |
  | --- | --- | --- | --- |
  | `01-login` | E2E 로그인 직후 메인 화면 | `process-gpt-completion_automated-task-execution-01-login.png` | 자동 실행 데모 시작 전 사용자 로그인 화면 |
  | `01-todolist-initial` | 자동 실행 프로세스 진입 직후 `serviceTask` 워크아이템이 실행 중인 상태 | `process-gpt-completion_automated-task-execution-01-todolist-initial.png` | 서비스 작업이 백엔드에서 자동으로 처리되기 시작한 모습 |
  | `01-service-task-done` | `serviceTask` 가 `DONE` 으로 전이되어 결과 로그가 표시된 상태 | `process-gpt-completion_automated-task-execution-01-service-task-done.png` | MCP 도구가 성공적으로 실행되어 결과가 워크아이템에 기록된 모습 |
  | `01-next-activity-shown` | 후속 활동의 워크아이템이 노출된 상태 | `process-gpt-completion_automated-task-execution-01-next-activity-shown.png` | 자동 실행 이후 다음 활동으로 프로세스가 진행된 모습 |
- Trace/video: Playwright 실패 시 보존됩니다.
- 결과 JSON: `openspec/specs/completion_automated-task-execution/e2e/results/results.json`
