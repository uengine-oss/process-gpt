# 자동 작업 실행 E2E 커버리지 매트릭스

## 범위
- 스위트 슬러그: `completion_automated-task-execution`
- 원본 명세 ID: `completion_automated-task-execution`
- 원본 명세:
  - `openspec/specs/completion_automated-task-execution/spec.md`
- 백엔드/제품 계약:
  - `services/completion/polling_service` 폴링 워커: `polling_service.safe_handle_workitem`, `workitem_processor.handle_service_workitem`, `workitem_processor._execute_script_tasks`
  - MCP 도구 실행: `mcp_processor.MCPProcessor.execute_mcp_tools` (테넌트 MCP 설정 → 도구 호출 → 결과 dict 반환)
  - 스크립트 실행: `code_executor.execute_python_code` (subprocess `python` 실행, stdout/stderr 반환)
  - 데이터: `todolist` 워크아이템 (`status`, `output`, `log`), `bpm_proc_inst` 진행, `proc_def`/`proc_def_version` (`serviceTask`/`scriptTask` activity), `configuration.mcpServers` 테넌트 MCP 설정
  - 외부 boundary: MCP 서버 (E2E에서는 `mock-mcp` 컨테이너로 결정성 확보), LLM 프록시 (E2E에서는 기존 `mock-llm` 재사용해 도구 호출 결정성 확보)
- E2E 루트: `openspec/specs/completion_automated-task-execution/e2e/`
- Playwright 명세: `openspec/specs/completion_automated-task-execution/e2e/tests/completion_automated-task-execution.spec.mjs`
- 결과 디렉터리: `openspec/specs/completion_automated-task-execution/e2e/results/`

## 재사용 산출물
- `docker-compose.e2e.yml`: 기존 `db`, `kong`, `auth`, `rest`, `mock-llm`, `completion`, `frontend`, `gateway`, `db-seed-*` 패턴을 그대로 사용합니다.
- `openspec/specs/completion_agent-memory-chat/e2e/docker/nginx.e2e.conf`: 게이트웨이 라우팅 규칙 (필요 시 todolist API 경로 추가만 후속 작업).
- `openspec/specs/completion_agent-memory-chat/e2e/scripts/mock_llm.py`: serviceTask MCP 실행 시 LangChain agent 가 사용하는 LLM 호출 결정성 확보.
- 메모리: [[coverage-py-usr2-flush]] (폴링 워커 long-running coverage flush), [[mem0-vecs-table-reinit]] (db 재시작 후 vecs 초기화), [[spa-http-server-port-8080]] (프론트엔드 게이트웨이 포트).

## 시나리오 목록
| ID | 시나리오 문서 | Playwright 테스트 제목 | 주요 동작 |
| --- | --- | --- | --- |
| 01 | `01-service-task-mcp-success.md` | `서비스 작업 워크아이템이 MCP 도구로 자동 실행되고 결과가 DONE 으로 기록된다` | UI: `/login` → `/todolist` 에서 `serviceTask` 워크아이템이 IN_PROGRESS → DONE 으로 이동, 결과 로그 노출 |
| 02 | `02-service-task-mcp-failure.md` | `MCP 도구가 실패하면 워크아이템 로그에 실패 내역이 기록된다` | UI: 동일 화면에서 실패 도구를 가진 두 번째 워크아이템이 DONE 으로 이동, 로그에 실패 도구·오류 표시 |
| 03 | `03-script-task-success.md` | `스크립트 작업이 정상 종료되면 stdout 이 결과로 기록되고 트리거 워크아이템이 DONE 으로 전이된다` | UI: `/todolist` 의 `스크립트 03 트리거` userTask 가 DONE 으로 이동하고 후속 scriptTask 가 inline 실행되어 stdout 마커 파일이 생성됨 |
| 04 | `04-script-task-failure.md` | `스크립트 작업이 비정상 종료되면 stderr 가 결과로 기록되고 트리거 워크아이템이 DONE 으로 전이된다` | UI: `/todolist` 의 `스크립트 04 트리거` userTask 가 DONE 으로 이동하고 후속 scriptTask (sys.exit(1)) 가 stderr 마커 파일을 생성함 |

> 본 스위트의 사용자 검증 표면은 frontend `/todolist` 화면(KanbanBoard) 입니다. 폴링 워커는 백엔드에서 자동 실행되며, 사용자는 워크아이템이 SUBMITTED/IN_PROGRESS 컬럼에서 DONE 컬럼으로 이동하는 것과 결과 로그를 관찰합니다. 시나리오 01/02 의 워크아이템 `user_id` 는 `<agent>,<human-user>` 콤마 결합 형식으로 시드되어 폴링 워커는 에이전트로 인식하고, 프론트엔드는 `user_id LIKE %<human-user>%` 필터로 동일 워크아이템을 사용자 시야에 노출합니다.

