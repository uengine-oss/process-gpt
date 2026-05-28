# 워크아이템 폴링 실행 E2E 커버리지 매트릭스

## 범위
- 스위트 슬러그: `completion_workitem-polling-execution`
- 원본 명세 ID: `completion_workitem-polling-execution`
- 원본 명세:
  - `openspec/specs/completion_workitem-polling-execution/spec.md`
- 백엔드/제품 계약:
  - 폴링 워커 진입점: `services/completion/polling_service/polling_service.py` 의 `polling_workitem`, `safe_handle_workitem`, `cleanup_task`
  - 워크아이템 처리 본체: `services/completion/polling_service/workitem_processor.py` 의 `handle_workitem` (userTask/scriptTask/manualTask, LangChain 기반 완료 판정 + `execute_next_activity`), `handle_service_workitem` (serviceTask 결과 기록), `handle_pending_workitem` (subProcess 부모 재개), `_check_service_tasks` (다음 serviceTask 승격), `update_instance_status_on_error` (RUNNING/COMPLETED 전이)
  - 데이터 계약: `todolist` (`status`, `consumer`, `retry`, `updated_at`, `output`, `log`, `user_id`), `bpm_proc_inst` (`status`, `current_activity_ids`, `end_date`), `proc_def`/`proc_def_version` (`activities`, `sequences`, `subProcesses`)
  - 데이터 액세스: `services/completion/polling_service/database.py` 의 `fetch_workitem_with_submitted_status`, `fetch_workitem_with_pending_status`, `cleanup_stale_consumers`
  - 외부 boundary: LLM 프록시(`handle_workitem` 의 `prompt_completed` / `prompt_next_activity` 등), MCP 도구 서버(`handle_service_workitem`), SMTP(`smtp_handler` — `external_customer` 안내 메일)
- E2E 루트: `openspec/specs/completion_workitem-polling-execution/e2e/`
- Playwright 명세: (본 스위트는 Phase A 산출물 한정 — 실행 가능한 Playwright 시나리오 없음)
- 결과 디렉터리: `openspec/specs/completion_workitem-polling-execution/e2e/results/`

## 본 스위트의 현재 상태 (Phase A 한정)

본 스위트는 `/e2e-tests` 워크플로의 **Phase A (Plan)** 단계 산출물만을 포함합니다. 사용자 결정에 따라 Phase B (Docker infra), Phase D (Playwright 구현), Phase E (검증/커버리지 게이트), Phase F (실행 요약 외 자료) 는 본 turn 에서 수행하지 않습니다. 그 사유는 아래 "보류 사유 (공통)" 절에 정리되어 있습니다.

본 문서는:
1. 원본 명세의 7개 Requirement 와 해당 OpenSpec Scenario 들을 **모두** 매핑합니다.
2. 매핑된 시나리오 문서(`01`~`07`)를 placeholder 로 두되, 각각 사용자 검증 표면·필요 인프라·보류 사유를 한국어로 정리합니다.
3. 실제 Playwright 구현 시 활용해야 할 mock-llm 확장 포인트, BPMN 시드 구조, SMTP/시계 조작 방안을 명시해 후속 작업의 진입 비용을 낮춥니다.

## 재사용 산출물
- `docker-compose.e2e.yml` 의 `completion-polling`, `mock-llm-ate`, `db`, `kong`, `auth`, `rest`, `frontend`, `gateway`, `db-seed-automated-task-execution` 패턴: 폴링 워커 + 게이트웨이 + Supabase 전 구조를 그대로 재사용할 수 있습니다.
- `openspec/specs/completion_automated-task-execution/e2e/scripts/mock_llm.py`: serviceTask 경로의 LangChain react agent 호출을 결정적으로 처리합니다. 본 스위트의 Req 2/3/4/5 를 실제 검증하려면 이 mock 에 `prompt_completed` / `prompt_next_activity` / `prompt_role_resolution` 응답을 추가해야 합니다.
- `openspec/specs/completion_automated-task-execution/e2e/scripts/sitecustomize.py`: `mcp_processor.sanitize_mcp_tools` 패치(폴링 워커 컨테이너 공용).
- `openspec/specs/completion_automated-task-execution/e2e/docker/Dockerfile.polling-coverage` + `coveragerc.e2e`: 폴링 워커 backend coverage 인스트루먼트.
- `openspec/specs/completion_automated-task-execution/e2e/seed_files/e2e_seed.sql`: `localhost` 테넌트, `ate-e2e@uengine.org` 로그인 사용자, agent 사용자 행, MCP 서버 설정 — 본 스위트 시나리오 시드의 기반.
- 메모리: [[polling-mcp-processor-quirks]] (폴링 워커 동시성 + sanitize 패치), [[completion-script-task-execution-path]] (scriptTask 와 LangChain 파이프라인 관계), [[coverage-py-usr2-flush]] (장기 실행 워커 coverage flush), [[completion-coverage-override-workdir]] (Dockerfile WORKDIR 함정), [[compose-override-relative-paths]] (compose override 경로 기준), [[notifications-updated-at-missing]] (init.sql 결손 컬럼 패턴 — 본 스위트에서도 `todolist.updated_at` 의 신뢰성 확인 필요).

