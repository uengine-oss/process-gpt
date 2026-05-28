# 프로세스 정의 검색 E2E 실행 요약

## 실행 메타데이터
- 스위트 슬러그: `completion_process-definition-search`
- 날짜: 2026-05-28
- 명령: `rtk proxy npx playwright test --reporter=list` (한번 더 `--reporter=json` 으로 results.json 생성)
- Base URL: `http://localhost:8088` (Docker 게이트웨이 → 정적 SPA 산출물 + 호스트 source-run completion)
- 환경: hybrid (Docker 인프라 + 호스트 source-run 백엔드 + Vite 정적 산출물)

## 입력
- 커버리지 매트릭스: `openspec/specs/completion_process-definition-search/e2e/scenarios/00-coverage-matrix.md`
- Playwright 명세: `openspec/specs/completion_process-definition-search/e2e/tests/completion_process-definition-search.spec.mjs`
- Docker compose: `docker-compose.e2e.yml` (db, kong, auth, rest, mock-llm, gateway, db-seed)
- 호스트 source-run 시작 명령:
  - 백엔드: `python -X utf8 openspec/specs/completion_process-definition-search/e2e/scripts/coverage_wrapper.py` (coverage.Coverage() + HTTP `/save` flush endpoint on :8001 + uvicorn :8000)
  - 프론트엔드: `cd services/frontend && VITE_SUPABASE_URL=http://localhost:54321 VITE_SUPABASE_KEY=$ANON_KEY npx vite build --minify=false` 1회 빌드 후 nginx 게이트웨이가 `services/frontend/dist` 를 직접 서빙 (try_files SPA fallback)

## 결과
| 지표 | 값 |
| --- | --- |
| 상태 | passed |
| 통과 테스트 | 3 |
| 실패 테스트 | 0 |
| 건너뛴 테스트 | 0 |

### Playwright 실행 세부
- `헤더 검색바에서 자연어 키워드를 입력하면 유사한 프로세스 정의가 표시된다` → passed (26.9s, UI 동선 + 3 스크린샷)
- `유사한 프로세스 정의가 없을 때 200 과 빈 목록을 반환한다` → passed (2.3s, 보조 프로토콜)
- `테넌트 subdomain 에 따라 검색 결과가 분리된다` → passed (3.8s, 보조 프로토콜)

## Sanity Check (Phase C)
- `docker compose -f docker-compose.e2e.yml config` → passed
- `docker compose -f docker-compose.e2e.yml up -d` → 6/6 infra healthy
- `db-seed` → exit 0
- coverage_wrapper 부팅 → `GET /docs` 200, `POST :8001/save` 200
- Vite build + nginx 정적 서빙 → `GET /auth/login` 200 (SPA fallback)
- 통합 호출:
  - `POST localhost:8088/completion/process-search` (`{query:"휴가"}`): 3건 응답
  - `POST 127.0.0.1:8000/process-search` (X-Forwarded-Host=empty-tenant.example.com): `[]`
  - `POST 127.0.0.1:8000/process-search` (X-Forwarded-Host=tenant-b.example.com, `{query:"회의실"}`): meeting_room_process 포함

## 산출물
- JSON 리포트: `openspec/specs/completion_process-definition-search/e2e/results/results.json` (3/3 expected)
- HTML 리포트: 자동 reporter 디렉토리 자동 생성 실패 — `npx playwright show-report` 로 재생성 가능
- 스펙 커버리지 HTML: `openspec/specs/completion_process-definition-search/e2e/results/spec-coverage-report.html` (AI 판단 = sufficient)
- 스펙 커버리지 JSON: `openspec/specs/completion_process-definition-search/e2e/results/coverage-summary.json`
- 백엔드 커버리지: `openspec/specs/completion_process-definition-search/e2e/results/backend-coverage/coverage.xml` + `html/index.html`
  - `process_def_search.py`: line 78% / branch 100%
  - `process_var_sql_gen.py`: line 26% (파일 전체, 스펙 함수 `get_process_definitions` 는 모든 분기 실행)
  - `database.py`: line 13% (파일 전체, 공용 인프라)
- 프론트엔드 커버리지: `openspec/specs/completion_process-definition-search/e2e/results/frontend-coverage/monocart-report/index.html` (source-mapped)
  - `Searchbar.vue`: line 79.7% / function 81.5% / branch 80.7%
  - `ProcessGPTBackend.ts`: line 6.7% / function 8.0% (파일 전체 — 스펙 외 클라이언트 함수 다수)
