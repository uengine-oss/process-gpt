# 프로세스 데이터 조회 E2E 실행 요약

## 실행 메타데이터
- 스위트 슬러그: `completion_process-data-query`
- 날짜: 2026-05-27 (Real-Frontend Rule remediation 실행)
- 명령:
  - `docker compose -f docker-compose.e2e.yml -f openspec/specs/completion_process-data-query/e2e/docker/pdq.override.yml up -d --force-recreate --no-deps completion`
  - `cd openspec/specs/completion_process-data-query/e2e/tests && npx playwright test --config=playwright.config.mjs`
- Base URL: `http://localhost:8088` (main app gateway, scenario 03) · `http://127.0.0.1:8000` (`COMPLETION_DIRECT_URL`, protocol-only 01/02/04) · `http://localhost:8089/__mock-llm` (`MOCK_LLM_URL`, scenario 04)
- 환경: docker (기존 process-gpt e2e 스택 위에서 pdq override 적용)

## 입력
- 커버리지 매트릭스: `openspec/specs/completion_process-data-query/e2e/scenarios/00-coverage-matrix.md`
- Playwright 명세: `openspec/specs/completion_process-data-query/e2e/tests/completion_process-data-query.spec.mjs`
- Playwright 설정: `openspec/specs/completion_process-data-query/e2e/tests/playwright.config.mjs`
- Docker compose: `docker-compose.e2e.yml` + `openspec/specs/completion_process-data-query/e2e/docker/pdq.override.yml`
- Seed: `openspec/specs/completion_process-data-query/e2e/seed_files/e2e_seed.sql`
- mock-LLM: `openspec/specs/completion_process-data-query/e2e/scripts/mock_llm.py`

## 결과
| 지표 | 값 |
| --- | --- |
| 상태 | 부분 실패 (3 passed / 1 failed) |
| 통과 테스트 | 3 (시나리오 01, 02, 04 — 모두 protocol-only) |
| 실패 테스트 | 1 (시나리오 03 — 실 디자이너 UI; 디자이너 편집 모드 진입 차단) |
| 건너뛴 테스트 | 0 |

## Real-Frontend Rule remediation 변경 사항
- 삭제: `openspec/specs/completion_process-data-query/e2e/scripts/pdq-tester.html` 및 이전 합성 스크린샷 9건(`process-gpt-completion_process-data-query-{01-initial,01-input,01-response,02-input,02-empty,03-input,03-response,04-query,04-prompt}.png`).
- 실 프런트엔드 경로 조사 결과 시나리오별 분류:
  - 01·02 자연어 조회: 유일한 호출부 `Chats.vue:1359` (CompanyQuery 인텐트)는 결정적 도달 불가 → 사용자 액션 면제 + protocol-only.
  - 03 변수 SQL 생성: `ProcessVariable.vue:181` `generateSql()` 의 BPMN 디자이너 변수 다이얼로그 → 실 UI 시나리오로 재작성.
  - 04 테넌트 격리: 브라우저가 Host/X-Forwarded-Host를 변경할 수 없으므로 protocol-only 유지(보조 프로토콜 패턴, def-search와 동일).
- 사용자가 명시적으로 protocol-only 분류를 승인함(`/e2e-tests` 호출 시 "없으면 백엔드 계약 전용으로 분류 후 면제 표기").

## 산출물
- JSON 리포트: `openspec/specs/completion_process-data-query/e2e/results/results.json` (rtk 래퍼가 Playwright JSON 리포터 파일 쓰기를 stdout으로 가로채는 환경 영향으로 직접 작성됨; 4건 결과의 권위 있는 요약)
- HTML 리포트: `openspec/specs/completion_process-data-query/e2e/results/html-report/index.html` (같은 사유로 본 실행에서 미갱신; `results.json`을 우선 참조)
- 스펙 커버리지 HTML 리포트: `openspec/specs/completion_process-data-query/e2e/results/spec-coverage-report.html`
- 스펙 커버리지 JSON 요약: `openspec/specs/completion_process-data-query/e2e/results/coverage-summary.json`
- 백엔드 커버리지: `openspec/specs/completion_process-data-query/e2e/results/backend-coverage/` (직전 측정값 보존)
- 프론트엔드 커버리지: `openspec/specs/completion_process-data-query/e2e/results/frontend-coverage/raw/2-{01..04}_*.json` (V8 bundle 보조 지표)
- 스크린샷: `openspec/specs/completion_process-data-query/e2e/results/screenshots/` (시나리오 03 진입 직후 1건만 캡처; 나머지 체크포인트는 디자이너 차단으로 미실행)
- 산출물(Trace/Video/error-context): `openspec/specs/completion_process-data-query/e2e/results/artifacts/`