## 시나리오 목록
| ID | 시나리오 문서 | Playwright 테스트 제목 (계획) | 주요 동작 | 현재 상태 |
| --- | --- | --- | --- | --- |
| 01 | `01-submitted-workitem-claim.md` | `폴링 워커가 SUBMITTED 워크아이템을 클레임해 처리한다` | UI: `/todolist` 에서 SUBMITTED 워크아이템이 IN_PROGRESS/DONE 컬럼으로 이동하며 `consumer` 가 설정/해제 | 보류 — Req 1 의 핵심 동선은 ATE 스위트가 이미 검증 (재사용/연계 기록만) |
| 02 | `02-completion-and-next-activity.md` | `완료 조건을 만족한 활동이 DONE 으로 전이되고 다음 활동 워크아이템이 IN_PROGRESS 로 생성된다` | UI: 사용자 활동 제출 후 다음 활동 카드가 IN_PROGRESS 컬럼에 등장 | 보류 — `handle_workitem` LangChain 파이프라인 mock-llm 확장 필요 |
| 03 | `03-instance-state-transition.md` | `종료 활동이 완료되면 인스턴스가 COMPLETED 로 전이되고 종료 시각이 기록된다` | UI: `/process-instances` 또는 인스턴스 상세에서 인스턴스 상태 RUNNING → COMPLETED | 보류 — Scenario 02 와 동일한 LangChain 의존성 |
| 04 | `04-subprocess-create-and-resume.md` | `서브프로세스 활동 시 자식 인스턴스가 생성되고 자식 완료 후 부모 워크아이템이 다시 진행 대상으로 전이된다` | UI: 부모 인스턴스 화면에서 자식 인스턴스 진입/완료, 부모 활동 재개 | 보류 — `subProcesses` BPMN 구조 + `handle_pending_workitem` 경로 시드 필요 |
| 05 | `05-retry-limit-force-done.md` | `재시도 횟수가 3회를 초과한 워크아이템은 DONE 으로 강제 종료되고 오류 로그가 기록된다` | UI: 워크아이템 카드 로그에 `[Error]` 메시지 + 상태 DONE | 보류 — 결정적 3회 실패 주입(`safe_handle_workitem` 예외 경로) 필요 |
| 06 | `06-external-customer-email.md` | `다음 활동 담당자가 external_customer 인 경우 외부 폼 링크 안내 이메일이 발송된다` | UI: 사용자 활동 제출 후 다음 활동 진행 + SMTP capture 파일 확인 | 보류 — SMTP capture 인프라(`smtp_handler` patch) + `endpoint=external_customer` 시드 필요 |
| 07 | `07-stale-claim-recovery.md` | `30분 이상 갱신되지 않은 SUBMITTED 워크아이템의 클레임이 정리 주기에 의해 해제된다` | UI: 정체 워크아이템이 다시 SUBMITTED 컬럼에 노출 | 보류 — `cleanup_task` 5분 주기 + `updated_at < now() - 30분` 시드 + 시계 조작 또는 장시간 대기 필요 |

> 본 스위트의 사용자 검증 표면은 frontend `/todolist` (KanbanBoard) 와 `/process-instances` 인스턴스 상세 화면입니다. 폴링 워커는 백엔드에서 자동 실행되므로 사용자는 SUBMITTED → IN_PROGRESS → DONE 컬럼 이동, 로그/결과 표시, 인스턴스 상태 배지 변화를 관찰합니다.

> 본 스위트의 `user_id` 시드 규칙은 ATE 스위트와 동일하게 `<agent_uuid>,<human_uuid>` 콤마 결합 형식을 사용하거나, userTask 의 경우 단일 human UUID 를 사용합니다. 프론트엔드 KanbanBoard 는 `user_id LIKE %<human_uuid>%` 필터로 워크아이템을 노출합니다.

