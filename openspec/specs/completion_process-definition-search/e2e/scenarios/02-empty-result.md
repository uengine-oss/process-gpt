# E2E 시나리오 02: 유사 결과 없음일 때 200 과 빈 목록 반환

## 메타데이터
- 스위트 슬러그: `completion_process-definition-search`
- 원본 명세 ID: `completion_process-definition-search`
- 시나리오 ID: `02`
- Playwright 테스트 제목: `유사한 프로세스 정의가 없을 때 200 과 빈 목록을 반환한다`
- 원본 명세:
  - `openspec/specs/completion_process-definition-search/spec.md`

## 목적
질의와 유사한 프로세스 정의가 없거나 벡터 검색 자체가 실패해도 `POST /process-search` 가 `200` 과 빈 배열을 반환해야 한다는 계약(spec.md 의 `검색 결과 없음` 명세 시나리오)을 보장한다. 헤더 검색바가 동일 라우트를 호출하지만 UI 는 빈 결과를 별도 화면이 아니라 동일 결과 패널의 빈 상태로 표시하므로, 명세의 계약 자체는 보조 프로토콜로 직접 검증한다.

## 사전 조건
- completion 컨테이너가 호스트에서 `http://localhost:8000` 으로 직접 접근 가능하다 (게이트웨이 우회).
- `vecs.documents` 에 `localhost` 테넌트의 프로세스 정의는 시드되어 있지만 `empty-tenant` 테넌트는 시드되어 있지 않다.
- `mock-llm` 임베딩은 결정성이지만 본 시나리오는 임계 기반이 아니라 테넌트 필터가 빈 결과를 반환하는 정상 분기(`get_process_definitions` 의 `Vector search succeeded with empty filter result`)를 통해 빈 목록 계약을 검증한다.

## 테스트 데이터 및 Stub
| 이름 | 유형 | 경로 또는 route | 목적 |
| --- | --- | --- | --- |
| 빈 테넌트 호출 | request | `X-Forwarded-Host: empty-tenant.example.com` | 시드 데이터가 없는 테넌트로 강제 |
| 임의 질의 | fixture | `query: "휴가"` | 다른 테넌트에는 존재하는 키워드를 사용해도 본 테넌트에서 빈 결과여야 함을 확인 |

## 절차
1. Playwright `request` 컨텍스트로 `POST http://localhost:8000/process-search` 를 호출한다 (게이트웨이의 `X-Forwarded-Host` 덮어쓰기 회피).
2. 요청 헤더에 `X-Forwarded-Host: empty-tenant.example.com` 을 포함하고 본문은 `{ "query": "휴가" }` 이다.
3. 응답 상태와 본문을 검증한다.

## 기대 결과
- 응답 상태는 `200` 이다.
- 응답 본문은 빈 배열 `[]` 이거나 길이가 0 인 리스트이다.
- 백엔드 로그/카운터가 `Vector search failed` fallback 분기 또는 정상 빈 결과 분기 중 하나로 처리되어 있다 (둘 다 명세상 동일하게 `[]` 로 노출).

## 커버하는 요구사항
| 명세 | 요구사항 | 시나리오 |
| --- | --- | --- |
| `completion_process-definition-search` | 자연어 프로세스 정의 검색 | 검색 결과 없음 |

## 산출물
- 스크린샷 체크포인트: 본 시나리오는 보조 프로토콜 검증으로 별도 UI 표면이 없습니다. UI 빈 결과 표시는 시나리오 01 의 결과 패널 동작과 동일하게 처리됩니다.
- Trace/video: Playwright 실패 시 보존됩니다.
- 결과 JSON: `openspec/specs/completion_process-definition-search/e2e/results/results.json`
