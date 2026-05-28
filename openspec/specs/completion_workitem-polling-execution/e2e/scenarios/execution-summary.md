# 워크아이템 폴링 실행 E2E 실행 요약

## 실행 메타데이터
- 스위트 슬러그: `completion_workitem-polling-execution`
- 날짜: 2026-05-27
- 명령: `node node_modules/@playwright/test/cli.js test --config playwright.config.mjs` (`openspec/specs/completion_workitem-polling-execution/e2e/tests/` 기준)
- Base URL: `http://localhost:8088` (공유 nginx 게이트웨이)
- 환경: 기존 `docker-compose.e2e.yml` 스택 재사용 — `process-gpt-e2e-db`, `kong`, `auth`, `rest`, `mock-llm-ate`, `completion-polling`, `frontend`, `gateway` healthy. ATE 스위트가 이미 시드한 `ate_demo_proc.e2e-instance-0001` 인스턴스 및 success/failure serviceTask 워크아이템을 그대로 활용.

## 입력
- 커버리지 매트릭스: `openspec/specs/completion_workitem-polling-execution/e2e/scenarios/00-coverage-matrix.md`
- 시나리오 문서 1–7: `01-submitted-workitem-claim.md` … `07-stale-claim-recovery.md`
- Playwright 명세: `tests/completion_workitem-polling-execution.spec.mjs` (본 turn 신규)
- Playwright config: `tests/playwright.config.mjs` (본 turn 신규)
- node_modules: `tests/node_modules` — ATE 스위트의 `node_modules` 로 디렉터리 junction ([[playwright-node-modules-junction]])
- Docker compose: `docker-compose.e2e.yml` (수정 없음 — ATE 가 부트한 동일 스택 사용)
- 시드: 본 스위트 별도 시드 파일 없음. ATE 의 `e2e_seed.sql` 결과를 in-place 재사용하며, 테스트 시작 시 success 워크아이템 `11111111-aaaa-aaaa-aaaa-000000000001` 만 SQL 로 SUBMITTED 상태로 리셋.

## 결과
| 지표 | 값 |
| --- | --- |
| 상태 | passed |
| 통과 테스트 | 1 |
| 실패 테스트 | 0 |
| 건너뛴 테스트 | 0 |
| 실행 시간 | 약 2.1분 (KanbanBoard reload 폴링 + DB 폴링 합산) |

본 turn 의 통합 검증 테스트:
- `폴링 워커가 SUBMITTED serviceTask 워크아이템을 자동으로 클레임하고 DONE 으로 전이한다` — PASS

본 테스트는 폴링 워커가 SUBMITTED + consumer NULL 워크아이템을 한 폴링 주기 안에 클레임해 `safe_handle_workitem` → `handle_service_workitem` → DONE 으로 전이하는 동선(`fetch_workitem_with_submitted_status` + `update_instance_status_on_error` 의 정상 분기)을 KanbanBoard UI 와 DB 직접 조회로 결정적 검증한다. Req 1 의 핵심 시나리오를 본 스위트 고유의 reset → 관찰 절차로 명시적으로 다시 통과시키며, ATE 스위트가 같은 인프라를 검증한 사실에만 의존하지 않는다.

## 산출물
- JSON 리포트: `openspec/specs/completion_workitem-polling-execution/e2e/results/results.json`
- HTML 리포트: `openspec/specs/completion_workitem-polling-execution/e2e/results/html-report/index.html`
- 스펙 커버리지 HTML 리포트: `openspec/specs/completion_workitem-polling-execution/e2e/results/spec-coverage-report.html`
- 스펙 커버리지 JSON 요약: `openspec/specs/completion_workitem-polling-execution/e2e/results/coverage-summary.json`
- 백엔드 커버리지: 별도 수집 없음 — `completion-polling` 컨테이너를 ATE 스위트와 공유 사용하므로 ATE 의 누적 백엔드 coverage 산출물(`openspec/specs/completion_automated-task-execution/e2e/results/backend-coverage/`)을 참조 증거로 사용 ([[shared-completion-container-restart-502]]).
- 프론트엔드 커버리지: V8 raw JSON 만 수집 — `openspec/specs/completion_workitem-polling-execution/e2e/results/frontend-coverage/raw/` (16MB, bundle-level 보조 증거). Monocart 리포트 미생성, 소스맵 기반 매핑은 본 스위트 활성화 단계에서 별도 source-build coverage 이미지 도입 시 수행 ([[frontend-source-build-oom]]).
- 스크린샷: `openspec/specs/completion_workitem-polling-execution/e2e/results/screenshots/` 아래 4장.