## 요구사항 커버리지
| 명세 | 요구사항 | 필수 수준 | 커버 시나리오 | 비고 |
| --- | --- | --- | --- | --- |
| `completion_workitem-polling-execution` | 제출된 워크아이템 자동 폴링 | SHALL | 01 (보류, ATE 연계) | ATE 스위트의 `db-seed-automated-task-execution` + `mock-llm-ate` 가 동일 진입점을 이미 검증함 |
| `completion_workitem-polling-execution` | 완료 판정과 다음 활동 진행 | SHALL | 02 (보류) | `handle_workitem` LangChain mock 확장 의존 |
| `completion_workitem-polling-execution` | 프로세스 인스턴스 상태 전이 | SHALL | 03 (보류) | Scenario 02 의존 |
| `completion_workitem-polling-execution` | 서브프로세스 생성과 부모 재개 | SHALL | 04 (보류) | `subProcesses` 정의 + `handle_pending_workitem` 시드 필요 |
| `completion_workitem-polling-execution` | 처리 실패 재시도 제한 | SHALL | 05 (보류) | 결정적 3회 실패 주입 필요 |
| `completion_workitem-polling-execution` | 외부 고객 대상 이메일 안내 | SHALL | 06 (보류) | SMTP capture 패치 필요 |
| `completion_workitem-polling-execution` | 정체된 처리 클레임 회수 | SHALL | 07 (보류) | `updated_at` 시계 시드 + 5분 cleanup 주기 |

## 명세 시나리오 커버리지
| 명세 | 요구사항 | 명세 시나리오 | 커버 시나리오 | 사용자 검증 표면 |
| --- | --- | --- | --- | --- |
| `completion_workitem-polling-execution` | 제출된 워크아이템 자동 폴링 | 제출 워크아이템 클레임 | 01 (보류) | `/todolist` 컬럼 이동 (SUBMITTED → IN_PROGRESS) |
| `completion_workitem-polling-execution` | 완료 판정과 다음 활동 진행 | 워크아이템 완료 후 다음 활동 생성 | 02 (보류) | `/todolist` 다음 활동 카드 등장 |
| `completion_workitem-polling-execution` | 완료 판정과 다음 활동 진행 | 완료 조건 미충족 | 02 (보류) | 카드 상태 `PENDING` + 사유 로그 |
| `completion_workitem-polling-execution` | 완료 판정과 다음 활동 진행 | LLM 출력 파싱 실패 | 02 (보류) | 카드 상태 `PENDING` + 시스템 메시지 로그 |
| `completion_workitem-polling-execution` | 프로세스 인스턴스 상태 전이 | 종료 활동 완료 시 인스턴스 완료 | 03 (보류) | 인스턴스 상세 상태 배지 `COMPLETED` |
| `completion_workitem-polling-execution` | 프로세스 인스턴스 상태 전이 | 진행 중 인스턴스 유지 | 03 (보류) | 인스턴스 상세 상태 배지 `RUNNING` |
| `completion_workitem-polling-execution` | 서브프로세스 생성과 부모 재개 | 서브프로세스 자식 인스턴스 생성 | 04 (보류) | 자식 인스턴스 카드 신규 등장 |
| `completion_workitem-polling-execution` | 서브프로세스 생성과 부모 재개 | 자식 완료 시 부모 재개 | 04 (보류) | 부모 워크아이템 카드 재진입 |
| `completion_workitem-polling-execution` | 처리 실패 재시도 제한 | 실패 후 재시도 | 05 (보류) | 카드 로그 `다시 시도하겠습니다. (시도 N/3)` |
| `completion_workitem-polling-execution` | 처리 실패 재시도 제한 | 재시도 한도 초과 | 05 (보류) | 카드 로그 `[Error]` + 상태 DONE |
| `completion_workitem-polling-execution` | 외부 고객 대상 이메일 안내 | 외부 고객 안내 이메일 발송 | 06 (보류) | SMTP capture 파일 + UI 진행 알림 |
| `completion_workitem-polling-execution` | 정체된 처리 클레임 회수 | 정체 워크아이템 회수 | 07 (보류) | 카드가 다시 SUBMITTED 컬럼에 노출 |

## 스펙 관련 코드 표면

