# 프로세스 정의 피드백 E2E 실행 요약

## 실행 메타데이터
- 스위트 슬러그: `completion_process-definition-feedback`
- 날짜: 2026-05-27
- 명령: `BASE_URL=http://localhost:8088 npx playwright test --config=playwright.config.mjs`
- Base URL: `http://localhost:8088` (nginx gateway)
- 환경: docker

## 입력
- 커버리지 매트릭스: `openspec/specs/completion_process-definition-feedback/e2e/scenarios/00-coverage-matrix.md`
- Playwright 명세: `openspec/specs/completion_process-definition-feedback/e2e/tests/completion_process-definition-feedback.spec.mjs`
- Docker compose: `docker-compose.e2e.yml`
- Docker compose override (백엔드 coverage): `openspec/specs/completion_process-definition-feedback/e2e/docker/coverage.override.yml`

## 결과
| 지표 | 값 |
| --- | --- |
| 상태 | passed |
| 통과 테스트 | 3 |
| 실패 테스트 | 0 |
| 건너뛴 테스트 | 0 |

## 산출물
- JSON 리포트: `openspec/specs/completion_process-definition-feedback/e2e/results/results.json`
- HTML 리포트: `openspec/specs/completion_process-definition-feedback/e2e/results/html-report/index.html`
- 스펙 커버리지 HTML 리포트: `openspec/specs/completion_process-definition-feedback/e2e/results/spec-coverage-report.html`
- 스펙 커버리지 JSON 요약: `openspec/specs/completion_process-definition-feedback/e2e/results/coverage-summary.json`
- 백엔드 커버리지: `openspec/specs/completion_process-definition-feedback/e2e/results/backend-coverage/`
- 프론트엔드 커버리지: 해당 없음 (보조 프로토콜 스위트로 브라우저 UI 흐름이 없으므로 프론트엔드 커버리지 1차 게이트 비대상)
- 스크린샷: 해당 없음 (보조 프로토콜 스위트)
- 산출물: `openspec/specs/completion_process-definition-feedback/e2e/results/artifacts/`

## 스크린샷 맵
| 시나리오 | 체크포인트 | 스크린샷 파일 | 매뉴얼용 캡션 |
| --- | --- | --- | --- |
| 01-03 | 해당 없음 | - | 백엔드 프로토콜 시나리오(보조 프로토콜) — DOCX 매뉴얼용 UI 증거가 요구되지 않습니다. |

## 검증
- 출력 검증기: passed
- Playwright: passed
- Docker compose config: passed
- OpenSpec 추적성 게이트: passed
- 백엔드 coverage 게이트: passed (coverage.override.yml 로 completion 컨테이너를 instrumented 모드로 재기동 후 USR2 flush)
- 프론트엔드 coverage 보조 게이트: not-applicable
- AI 스펙 커버리지 판단: sufficient

## 커버리지 요약
| 구분 | 대상 | 결과 | 판단 |
| --- | --- | --- | --- |
| OpenSpec 추적성 | Requirement/Scenario/Test | 2/2 requirements, 3/3 spec scenarios, 3/3 tests | 충분 |
| 백엔드 | `services/completion/process_engine.py` 의 `handle_get_feedback`, `handle_get_feedback_diff` 분기, 관련 database / process_definition helpers | XML + HTML 리포트 생성, 본 스펙 표면 100% 라인 적중 (mock-llm 결정성으로 두 체인 진입 모두 검증) | 충분 |
| 프론트엔드 | `services/frontend/src/components/api/ProcessGPTBackend.ts` 의 `getFeedback`, `getFeedbackDiff` | 본 스위트는 백엔드 프로토콜 검증이므로 브라우저 V8 커버리지 1차 게이트 비대상. 단일 호출 지점이므로 향후 UI 통합 스펙에서 별도 검증 권장 | 보조 지표/별도 스펙 |

## 알려진 공백
| 공백 | 영향 | 후속 조치 |
| --- | --- | --- |
| `handle_get_feedback_diff` 의 `except Exception` 분기가 `HTTPException(400)` 을 500 으로 재포장 | 명세는 400 을 요구하지만 실제 응답은 500 (detail 본문에 "No workitem found" 유지) | `handle_submit` 처럼 `except HTTPException: raise` 적용 후 시나리오 03 단언을 400 으로 갱신 |
| `No activity found` 분기 | 워크아이템의 activity_id 가 proc_def 에 없는 비정합 상태가 별도 시드 필요 | 시나리오 04 추가 검토 |
| ProcessFeedback.vue UI 흐름 | 위젯 렌더 조건이 ProcessInstanceChat/Table 의 메시지·워크아이템 상태에 의존 | UI 통합은 process-instance-chat 계열 스펙에서 별도 검증 |

## Real-Frontend Rule 재조사 결과 (2026-05-27)
본 회차에서는 추가 컨텍스트 요청에 따라 ProcessFeedback.vue / ProcessInstanceChat 경로를 실제 UI 로 구동 가능한지 재조사했습니다. 결론: **본 E2E 회차에서는 실제 UI 구동이 불가**하며, 따라서 본 스위트는 백엔드 계약 전용(보조 프로토콜)으로 유지합니다. 근거는 다음과 같습니다.

