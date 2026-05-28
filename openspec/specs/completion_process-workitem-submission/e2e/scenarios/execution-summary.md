# 프로세스 워크아이템 생성·제출 E2E 실행 요약

## 실행 메타데이터
- 스위트 슬러그: `completion_process-workitem-submission`
- 날짜: 2026-05-27
- 명령: `node_modules/.bin/playwright test --config=openspec/specs/completion_process-workitem-submission/e2e/tests/playwright.config.mjs`
- Base URL: `http://localhost:8090` (gateway-wis → frontend / completion)
- 환경: docker

## 입력
- 커버리지 매트릭스: `openspec/specs/completion_process-workitem-submission/e2e/scenarios/00-coverage-matrix.md`
- Playwright 명세: `openspec/specs/completion_process-workitem-submission/e2e/tests/completion_process-workitem-submission.spec.mjs`
- Docker compose: `docker-compose.e2e.yml` + `openspec/specs/completion_process-workitem-submission/e2e/docker/coverage.override.yml`

## 스코프 재조정 (Real-Frontend Rule 적용)
이전 산출물은 합성 테스터 HTML(`scripts/wis-tester.html`) 을 `page.route()` 로 주입해 사용자 액션을 흉내냈고, 이는 SKILL.md 의 Real-Frontend Rule 위반이다. 본 실행에서 wis-tester.html, 기존 합성 스크린샷 14장(`results` 산출물), Playwright 스크립트의 테스터 의존 로직을 모두 제거하고, `services/frontend/src/**` 코드 grep 으로 실제 사용자 트리거 경로를 추적한 결과에 따라 시나리오를 두 클래스로 재분류했다.

| 분류 | 시나리오 | 사유 |
| --- | --- | --- |
| 실제 프런트엔드 워크플로우 | 04 | `/completion/complete` 는 `ProcessGPTBackend.executeInstance()` → todolist `putWorkItemComplete()` 에서 발화. `/auth/login` 로그인 후 `/todolist/<task-id>` 에 진입해 SPA-origin POST 로 발화시키고 실제 화면 스크린샷 캡쳐. |
| 백엔드 계약 전용 (스크린샷 면제) | 01, 02, 03, 05, 06, 07, 08, 09 | grep 결과 `/completion/initiate` 는 frontend 어디에서도 호출되지 않음 — 스케줄러/백엔드/외부 트리거 경로. `/role-binding` 의 기본값 분기는 `ProcessGPTExecute.vue` 의 `hasDefaultRole === true` 경로에서 호출되지 않음. `/complete` 의 task_id 단독·필수 누락 분기는 SPA 가 항상 두 식별자를 함께 전송하므로 UI 에서 발화되지 않음. 모두 Playwright `request` 로 게이트웨이를 통과시켜 계약을 검증, 스크린샷 의무는 면제. |

## 결과
| 지표 | 값 |
| --- | --- |
| 상태 | passed |
| 통과 테스트 | 9 |
| 실패 테스트 | 0 |
| 건너뛴 테스트 | 0 |

## 산출물
- JSON 리포트: `openspec/specs/completion_process-workitem-submission/e2e/results/results.json`
- HTML 리포트: `openspec/specs/completion_process-workitem-submission/e2e/results/html-report/index.html`
- 스펙 커버리지 HTML 리포트: `openspec/specs/completion_process-workitem-submission/e2e/results/spec-coverage-report.html`
- 스펙 커버리지 JSON 요약: `openspec/specs/completion_process-workitem-submission/e2e/results/coverage-summary.json`
- 백엔드 커버리지: `openspec/specs/completion_process-workitem-submission/e2e/results/backend-coverage/`
- 프론트엔드 커버리지: `openspec/specs/completion_process-workitem-submission/e2e/results/frontend-coverage/raw/` (V8 보조 — minified bundle)
- 스크린샷: `openspec/specs/completion_process-workitem-submission/e2e/results/screenshots/`
- 산출물: `openspec/specs/completion_process-workitem-submission/e2e/results/artifacts/`

## 스크린샷 맵
| 시나리오 | 체크포인트 | 스크린샷 파일 | 매뉴얼용 캡션 |
| --- | --- | --- | --- |
| 04 | `04-todolist-form` | `openspec/specs/completion_process-workitem-submission/e2e/results/screenshots/process-gpt-completion_process-workitem-submission-04-todolist-form.png` | 사용자가 todolist 에서 워크아이템 폼을 여는 첫 화면 |
| 04 | `04-todolist-submitted` | `openspec/specs/completion_process-workitem-submission/e2e/results/screenshots/process-gpt-completion_process-workitem-submission-04-todolist-submitted.png` | 폼 제출 후 SUBMITTED 상태가 확정된 화면 |

