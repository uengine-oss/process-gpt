# 프로세스 데이터 조회 E2E 커버리지 매트릭스

## 범위
- 스위트 슬러그: `completion_process-data-query`
- 원본 명세 ID: `completion_process-data-query`
- 원본 명세:
  - `openspec/specs/completion_process-data-query/spec.md`
- 백엔드/제품 계약:
  - 소유 서비스: `services/completion` FastAPI (`process_var_sql_gen.py`)
  - 노출 라우트: `POST /process-data-query`, `POST /process-var-sql` (langserve `/invoke` 호환)
  - 데이터 의존성: `proc_def`, `form_def`, `bpm_proc_inst`, `todolist`, `users`, `tenants` (Supabase Postgres)
  - 외부 경계: OpenAI 호환 LLM (mock-llm-pdq 컨테이너로 대체)
- E2E 루트: `openspec/specs/completion_process-data-query/e2e/`
- Playwright 명세: `openspec/specs/completion_process-data-query/e2e/tests/completion_process-data-query.spec.mjs`
- 결과 디렉터리: `openspec/specs/completion_process-data-query/e2e/results/`

## Real-Frontend Rule 적합성 재정렬 (2026-05-27)
이전 버전의 본 스위트는 `scripts/pdq-tester.html`을 `page.route()`로 주입해 합성 tester 페이지를 화면으로 사용하였다. 이는 Real-Frontend Rule 위반에 해당하므로 다음과 같이 재구성하였다.