### 백엔드
| 파일 | 함수/클래스/라우트 | 관련 요구사항 | 커버리지 기준 | 선정 근거 |
| --- | --- | --- | --- | --- |
| `services/completion/polling_service/polling_service.py` | `polling_workitem`, `safe_handle_workitem`, `cleanup_task` | Req 1, Req 5, Req 7 | line >= 70%, branch >= 60% | 폴링 진입점, retry 분기, cleanup 주기 트리거. 본 파일의 `safe_handle_workitem` 예외 경로(line 79–96)가 Req 5 의 핵심 |
| `services/completion/polling_service/database.py` | `fetch_workitem_with_submitted_status`, `fetch_workitem_with_pending_status`, `cleanup_stale_consumers` | Req 1, Req 7 | line >= 70% | 폴링 조회 + 정체 회수 SQL 의 단일 진입점. `cleanup_stale_consumers` 는 Req 7 의 유일한 구현체 |
| `services/completion/polling_service/workitem_processor.py` | `handle_workitem`, `execute_next_activity`, `_check_service_tasks`, `update_instance_status_on_error` | Req 2, Req 3, Req 5 | line >= 60% (handle_workitem 은 partial), branch >= 50% | userTask/scriptTask 의 완료 판정과 다음 활동 진행. line 1414 의 `process_instance.status = "COMPLETED"` 가 Req 3 의 직접 구현 |
| `services/completion/polling_service/workitem_processor.py` | `handle_service_workitem`, `handle_pending_workitem`, `get_workitem_position` | Req 1, Req 4 | line >= 70% | serviceTask 결과 기록(Req 1 의 ATE 연계) + subProcess 부모 PENDING 평가(Req 4 의 자식 완료 시 부모 재개) |
| `services/completion/polling_service/smtp_handler.py` | 외부 고객 안내 이메일 발송 함수 | Req 6 | line >= 70% | `external_customer` endpoint 분기에서만 사용되는 단일 책임 모듈 |
| `services/completion/polling_service/process_definition.py` | `find_end_activity`, `find_activity_by_id`, 서브프로세스 탐색 | Req 3, Req 4 | function = 100% (관련 함수에 한정) | 종료 활동 식별과 서브프로세스 시퀀스 탐색 — Req 3/4 판정에 사용 |

> 본 스위트가 활성화될 때 백엔드 coverage 는 ATE 스위트와 동일한 `Dockerfile.polling-coverage` + `coveragerc.e2e` + `USR2` flush 경로를 재사용합니다 ([[coverage-py-usr2-flush]]). 단일 `completion-polling` 컨테이너가 ATE 와 본 스위트의 워크아이템을 모두 처리하므로, 결과 수집 시 ATE 시나리오 영향을 분리해 보고서에 명시해야 합니다.

### 프론트엔드
| 파일 | 컴포넌트/함수/API 호출 | 관련 요구사항 | 커버리지 기준 | 선정 근거 |
| --- | --- | --- | --- | --- |
| `services/frontend/src/components/apps/todolist/TodolistCard.vue` | KanbanBoard 워크아이템 컬럼 표시 | Req 1, Req 2, Req 5, Req 7 | line >= 50% (V8 보조) | 사용자가 SUBMITTED/IN_PROGRESS/DONE 전이를 관찰하는 1차 화면 |
| `services/frontend/src/components/apps/todolist/WorkItem.vue` | 워크아이템 상태/로그/결과 카드 | Req 1, Req 2, Req 5 | line >= 50% (V8 보조) | `log`/`output`/`retry` 가 사용자에게 노출되는 컴포넌트 — Req 5 의 `[Error]` 로그 표시도 본 컴포넌트 |
| `services/frontend/src/components/ProcessInstanceRunning.vue` 또는 인스턴스 상세 화면 | 인스턴스 상태 배지·종료 시각 표시 | Req 3 | line >= 30% (V8 보조) | RUNNING/COMPLETED 전이가 사용자에게 보이는 표면 |
| `services/frontend/src/components/apps/todolist/SubProcessCard.vue` (또는 등가) | 자식 인스턴스 카드 | Req 4 | line >= 30% (V8 보조) | 자식 인스턴스 진입/복귀 시 사용자 관찰 표면. 구체 파일은 본 스위트 활성화 시 확정 |

> 프론트엔드 source-mapped 커버리지는 기존 `completion_agent-memory-chat` 의 `Dockerfile.coverage-prebuilt` + 호스트 사전 빌드 패턴을 재사용 대상으로 둡니다 ([[frontend-source-build-oom]]). 본 스위트는 Phase A 한정이므로 실측 수집은 보류이며, 본 스위트 활성화 시 위 보조 지표 기준을 V8 bundle 한계로 명시해야 합니다.

