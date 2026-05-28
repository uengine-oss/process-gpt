# E2E 시나리오 01: 헤더 검색바 자연어 검색으로 유사 프로세스 정의 표시

## 메타데이터
- 스위트 슬러그: `completion_process-definition-search`
- 원본 명세 ID: `completion_process-definition-search`
- 시나리오 ID: `01`
- Playwright 테스트 제목: `헤더 검색바에서 자연어 키워드를 입력하면 유사한 프로세스 정의가 표시된다`
- 원본 명세:
  - `openspec/specs/completion_process-definition-search/spec.md`

## 목적
사용자가 화면 상단 헤더의 검색바에 자연어 키워드(예: `휴가`)를 입력해 Enter 를 누르면, 브라우저가 `POST /completion/process-search` 를 호출해 백엔드 벡터 검색으로 유사한 프로세스 정의를 받아 `유사한 프로세스 정의` 카테고리로 표시하는 사용자 경로를 보장한다. 이 시나리오는 spec.md 의 `자연어 프로세스 정의 검색` 요구사항을 실제 사용자 경로에서 검증한다.

## 사전 조건
- 게이트웨이(nginx) → 프론트엔드(`/`) / 게이트웨이 → completion(`/completion/*`) 경로가 모두 source-run 으로 살아 있다.
- Supabase 인프라(`db`, `kong`, `auth`, `rest`)가 healthy 이며, `e2e@uengine.org` 사용자가 시드되어 있다.
- `vecs.documents` 테이블에 `localhost` 테넌트의 `process_definition` 타입 문서 3건이 시드되어 있다 (`휴가신청`, `구매요청`, `출장신청`).
- `mock-llm` 의 `/v1/embeddings` 가 결정성 임베딩을 반환한다.

## 테스트 데이터 및 Stub
| 이름 | 유형 | 경로 또는 route | 목적 |
| --- | --- | --- | --- |
| `e2e_seed.sql` | seed | `openspec/specs/completion_process-definition-search/e2e/seed_files/e2e_seed.sql` | 프로세스 정의 3건 + `vecs.documents` 임베딩 시드 |
| `mock-llm` | stub | `http://mock-llm:8080/v1/embeddings` | 결정성 임베딩 응답 |
| 로그인 사용자 | fixture | `e2e@uengine.org` / `e2epassword` | 헤더 검색바 노출에 필요한 인증 세션 |

## 절차
1. 사용자는 브라우저에서 `http://localhost:8088/auth/login` 으로 이동한다.
2. 사용자는 이메일/비밀번호를 입력하고 로그인 버튼을 클릭한다.
3. 로그인 후 사용자는 헤더 검색바(돋보기 아이콘 옆 입력창)를 클릭한다.
4. 사용자는 자연어 키워드 `휴가` 를 입력한다.
5. 사용자는 Enter 키를 누른다.
6. 사용자는 검색 결과 메뉴에서 `유사한 프로세스 정의` 카테고리가 나타나기를 기다린다.
7. 사용자는 결과 항목 제목에 시드한 프로세스 정의명이 포함되어 있는지 확인한다.

## 기대 결과
- 검색 결과 패널이 열리고 `유사한 프로세스 정의` 섹션 헤더가 표시된다.
- 섹션 내 결과 항목으로 `휴가신청` 이 표시된다.
- 브라우저는 `POST /completion/process-search` 요청을 1회 보내고 응답 본문이 1~3 건의 문서 배열이다 (각 문서는 `page_content` 와 `metadata` 를 포함).
- 사용자 화면에 결과 항목이 클릭 가능한 링크로 렌더링된다.

## 커버하는 요구사항
| 명세 | 요구사항 | 시나리오 |
| --- | --- | --- |
| `completion_process-definition-search` | 자연어 프로세스 정의 검색 | 유사 프로세스 정의 검색 성공 |

## 산출물
- 스크린샷 체크포인트:
  | 체크포인트 | 캡처할 UI 상태 | 예상 파일 | 매뉴얼용 캡션 |
  | --- | --- | --- | --- |
  | `01-search-initial` | 로그인 직후 헤더 검색바가 비어 있는 초기 상태 | `process-gpt-completion_process-definition-search-01-search-initial.png` | 헤더 검색바 초기 상태 |
  | `01-search-input` | 검색바에 `휴가` 가 입력되어 있고 아직 전송 전인 상태 | `process-gpt-completion_process-definition-search-01-search-input.png` | 자연어 검색어 입력 |
  | `01-search-result` | `유사한 프로세스 정의` 카테고리에 결과 항목이 표시된 상태 | `process-gpt-completion_process-definition-search-01-search-result.png` | 유사 프로세스 정의 결과 |
- Trace/video: Playwright 실패 시 보존됩니다.
- 결과 JSON: `openspec/specs/completion_process-definition-search/e2e/results/results.json`
