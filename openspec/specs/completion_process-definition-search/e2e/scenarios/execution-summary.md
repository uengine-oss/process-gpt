# 프로세스 정의 검색 E2E 실행 요약

## 실행 메타데이터
- 스위트 슬러그: `completion_process-definition-search`
- 날짜: 2026-05-22
- 명령: `npx playwright test --config=../../openspec/specs/completion_process-definition-search/e2e/tests/playwright.config.mjs` (작업 디렉터리 `services/frontend`)
- Base URL: `http://localhost:8088` (nginx 게이트웨이)
- 환경: docker (`docker-compose.e2e.yml`)

## 입력
- 커버리지 매트릭스: `openspec/specs/completion_process-definition-search/e2e/scenarios/00-coverage-matrix.md`
- Playwright 명세: `openspec/specs/completion_process-definition-search/e2e/tests/completion_process-definition-search.spec.mjs`
- Docker compose: `docker-compose.e2e.yml`

## 결과
| 지표 | 값 |
| --- | --- |
| 상태 | passed |
| 통과 테스트 | 3 |
| 실패 테스트 | 0 |
| 건너뛴 테스트 | 0 |

## 워크플로 실행 절차
1. Docker compose 검증: `docker compose -f docker-compose.e2e.yml config --quiet` → 통과
2. 스택 기동: `docker-compose.e2e.yml` 스택이 기동된 상태에서 다음 변경분을 반영
   - `mock-llm` 스텁에 임베딩 실패 주입 토글(`POST /control/embed-fail`) 추가 → `mock-llm` 재생성
   - `db-seed-process-search` 서비스로 프로세스 정의 시드 적용 (`tenant-b` 테넌트 생성, `proc_def` 4건, `documents` 4건)
3. Sanity Check (게이트웨이 경유 실제 요청 경로):
   - 컨테이너 상태: db/auth/kong/completion/mock-llm healthy, gateway/frontend running
   - `POST http://localhost:8088/completion/process-search` (`localhost` 테넌트) → `200` + 프로세스 정의 후보 3건
   - 임베딩 실패 토글 ON → `POST .../completion/process-search` → `200` + 빈 목록 `[]` (graceful degradation 확인)
   - 임베딩 실패 토글 OFF → `POST .../completion/process-search` → `200` + 후보 3건 복원
   - `X-Forwarded-Host: tenant-b.example.com` 헤더로 `POST .../completion/process-search` → `200` + `tenant-b` 전용 후보 1건 (테넌트 격리 확인)
   - 브라우저 → 게이트웨이 → completion → `documents`/`mock-llm` 경로 정상 확인
4. Playwright 3개 시나리오 실행 → 3개 통과

## 산출물
- JSON 리포트: `openspec/specs/completion_process-definition-search/e2e/results/results.json`
- HTML 리포트: `openspec/specs/completion_process-definition-search/e2e/results/html-report/index.html`
- 스크린샷: `openspec/specs/completion_process-definition-search/e2e/results/screenshots/`
- 산출물: `openspec/specs/completion_process-definition-search/e2e/results/artifacts/`

## 스크린샷 맵
| 시나리오 | 체크포인트 | 스크린샷 파일 | 매뉴얼용 캡션 |
| --- | --- | --- | --- |
| 01 | `01-search-initial` | `openspec/specs/completion_process-definition-search/e2e/results/screenshots/process-gpt-completion_process-definition-search-01-search-initial.png` | 화면 상단의 통합 검색창에서 업무를 검색할 수 있습니다 |
| 01 | `01-search-input` | `openspec/specs/completion_process-definition-search/e2e/results/screenshots/process-gpt-completion_process-definition-search-01-search-input.png` | 찾고 싶은 업무를 자연어로 입력합니다 |
| 01 | `01-search-result` | `openspec/specs/completion_process-definition-search/e2e/results/screenshots/process-gpt-completion_process-definition-search-01-search-result.png` | 입력한 내용과 비슷한 프로세스 정의 후보가 목록으로 표시됩니다 |
| 02 | `02-search-input` | `openspec/specs/completion_process-definition-search/e2e/results/screenshots/process-gpt-completion_process-definition-search-02-search-input.png` | 검색어를 입력하고 검색을 실행합니다 |
| 02 | `02-search-empty` | `openspec/specs/completion_process-definition-search/e2e/results/screenshots/process-gpt-completion_process-definition-search-02-search-empty.png` | 검색 처리에 문제가 있어도 오류 없이 결과가 없다는 안내가 표시됩니다 |
| 03 | `03-search-result` | `openspec/specs/completion_process-definition-search/e2e/results/screenshots/process-gpt-completion_process-definition-search-03-search-result.png` | 검색 결과에는 현재 회사(테넌트)의 프로세스 정의만 표시됩니다 |

## 검증
- 출력 검증기: passed (`python .claude/skills/e2e-tests/scripts/validate_e2e_outputs.py --suite completion_process-definition-search --suite-root openspec/specs/completion_process-definition-search/e2e --require-results`)
- Playwright: passed (3/3)
- Docker compose config: passed (`docker compose -f docker-compose.e2e.yml config --quiet`)

## 알려진 공백
| 공백 | 영향 | 후속 조치 |
| --- | --- | --- |
| `/vision-process-search` 라우트 | 코드상 `/process-search` 와 동일 핸들러이며 이미지 분석 동작이 라우팅되지 않음(dead code). 별도 E2E 시나리오 미생성 | 두 라우트의 동일 동작은 코드 검토로 확인됨. 이미지 입력 UI가 추가되면 시나리오 보강 |
| 임베딩 실패 주입 방식 | 실제 호출자(`OpenAIEmbeddings`)가 텍스트를 토큰화하므로 질의 문자열 매칭이 아닌 `mock-llm` 런타임 토글로 실패를 주입 | 임베딩 경계 동작이 바뀌면 토글 메커니즘 재확인 필요 |
| 실행 환경 모듈 해석 | Playwright 설정/명세가 `@playwright/test` 를 import 하므로 `openspec/node_modules` → `services/frontend/node_modules` 정션이 필요 (테스트 실행용 환경 설정, 산출물 아님) | 클린 체크아웃에서 실행 시 해당 정션 생성 후 실행 |
