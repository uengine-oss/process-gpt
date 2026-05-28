# E2E 시나리오 03: 프로세스 변수 SQL 스키마 생성 성공 (실 디자이너 UI)

## 메타데이터
- 스위트 슬러그: `completion_process-data-query`
- 원본 명세 ID: `completion_process-data-query`
- 시나리오 ID: `03`
- Playwright 테스트 제목: `03 BPMN 디자이너 프로세스 변수에서 SQL 생성을 누르면 CREATE TABLE SQL이 반환된다`
- 원본 명세:
  - `openspec/specs/completion_process-data-query/spec.md`
- 분류: **실 프런트엔드 사용자-액션 시나리오**

## 목적
BPMN 디자이너 사용자가 프로세스 변수 편집기에서 변수 이름과 해소 규칙을 입력하고 데이터 소스를 SQL로 설정한 뒤 "generate" 버튼을 누르면, 프런트엔드가 `POST /completion/process-var-sql/invoke`를 호출하고 응답으로 받은 SQL이 변수의 SQL 필드에 채워지는 사용자 경험을 보장한다.

## 실 프런트엔드 진입 경로
- 라우트: `/definitions/<process-definition-id>` ([services/frontend/src/router/MainRoutes.ts:100](services/frontend/src/router/MainRoutes.ts#L100) → `ProcessDefinitionChat.vue` → `ProcessDesigner.vue`).
- 호출부: [services/frontend/src/components/designer/bpmnModeling/bpmn/mapper/ProcessVariable.vue:181](services/frontend/src/components/designer/bpmnModeling/bpmn/mapper/ProcessVariable.vue#L181) `generateSql()`.
- 트리거: 디자이너 상단의 "프로세스 변수" 버튼(`#processVariables`) 클릭 → 변수 추가/편집 다이얼로그 → 변수 이름/타입(Text)/설명 입력 → 데이터 소스를 `SQL` 또는 `database`로 변경 → "generate" 버튼 클릭.

## 사전 조건
- frontend(SPA 이미지) + gateway(nginx :8088) + completion(FastAPI :8000) + Supabase 전체 + mock-llm-pdq 정상 기동.
- DB seed: `e2e_seed.sql` 적용. 사용자 `e2e@uengine.org` / `e2epassword` 로그인 가능, `localhost` 테넌트에 `vacation_request_process` proc_def 존재.
- mock-llm-pdq는 prompt에 SQL 생성 의도가 보이면 ```sql\nCREATE TABLE ...;\n``` 코드 블록을 결정적으로 반환한다.

## 테스트 데이터 및 Stub
| 이름 | 유형 | 경로 또는 route | 목적 |
| --- | --- | --- | --- |
| e2e_seed.sql | seed | `openspec/specs/completion_process-data-query/e2e/seed_files/e2e_seed.sql` | 로그인 사용자와 디자이너에서 열 proc_def 시드 |
| mock_llm.py SQL 분기 | stub | `openspec/specs/completion_process-data-query/e2e/scripts/mock_llm.py` | `/process-var-sql` prompt에 대해 ```sql``` 코드 블록 결정적 반환 |
| 로그인 helper | fixture | `tests/completion_process-data-query.spec.mjs` 내 `login()` | `.cp-id` / `.cp-pwd` / `.cp-login` 패턴 (def-search 스위트와 동일) |

## 절차
1. 사용자가 `/auth/login`에 진입해 `e2e@uengine.org` / `e2epassword`로 로그인한다.
2. 사용자가 `/definitions/vacation_request_process`로 이동해 BPMN 디자이너가 로드되기를 기다린다.
3. 사용자가 상단 도구 모음의 "프로세스 변수" 버튼(`#processVariables`)을 클릭해 변수 다이얼로그를 연다.
4. 사용자가 변수 이름(`cp-v-name` 입력)에 `total_vacation_days_remains`를 입력한다.
5. 사용자가 변수 타입(`cp-v-type`)을 `Text`로 선택한다.
6. 사용자가 설명(`#hem` 입력)에 `vacation_addition 테이블의 휴가일수에서 vacation_request 사용일수를 제외`를 입력한다.
7. 사용자가 데이터 소스 드롭다운에서 `SQL`을 선택해 SQL textarea와 generate/test 버튼이 표시되도록 한다.
8. 사용자가 "generate" 버튼을 클릭한다.
9. 사용자가 SQL textarea에 `CREATE TABLE` 로 시작하는 SQL이 채워졌는지 확인한다.

## 기대 결과
- 응답 HTTP 상태 코드는 200이다 (`page.waitForResponse`로 `/completion/process-var-sql/invoke` 검증).
- SQL textarea에는 ```sql``` 마커가 제거된 순수 SQL이 채워지고 `CREATE TABLE`로 시작한다.
- `cp-v-add` 버튼이 활성 상태로 표시되어 변수 저장이 가능한 상태이다.

## 커버하는 요구사항
| 명세 | 요구사항 | 시나리오 |
| --- | --- | --- |
| `completion_process-data-query` | 프로세스 변수 SQL 스키마 생성 | 변수 SQL 생성 성공 |

## 산출물
- 스크린샷 체크포인트:
  | 체크포인트 | 캡처할 UI 상태 | 예상 파일 | 매뉴얼용 캡션 |
  | --- | --- | --- | --- |
  | `03-designer-loaded` | 로그인 후 디자이너가 열린 상태 | `process-gpt-completion_process-data-query-03-designer-loaded.png` | BPMN 디자이너 진입 직후 화면 |
  | `03-variables-dialog` | 프로세스 변수 다이얼로그가 열린 직후 | `process-gpt-completion_process-data-query-03-variables-dialog.png` | 프로세스 변수 편집기 |
  | `03-variable-input` | 이름·설명·데이터소스 입력 완료, generate 버튼 노출 | `process-gpt-completion_process-data-query-03-variable-input.png` | SQL 데이터 소스 입력 완료 |
  | `03-sql-generated` | SQL textarea에 CREATE TABLE SQL이 채워진 상태 | `process-gpt-completion_process-data-query-03-sql-generated.png` | 생성된 SQL이 변수에 반영된 상태 |
- Trace/video: Playwright 실패 시 보존됩니다.
- 결과 JSON: `openspec/specs/completion_process-data-query/e2e/results/results.json`