## 미검증 및 보류 항목

본 스위트의 **모든** 시나리오가 보류 상태입니다. 항목별 보류 사유와 후속 조치는 다음과 같습니다.

| 항목 | 사유 | 후속 조치 |
| --- | --- | --- |
| 시나리오 01 (제출 워크아이템 클레임) | Req 1 의 핵심 동선(SUBMITTED 조회 + consumer claim + handle_*)은 이미 `completion_automated-task-execution` 스위트가 검증함. 본 스위트에서 별도 검증할 추가 표면이 없음. | 본 시나리오를 활성화하지 않고 ATE 결과를 참조하는 trace 로 유지하거나, 본 스펙 고유 데이터(예: PENDING 분기)로 보강해 활성화 |
| 시나리오 02 (완료 판정 + 다음 활동) | `handle_workitem` 의 LangChain `prompt_completed` / `prompt_next_activity` 응답을 결정적으로 mock 해야 함. 기존 `mock-llm-ate` 는 react agent tool_calls 만 처리하며 완료 판정 prompt 응답은 미구현 ([[completion-script-task-execution-path]]). | mock-llm-ate `mock_llm.py` 에 `prompt_completed`/`prompt_next_activity` JSON 응답 + role resolution 응답 추가, BPMN 시드에 userTask → 다음 활동 시퀀스 추가 |
| 시나리오 03 (인스턴스 상태 전이) | 정상 경로 COMPLETED 전이는 `execute_next_activity` 의 마지막 활동 처리에서 발생. Scenario 02 와 동일한 mock-llm 확장 의존 | Scenario 02 활성화 후 종료 활동을 가진 BPMN 추가 시드 + 인스턴스 상세 UI 셀렉터 확정 |
| 시나리오 04 (서브프로세스) | `proc_def_version.definition.subProcesses` 에 자식 BPMN 정의 + 부모 인스턴스가 자식 인스턴스를 생성하고 자식 모두 완료 시 부모 PENDING workitem 을 DONE 으로 전환하는 `handle_pending_workitem` 경로(line 4196–) 가 필요. BPMN 모델링 + 두 인스턴스 라이프사이클 + UI 표면 매핑 작업이 큼 | 별도 작업으로 분리: subProcesses 정의 BPMN 시드 → 자식 인스턴스 자동 생성 검증 → 자식 완료 시 부모 재개 검증 |
| 시나리오 05 (재시도 한도) | `safe_handle_workitem` 의 except 분기를 결정적으로 3회 트리거하려면 mock-llm 또는 mock-mcp 가 매 호출마다 예외를 던지도록 구성해야 함. retry 카운터는 매 호출마다 1 증가하므로 폴링 주기(5초) × 3회 = 약 15–20초 대기가 필요. retry=3 으로 직접 시드해 한 번의 실패로 DONE 강제 종료 분기를 트리거하는 단축 경로 가능 (`handle_service_workitem` line 4022 `if workitem['retry'] >= 3: update_instance_status_on_error(...)`) | 두 시나리오로 분리: 5a) 결정적 3회 실패 + retry counter 증가 관찰, 5b) `retry=3` 직접 시드 + 단일 실행 분기로 DONE 강제 종료 검증 |
| 시나리오 06 (외부 고객 이메일) | `smtp_handler` 의 실제 SMTP 전송 경로를 capture 로 대체해야 함. 기존 e2e 인프라에 SMTP capture 컨테이너가 없으며, `external_customer` endpoint 와 role_bindings 시드, fcm-service 와 다른 별도 capture mount 필요 | SMTP 캡처 컨테이너(예: aiosmtpd 기반 mock-smtp) 추가 + `smtp_handler` 환경변수로 SMTP host 주입 + role_bindings 에 `endpoint=external_customer` + 고객 이메일 변수 시드 |
| 시나리오 07 (정체 클레임 회수) | `cleanup_task` 가 5분 간격(`asyncio.sleep(300)`) 으로 실행되어 한 번의 사이클을 보려면 최소 5분 대기가 필요. 또한 `updated_at < now() - 30분` 조건을 만족하려면 시드 시점에 과거 timestamp 를 직접 주입해야 함. | 옵션 A: 시드에서 `updated_at = now() - interval '31 minutes'` + 폴링 워커 환경변수로 cleanup 주기 단축(코드 변경 필요) + 5분 대기. 옵션 B: 통합 테스트에서 `cleanup_stale_consumers` 직접 호출하는 단위 테스트로 대체 |

