# E2E 시나리오 03: 테넌트 subdomain 에 따라 검색 결과가 분리된다

## 메타데이터
- 스위트 슬러그: `completion_process-definition-search`
- 원본 명세 ID: `completion_process-definition-search`
- 시나리오 ID: `03`
- Playwright 테스트 제목: `테넌트 subdomain 에 따라 검색 결과가 분리된다`
- 원본 명세:
  - `openspec/specs/completion_process-definition-search/spec.md`

## 목적
`services/completion/main.py` 의 `DBConfigMiddleware` 가 요청 헤더 `X-Forwarded-Host` 로부터 subdomain 을 추출해 `database.subdomain_var` 에 주입하고, `get_process_definitions` 가 해당 tenant_id 로 `vecs.documents` 를 필터한다는 명세(`검색 범위의 테넌트 격리`)를 검증한다. 게이트웨이 nginx 가 `X-Forwarded-Host` 를 덮어쓰는 패턴이 있으므로, 완전성을 위해 본 검증은 게이트웨이를 우회해 completion 컨테이너에 직접 요청한다.

## 사전 조건
- `vecs.documents` 에 두 테넌트의 데이터가 시드되어 있다:
  - `localhost`: `휴가신청`, `구매요청`, `출장신청`
  - `tenant-b`: `장비대여`, `회의실예약`
- completion 컨테이너가 호스트에서 `http://localhost:8000` 으로 직접 접근 가능하다 (게이트웨이 우회).
- 두 테넌트 모두 동일한 시드된 `tenant_id` 컬럼 값과 metadata 를 가진다.

## 테스트 데이터 및 Stub
| 이름 | 유형 | 경로 또는 route | 목적 |
| --- | --- | --- | --- |
| 다중 테넌트 시드 | seed | `e2e_seed.sql` 의 `vecs.documents` insert 두 묶음 | tenant 분리 검증 데이터 |
| 게이트웨이 우회 호출 | request | `http://localhost:8000/process-search` | nginx 의 `X-Forwarded-Host` 덮어쓰기 회피 |

## 절차
1. Playwright `request` 컨텍스트로 `POST http://localhost:8000/process-search` 를 두 번 호출한다.
2. 첫 호출 헤더: `X-Forwarded-Host: localhost`, 본문: `{ "query": "휴가" }`
3. 두 번째 호출 헤더: `X-Forwarded-Host: tenant-b.example.com`, 본문: `{ "query": "회의실" }`
4. 두 응답의 결과 항목을 비교한다.

## 기대 결과
- 첫 응답은 `localhost` 테넌트 시드 항목(`휴가신청`)을 포함하고 `tenant-b` 시드 항목(`회의실예약`, `장비대여`)은 포함하지 않는다.
- 두 번째 응답은 `tenant-b` 테넌트 시드 항목(`회의실예약`)을 포함하고 `localhost` 시드 항목을 포함하지 않는다.
- 두 응답 모두 상태 `200` 이며 본문은 배열이다.

## 커버하는 요구사항
| 명세 | 요구사항 | 시나리오 |
| --- | --- | --- |
| `completion_process-definition-search` | 검색 범위의 테넌트 격리 | 테넌트별 검색 범위 제한 |

## 산출물
- 스크린샷 체크포인트: 본 시나리오는 보조 프로토콜 검증으로 별도 UI 표면이 없습니다.
- Trace/video: Playwright 실패 시 보존됩니다.
- 결과 JSON: `openspec/specs/completion_process-definition-search/e2e/results/results.json`