## 스크린샷 맵
| 시나리오 | 체크포인트 | 스크린샷 파일 | 매뉴얼용 캡션 |
| --- | --- | --- | --- |
| 01 | `01-login` | `process-gpt-completion_workitem-polling-execution-01-login.png` | 폴링 검증용 사용자 로그인 직후 화면 |
| 01 | `02-submitted-initial` | `process-gpt-completion_workitem-polling-execution-02-submitted-initial.png` | 폴링 시작 전 KanbanBoard 의 SUBMITTED 워크아이템 |
| 01 | `03-claimed-or-done` | `process-gpt-completion_workitem-polling-execution-03-claimed-or-done.png` | 폴링 워커가 클레임·완료 처리한 직후 KanbanBoard 상태 |
| 01 | `04-card-detail` | `process-gpt-completion_workitem-polling-execution-04-card-detail.png` | 완료된 워크아이템 카드 상세 (결과/로그 영역) |
| 02 | `02-submit-form` 외 | 미생성 (시나리오 02–07 보류) | 본 스위트 활성화 시 작성 |

## 검증
- 출력 검증기: PASS — `python .claude/skills/e2e-tests/scripts/validate_e2e_outputs.py --suite completion_workitem-polling-execution --suite-root openspec/specs/completion_workitem-polling-execution/e2e` 가 `OK: E2E output contract validated` 출력.
- Playwright: PASS (1/1)
- Docker compose config: 본 turn 수정 없음 (재실행 불필요)
- OpenSpec 추적성 게이트: PASS — `node .claude/skills/e2e-tests/scripts/evaluate_spec_coverage.mjs --suite completion_workitem-polling-execution --suite-root openspec/specs/completion_workitem-polling-execution/e2e --spec openspec/specs/completion_workitem-polling-execution/spec.md --write-summary` 결과 requirements 7/7 (100%), spec scenarios 12/12 (100%), declared tests 1/1 통과.
- 백엔드 coverage 게이트: 본 turn 직접 재수집 없음 — 공유 컨테이너 영향. AI 판단은 `spec-coverage-report.html` 참고.
- 프론트엔드 coverage 보조 게이트: V8 bundle 수준 raw 수집만 수행 — source-mapped 매핑은 미수행 (제약 명시).
- AI 스펙 커버리지 판단: **partial** — Req 1 + Req 2 의 serviceTask 분기는 실측 검증, 나머지 Req 2/3/4/5/6/7 은 보류 상태 (`spec-coverage-report.html` 참고).

## 커버리지 요약
| 구분 | 대상 | 결과 | 판단 |
| --- | --- | --- | --- |
| OpenSpec 추적성 | 7 Requirement / 12 Scenario | 7/7 · 12/12 매핑, 1/1 테스트 통과 | PASS (게이트), 실행은 partial |
| 백엔드 | `polling_service.py`, `workitem_processor.py`, `database.py`, `smtp_handler.py`, `process_definition.py` | 공유 컨테이너 — ATE 누적 결과 참조 | Req 1 + serviceTask 경로 충분, Req 4/6/7 0% |
| 프론트엔드 | `TodolistCard.vue`, `WorkItem.vue` 외 | V8 raw bundle-level | 보조 지표 — 원본 파일 매핑 미수행 |

