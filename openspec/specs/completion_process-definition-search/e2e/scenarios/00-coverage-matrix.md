# 프로세스 정의 검색 E2E 커버리지 매트릭스

## 범위
- 스위트 슬러그: `completion_process-definition-search`
- 원본 명세 ID: `completion_process-definition-search` <!-- `<microservice>_<domain>-<feature>` 형식이므로 스위트 슬러그와 동일하게 유지 -->
- 원본 명세:
  - `openspec/specs/completion_process-definition-search/spec.md`
- 백엔드/제품 계약:
  - 소유 백엔드: `completion` 서비스 (`services/completion`, FastAPI, 포트 8000)
  - API 라우트: `POST /process-search`, `POST /vision-process-search` (`process_def_search.py` 의 동일 핸들러 `combine_input_with_process_definition`)
  - 검색 로직: `process_var_sql_gen.py` 의 `get_process_definitions` — `documents` 테이블 + `match_documents` RPC 유사도 검색
  - 테넌트 격리: 검색 필터 `{"tenant_id": <subdomain>, "type": "process_definition"}` (`subdomain_var`)
  - 임베딩 경계: LLM 프록시 경유 `OpenAIEmbeddings` (E2E 에서는 `mock-llm` 스텁으로 대체)
- E2E 루트: `openspec/specs/completion_process-definition-search/e2e/`
- Playwright 명세: `openspec/specs/completion_process-definition-search/e2e/tests/completion_process-definition-search.spec.mjs`
- 결과 디렉터리: `openspec/specs/completion_process-definition-search/e2e/results/`

## 시나리오 목록
| ID | 시나리오 문서 | Playwright 테스트 제목 | 주요 동작 |
| --- | --- | --- | --- |
| 01 | `01-natural-language-search.md` | `자연어 질의로 유사한 프로세스 정의를 검색한다` | 헤더 통합 검색창에 질의 입력 후 검색 → "유사한 프로세스 정의" 결과 확인 |
| 02 | `02-empty-result-graceful.md` | `검색 처리에 실패해도 오류 없이 빈 결과가 표시된다` | 임베딩 실패를 유발하는 질의로 검색 → 오류 화면 대신 "검색 결과가 없습니다" 빈 상태 확인 |
| 03 | `03-tenant-isolation.md` | `검색 결과가 현재 테넌트의 프로세스 정의로 한정된다` | localhost 테넌트로 검색 → 다른 테넌트 전용 프로세스 정의가 결과에 없음을 확인 |

## 요구사항 커버리지
| 명세 | 요구사항 | 필수 수준 | 커버 시나리오 | 비고 |
| --- | --- | --- | --- | --- |
| `completion_process-definition-search` | 자연어 프로세스 정의 검색 | SHALL | 01, 02 | 정상 검색과 graceful 빈 결과를 모두 검증 |
| `completion_process-definition-search` | 검색 범위의 테넌트 격리 | SHALL | 03 | 요청 subdomain 테넌트로 검색 범위 한정 |

## 명세 시나리오 커버리지
| 명세 | 요구사항 | 명세 시나리오 | 커버 시나리오 | 사용자 검증 표면 |
| --- | --- | --- | --- | --- |
| `completion_process-definition-search` | 자연어 프로세스 정의 검색 | 유사 프로세스 정의 검색 성공 | 01 | 헤더 검색창 입력 / 검색 실행 / "유사한 프로세스 정의" 결과 목록 |
| `completion_process-definition-search` | 자연어 프로세스 정의 검색 | 검색 결과 없음 | 02 | 헤더 검색창 입력 / 검색 실행 / "검색 결과가 없습니다" 빈 상태 화면 |
| `completion_process-definition-search` | 검색 범위의 테넌트 격리 | 테넌트별 검색 범위 제한 | 03 | 헤더 검색창 입력 / 검색 실행 / 결과 목록에 타 테넌트 정의 미포함 (+ 보조 프로토콜 비교) |

## 미검증 및 보류 항목
| 항목 | 사유 | 후속 조치 |
| --- | --- | --- |
| `/vision-process-search` 이미지 입력 경로 | 코드상 `/process-search` 와 동일 핸들러를 사용하며 이미지 분석 동작이 라우팅되지 않음(dead code). 별도 사용자 화면도 없음 | 시나리오 미생성. 두 라우트가 동일 동작임을 시나리오 03 보조 프로토콜 검증에서 확인 |
| 임베딩/벡터 유사도 점수 정확성 | 임베딩은 비결정 외부 경계이므로 `mock-llm` 스텁으로 대체. 유사도 순위 정확성은 본 스위트의 검증 대상이 아님 | 시드 데이터 기반의 결정적 결과만 검증 |

## 체크리스트
- [x] 모든 Requirement가 하나 이상의 E2E 시나리오에 매핑되어 있습니다.
- [x] 중요한 OpenSpec Scenario가 E2E 시나리오에 매핑되어 있거나 미검증 및 보류 항목에 기록되어 있습니다.
- [x] 사람이 읽는 요구사항명, 명세 시나리오명, 목적, 절차, 기대 결과는 한국어로 작성되어 있습니다.
- [x] 원본 OpenSpec에 영어 설명이 있더라도 E2E 문서에는 한국어 의미로 변환되어 있으며, API 경로·필드명·이벤트명 같은 계약 식별자만 원문으로 유지합니다.
- [x] 원본 명세가 하나의 백엔드 연계 피쳐 또는 응집된 사용자 workflow 범위이며, 마이크로서비스 전체 요약이나 프론트엔드 단독 명세가 아닙니다.
- [x] 원본 명세의 서비스 접두어 또는 도메인 구분자가 `frontend`, `ui`, `react`, `page`, `component` 같은 구현 레이어가 아닙니다.
- [x] E2E가 실행할 소유 백엔드 서비스/API/데이터 계약이 명확합니다.
- [x] 서비스 접두형 명세 ID를 사용하는 경우 스위트 슬러그가 동일한 값을 유지합니다.
- [x] E2E 시나리오, 테스트 스크립트, seed/stub, 실행 결과, 스크린샷은 `openspec/specs/completion_process-definition-search/e2e/` 아래에 응집되어 있습니다.
- [x] 사용자-facing 시나리오는 직접 API 요청이 아니라 브라우저 UI 상호작용으로 검증합니다.
- [x] 시나리오별 스크린샷 체크포인트가 매뉴얼에 재사용할 수 있는 UI 상태를 설명합니다.
- [x] 결과 경로가 `OUTPUT_CONTRACT.md`와 일치합니다.
