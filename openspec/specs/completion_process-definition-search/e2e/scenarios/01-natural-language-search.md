# E2E 시나리오 01: 자연어 질의로 유사한 프로세스 정의를 검색한다

## 메타데이터
- 스위트 슬러그: `completion_process-definition-search`
- 원본 명세 ID: `completion_process-definition-search`
- 시나리오 ID: `01`
- Playwright 테스트 제목: `자연어 질의로 유사한 프로세스 정의를 검색한다`
- 원본 명세:
  - `openspec/specs/completion_process-definition-search/spec.md`

## 목적
사용자가 시작하거나 참고할 프로세스 정의의 정확한 이름을 모르는 상황에서, 헤더 통합 검색창에 자연어 질의를 입력해 의미적으로 유사한 프로세스 정의 후보를 찾을 수 있어야 한다. 이 시나리오는 브라우저 → nginx 게이트웨이 → `completion` 백엔드 `POST /process-search` → `documents` 벡터 검색 경로가 실제로 동작하여, 검색 결과가 "유사한 프로세스 정의" 카테고리로 화면에 표시되는지 검증한다. 검색 후보는 최대 3건까지 반환된다는 계약을 함께 확인한다.

## 사전 조건
- E2E Docker 스택이 기동되어 있고 `frontend`, `gateway`(nginx), `completion`, Supabase(`db`/`kong`/`auth`/`rest`), 임베딩 스텁 `mock-llm` 컨테이너가 정상 상태이다.
- `db-seed-process-search` 시드가 적용되어 `localhost` 테넌트에 프로세스 정의 3건과 그에 대응하는 `documents`(type `process_definition`) 임베딩 행이 등록되어 있다.
- 로그인 사용자 `e2e@uengine.org` / `e2epassword` 가 `localhost` 테넌트 프로필로 존재한다(공용 시드).

## 테스트 데이터 및 Stub
| 이름 | 유형 | 경로 또는 route | 목적 |
| --- | --- | --- | --- |
| `e2e_seed.sql` | seed | `openspec/specs/completion_process-definition-search/e2e/seed_files/e2e_seed.sql` | `localhost` 테넌트 프로세스 정의 3건(`proc_def`)과 검색 인덱스(`documents`) 등록 |
| `mock-llm` 임베딩 스텁 | route(외부 경계) | `http://mock-llm:8080/v1/embeddings` | 비결정적 임베딩 호출을 결정적 벡터로 대체 |
| `POST /process-search` | route | `http://localhost:8088/completion/process-search` | 검색 질의를 받아 유사 프로세스 정의 후보 목록 반환 |

## 절차
1. 사용자가 로그인 화면에서 `e2e@uengine.org` 계정으로 로그인한다.
2. 사용자가 메인 화면으로 진입하여 상단 헤더의 통합 검색창을 확인한다.
3. 사용자가 검색창에 자연어 질의(예: `휴가`)를 입력한다.
4. 사용자가 Enter 키를 눌러 검색을 실행한다.
5. 사용자가 검색 결과 패널에서 "유사한 프로세스 정의" 카테고리와 후보 목록을 확인한다.

## 기대 결과
- 검색 결과 패널이 열리고 "유사한 프로세스 정의" 카테고리가 표시된다.
- 카테고리에는 시드로 등록한 프로세스 정의가 후보로 나타나며, 후보 수는 최대 3건이다.
- 후보 목록에 `휴가 신청 및 승인 프로세스` 항목이 포함된다.
- 브라우저가 호출한 `POST /completion/process-search` 응답이 `200` 상태이고 본문이 비어 있지 않은 후보 배열이다.

## 커버하는 요구사항
| 명세 | 요구사항 | 시나리오 |
| --- | --- | --- |
| `completion_process-definition-search` | 자연어 프로세스 정의 검색 | 유사 프로세스 정의 검색 성공 |

## 산출물
- 스크린샷 체크포인트:
  | 체크포인트 | 캡처할 UI 상태 | 예상 파일 | 매뉴얼용 캡션 |
  | --- | --- | --- | --- |
  | `01-search-initial` | 로그인 후 헤더 통합 검색창이 보이는 초기 화면 | `process-gpt-completion_process-definition-search-01-search-initial.png` | 화면 상단의 통합 검색창에서 업무를 검색할 수 있습니다 |
  | `01-search-input` | 검색창에 자연어 질의를 입력한 상태 | `process-gpt-completion_process-definition-search-01-search-input.png` | 찾고 싶은 업무를 자연어로 입력합니다 |
  | `01-search-result` | "유사한 프로세스 정의" 후보가 표시된 결과 패널 | `process-gpt-completion_process-definition-search-01-search-result.png` | 입력한 내용과 비슷한 프로세스 정의 후보가 목록으로 표시됩니다 |
- Trace/video: Playwright 실패 시 보존됩니다.
- 결과 JSON: `openspec/specs/completion_process-definition-search/e2e/results/results.json`
