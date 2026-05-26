# E2E 시나리오 02: 검색 처리에 실패해도 오류 없이 빈 결과가 표시된다

## 메타데이터
- 스위트 슬러그: `completion_process-definition-search`
- 원본 명세 ID: `completion_process-definition-search`
- 시나리오 ID: `02`
- Playwright 테스트 제목: `검색 처리에 실패해도 오류 없이 빈 결과가 표시된다`
- 원본 명세:
  - `openspec/specs/completion_process-definition-search/spec.md`

## 목적
이 명세의 가장 특징적인 동작은 graceful degradation 이다. 내부 유사도 검색(임베딩 호출, 벡터 검색)이 실패하더라도 시스템은 요청을 오류로 끝내지 않고 `200` 상태와 빈 목록을 반환해야 한다. 사용자 화면에서는 오류 메시지나 깨진 화면이 아니라 "검색 결과가 없습니다" 빈 상태가 안내되어, 검색이 사용자 흐름을 끊지 않아야 한다. 이 시나리오는 임베딩 외부 경계에 결정적 실패를 주입한 상태에서 사용자가 검색을 수행했을 때, 브라우저 검색 흐름이 빈 상태로 우아하게 마무리되는지 검증한다.

## 사전 조건
- E2E Docker 스택이 기동되어 있고 `frontend`, `gateway`(nginx), `completion`, Supabase, 임베딩 스텁 `mock-llm` 컨테이너가 정상 상태이다.
- `mock-llm` 임베딩 스텁은 실패 주입 토글을 제공한다. `POST /control/embed-fail` 본문 `{"enabled": true}` 를 호출하면 이후 모든 `/v1/embeddings` 요청에 대해 오류 응답(HTTP 400)을 반환한다. `{"enabled": false}` 로 복원한다. 이는 비결정적 외부 경계에 대한 명시적 실패 주입이며, `completion` 서비스 자체(라우팅·JSON 파싱·빈 목록 폴백)는 스텁하지 않는다.
- 실제 호출자(langchain `OpenAIEmbeddings`)는 텍스트를 토큰화하여 전송하므로 질의 문자열 매칭만으로는 특정 검색을 실패시킬 수 없다. 따라서 런타임 토글로 실패를 주입한다.
- 로그인 사용자 `e2e@uengine.org` / `e2epassword` 가 존재한다(공용 시드).

## 테스트 데이터 및 Stub
| 이름 | 유형 | 경로 또는 route | 목적 |
| --- | --- | --- | --- |
| 임베딩 실패 토글 | route(외부 경계, 실패 주입) | `POST http://localhost:8899/control/embed-fail` | 테스트 setup/teardown 에서 임베딩 실패를 켜고 끔 |
| `mock-llm` 임베딩 스텁 | route(외부 경계) | `http://mock-llm:8080/v1/embeddings` | 토글이 켜진 동안 오류 응답을 반환해 벡터 검색 예외를 유발 |
| `POST /process-search` | route | `http://localhost:8088/completion/process-search` | 검색 실패 시에도 `200` + 빈 목록을 반환하는 graceful 동작 검증 |

## 절차
1. (setup, 비 UI) 테스트가 `mock-llm` 실패 토글을 켜서 임베딩 호출이 실패하도록 만든다.
2. 사용자가 로그인 화면에서 `e2e@uengine.org` 계정으로 로그인한다.
3. 사용자가 메인 화면으로 진입하여 상단 헤더의 통합 검색창을 확인한다.
4. 사용자가 검색창에 자연어 질의(예: `보고서 작성`)를 입력한다.
5. 사용자가 Enter 키를 눌러 검색을 실행한다.
6. 사용자가 검색 결과 패널의 상태를 확인한다.
7. (teardown, 비 UI) 테스트가 실패 토글을 꺼서 임베딩 동작을 복원한다.

## 기대 결과
- 검색 처리 중 임베딩 호출이 실패하지만 화면에 오류 메시지나 깨진 화면이 표시되지 않는다.
- 검색 결과 패널에 "검색 결과가 없습니다" 빈 상태 안내가 표시된다.
- "유사한 프로세스 정의" 카테고리는 표시되지 않는다.
- 브라우저가 호출한 `POST /completion/process-search` 응답이 `500` 오류가 아니라 `200` 상태이며 본문은 빈 목록(`[]`)이다.

## 커버하는 요구사항
| 명세 | 요구사항 | 시나리오 |
| --- | --- | --- |
| `completion_process-definition-search` | 자연어 프로세스 정의 검색 | 검색 결과 없음 |

## 산출물
- 스크린샷 체크포인트:
  | 체크포인트 | 캡처할 UI 상태 | 예상 파일 | 매뉴얼용 캡션 |
  | --- | --- | --- | --- |
  | `02-search-input` | 검색창에 질의를 입력한 상태 | `process-gpt-completion_process-definition-search-02-search-input.png` | 검색어를 입력하고 검색을 실행합니다 |
  | `02-search-empty` | "검색 결과가 없습니다" 빈 상태가 표시된 결과 패널 | `process-gpt-completion_process-definition-search-02-search-empty.png` | 검색 처리에 문제가 있어도 오류 없이 결과가 없다는 안내가 표시됩니다 |
- Trace/video: Playwright 실패 시 보존됩니다.
- 결과 JSON: `openspec/specs/completion_process-definition-search/e2e/results/results.json`