## 보류 사유 (공통)

본 스위트가 Phase A 한정으로 종료된 1차 사유는 다음과 같습니다.

1. **본 스펙의 핵심 동작이 `handle_workitem` LangChain 파이프라인에 분포**: Req 2/3/4 의 검증 가능한 경로는 모두 `handle_workitem` → `prompt_completed` → `execute_next_activity` 흐름을 통과해야 합니다. 기존 `mock-llm-ate` 는 react agent 의 tool_calls 만 결정적으로 응답하며, 본 흐름의 다단계 prompt 응답을 처리하지 않습니다. mock-llm 확장은 본 스위트의 별도 사전 작업으로 분리하는 것이 합리적입니다 ([[completion-script-task-execution-path]]).
2. **Req 4 의 BPMN 인프라 비용**: 서브프로세스는 `proc_def_version.definition.subProcesses` 구조 + 부모-자식 인스턴스 자동 생성/재개 로직을 수반하므로, 단일 시나리오로 정리하기에 BPMN 모델링과 자식 인스턴스 UI 검증 표면을 별도 설계해야 합니다.
3. **Req 6 의 외부 boundary**: SMTP 는 기존 E2E 인프라에 없는 새 boundary 입니다. `mock-smtp` 컨테이너와 capture 디렉터리 등 새 인프라 도입이 필요합니다.
4. **Req 7 의 시계 의존성**: `cleanup_task` 의 5분 주기와 30분 stale 기준은 결정적 E2E 에 불리합니다. 본 항목은 단위/통합 테스트에서 `cleanup_stale_consumers` 를 직접 호출하는 형태가 더 적합할 가능성이 있습니다.
5. **Req 1 의 중복 검증**: 기존 ATE 스위트가 Req 1 의 핵심 동선을 이미 결정적으로 검증하므로, 본 스위트에서 동일 동선을 다시 구현하는 것은 ROI 가 낮습니다.

## 체크리스트
- [x] 모든 Requirement 가 하나 이상의 E2E 시나리오 placeholder 에 매핑되어 있습니다.
- [x] 중요한 OpenSpec Scenario 가 E2E 시나리오 placeholder 또는 미검증 및 보류 항목에 기록되어 있습니다.
- [x] 사람이 읽는 요구사항명, 명세 시나리오명, 목적, 절차, 기대 결과는 한국어로 작성되어 있습니다.
- [x] 원본 OpenSpec 의 한국어 의미가 보존되어 있으며, `serviceTask`/`SUBMITTED`/`DONE`/`COMPLETED`/`PENDING`/`external_customer`/`todolist`/`bpm_proc_inst` 등 계약 식별자는 원문 유지합니다.
- [x] 원본 명세가 하나의 백엔드 연계 피쳐(폴링 워커 동작) 범위이며, 마이크로서비스 전체 요약이나 프론트엔드 단독 명세가 아닙니다.
- [x] 원본 명세의 서비스 접두어가 `completion` 으로 구현 레이어가 아닙니다.
- [x] E2E 가 실행할 소유 백엔드 서비스(`services/completion/polling_service`) 와 데이터 계약(`todolist`/`bpm_proc_inst`)이 명확합니다.
- [x] 서비스 접두형 명세 ID `completion_workitem-polling-execution` 가 스위트 슬러그와 동일합니다.
- [x] E2E 산출물(시나리오, 매트릭스, 실행 요약)이 `openspec/specs/completion_workitem-polling-execution/e2e/` 아래에 응집되어 있습니다.
- [x] 사용자-facing 시나리오는 (활성화 시) `/todolist`/`/process-instances` UI 상호작용으로 검증하도록 계획되어 있습니다.
- [x] 시나리오별 스크린샷 체크포인트 후보가 placeholder 문서에 한국어 캡션으로 정의되어 있습니다.
- [x] 스펙 관련 백엔드/프론트엔드 파일과 함수가 코드 표면 표에 기록되어 있습니다.
- [x] 커버리지 기준이 전체 저장소가 아닌 스펙 관련 파일/함수 중심으로 정의되어 있습니다.
- [x] 결과 경로가 `OUTPUT_CONTRACT.md` 의 `openspec/specs/<spec-name>/e2e/results/` 와 일치하도록 계획되어 있습니다.
- [ ] Playwright 시나리오·Docker compose·시드·실행 결과·스크린샷이 작성되어 있습니다. **— 본 스위트는 Phase A 한정, 보류**
