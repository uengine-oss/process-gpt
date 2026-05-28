# 프로세스 정의 검색 E2E 커버리지 매트릭스

## 범위
- 스위트 슬러그: `completion_process-definition-search`
- 원본 명세 ID: `completion_process-definition-search`
- 원본 명세:
  - `openspec/specs/completion_process-definition-search/spec.md`
- 백엔드/제품 계약:
  - `services/completion` FastAPI 라우트: `POST /process-search`, `POST /vision-process-search`
  - 벡터 저장소: Supabase pgvector (`vecs.documents`) + `match_documents` RPC, 1536차원 임베딩
  - 임베딩 외부 경계: OpenAI 호환 임베딩 프록시 (E2E 에서는 `mock-llm` 의 `/v1/embeddings` 로 결정성 확보)
  - 테넌트 컨텍스트: `services/completion/main.py` 의 `DBConfigMiddleware` 가 요청 헤더 `X-Forwarded-Host` 를 `subdomain` 으로 변환하여 `database.subdomain_var` 에 주입
- E2E 루트: `openspec/specs/completion_process-definition-search/e2e/`
- Playwright 명세: `openspec/specs/completion_process-definition-search/e2e/tests/completion_process-definition-search.spec.mjs`
- 결과 디렉터리: `openspec/specs/completion_process-definition-search/e2e/results/`

## 시나리오 목록
| ID | 시나리오 문서 | Playwright 테스트 제목 | 주요 동작 |
| --- | --- | --- | --- |
| 01 | `01-search-success.md` | `헤더 검색바에서 자연어 키워드를 입력하면 유사한 프로세스 정의가 표시된다` | UI: 헤더 Searchbar 입력 → `유사한 프로세스 정의` 카테고리 결과 표시 |
| 02 | `02-empty-result.md` | `유사한 프로세스 정의가 없을 때 200 과 빈 목록을 반환한다` | 보조 프로토콜: 비매칭 키워드로 `POST /completion/process-search` 호출 → `200`/`[]` |
| 03 | `03-tenant-isolation.md` | `테넌트 subdomain 에 따라 검색 결과가 분리된다` | 보조 프로토콜: 두 테넌트 subdomain 으로 `POST /process-search` 호출 → 결과 분리 확인 |

> 시나리오 02/03 은 라우트 분기/테넌트 격리 계약 검증이며 UI 표면이 별도 화면이 아니라 동일한 헤더 검색바 경로의 보조 검증입니다. 사용자-facing 시나리오는 01 입니다.

## 요구사항 커버리지
| 명세 | 요구사항 | 필수 수준 | 커버 시나리오 | 비고 |
| --- | --- | --- | --- | --- |
| `completion_process-definition-search` | 자연어 프로세스 정의 검색 | SHALL | 01, 02 | 검색 성공 + 빈 결과 |
| `completion_process-definition-search` | 검색 범위의 테넌트 격리 | SHALL | 03 | subdomain 기반 결과 분리 |

## 명세 시나리오 커버리지
| 명세 | 요구사항 | 명세 시나리오 | 커버 시나리오 | 사용자 검증 표면 |
| --- | --- | --- | --- | --- |
| `completion_process-definition-search` | 자연어 프로세스 정의 검색 | 유사 프로세스 정의 검색 성공 | 01 | 헤더 검색바 입력 → `유사한 프로세스 정의` 결과 카테고리 |
| `completion_process-definition-search` | 자연어 프로세스 정의 검색 | 검색 결과 없음 | 02 | 보조 프로토콜 (UI 가 동일 경로를 공유하므로 별도 화면 없음) |
| `completion_process-definition-search` | 검색 범위의 테넌트 격리 | 테넌트별 검색 범위 제한 | 03 | 보조 프로토콜 (게이트웨이 우회 + X-Forwarded-Host) |

## 스펙 관련 코드 표면
### 백엔드
| 파일 | 함수/클래스/라우트 | 관련 요구사항 | 커버리지 기준 | 선정 근거 |
| --- | --- | --- | --- | --- |
| `services/completion/process_def_search.py` | `combine_input_with_process_definition` (`POST /process-search`, `POST /vision-process-search`) | 자연어 검색 라우트 | function = 100% | 두 라우트 진입 핸들러 |
| `services/completion/process_def_search.py` | `add_routes_to_app` | 라우트 등록 | function = 100% | FastAPI 라우트 등록 진입점 |
| `services/completion/process_var_sql_gen.py` | `get_process_definitions` | 벡터 유사도 검색 + 테넌트 필터 + 실패 시 빈 목록 | line >= 80% / branch >= 75% | `k=3` 제한, `tenant_id` 필터, `Exception` → `[]` 분기 핵심 |
| `services/completion/database.py` | `get_vector_store` | Supabase 벡터 스토어 인스턴스화 | function 호출 검증 | `match_documents` RPC 진입 |
| `services/completion/database.py` | `update_tenant_id`, `subdomain_var` 사용 | 테넌트 컨텍스트 | function 호출 검증 | `X-Forwarded-Host` → `tenant_id` |

