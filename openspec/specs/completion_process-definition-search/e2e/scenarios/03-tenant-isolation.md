# E2E 시나리오 03: 검색 결과가 현재 테넌트의 프로세스 정의로 한정된다

## 메타데이터
- 스위트 슬러그: `completion_process-definition-search`
- 원본 명세 ID: `completion_process-definition-search`
- 시나리오 ID: `03`
- Playwright 테스트 제목: `검색 결과가 현재 테넌트의 프로세스 정의로 한정된다`
- 원본 명세:
  - `openspec/specs/completion_process-definition-search/spec.md`

## 목적
process-gpt 는 여러 회사가 공유하는 멀티테넌트 SaaS 이며, 검색은 요청 subdomain 이 가리키는 테넌트의 프로세스 정의로만 한정되어야 한다. 한 회사 사용자의 검색에 다른 회사의 프로세스 정의가 섞여 나오면 안 된다. 이 시나리오는 `localhost` 테넌트로 로그인한 사용자가 검색했을 때, 다른 테넌트(`tenant-b`)에만 등록된 프로세스 정의가 결과에 절대 나타나지 않음을 브라우저 검색 흐름으로 검증한다. 보조적으로, 동일한 `POST /process-search` 엔드포인트가 요청 테넌트에 따라 다른 결과로 한정되는지를 프로토콜 수준에서 함께 확인한다.

## 사전 조건
- E2E Docker 스택이 기동되어 있고 `frontend`, `gateway`(nginx), `completion`, Supabase, 임베딩 스텁 `mock-llm` 컨테이너가 정상 상태이다.
- `db-seed-process-search` 시드가 적용되어 `localhost` 테넌트에 프로세스 정의 3건, `tenant-b` 테넌트에 전용 프로세스 정의 1건(`외부 테넌트 전용 프로세스`)과 각 검색 인덱스(`documents`)가 등록되어 있다.
- 로그인 사용자 `e2e@uengine.org` 는 `localhost` 테넌트 프로필을 가진다(공용 시드).

## 테스트 데이터 및 Stub
| 이름 | 유형 | 경로 또는 route | 목적 |
| --- | --- | --- | --- |
| `e2e_seed.sql` | seed | `openspec/specs/completion_process-definition-search/e2e/seed_files/e2e_seed.sql` | `localhost` 정의 3건과 `tenant-b` 전용 정의 1건을 각 테넌트 범위로 등록 |
| `mock-llm` 임베딩 스텁 | route(외부 경계) | `http://mock-llm:8080/v1/embeddings` | 임베딩 호출을 결정적 벡터로 대체 |
| `X-Forwarded-Host` 헤더 | fixture(테넌트 식별) | `POST /completion/process-search` 요청 헤더 | 보조 프로토콜 검증에서 요청 테넌트를 `localhost` 와 `tenant-b` 로 전환 |

## 절차
1. 사용자가 로그인 화면에서 `e2e@uengine.org` 계정(`localhost` 테넌트)으로 로그인한다.
2. 사용자가 메인 화면으로 진입하여 상단 헤더의 통합 검색창을 확인한다.
3. 사용자가 검색창에 자연어 질의(예: `프로세스`)를 입력하고 Enter 키를 눌러 검색한다.
4. 사용자가 "유사한 프로세스 정의" 결과 목록을 확인한다.
5. (보조 프로토콜 검증) `POST /completion/process-search` 를 `tenant-b` 테넌트로 호출했을 때와 `localhost` 테넌트로 호출했을 때의 후보가 서로 격리되는지 확인한다.

## 기대 결과
- 검색 결과의 "유사한 프로세스 정의" 카테고리에는 `localhost` 테넌트에 등록된 정의만 표시된다.
- 결과 목록에 `tenant-b` 전용 정의인 `외부 테넌트 전용 프로세스` 가 포함되지 않는다.
- 보조 프로토콜 검증에서, `tenant-b` 테넌트로 호출한 `POST /process-search` 응답에는 `tenant-b` 전용 정의가 포함되지만 `localhost` 테넌트로 호출한 응답에는 포함되지 않는다.

## 커버하는 요구사항
| 명세 | 요구사항 | 시나리오 |
| --- | --- | --- |
| `completion_process-definition-search` | 검색 범위의 테넌트 격리 | 테넌트별 검색 범위 제한 |

## 산출물
- 스크린샷 체크포인트:
  | 체크포인트 | 캡처할 UI 상태 | 예상 파일 | 매뉴얼용 캡션 |
  | --- | --- | --- | --- |
  | `03-search-result` | localhost 테넌트 검색 결과 목록(타 테넌트 정의 미포함) | `process-gpt-completion_process-definition-search-03-search-result.png` | 검색 결과에는 현재 회사(테넌트)의 프로세스 정의만 표시됩니다 |
- Trace/video: Playwright 실패 시 보존됩니다.
- 결과 JSON: `openspec/specs/completion_process-definition-search/e2e/results/results.json`