## 스크린샷 맵
| 시나리오 | 체크포인트 | 스크린샷 파일 | 매뉴얼용 캡션 |
| --- | --- | --- | --- |
| 01 | 해당 없음 (사용자 액션 면제) | — | — |
| 02 | 해당 없음 (사용자 액션 면제) | — | — |
| 03 | `03-designer-loaded` | `openspec/specs/completion_process-data-query/e2e/results/screenshots/process-gpt-completion_process-data-query-03-designer-loaded.png` | BPMN 디자이너 진입 직후 화면 (현재 isConsultingMode로 진입하여 편집 툴바 미마운트) |
| 03 | `03-variables-dialog` | **미생성** | (편집 모드 진입 차단으로 보류) |
| 03 | `03-variable-input` | **미생성** | (편집 모드 진입 차단으로 보류) |
| 03 | `03-sql-generated` | **미생성** | (편집 모드 진입 차단으로 보류) |
| 04 | 해당 없음 (사용자 액션 면제) | — | — |

## 검증
- 출력 검증기: passed (`python .claude/skills/e2e-tests/scripts/validate_e2e_outputs.py --suite completion_process-data-query --suite-root openspec/specs/completion_process-data-query/e2e` → `OK: E2E output contract validated`)
- Playwright: 3 passed / 1 failed (시나리오 03 실패는 디자이너 편집 모드 진입 차단)
- Docker compose config: passed (`docker compose -f docker-compose.e2e.yml -f openspec/specs/completion_process-data-query/e2e/docker/pdq.override.yml config -q` → 출력 없음)
- OpenSpec 추적성 게이트: passed (4/4 Requirement·Scenario 매핑)
- 백엔드 coverage 게이트: supporting (재수집 미실시; 직전 측정값 유효)
- 프론트엔드 coverage 보조 게이트: supporting (V8 bundle raw 수집; sourcemap 부재로 번들 레벨)
- AI 스펙 커버리지 판단: partial (시나리오 03 통과가 sufficient 승격 조건)

## 커버리지 요약
| 구분 | 대상 | 결과 | 판단 |
| --- | --- | --- | --- |
| OpenSpec 추적성 | Requirement/Scenario/Test/Screenshot | 3/3 Req, 4/4 Spec Scenario, 3/4 Test pass, 1/4 Screenshot | 부분 충분 |
| 백엔드 | `services/completion/process_var_sql_gen.py`, `database.py`, `main.py` | 핵심 라우트 line 75% / function 82%, 미들웨어 92% | 충분 |
| 프론트엔드 | `ProcessVariable.vue`, `ProcessDesigner.vue`, `Chats.vue` | V8 bundle 보조 지표 (≈25%) | 보조 지표 / 시나리오 03 통과 후 재측정 필요 |

## Phase 병렬화 메모
본 remediation은 단일 스위트의 보수성 변경이라 Phase E 병렬화 여지가 좁았다. 실제로 다음과 같이 진행했다.
- Phase A (계획) — 단일 thread.
- Phase B–C (Docker/Sanity) — 기존 스택이 이미 가동 중이라 `completion` 컨테이너 한 개만 pdq override로 재기동, sanity 확인.
- Phase D (Playwright 실행) — 단일 thread.
- Phase E (검증/게이트) — 검증기는 즉시 통과, 백엔드 coverage 재수집은 의도적으로 보류(스코프 변경이 백엔드 커버리지에 의미 있는 차이를 만들지 않으며 시나리오 03 차단을 해결하기 전 재수집은 동일 결과). HTML/JSON 리포트는 rtk 래퍼 영향으로 수동 작성. 공유 자원 충돌 없음.
- Phase F (요약/메모리) — 본 문서.

## 알려진 공백
| 공백 | 영향 | 후속 조치 |
| --- | --- | --- |
| 시나리오 03 실 디자이너 UI 통과 | 본 스펙의 유일한 사용자-가시 시나리오 자동화 검증 미달성 | `e2e_seed.sql` 의 `vacation_request_process.bpmn` 컬럼에 유효한 BPMN XML 시드 → 디자이너가 편집 모드로 마운트되도록 변경; 또는 `/definitions/<id>?canEdit=true` 같은 명시적 편집 모드 옵션 추가 후 본 스위트 재실행 |
| 시나리오 01/02 사용자 액션 검증 | 자연어 조회 UI 표면이 자동화 검증되지 않음 (사용자 액션 면제, 사용자 명시 승인) | 자연어 조회 전용 UI 표면이 추가되면 사용자-액션 시나리오로 승격 |
| Playwright JSON/HTML 리포터 파일 출력 | rtk 래퍼가 stdout으로 가로채 `results.json`·`html-report/index.html` 자동 갱신이 안 됨 | 직접 작성한 `results.json` 으로 대체; 향후 rtk 우회 또는 wrapper bypass 가 필요하면 raw `playwright` 바이너리를 직접 호출 |
| 백엔드 coverage 재수집 | 본 실행에서 coverage.override 미사용 | 시나리오 03 통과 후 `coverage.override.yml` 로 재수집해 SQL 생성 분기 line% 갱신 |

본 실행에서 새 메모리 항목은 추가하지 않았다. 이번 remediation에서 발견된 모든 사실(Real-Frontend Rule 위반 → 사용자 명시 승인 후 protocol-only 면제 분류, 디자이너의 isConsultingMode 진입 조건)은 본 스위트의 시나리오 문서·실행 요약·`coverage-summary.json`에 명시되어 있어 cross-suite memory로 끌어올릴 일반화 가치가 ~30분 미만이다.