- `scripts/pdq-tester.html` 및 이전 스크린샷 9건은 삭제되었다.
- 실 프런트엔드 경로 조사 결과:
  - `/completion/process-data-query` (자연어 `{query, user_id, chat_room_id}`) → 유일한 호출부는 [services/frontend/src/views/apps/chat/Chats.vue:1359](services/frontend/src/views/apps/chat/Chats.vue#L1359)이며 시스템 챗 룸 + 채팅 백엔드 + intent 분류가 `work === 'CompanyQuery'`를 반환해야만 트리거된다. 결정적 도달 불가 → **사용자 액션 면제**.
  - `/completion/process-var-sql/invoke` → [services/frontend/src/components/designer/bpmnModeling/bpmn/mapper/ProcessVariable.vue:181](services/frontend/src/components/designer/bpmnModeling/bpmn/mapper/ProcessVariable.vue#L181) `generateSql()`. BPMN 디자이너 → 프로세스 변수 다이얼로그 → 데이터 소스 SQL → "generate" 버튼. **실 UI 경로 존재**.
  - `/completion/process-data-query/invoke` (`testSql()`) → 같은 컴포넌트의 "test" 버튼이나 `{var_name}`만 보내며 본 스펙의 자연어 조회 계약을 형성하지 않음.
  - 테넌트 격리 → 게이트웨이 `Host`/`X-Forwarded-Host`에 의해 결정되며 브라우저 사용자가 직접 조작할 수 없음 → **백엔드 직접 호출로 검증**.
- 따라서 시나리오 01/02/04는 protocol-only로 분류해 직접 `pwRequest`로 호출하고, 시나리오 03만 BPMN 디자이너의 실 UI 경로로 구동한다.

## 재사용 산출물
- 로그인/네비게이션 helper: `completion_process-definition-search/e2e/tests/completion_process-definition-search.spec.mjs`의 `login()` 패턴(`.cp-id`, `.cp-pwd`, `.cp-login`)을 그대로 사용한다.
- `COMPLETION_DIRECT_URL` + `X-Forwarded-Host` 보조 프로토콜 시나리오 패턴: 같은 def-search 스위트에서 도입된 패턴을 그대로 적용한다.
- mock-LLM 패턴: `completion_agent-memory-chat/e2e/scripts/mock_llm.py`의 OpenAI 호환 stub 패턴을 본 스펙의 `mock_llm.py`로 복제 (마지막 prompt 캡처, `_EMPTY_` 분기 등 추가).
- coverage override: `completion_agent-memory-chat/e2e/docker/coverage.override.yml` 구조를 따르며 [[completion-coverage-override-workdir]], [[compose-override-relative-paths]] 메모리를 적용한다.
- 게이트웨이 패턴: `completion_agent-memory-chat`의 nginx.e2e.conf 패턴과 동일한 `docker/nginx.e2e.conf`.

## 시나리오 목록
| ID | 시나리오 문서 | Playwright 테스트 제목 | 주요 동작 |
| --- | --- | --- | --- |
| 01 | `01-process-data-query-success.md` | `01 자연어 프로세스 데이터 조회가 HTML table 문자열을 반환한다 (protocol-only)` | 백엔드 직접 호출로 `<table>` 응답 검증 (사용자-액션 면제) |
| 02 | `02-process-data-query-empty.md` | `02 표로 만들 결과가 없으면 빈 본문이 반환된다 (protocol-only)` | `_EMPTY_` 마커 prompt로 빈 본문 응답 검증 (사용자-액션 면제) |
| 03 | `03-process-var-sql-success.md` | `03 BPMN 디자이너 프로세스 변수에서 SQL 생성을 누르면 CREATE TABLE SQL이 반환된다` | 실 디자이너 UI에서 변수 SQL 생성 버튼을 클릭해 SQL 채워짐 검증 |
| 04 | `04-tenant-isolation.md` | `04 프로세스 데이터 조회는 요청 테넌트 범위로 한정된다 (protocol-only)` | localhost 테넌트 호출이 mock-LLM prompt에 타 테넌트 proc_def를 포함하지 않음을 검증 (사용자-액션 면제) |

## 요구사항 커버리지
| 명세 | 요구사항 | 필수 수준 | 커버 시나리오 | 비고 |
| --- | --- | --- | --- | --- |
| `completion_process-data-query` | 자연어 프로세스 데이터 조회 | SHALL | 01, 02 | 백엔드 계약 전용 (사용자 액션 면제). 채팅 인텐트 의존성 해소 시 UI 시나리오로 승격 |
| `completion_process-data-query` | 프로세스 변수 SQL 스키마 생성 | SHALL | 03 | BPMN 디자이너 실 UI 클릭으로 검증 |
| `completion_process-data-query` | 조회 범위의 테넌트 격리 | SHALL | 04 | mock-LLM이 마지막으로 받은 prompt에서 타 테넌트 proc_def 부재를 확인 (보조 프로토콜) |

## 명세 시나리오 커버리지
| 명세 | 요구사항 | 명세 시나리오 | 커버 시나리오 | 사용자 검증 표면 |
| --- | --- | --- | --- | --- |
| `completion_process-data-query` | 자연어 프로세스 데이터 조회 | 데이터 조회 성공 | 01 | **없음 (사용자 액션 면제)** — 본 스펙의 자연어 입력은 채팅 인텐트(`work: 'CompanyQuery'`) 경로로만 도달 가능 |
| `completion_process-data-query` | 자연어 프로세스 데이터 조회 | 표로 만들 결과가 없음 | 02 | **없음 (사용자 액션 면제)** — 동일 이유 |
| `completion_process-data-query` | 프로세스 변수 SQL 스키마 생성 | 변수 SQL 생성 성공 | 03 | `/definitions/<id>` 디자이너 → `#processVariables` → 변수 다이얼로그 → 데이터 소스 SQL → "generate" 버튼 |
| `completion_process-data-query` | 조회 범위의 테넌트 격리 | 테넌트별 데이터 조회 제한 | 04 | **없음 (사용자 액션 면제)** — 브라우저는 임의 Host/X-Forwarded-Host 설정 불가 |

## 스펙 관련 코드 표면
### 백엔드
| 파일 | 함수/클래스/라우트 | 관련 요구사항 | 커버리지 기준 | 선정 근거 |
| --- | --- | --- | --- | --- |
| `services/completion/process_var_sql_gen.py` | `add_routes_to_app`, `combine_input`, `combine_input_with_process_table_schema` | 자연어 프로세스 데이터 조회, 프로세스 변수 SQL 스키마 생성 | line >= 70%, function >= 80% | `/process-data-query`, `/process-var-sql` 라우트 등록 및 입력 분기 본체 |
| `services/completion/process_var_sql_gen.py` | `extract_markdown_code_blocks`, `extract_html_table`, `clean_html_string`, `get_form_definition`, `get_process_instances` | 자연어 프로세스 데이터 조회, 프로세스 변수 SQL 스키마 생성 | line >= 60% | LLM 응답을 SQL/HTML로 정제하는 후처리 체인 |
| `services/completion/database.py` | `fetch_all_process_definition_ids`, `fetch_process_instance_list`, `fetch_all_ui_definition`, `fetch_organization_chart`, `fetch_todolist_by_user_id`, `generate_create_statement_for_table`, `subdomain_var`, `update_tenant_id` | 자연어 프로세스 데이터 조회, 테넌트 격리 | function >= 60% | `subdomain_var` 기반 테넌트 필터링이 일어나는 지점 |
| `services/completion/main.py` | `DBConfigMiddleware` | 테넌트 격리 | function >= 90% | `X-Forwarded-Host` → `subdomain_var` 매핑 |

### 프론트엔드
| 파일 | 컴포넌트/함수/API 호출 | 관련 요구사항 | 커버리지 기준 | 선정 근거 |
| --- | --- | --- | --- | --- |
| `services/frontend/src/components/designer/bpmnModeling/bpmn/mapper/ProcessVariable.vue` | `generateSql` (`/completion/process-var-sql/invoke` 호출부) | 프로세스 변수 SQL 스키마 생성 | 참고 (browser V8/bundle 보조) | 시나리오 03이 사용자 액션으로 실 호출하는 표면 |
| `services/frontend/src/components/designer/bpmnModeling/ProcessDesigner.vue` | `openProcessVariables`, `#processVariables` 버튼 | 프로세스 변수 SQL 스키마 생성 | 참고 (browser V8/bundle 보조) | 디자이너에서 변수 다이얼로그를 여는 진입 컴포넌트 |
| `services/frontend/src/views/apps/chat/Chats.vue` (라인 1358-1372) | `/completion/process-data-query` 호출부 (CompanyQuery 인텐트) | 자연어 프로세스 데이터 조회 | 참고 (현재 E2E에서 도달하지 않음) | 본 스펙의 자연어 입력 표면이나 채팅 인텐트 의존성으로 결정적 도달 불가, 사용자 액션 면제 사유 |

## 미검증 및 보류 항목
| 항목 | 사유 | 후속 조치 |
| --- | --- | --- |
| 시나리오 03 디자이너 UI 테스트 통과 | 시드된 `vacation_request_process` proc_def의 `bpmn` 값이 `<bpmn />`로 비어 있어 `/definitions/vacation_request_process` 진입 시 `ProcessDefinitionChat.vue`가 `isConsultingMode` 분기로 들어가 채팅 UI를 띄우고 디자이너 툴바(`#processVariables`)가 마운트되지 않는다. 로그인·라우팅·`ProcessVariable.vue`까지의 사용자 경로는 코드로 작성되어 있으나 현재 실행 시 `#processVariables` 가시성 검증에서 실패한다. | (a) 시드된 `vacation_request_process`의 `bpmn` 컬럼에 유효한 BPMN XML을 채워 디자이너가 편집 모드로 마운트되도록 `e2e_seed.sql`을 보강하거나, (b) `/definitions/<id>?canEdit=true` 와 같은 명시적 편집 모드 진입 옵션을 도입한다. 둘 중 한 가지가 적용되면 시나리오 03의 실 UI 테스트가 의도대로 통과한다. |
| 시나리오 01/02의 실 프런트엔드 사용자 액션 검증 | 자연어 `/process-data-query`의 유일한 호출부는 `Chats.vue` 시스템 챗의 `CompanyQuery` 인텐트 분기이며, 채팅 백엔드 + intent 분류 LLM mocking까지 끌어들이지 않으면 결정적으로 도달 불가. 사용자가 명시적으로 protocol-only 면제 옵션을 승인함. | 자연어 조회를 단독으로 노출하는 UI 표면이 추가되면 시나리오 01/02를 사용자-액션 시나리오로 승격한다. |
| 시나리오 04의 실 프런트엔드 사용자 액션 검증 | 테넌트 컨텍스트가 게이트웨이의 `Host`/`X-Forwarded-Host`로 결정되어 브라우저 사용자 액션으로 변경할 수 없음. | nginx에 다중 가상 호스트가 추가되면 두 origin에서 같은 사용자 작업을 수행하는 UI 비교 시나리오로 확장한다. |
| 명세 시나리오 "표로 만들 결과가 없음" → 응답 본문 `null` | 현재 구현은 `StrOutputParser` 후처리로 인해 항상 문자열을 반환하며 `null` 분기가 사실상 동작하지 않음. 시나리오 02는 빈 본문 반환 동작에 초점을 둠. | `process_data_query_chain`(현재 미사용) 경로 활성화 또는 `None` 반환 분기가 생기면 시나리오를 보강한다. |

## 체크리스트
- [x] 모든 Requirement가 하나 이상의 E2E 시나리오에 매핑되어 있습니다.
- [x] 중요한 OpenSpec Scenario가 E2E 시나리오에 매핑되어 있거나 미검증 및 보류 항목에 기록되어 있습니다.
- [x] 사람이 읽는 요구사항명, 명세 시나리오명, 목적, 절차, 기대 결과는 한국어로 작성되어 있습니다.
- [x] 원본 OpenSpec에 영어 설명이 있더라도 E2E 문서에는 한국어 의미로 변환되어 있으며, API 경로·필드명·이벤트명 같은 계약 식별자만 원문으로 유지합니다.
- [x] 원본 명세가 하나의 백엔드 연계 피쳐 또는 응집된 사용자 workflow 범위이며, 마이크로서비스 전체 요약이나 프론트엔드 단독 명세가 아닙니다.
- [x] 원본 명세의 서비스 접두어 또는 도메인 구분자가 `frontend`, `ui`, `react`, `page`, `component` 같은 구현 레이어가 아닙니다.
- [x] E2E가 실행할 소유 백엔드 서비스/API/데이터 계약이 명확합니다.
- [x] 서비스 접두형 명세 ID를 사용하는 경우 스위트 슬러그가 동일한 값을 유지합니다.
- [x] E2E 시나리오, 테스트 스크립트, seed/stub, 실행 결과, 스크린샷은 `openspec/specs/completion_process-data-query/e2e/` 아래에 응집되어 있습니다.
- [x] 사용자-facing 시나리오(03)는 직접 API 요청이 아니라 브라우저 UI 상호작용으로 검증합니다. 시나리오 01/02/04는 사용자-액션 면제 사유를 명시했습니다.
- [x] 시나리오별 스크린샷 체크포인트가 매뉴얼에 재사용할 수 있는 UI 상태를 설명합니다 (사용자-액션 면제 시나리오는 스크린샷 없음 명시).
- [x] 스펙 관련 백엔드/프론트엔드 파일과 함수가 코드 표면 표에 기록되어 있습니다.
- [x] 커버리지 기준이 전체 저장소가 아니라 스펙 관련 파일/함수 중심으로 정의되어 있습니다.
- [x] 결과 경로가 `OUTPUT_CONTRACT.md`와 일치합니다.