### 프론트엔드
| 파일 | 컴포넌트/함수/API 호출 | 관련 요구사항 | 커버리지 기준 | 선정 근거 |
| --- | --- | --- | --- | --- |
| `services/frontend/src/layouts/full/vertical-header/Searchbar.vue` | `search` 메서드, 결과 렌더링 | 검색 입력/결과 표시 표면 | line >= 60% | 사용자 진입점 |
| `services/frontend/src/components/api/ProcessGPTBackend.ts` | `search`, `searchVector` | `/completion/process-search` 호출 + 결과 매핑 | line >= 50% (관련 함수 한정) | 백엔드 호출 클라이언트 |

> 프론트엔드 source-mapped 커버리지는 `services/frontend` 를 호스트에서 `npx vite build --minify=false --sourcemap` 으로 사전 빌드한 뒤 prebuilt 이미지로 마운트하는 패턴을 시도하고, 실패하면 V8 번들 coverage 를 보조 지표로 기록합니다.

## 재사용 산출물
- `openspec/e2e/scripts/mock_llm.py` — `/v1/embeddings` 결정성 임베딩 응답(`hash(token) % N`) 을 그대로 사용.
- `openspec/e2e/scripts/monocart_report.mjs`, `openspec/e2e/scripts/write_coverage_report.mjs` — 프론트엔드 V8/source-mapped coverage 병합 및 AI 커버리지 HTML 리포트 생성기 재사용.
- `openspec/specs/completion_agent-memory-chat/e2e/docker/nginx.e2e.conf` 의 `/completion/` 프록시 룰을 참고하여 본 스위트 게이트웨이 설정 작성.
- `infra/volumes/db/*` Supabase 초기화 스크립트와 `init.sql` 시드를 그대로 재사용 (compose volume 매핑).

## 미검증 및 보류 항목
| 항목 | 사유 | 후속 조치 |
| --- | --- | --- |
| `POST /vision-process-search` | 비전 입력 UI 가 본 스위트의 사용자 표면(헤더 검색)에 존재하지 않음 | 비전 입력 UI 가 추가되면 별도 시나리오로 분리. 라우트 자체는 텍스트 시나리오 핸들러와 동일 (`combine_input_with_process_definition`) |
| 프론트엔드 source-mapped coverage | prebuilt 이미지가 sourcemap 없이 제공될 경우 V8 번들 보조 지표만 수집됨 | source-built coverage 이미지 패턴이 정착되면 재수집 |

## 체크리스트
- [x] 모든 Requirement 가 하나 이상의 E2E 시나리오에 매핑되어 있습니다.
- [x] 중요한 OpenSpec Scenario 가 E2E 시나리오에 매핑되어 있거나 미검증 및 보류 항목에 기록되어 있습니다.
- [x] 사람이 읽는 요구사항명, 명세 시나리오명, 목적, 절차, 기대 결과는 한국어로 작성되어 있습니다.
- [x] 원본 OpenSpec 의 영어 표현은 한국어로 변환되었고, API 경로/필드명/이벤트명은 원문 식별자를 유지합니다.
- [x] 원본 명세가 하나의 백엔드 연계 피쳐 범위이며, 마이크로서비스 전체 요약이나 프론트엔드 단독 명세가 아닙니다.
- [x] 명세 ID 의 서비스 접두어/도메인 구분자가 frontend/ui/react/page/component 같은 구현 레이어가 아닙니다.
- [x] 실행 대상인 소유 백엔드 서비스/API/데이터 계약이 명확합니다.
- [x] 서비스 접두형 명세 ID 와 스위트 슬러그가 동일합니다.
- [x] E2E 시나리오/스크립트/seed/실행 결과/스크린샷은 `openspec/specs/completion_process-definition-search/e2e/` 아래에 응집되어 있습니다.
- [x] 사용자-facing 시나리오(01)는 직접 API 가 아니라 헤더 검색바 UI 상호작용으로 검증합니다.
- [x] 시나리오별 스크린샷 체크포인트가 매뉴얼 재사용 가능한 UI 상태를 설명합니다.
- [x] 스펙 관련 백엔드/프론트엔드 파일과 함수가 코드 표면 표에 기록되어 있습니다.
- [x] 커버리지 기준이 전체 저장소가 아니라 스펙 관련 파일/함수 중심으로 정의되어 있습니다.
- [x] 결과 경로가 `OUTPUT_CONTRACT.md` 와 일치합니다.