> 시나리오 03/04 의 `scriptTask` 는 `services/completion/polling_service/workitem_processor.py:handle_workitem` 의 LangChain 완료/다음활동 판정 파이프라인을 거쳐 `_execute_script_tasks` 가 *다음* 활동으로서 inline 실행하는 구조입니다. 본 스위트는 userTask 선행(`act_setup_03/04`)을 시드하여 폴링 워커가 그 path 를 실제로 타도록 하며, mock-llm-ate 가 도구 없는 chat completion 요청에 generic JSON 응답을 반환해 LangChain 파이프라인이 결정적으로 끝나도록 합니다. scriptTask 결과의 결정적 증거는 pythonCode 가 컨테이너의 `/coverage/ate_script_0(3|4).(out|err)` 마커 파일에 stdout/stderr 를 기록하는 부수효과로 검증합니다.

## 요구사항 커버리지
| 명세 | 요구사항 | 필수 수준 | 커버 시나리오 | 비고 |
| --- | --- | --- | --- | --- |
| `completion_automated-task-execution` | 서비스 작업의 MCP 도구 실행 | SHALL | 01, 02 | 도구 실행 성공/실패 모두 검증 |
| `completion_automated-task-execution` | 스크립트 작업의 코드 실행 | SHALL | 03, 04 | userTask 선행 + scriptTask inline 실행 (stdout/stderr 마커 파일 검증) |

## 명세 시나리오 커버리지
| 명세 | 요구사항 | 명세 시나리오 | 커버 시나리오 | 사용자 검증 표면 |
| --- | --- | --- | --- | --- |
| `completion_automated-task-execution` | 서비스 작업의 MCP 도구 실행 | 서비스 작업 도구 실행 성공 | 01 | todolist 워크아이템 상태/`output`/`log` 노출 |
| `completion_automated-task-execution` | 서비스 작업의 MCP 도구 실행 | 도구 실행 실패 기록 | 02 | todolist 워크아이템 `log` 에 실패 도구·오류 메시지 노출 |
| `completion_automated-task-execution` | 스크립트 작업의 코드 실행 | 스크립트 작업 코드 실행 성공 | 03 | `스크립트 03 트리거` userTask DONE + pythonCode 의 `/coverage/ate_script_03.out` 마커 파일 |
| `completion_automated-task-execution` | 스크립트 작업의 코드 실행 | 스크립트 작업 코드 실행 실패 | 04 | `스크립트 04 트리거` userTask DONE + pythonCode 의 `/coverage/ate_script_04.err` 마커 파일 |

## 스펙 관련 코드 표면
### 백엔드
| 파일 | 함수/클래스/라우트 | 관련 요구사항 | 커버리지 기준 | 선정 근거 |
| --- | --- | --- | --- | --- |
| `services/completion/polling_service/polling_service.py` | `safe_handle_workitem`, `polling_workitem` | 양쪽 요구사항 | line >= 70% | 폴링 진입점, `serviceTask`/`scriptTask` 분기 |
| `services/completion/polling_service/workitem_processor.py` | `handle_service_workitem` | 서비스 작업 실행 | line >= 70%, branch >= 60% | MCP 결과 정리 / `output` 기록 / `DONE` 전이 핵심 분기 |
| `services/completion/polling_service/workitem_processor.py` | `_execute_script_tasks` | 스크립트 작업 실행 | line >= 80%, branch >= 70% | `returncode` 분기로 stdout/stderr 와 다음 활동 결정 |
| `services/completion/polling_service/workitem_processor.py` | `_check_service_tasks` | 서비스 작업 실행 | function = 100% | 다음 `serviceTask` 워크아이템을 `SUBMITTED` 로 승격 |
| `services/completion/polling_service/mcp_processor.py` | `MCPProcessor.get_mcp_tools_from_tenant`, `initialize_mcp_client`, `execute_mcp_tools` | 서비스 작업 실행 | line >= 70% | 테넌트 MCP 설정 로딩과 도구 호출 핵심 경로 |
| `services/completion/polling_service/code_executor.py` | `execute_python_code`, `execute_python_file` | 스크립트 작업 실행 | line >= 70% | 03/04 시나리오에서 호출 (정상/비정상 종료 양쪽) |
| `services/completion/polling_service/workitem_processor.py` | `_execute_script_tasks` | 스크립트 작업 실행 | branch >= 60% | `returncode != 0` 분기로 stdout/stderr 와 다음 활동 결정 |
| `services/completion/polling_service/workitem_processor.py` | `run_completed_determination`, `resolve_next_activity_payloads` | 스크립트 작업 실행 | line >= 50% | userTask 완료 판정 → scriptTask next 결정 (pure Python) |

