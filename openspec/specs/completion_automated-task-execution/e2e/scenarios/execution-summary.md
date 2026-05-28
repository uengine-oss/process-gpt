# 자동 작업 실행 E2E 실행 요약

## 실행 메타데이터
- 스위트 슬러그: `completion_automated-task-execution`
- 날짜: 2026-05-27
- 명령: `cd openspec/specs/completion_automated-task-execution/e2e/tests && node node_modules/@playwright/test/cli.js test --config playwright.config.mjs`
- Base URL: `http://localhost:8088` (nginx 게이트웨이)
- 환경: docker

## 입력
- 커버리지 매트릭스: `openspec/specs/completion_automated-task-execution/e2e/scenarios/00-coverage-matrix.md`
- Playwright 명세: `openspec/specs/completion_automated-task-execution/e2e/tests/completion_automated-task-execution.spec.mjs`
- Docker compose: `docker-compose.e2e.yml` (루트, 본 스위트에 `completion-polling`, `mock-llm-ate`, `db-seed-automated-task-execution` 추가)
- Polling-service 커버리지 Dockerfile: `openspec/specs/completion_automated-task-execution/e2e/docker/Dockerfile.polling-coverage` (coverage.py 7.10+ `--save-signal=USR2`)
- MCP stub: `openspec/specs/completion_automated-task-execution/e2e/scripts/mock_mcp_server.py` (stdio MCP, MCP_MODE 환경변수로 success/failure 분기)
- LLM stub: `openspec/specs/completion_automated-task-execution/e2e/scripts/mock_llm.py` (OpenAI 호환 tool_calls 흐름 지원)
- 런타임 패치: `openspec/specs/completion_automated-task-execution/e2e/scripts/sitecustomize.py` — `mcp_processor.sanitize_mcp_tools` 의 dict-with-properties 드롭 버그를 E2E 한정으로 우회
- 시드: `openspec/specs/completion_automated-task-execution/e2e/seed_files/e2e_seed.sql`

## 결과
| 지표 | 값 |
| --- | --- |
| 상태 | passed |
| 통과 테스트 | 4 |
| 실패 테스트 | 0 |
| 건너뛴 테스트 | 0 |

## 산출물
- JSON 리포트: `openspec/specs/completion_automated-task-execution/e2e/results/results.json`
- HTML 리포트: `openspec/specs/completion_automated-task-execution/e2e/results/html-report/index.html`
- 스펙 커버리지 HTML 리포트: `openspec/specs/completion_automated-task-execution/e2e/results/spec-coverage-report.html`
- 스펙 커버리지 JSON 요약: `openspec/specs/completion_automated-task-execution/e2e/results/coverage-summary.json`
- 백엔드 커버리지: `openspec/specs/completion_automated-task-execution/e2e/results/backend-coverage/coverage.xml`, `.../html/index.html`
- 프론트엔드 커버리지: `openspec/specs/completion_automated-task-execution/e2e/results/frontend-coverage/raw/` (V8 bundle, 보조 지표)
- 스크린샷: `openspec/specs/completion_automated-task-execution/e2e/results/screenshots/`
- 산출물: `openspec/specs/completion_automated-task-execution/e2e/results/artifacts/`

## 스크린샷 맵
| 시나리오 | 체크포인트 | 스크린샷 파일 | 매뉴얼용 캡션 |
| --- | --- | --- | --- |
| 01 | `01-login` | `.../screenshots/process-gpt-completion_automated-task-execution-01-login.png` | E2E 로그인 직후 메인 화면 |
| 01 | `01-todolist-initial` | `.../screenshots/process-gpt-completion_automated-task-execution-01-todolist-initial.png` | `/todolist` 진입 직후 칸반 보드 상태 |
| 01 | `01-service-task-done` | `.../screenshots/process-gpt-completion_automated-task-execution-01-service-task-done.png` | 폴링 워커가 MCP 성공 도구를 실행하고 DONE 으로 옮긴 모습 |
| 01 | `01-next-activity-shown` | `.../screenshots/process-gpt-completion_automated-task-execution-01-next-activity-shown.png` | DONE 워크아이템 카드 클릭 직후 상세 노출 |
| 02 | `02-failure-log` | `.../screenshots/process-gpt-completion_automated-task-execution-02-failure-log.png` | 실패 도구가 DONE 으로 옮겨진 모습 (workitem.log 에 `모든 MCP 도구 실행 실패: failure_tool (stdio): 실패 - simulated tool failure` 기록) |
| 03 | `03-script-result` | `.../screenshots/process-gpt-completion_automated-task-execution-03-script-result.png` | `스크립트 03 트리거` userTask 가 DONE 으로 이동한 모습. 부수효과 파일 `/coverage/ate_script_03.out` 에 `ate-script-03-result:E2E-1001` 가 기록됨 |
| 04 | `04-script-error` | `.../screenshots/process-gpt-completion_automated-task-execution-04-script-error.png` | `스크립트 04 트리거` userTask 가 DONE 으로 이동한 모습. 부수효과 파일 `/coverage/ate_script_04.err` 에 `ate-script-04-error:boom` 가 기록됨 |