> 시나리오 01/02/03/05/06/07/08/09 는 Real-Frontend Rule 스코프 재조정으로 스크린샷 의무가 면제되었다.

## 검증
- 출력 검증기: passed (`python .claude/skills/e2e-tests/scripts/validate_e2e_outputs.py --suite completion_process-workitem-submission --suite-root openspec/specs/completion_process-workitem-submission/e2e`)
- Playwright: passed (9/9)
- Docker compose config: passed
- OpenSpec 추적성 게이트: passed (Requirement 5/5, Spec Scenario 10/10, Playwright 9/9, 스크린샷 2/2 — 백엔드 계약 시나리오의 면제 처리는 매트릭스 및 시나리오 문서에 명시)
- 백엔드 coverage 게이트: passed (스펙 관련 함수 모두 실행됨)
- 프론트엔드 coverage 보조 게이트: bundle V8 보조 지표 수집 (소스맵 없음)
- AI 스펙 커버리지 판단: sufficient

## 커버리지 요약
| 구분 | 대상 | 결과 | 판단 |
| --- | --- | --- | --- |
| OpenSpec 추적성 | Requirement/Scenario/Test/Screenshot | 5/5 requirements, 10/10 spec scenarios, 9/9 tests, 2/2 스크린샷 (백엔드 계약 시나리오는 의무 면제) | 충분 |
| 백엔드 | `services/completion/process_engine.py` (handle_initiate/handle_submit/handle_role_binding), `process_definition.py`, `proc_def_versioning.py`, `database.py`, `main.py`(DBConfigMiddleware) | XML+HTML report 생성 완료, 스펙 관련 함수 모두 실행 | 충분 (TODO/SUBMITTED/400/500/role-binding default/version/tenant 분기 커버) |
| 프론트엔드 | `ProcessGPTBackend.executeInstance/putWorkItemComplete`, `FormWorkItem.vue`, `/auth/login` 진입 (시나리오 04 한 건) | V8 bundle 보조 — 메인 SPA 이미지가 minified, 소스맵 미생성 | 보조 지표 (시나리오 04 가 실제 SPA 위에서 발화됨을 화면 스크린샷으로 입증) |

## 병렬 실행
- Phase E 의 backend coverage 재수집은 Playwright 실행과 직렬화하여 진행 (공유 자원인 `process-gpt-e2e-completion` 컨테이너가 동시에 한 가지 mount 구성만 유지 가능 — `compose-force-recreate-stale-mount` 메모리).
- `validate_e2e_outputs.py` 와 `evaluate_spec_coverage.mjs` 는 결과 파일에 대한 순수 read 이므로 Playwright 실행 이후 직렬로 실행했다 (파일 수가 적어 병렬화 이득 미미).

## 알려진 공백
| 공백 | 영향 | 후속 조치 |
| --- | --- | --- |
| `/vision-complete` 별도 시나리오 | `handle_submit` 을 공유해 동일 경로가 04/05 로 커버됨 | 핸들러가 분기되면 신규 시나리오 추가 |
| LLM 폴백 role binding 경로 | mock-llm 의존성, 본 스위트 범위 외 | 별도 LLM 결정성 스위트에서 다룸 |
| `handle_initiate` 상태 코드 누수 (`400`→`500`) | 메시지 보존되지만 스펙 SHALL 위반 | 구현측에서 `except HTTPException: raise` 추가 필요 — `handle_submit` 패턴 일치화 |
| `/initiate`, `/role-binding` 기본값 분기, `/complete` task_id 단독·필수 누락 분기의 실제 사용자 UI 트리거 | 현재 SPA 가 해당 경로를 사용자에게 노출하지 않음 (코드 grep 으로 확인) | 향후 프런트엔드가 해당 경로를 사용자에게 노출하면 실제 프런트엔드 시나리오로 승격 |

## Phase F 메모리 캡처
- 신규 메모리 추가: 없음. 이번 재작성에서 30 분 이상 막힌 새로운 함정/우회는 없었다 (`completion_process-activity-rework` 의 `login()` + `callCompletionApi()` 패턴, role-binding 응답이 이중 인코드 JSON 문자열이라는 점은 코드/응답에서 직접 확인 가능).
- 스크립트 승격: 없음. 본 스위트에서 `tests/completion_process-workitem-submission.spec.mjs` 는 다른 스위트가 이미 사용 중인 `login` 헬퍼와 `callCompletionApi` 헬퍼 패턴을 그대로 재사용했고, 새로 작성한 스위트-전용 헬퍼 중 두 번 이상 재사용된 추상이 없어 `openspec/e2e/scripts/` 로 승격하지 않는다.