## 알려진 공백
| 공백 | 영향 | 후속 조치 |
| --- | --- | --- |
| 시나리오 02 (완료 판정 + 다음 활동) 실행 | Req 2 의 userTask LangChain 완료 판정, 미충족 시 PENDING, LLM 파싱 실패 시 PENDING 미검증 | `mock-llm-ate` 에 `prompt_completed`/`prompt_next_activity`/invalid-json 응답 추가 후 활성화 |
| 시나리오 03 (인스턴스 상태 전이) 실행 | Req 3 의 인스턴스 COMPLETED 전이 미검증 (RUNNING 유지만 본 turn 으로 간접 관찰) | 종료 활동을 가진 BPMN 시드 + 인스턴스 상세 UI 셀렉터 확정 |
| 시나리오 04 (서브프로세스) 실행 | Req 4 의 자식 인스턴스 생성/부모 재개 미검증 | `subProcesses` BPMN 시드 + `handle_pending_workitem` 경로 검증 |
| 시나리오 05 (재시도 한도) 실행 | Req 5 의 retry counter / force-DONE 분기 미검증 | `mock-mcp` 실패 모드 + retry=3 직접 시드 |
| 시나리오 06 (SMTP) 실행 | Req 6 의 외부 고객 메일 발송 미검증 | `mock-smtp` capture 컨테이너 + `smtp_handler` host override |
| 시나리오 07 (stale claim 회수) 실행 | Req 7 의 cleanup 경로 미검증 | cleanup 주기 환경변수 단축 또는 `cleanup_stale_consumers` 직접 호출 단위 테스트 |
| 본 turn 의 단일 테스트 한정 | Req 1 의 `PENDING` 폴링 경로(`fetch_workitem_with_pending_status`) 와 동시 polling tick 의 `consumer` race 케이스 미검증 | 본 스펙 고유 PENDING 시드 + concurrent test mode 추가 |

## Phase E 병렬 메모
본 turn 은 Playwright 단일 테스트만 실행했고, Phase E 의 백엔드 coverage 재수집은 공유 `completion-polling` 컨테이너 영향으로 의도적으로 직렬화 보류했다. 향후 본 스위트 활성화 시:
- 백엔드 coverage 재수집과 본 스위트 Playwright 실행은 직렬화 필수 — 공유 컨테이너 restart 시 ATE Playwright 와 502 충돌 가능 ([[shared-completion-container-restart-502]]).
- 출력 검증기와 traceability 게이트는 본 turn 에서도 산출물 read-only 작업이므로 병렬 실행 가능했으나, 단일 테스트 규모상 직렬 실행이 충분히 빨라 직렬 수행.
- 프론트엔드 source-mapped coverage 재수집은 [[frontend-source-build-oom]] 의 호스트 사전 빌드 단계 + 별도 coverage frontend 컨테이너가 필요하므로 본 turn 범위 밖.

## 메모리 캡처
- 신규 메모리 추가 없음. 본 turn 의 통합 검증은 ATE 스위트의 인프라/시드/mock 패턴을 그대로 따랐고, 다음 함정/우회는 이미 메모리화되어 있다:
  - `node_modules` junction — [[playwright-node-modules-junction]]
  - 공유 completion 컨테이너 재시작 시 502 — [[shared-completion-container-restart-502]]
  - 프론트엔드 source-map 빌드 OOM — [[frontend-source-build-oom]]
  - 폴링 워커 mcp_processor 동시성 함정 — [[polling-mcp-processor-quirks]]
  - scriptTask 실행 경로 — [[completion-script-task-execution-path]]
  - coverage USR2 flush — [[coverage-py-usr2-flush]]
- 본 스위트 추가 시나리오(02–07) 활성화 과정에서 30분 이상의 새 함정(예: `prompt_completed` mock JsonOutputParser 분기, mock-smtp aiosmtpd handshake 이슈, cleanup_task 환경변수 노출 누락)을 만나면 그 시점에 신규 메모리를 추가하는 것이 적절하다.

## 스크립트 promotion 검토
- 본 turn 에서 작성한 스크립트는 Playwright 테스트 자체뿐이며, ATE 스위트의 `mock_llm.py`/`mock_mcp_server.py`/`sitecustomize.py`/`Dockerfile.polling-coverage` 등 공용 자산은 그대로 in-place 재사용했다.
- 신규 promotion 대상 없음. 본 스위트 활성화 단계에서 SMTP capture 컨테이너 (`mock_smtp.py`) 가 도입되고, 추후 다른 스위트(예: 알림/이메일 관련) 가 동일 mock 을 요구하게 되면 그 시점에 `openspec/e2e/scripts/` 로 promotion 을 검토한다.