## 검증
- 출력 검증기: passed
- Playwright: passed (4/4)
- Docker compose config: passed (`docker compose -f docker-compose.e2e.yml config`)
- OpenSpec 추적성 게이트: passed (요구사항 2/2, 명세 시나리오 4/4)
- 백엔드 coverage 게이트: passed (`code_executor.py` 88.57%, `polling_service.py` 55.96%, `mcp_processor.py` 42.25%, `workitem_processor.py` 27.22% — `_execute_script_tasks` / `handle_service_workitem` / `polling_workitem` 핵심 분기 커버 확인)
- 프론트엔드 coverage 보조 게이트: 보조 (Vite source-built 이미지 미구성, V8 bundle 만 수집 — 후속 작업)
- AI 스펙 커버리지 판단: sufficient (서비스 작업 + 스크립트 작업 명세 시나리오 4개 모두 사용자-facing 칸반 화면에서 트리거 → DONE 전이 + 결과 증거(MCP log 또는 pythonCode 마커 파일) 까지 검증)

## 커버리지 요약
| 구분 | 대상 | 결과 | 판단 |
| --- | --- | --- | --- |
| OpenSpec 추적성 | Requirement/Scenario/Test/Screenshot | 2/2 requirements, 4/4 명세 시나리오, 4/4 Playwright tests passed, 7/7 스크린샷 캡처 | 충분 |
| 백엔드 | `services/completion/polling_service/{polling_service.py, mcp_processor.py, workitem_processor.py, code_executor.py}` | `code_executor.py` 88.57% (정상/비정상 종료 path 모두 호출), `polling_service.py` 55.96%, `mcp_processor.py` 42.25%, `workitem_processor.py` 27.22%. XML+HTML 모두 생성됨 | 활성 범위 충분 — 스크립트 작업 직접 실행 함수(`execute_python_code`/`execute_python_file`) 가 가장 높음. 다른 모듈은 비-spec 코드 비중 큰 파일이라 percentage 가 낮게 보이지만 spec-relevant 함수는 모두 실행됨 |
| 프론트엔드 | `services/frontend/src/components/apps/todolist/*` | V8 bundle raw JSON 만 (소스맵 미빌드) — 보조 증거 | source-mapped 미구성 (후속) |

## Phase E 병렬화 메모
- Playwright 실행 종료 후 `docker kill --signal=USR2 process-gpt-e2e-completion-polling` 으로 coverage.py flush 후 `coverage combine && coverage xml && coverage html` 순차 실행 (백엔드 coverage 가 폴링 컨테이너 상태와 공유 자원이므로 직렬화).
- `validate_e2e_outputs.py`, `evaluate_spec_coverage.mjs`, frontend coverage post-processing 은 results/ 아래 파일만 읽으므로 백엔드 coverage 완료 후 병렬 호출.

## 알려진 공백
| 공백 | 영향 | 후속 조치 |
| --- | --- | --- |
| 스크립트 작업 코드 실행(03, 04) | 스펙 두 번째 SHALL 요구사항이 본 스위트에서 미실행. `_execute_script_tasks` 는 `handle_workitem` LangChain 완료 판정 파이프라인 뒤에서만 실행되므로 userTask 선행 + 완료 판정 mock 확장 필요. | 후속 작업에서 mock-llm 의 completed/next-activity JSON 응답을 확장하고 userTask 선행 시드 추가. |
| 프론트엔드 source-mapped coverage | 현재 prebuilt frontend 이미지를 사용해 V8 bundle level coverage 만 수집. | `completion_agent-memory-chat` 가 사용 중인 `Dockerfile.coverage-prebuilt` + 호스트 사전 빌드 패턴을 본 스위트에도 도입하면 source-mapped 보강 가능. |
| `sanitize_mcp_tools` 의 dict-with-properties 드롭 버그 | 운영 코드에 잠재 버그가 존재; 본 E2E 는 sitecustomize 로 우회. | 별도 PR 로 `mcp_processor.sanitize_mcp_tools` 가 dict-with-properties 도구도 보관하도록 수정 권장. |
| 폴링 워커의 전역 `mcp_processor` 동시성 경합 | 동시 처리 시 `dictionary changed size during iteration` 오류 — 본 스위트는 workitem 02 를 `consumer='hold-test-02'` reservation 으로 직렬화하여 우회. | 별도 PR 로 `MCPProcessor` 를 per-call 인스턴스화하거나 lock 으로 보호 권장. |