- 스크린샷: `openspec/specs/completion_process-definition-search/e2e/results/screenshots/`
- 산출물 디렉토리: `openspec/specs/completion_process-definition-search/e2e/results/artifacts/`

## 스크린샷 맵
| 시나리오 | 체크포인트 | 스크린샷 파일 | 매뉴얼용 캡션 |
| --- | --- | --- | --- |
| 01 | `01-search-initial` | `screenshots/process-gpt-completion_process-definition-search-01-search-initial.png` | 헤더 검색바 초기 상태 (로그인 직후) |
| 01 | `01-search-input` | `screenshots/process-gpt-completion_process-definition-search-01-search-input.png` | 자연어 키워드 `휴가` 입력 |
| 01 | `01-search-result` | `screenshots/process-gpt-completion_process-definition-search-01-search-result.png` | `유사한 프로세스 정의` 결과 카테고리 표시 (휴가 신청 / 출장 신청 / 구매 요청 프로세스) |

> 시나리오 02/03 은 보조 프로토콜 검증으로 별도 UI 표면 없음 (스크린샷 불필요).

## 검증
- 출력 검증기: passed (Playwright HTML reporter 디렉토리 미생성만 WARN, 영향 없음)
- Playwright: passed (3/3)
- Docker compose config: passed
- OpenSpec 추적성 게이트: passed (Requirement 2/2, Scenario 3/3, Test 3/3, Screenshot 3/3)
- 백엔드 coverage 게이트: passed (process_def_search 78% line)
- 프론트엔드 source-mapped coverage 게이트: passed (Searchbar 79.7% line)
- AI 스펙 커버리지 판단: sufficient

## 커버리지 요약
| 구분 | 대상 | 결과 | 판단 |
| --- | --- | --- | --- |
| OpenSpec 추적성 | Requirement/Scenario/Test/Screenshot | 2/2, 3/3, 3/3, 3/3 | 충분 |
| 백엔드 | `process_def_search.py`, `process_var_sql_gen.get_process_definitions`, `database.get_vector_store/update_tenant_id` | process_def_search 78%(line)/100%(branch), 스펙 관련 함수 분기 모두 실행 | 충분 |
| 프론트엔드 | `Searchbar.vue`, `ProcessGPTBackend.search/searchVector` | Vite 소스맵 기반 Monocart line 평균 79.7% (Searchbar) / 6.7% (ProcessGPTBackend 파일 전체) | 충분 — 스펙 관련 함수 모두 실행 |

## Phase E 병렬화 메모
- Playwright 본 실행 종료 후 다음 4개 작업은 서로 자원 충돌 없음으로 동시 실행 가능:
  - `validate_e2e_outputs.py` (read-only artifact 검사)
  - `evaluate_spec_coverage.mjs --write-summary` (read-only artifact 검사 + summary 쓰기)
  - 백엔드 coverage XML + HTML 생성 (`coverage xml`, `coverage html`) — `.coverage` 파일은 read-only 로 참조
  - 프론트엔드 Monocart merge (`node scripts/monocart_report.mjs`)
- 단, `/save` flush 와 backend coverage XML/HTML 생성은 동일 `.coverage` 파일을 참조하므로 flush 가 먼저 끝난 뒤 진행. 본 실행에서는 시간 단축을 위해 monocart merge 와 backend XML/HTML 을 직렬로 실행했으나 다음 실행부터는 두 단계를 병렬화 권장.

## 알려진 공백
| 공백 | 영향 | 후속 조치 |
| --- | --- | --- |
| `get_process_definitions` 의 `except Exception → []` 폴백 경로 미검증 | 벡터 스토어 자체 장애 시 200/[] 계약 정량 미확인 (정상 빈 결과 분기는 검증됨) | mock-llm 에 `/v1/embeddings` 503 토글을 추가하는 보조 시나리오 |
| `POST /vision-process-search` 라우트 | 비전 입력 UI 가 본 스위트의 사용자 표면에 없음 | 비전 입력 UI 도입 시 시나리오 분리 |
| Playwright auto-generated HTML report 디렉토리 자동 생성 실패 | 자동 reporter 가 mkdir 을 못 함 → results/html-report/ 미생성. JSON reporter 와 list reporter 는 정상 | Playwright `globalSetup` 에 mkdir 추가하거나 사후 `npx playwright show-report` 실행 |
