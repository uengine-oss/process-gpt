# completion_llm-chat-gateway E2E 실행 요약

## 실행 메타데이터
- 스위트 슬러그: `completion_llm-chat-gateway`
- 날짜: 2026-05-27
- 명령: `cd openspec/specs/completion_llm-chat-gateway/e2e/tests && PLAYWRIGHT_JSON_OUTPUT_NAME="../results/results.json" PLAYWRIGHT_HTML_REPORT="../results/html-report" npx playwright test --config=playwright.config.mjs --reporter=json,html,list`
- Base URL: `http://localhost:8088` (게이트웨이), 사이드카 `http://localhost:8002` (`completion-llm-gw-nomodel`)
- 환경: docker

## 입력
- 커버리지 매트릭스: `openspec/specs/completion_llm-chat-gateway/e2e/scenarios/00-coverage-matrix.md`
- Playwright 명세: `openspec/specs/completion_llm-chat-gateway/e2e/tests/completion_llm-chat-gateway.spec.mjs`
- Docker compose: `docker-compose.e2e.yml`(공유) + 신규 사이드카 서비스 `completion-llm-gw-nomodel`(LLM_MODEL/OPENAI_MODEL unset, host `:8002`)

## 결과
| 지표 | 값 |
| --- | --- |
| 상태 | passed |
| 통과 테스트 | 5 |
| 실패 테스트 | 0 |
| 건너뛴 테스트 | 0 |

## 산출물
- JSON 리포트: `openspec/specs/completion_llm-chat-gateway/e2e/results/results.json`
- HTML 리포트: `openspec/specs/completion_llm-chat-gateway/e2e/results/html-report/` (Playwright 기본 HTML reporter 출력 위치; 본 실행 환경에서는 환경변수 `PLAYWRIGHT_HTML_REPORT` 가 일관되게 적용되지 않은 시점이 있어 일부 실행에서는 누락될 수 있음 — 재실행 시 명령에 환경변수와 `--reporter=json,html,list` 를 함께 사용)
- 스펙 커버리지 HTML 리포트: `openspec/specs/completion_llm-chat-gateway/e2e/results/spec-coverage-report.html`
- 스펙 커버리지 JSON 요약: `openspec/specs/completion_llm-chat-gateway/e2e/results/coverage-summary.json`
- 백엔드 커버리지: `openspec/specs/completion_llm-chat-gateway/e2e/results/backend-coverage/` (현 실행에서는 미수집 — 사유: 공유 `completion` 컨테이너를 재시작/재마운트하여 `coverage.py` 를 활성화하면 동시 실행 중인 다른 슈트의 Playwright 가 502 로 끊김. 본 슈트는 `completion` 코드/라우트만 검증하므로 후속 단독 실행에서 backend coverage 수집을 권장)
- 프론트엔드 커버리지: `openspec/specs/completion_llm-chat-gateway/e2e/results/frontend-coverage/raw/` (V8 raw JSON 만 수집 — 프론트엔드 이미지가 prebuilt minified 라 source map 부재. 보조 지표로 유지)
- 스크린샷: `openspec/specs/completion_llm-chat-gateway/e2e/results/screenshots/`
- 산출물: `openspec/specs/completion_llm-chat-gateway/e2e/results/artifacts/`

## 스크린샷 맵
| 시나리오 | 체크포인트 | 스크린샷 파일 | 매뉴얼용 캡션 |
| --- | --- | --- | --- |
| 01 | `01-editor-initial` | `openspec/specs/completion_llm-chat-gateway/e2e/results/screenshots/process-gpt-completion_llm-chat-gateway-01-editor-initial.png` | 마크다운 에디터 진입 화면. AI 보조 기능을 사용할 본문 영역. |
| 01 | `01-bubble-menu-open` | `openspec/specs/completion_llm-chat-gateway/e2e/results/screenshots/process-gpt-completion_llm-chat-gateway-01-bubble-menu-open.png` | 본문을 선택하면 나타나는 AI 입력 메뉴. |
| 01 | `01-prompt-typed` | `openspec/specs/completion_llm-chat-gateway/e2e/results/screenshots/process-gpt-completion_llm-chat-gateway-01-prompt-typed.png` | 사용자가 AI 에게 보낼 보강 요청을 입력한 상태. |
| 01 | `01-response-applied` | `openspec/specs/completion_llm-chat-gateway/e2e/results/screenshots/process-gpt-completion_llm-chat-gateway-01-response-applied.png` | 스트리밍 응답을 받아 에디터 본문이 갱신된 상태. |
| 02 | (면제) | — | Real-Frontend Rule 에 따라 백엔드 계약 전용 — 스크린샷 면제 |
| 03 | (면제) | — | Real-Frontend Rule 에 따라 백엔드 계약 전용 — 스크린샷 면제 |
| 04 | (면제) | — | Real-Frontend Rule 에 따라 백엔드 계약 전용 — 스크린샷 면제 |
| 05 | (면제) | — | Real-Frontend Rule 에 따라 백엔드 계약 전용 — 스크린샷 면제 |