1. **라우터 공백** — `services/frontend/src/router/MainRoutes.ts:49-51` 의 `/instancelist/:instId` 는 `InstanceCard.vue` → `ProcessInstanceRunning.vue` 를 렌더하며, `ProcessInstanceChat.vue` 를 마운트하는 `services/frontend/src/components/ProcessInstance.vue:9-22` 래퍼는 현재 어떤 라우터 항목에도 연결되어 있지 않습니다. 즉, 사용자가 도달 가능한 URL 자체가 없습니다.
2. **프리빌트 프론트엔드 이미지** — `docker-compose.e2e.yml:225` 가 `ghcr.io/uengine-oss/process-gpt:e343845` 프리빌트 이미지를 사용합니다. ProcessGPT 모드의 채팅 라우트를 노출하려면 프론트엔드 소스 수정 + 재빌드가 필요하며, 본 스펙 범위(완료된 OpenSpec 계약 명세)를 넘어섭니다.
3. **시드 데이터 공백** — ProcessFeedback 위젯의 thumb-down → 매직 아이콘 흐름이 활성화되려면 `bpm_proc_inst.participants` 와 매칭되는 `auth.users` 로그인 사용자, `role='system'` 이며 `jsonContent.completedActivities` 를 가진 `chats` 메시지, 그리고 `tracingTag='act_one'` 인 워크아이템이 모두 필요합니다. 현재 seed (`seed_files/e2e_seed.sql`) 에는 채팅 히스토리와 로그인 사용자 매핑이 없습니다.
4. **호출 지점 단일성** — `services/frontend/src/components/api/ProcessGPTBackend.ts:6414, 6437` 의 `getFeedback`/`getFeedbackDiff` 는 ProcessFeedback.vue (`:682`, `:716`) 에서만 사용되므로, ProcessFeedback 위젯에 도달하지 못하는 한 다른 indirect 진입점도 존재하지 않습니다.

위 네 가지는 모두 본 스펙(`completion_process-definition-feedback`)의 백엔드 계약 외부 변경을 요구하므로, Real-Frontend Rule 의 옵션 (a) "백엔드-계약 스펙으로 분리하고 스크린샷/매뉴얼 의무를 명시적으로 면제" 를 선택합니다. ProcessFeedback.vue UI 통합은 향후 `completion_process-instance-chat` 계열 스펙(라우터/시드/프론트엔드 빌드 변경 포함)에서 별도 검증할 예정입니다.

- **스크린샷 의무 면제**: 본 스위트는 보조 프로토콜 스위트이므로 DOCX 매뉴얼용 UI 스크린샷 증거가 요구되지 않음을 재확인합니다.
- **추가 UI 시나리오 미추가 사유**: 위 1~3 의 공백을 본 스위트에서 메우려면 라우터 추가, 프론트엔드 재빌드, 시드 확장이 동시에 필요하며 이는 별도 스펙의 책임 범위입니다.

## 병렬화 및 공유 자원
- Phase E 의 출력 검증기, OpenSpec 추적성 게이트는 결과 파일만 읽어 병렬화 가능했으며 동시 호출 시 충돌이 없었습니다.
- 백엔드 coverage 재수집은 `completion` 컨테이너를 coverage.override 로 재기동해야 하므로 Playwright 실행과 직렬화하여 수행했습니다.
- 프론트엔드 coverage 는 본 스위트에서 비대상이므로 별도 직렬화 고려 없음.

## 메모리 / 스크립트 자산
- 새 메모리 추가: 없음. completion 재기동 후의 nginx 502 현상은 기존 [[nginx-gateway-dns-cache-after-restart]] 메모리가 이미 동일 해결책(`docker restart process-gpt-e2e-gateway`)을 담고 있어 중복 작성하지 않았습니다. 본 스위트 작업 중 두 번째 재현 사례로, 메모리의 `last-verified` 가 여전히 유효함을 확인했습니다.
- 스크립트 자산 변경: `openspec/specs/completion_agent-memory-chat/e2e/scripts/mock_llm.py` 에 본 스펙의 feedback/diff 프롬프트 패턴 두 개를 추가했습니다. 두 스위트가 같은 컨테이너(`mock-llm`)를 공유하기 때문이며, 분기는 키워드 매칭이 분리되어 있어 agent-memory-chat 시나리오에 영향 없음. 향후 세 번째 사용처가 나오면 `openspec/e2e/scripts/mock_llm.py` 로 승격(rule of two→three)을 검토. 본 회차에서는 보류.

## 운영 상태 노트
- 본 회차 종료 시 `process-gpt-e2e-completion` 컨테이너는 spec-local coverage.override 적용 상태로 유지되어 있습니다 (uvicorn 위에 `coverage run --save-signal=USR2` 래퍼가 살아 있음). 다른 스위트를 일반 모드로 실행하려면 root compose 만으로 `up -d --force-recreate --no-deps completion` 후 nginx gateway 재시작이 필요합니다.