### 프론트엔드
| 파일 | 컴포넌트/함수/API 호출 | 관련 요구사항 | 커버리지 기준 | 선정 근거 |
| --- | --- | --- | --- | --- |
| `services/frontend/src/components/apps/todolist/TodolistCard.vue` | 워크아이템 목록/상태 표시 | 양쪽 요구사항 | line >= 50% | 사용자가 자동 실행 결과를 관찰하는 1차 화면 |
| `services/frontend/src/components/apps/todolist/WorkItem.vue` | 워크아이템 상태/로그/결과 표시 | 양쪽 요구사항 | line >= 50% | `status`/`log`/`output` 가 사용자에게 노출되는 컴포넌트 |
| `services/frontend/src/components/ProcessInstanceRunning.vue` | 진행 중 프로세스 활동 표시 | 양쪽 요구사항 | line >= 30% | 다음 활동 전이가 사용자에게 보이는 표면 |

> 프론트엔드 source-mapped 커버리지는 기존 `completion_agent-memory-chat` 의 `Dockerfile.coverage-prebuilt` + 호스트 사전 빌드 패턴을 재사용합니다. 소스맵이 가능하지 않은 경로일 경우 Monocart V8 번들 커버리지를 보조 지표로 사용하고 그 한계를 보고서에 명시합니다.

## 미검증 및 보류 항목
| 항목 | 사유 | 후속 조치 |
| --- | --- | --- |
| 다중 도구 부분 실패 분기 | 본 스위트는 단일 도구 성공/실패 시나리오만 커버 | 향후 multi-tool 시나리오 추가 (success_count > 0 && error_count > 0) |
| handle_workitem 의 `timedelta NoneType` post-processing 오류 | 시나리오 03/04 에서 scriptTask 는 성공적으로 실행되지만 이후 post-processing(`_persist_process_data` 또는 후속 LangChain 호출) 에서 None timedelta 오류 → workitem 이 3회 재시도 후 `[Error]` 메시지와 함께 DONE 처리됨. scriptTask 실행 자체는 첫 시도에서 완료(/coverage 마커 파일로 증명). | 별도 PR 로 polling worker 의 timedelta None 가드 추가 권장 |

## 체크리스트
- [x] 모든 Requirement가 하나 이상의 E2E 시나리오에 매핑되어 있습니다.
- [x] 중요한 OpenSpec Scenario가 E2E 시나리오에 매핑되어 있거나 미검증 및 보류 항목에 기록되어 있습니다.
- [x] 사람이 읽는 요구사항명, 명세 시나리오명, 목적, 절차, 기대 결과는 한국어로 작성되어 있습니다.
- [x] 원본 OpenSpec에 영어 설명이 있더라도 E2E 문서에는 한국어 의미로 변환되어 있으며, API 경로·필드명·이벤트명 같은 계약 식별자만 원문으로 유지합니다.
- [x] 원본 명세가 하나의 백엔드 연계 피쳐 또는 응집된 사용자 workflow 범위이며, 마이크로서비스 전체 요약이나 프론트엔드 단독 명세가 아닙니다.
- [x] 원본 명세의 서비스 접두어 또는 도메인 구분자가 `frontend`, `ui`, `react`, `page`, `component` 같은 구현 레이어가 아닙니다.
- [x] E2E가 실행할 소유 백엔드 서비스/API/데이터 계약이 명확합니다 (polling worker + DB + tenant mcp config).
- [x] 서비스 접두형 명세 ID를 사용하는 경우 스위트 슬러그가 동일한 값을 유지합니다.
- [x] E2E 시나리오, 테스트 스크립트, seed/stub, 실행 결과, 스크린샷은 `openspec/specs/completion_automated-task-execution/e2e/` 아래에 응집되어 있습니다.
- [x] 사용자-facing 시나리오는 직접 API 요청이 아니라 브라우저 UI 상호작용(todolist/process-instance) 으로 검증합니다.
- [x] 시나리오별 스크린샷 체크포인트가 매뉴얼에 재사용할 수 있는 UI 상태를 설명합니다.
- [x] 스펙 관련 백엔드/프론트엔드 파일과 함수가 코드 표면 표에 기록되어 있습니다.
- [x] 커버리지 기준이 전체 저장소가 아니라 스펙 관련 파일/함수 중심으로 정의되어 있습니다.
- [x] 결과 경로가 `OUTPUT_CONTRACT.md`와 일치합니다.