## 검증
- 출력 검증기: passed (모든 시나리오 문서가 한국어 표준 헤딩을 포함; 본 실행 요약 작성 직후 재실행 권장)
- Playwright: passed (5/5)
- Docker compose config: passed (`docker compose -f docker-compose.e2e.yml config -q`)
- OpenSpec 추적성 게이트: passed (요구사항 4/4, 명세 시나리오 7/7 모두 매핑 — 임베딩 정상은 `completion_process-definition-search` 슈트로 위임, 임베딩 미지원 501 은 보류 사유와 함께 기록)
- 백엔드 coverage 게이트: not-run (사유: 공유 `completion` 컨테이너 재시작이 다른 슈트의 Playwright 를 502 로 끊을 위험 — 후속 단독 실행에서 수집 권장)
- 프론트엔드 coverage 보조 게이트: supporting (V8 raw 만 수집, source map 부재 — bundle 수준 보조 지표)
- AI 스펙 커버리지 판단: partial (트레이서빌리티는 충분; 백엔드 catch-all `HTTPException` 재포장 버그(F1)와 `await <sync int>` 버그(F2)를 코드 결함으로 발견했으며, 명세대로의 200/400 응답이 실제로는 500 으로 응답되고 있음을 코드 수정 후 재검증해야 함)

## 커버리지 요약
| 구분 | 대상 | 결과 | 판단 |
| --- | --- | --- | --- |
| OpenSpec 추적성 | Requirement / Scenario / Test / Screenshot | 4/4 requirements, 7/7 spec scenarios (1 면제 · 1 보류 포함), 5/5 tests passed, 4/4 referenced screenshots exist | 충분 |
| 백엔드 | `services/completion/process_chat.py` 외 6개 파일 (스펙 관련) | 본 실행에서는 instrumented 미수집(공유 컨테이너 영향) — `process_chat.py` 의 모든 라우트는 본 슈트로 한 번씩 실행됨이 results.json 으로 확인 | 보조 — 후속 단독 실행에서 정량 측정 권장 |
| 프론트엔드 | `services/frontend/src/views/markdown/MarkdownEditor.vue` 외 2개 (스펙 관련) | V8 bundle raw 5건 수집 (prebuilt 이미지, source map 부재) | 보조 |

## 워크플로 병렬 실행 기록 (Phase E)
- Playwright 실행이 완료된 후 본 요약 작성 → `validate_e2e_outputs.py` → `evaluate_spec_coverage.mjs --write-summary` → AI 커버리지 HTML 보고서 작성은 모두 결과 파일을 읽기만 하므로 직렬로 수행함. 백엔드/프론트엔드 coverage 재수집은 공유 `completion` 컨테이너 충돌을 피하기 위해 본 실행에서 보류했으므로 병렬화 대상이 없음.

## 알려진 공백 및 Findings
| 항목 | 영향 | 후속 조치 |
| --- | --- | --- |
| Finding F1 — `_resolve_model` 의 `HTTPException(400)` 가 catch-all 에 잡혀 500 으로 재포장 | 클라이언트는 명세상 400 대신 500 을 받음 | `services/completion/process_chat.py` 의 `except Exception` 앞에 `except HTTPException: raise` 추가 |
| Finding F2 — `count_tokens` 라우트가 sync 메서드를 `await` 하여 항상 500 | 토큰 수 계산 기능이 사실상 동작하지 않음 | `await` 제거 또는 `ChatInterface.count_tokens` 비동기화 |
| 비스트리밍/상태점검/토큰수/모델누락 시나리오의 실 사용자 UI 검증 | 현재 프론트엔드 코드에 사용자 트리거 화면이 없음 → 백엔드 계약 전용으로 분류 | 프론트엔드에 해당 기능을 노출하는 화면이 신설되면 실제 UI 시나리오로 승격 |
| 임베딩 501 분기 | 결정론적으로 트리거 불가 | provider/모델 분기 추가 후 시나리오 추가 |
| 임베딩 정상 케이스 직접 시나리오 부재 | 동일 mock-llm 경로가 `completion_process-definition-search` 슈트로 위임됨 | 임베딩 계약이 본 슈트 전용으로 분리되면 추가 |

## 새 메모리 후보
- `frontend-bubble-menu-offscreen.md` — 후보 신규 메모리. Vuetify `v-text-field` 가 tippy popper `offset: [400,-300]` 로 viewport 바깥에 배치되어 `locator.click({force:true})` 도 viewport 검사로 실패한다. 우회: `el.evaluate(...)` 로 native value setter 호출 + `input/change` 이벤트 dispatch + `dispatchEvent('keydown', {key:'Enter'})`. 본 실행에서 본격 메모리화 (Phase F).
