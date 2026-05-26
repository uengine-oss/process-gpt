# Code To Spec 계획: completion 마이크로서비스

## 입력 범위
- 소스 폴더:
  - `services/completion` (FastAPI HTTP 서비스 본체 + `fcm_service/` 푸시 알림 워커 + `polling_service/` 워크아이템 폴링 워커)
- 제외 범위:
  - `services/completion/min.py` (`/generate_joke/*` LangServe 라우트): 라우트명과 동작이 불일치하는 실험성 코드이며, 테스트나 문서로 지원 계약임이 확인되지 않음. 제품 스펙 대신 열린 질문으로 남긴다.
  - `services/completion/frontend/`: Vue 프론트엔드 코드. 서비스 접두어로 사용하지 않으며, 백엔드 API 계약의 사용자 조작 evidence로만 활용한다.
  - `services/completion/Usage.py`, `app.py`(hello world 스텁), `migration_script.py`/`migration_rpc_function.sql`(운영자용 일회성 마이그레이션 CLI): 외부 클라이언트 계약이 아니므로 스펙 대상에서 제외하고 필요 시 열린 질문으로만 기록한다.
  - 비활성(주석 처리)된 LangServe `add_routes` 블록 및 라우트에 연결되지 않은 LLM 체인: 도달 불가능 코드이므로 계약으로 다루지 않는다.

## 분석 기준
- 스펙은 구현 요약이 아니라 외부에서 관측 가능한 행위 계약으로 작성한다.
- 내부 함수명, 클래스명, private helper, 모듈 경로, 파일 경로, 라인 번호는 스펙에 쓰지 않는다.
- Purpose, Requirement 제목, Requirement 본문, Scenario 제목, Scenario 단계는 한국어로 작성한다.
- `### Requirement:`와 `#### Scenario:` 접두어는 유지하되, 그 뒤의 이름은 한국어로 작성한다.
- 공개 API 경로, HTTP method, 요청/응답 필드명, 이벤트명, 설정 키, 상태 enum 값은 계약인 경우에만 원문을 유지한다.
- main spec은 마이크로서비스 전체가 아니라 하나의 피쳐 단위로 작성한다.
- `services/completion` 입력이므로 모든 스펙 ID는 `completion` 접두어로 시작한다. 이 서비스는 여러 업무 도메인(프로세스 실행, 정의 관리, LLM 게이트웨이, 에이전트 메모리, MCP, 알림, 사용자/테넌트 관리, 콜봇, 백그라운드 워커)에 걸치므로 `completion_<domain>-<feature>` 형식을 사용한다.
- 서비스 내부에서 발견한 외부 시스템명(mem0, MCP, FCM, Upstage 등)이나 프로토콜명은 `completion` 접두어를 대체하지 않는다.
- `frontend`, `ui`, `react`, `page`, `component`는 서비스 접두어 또는 도메인 구분자로 쓰지 않는다.

## 제안 스펙 분할

### `completion_process-workitem-submission`
- Service prefix: `completion` (`services/completion` 마이크로서비스 폴더명)
- Domain discriminator: `process` (프로세스 실행 도메인)
- Naming 결정 근거: `services/completion` 마이크로서비스 입력이므로 접두어를 `completion`으로 고정하고, 프로세스 인스턴스/워크아이템 생성·제출 도메인을 `process`로 구분한다.
- Feature: `workitem-submission` (워크아이템 생성·제출 및 역할 바인딩)
- 목적: 클라이언트가 프로세스 인스턴스를 시작하고, 폼 값을 담아 워크아이템을 제출하며, 프로세스 역할을 사용자 계정에 바인딩하는 피쳐.
- E2E 단위 판단: `/role-binding`으로 역할을 해소하고 `/initiate`로 인스턴스를 시작한 뒤 `/complete`로 워크아이템을 제출하는 하나의 사용자 흐름을 단일 suite로 검증할 수 있다.
- 백엔드/제품 계약 연결:
  - `POST /complete`, `POST /vision-complete`: `{input}` 봉투, 응답은 `workitem_data`(status `SUBMITTED`)
  - `POST /initiate`: `{input}` 봉투, 응답은 `workitem_data`(status `TODO`)
  - `POST /role-binding`: `{input}` 봉투, 응답은 `{roleBindings:[{roleName,userId}]}` JSON 문자열
  - 영속화: `bpm_proc_inst`, `todolist`, `proc_def`, `proc_inst_source` upsert
- 포함 유즈 케이스:
  - 신규 프로세스 인스턴스 시작과 초기 활동 워크아이템(`TODO`) 생성
  - 폼 값/역할 매핑을 담은 워크아이템 제출과 `SUBMITTED` 전이
  - 기존 `task_id` 워크아이템 갱신 및 `revert_from` 재제출
  - 역할 매핑 목록을 사용자 계정으로 해소
- 주요 관측 계약:
  - 필수 식별자 누락 시 `400`(`Process instance id is required`, `No initial activity found`, `No default user email found`)
  - 응답 워크아이템 필드: `id`, `proc_inst_id`, `proc_def_id`, `activity_id`, `status`, `assignees`, `output`, `version_tag`, `version`
  - 버전 해소 우선순위(명시 버전 → `prod_version` → 최신 major/minor → 기본 정의)
  - 테넌트 격리: 요청 subdomain 기반
- 다른 spec으로 분리할 범위:
  - `completion_process-activity-rework`: 재작업/보상은 별도 워크플로
  - `completion_workitem-polling-execution`: 제출 후 자동 처리는 워커 스펙
- 제외할 구현 세부:
  - 내부 핸들러/체인 함수 구성, langchain 캐시 동작
- frontend evidence:
  - 프로세스 시작 버튼, 폼 입력 화면, 역할 지정 화면
- 근거 유형:
  - routes, README API 예시, 영속화 테이블, 오류 응답
- 위험 또는 열린 질문:
  - `/complete`와 `/vision-complete`가 동일 핸들러를 공유하므로 vision 전용 동작 차이가 코드상 드러나지 않음

### `completion_process-activity-rework`
- Service prefix: `completion`
- Domain discriminator: `process`
- Naming 결정 근거: `services/completion` 입력, 프로세스 실행 도메인의 재작업 피쳐.
- Feature: `activity-rework` (완료된 활동 재작업 및 보상 코드 생성)
- 목적: 운영자가 특정 활동을 다시 수행 대상으로 식별하고, 재작업을 시작하며, 이전 자동 작업에 대한 보상(undo) 코드가 준비되도록 하는 피쳐.
- E2E 단위 판단: 재작업 후보 조회 → 재작업 시작 → 보상 워크아이템 생성 확인을 하나의 흐름으로 검증할 수 있다.
- 백엔드/제품 계약 연결:
  - `POST /get-rework-activities`: 응답 `{reference:[{id,name}], all:[{id,name}]}`
  - `POST /rework-complete`: 응답은 새 워크아이템 id를 키로 한 객체
  - 보상 코드 영속화: `mcp_python_code.compensation`
- 포함 유즈 케이스:
  - 인스턴스/활동 기준 재작업 가능 활동 목록 조회
  - 선택한 활동들의 재작업 시작(시작 활동 `IN_PROGRESS`, 나머지 `TODO`)
  - 되돌릴 수 있는 도구 사용 이력으로부터 보상 코드 생성
- 주요 관측 계약:
  - 워크아이템 미존재 시 `400 No workitem found`
  - 보상 코드가 이미 있거나 되돌릴 이벤트가 없으면 생성 생략
  - 보상 워크아이템은 `agent_orch='crewai-action'`, `status='IN_PROGRESS'`
- 다른 spec으로 분리할 범위:
  - `completion_workitem-polling-execution`: 생성된 보상 워크아이템의 실제 실행
- 제외할 구현 세부:
  - LLM 보상 코드 프롬프트 내부 구조
- frontend evidence:
  - 재작업 활동 선택 화면, 재작업 시작 버튼
- 근거 유형:
  - routes, 영속화 테이블, 이벤트 로그(`events`)
- 위험 또는 열린 질문:
  - 보상 대상에서 제외되는 도구 집합(`mem0`, `memento`, `human_asked`, `dmn_rule`, SELECT 전용 SQL)이 안정 계약인지 불확실

### `completion_process-definition-search`
- Service prefix: `completion`
- Domain discriminator: `process`
- Naming 결정 근거: `services/completion` 입력, 프로세스 정의 도메인의 검색 피쳐.
- Feature: `definition-search` (자연어 기반 프로세스 정의 검색)
- 목적: 사용자가 자연어 질의로 시작할 프로세스 정의를 의미 기반으로 찾는 피쳐.
- E2E 단위 판단: 질의 입력 → 유사 정의 결과 표시 → 빈 결과 처리를 하나의 흐름으로 검증할 수 있다.
- 백엔드/제품 계약 연결:
  - `POST /process-search`, `POST /vision-process-search`: 요청 `query`, 응답은 유사도 검색 결과 문서 목록(최대 3건)
  - 벡터 저장소(`documents`) 읽기, `tenant_id`/`type=process_definition` 필터
- 포함 유즈 케이스:
  - 자연어 질의로 프로세스 정의 후보 검색
  - 검색 실패 시 빈 목록 반환
- 주요 관측 계약:
  - 응답은 최대 3건의 유사 정의
  - 벡터 검색 오류 시 HTTP 200 + 빈 목록
  - 테넌트 격리: subdomain 필터
- 다른 spec으로 분리할 범위:
  - `completion_process-data-query`: 인스턴스/실행 데이터 질의는 별도
- 제외할 구현 세부:
  - LangChain Document 직렬화 형식
- frontend evidence:
  - 프로세스 검색 입력창, 결과 목록 화면
- 근거 유형:
  - routes, 벡터 저장소 필터
- 위험 또는 열린 질문:
  - `/vision-process-search`가 `/process-search`와 동일 핸들러를 공유, vision 차이 불명확

### `completion_process-definition-feedback`
- Service prefix: `completion`
- Domain discriminator: `process`
- Naming 결정 근거: `services/completion` 입력, 프로세스 정의 도메인의 작성 보조 피쳐.
- Feature: `definition-feedback` (활동 정의 피드백 및 버전 변경 비교)
- 목적: 프로세스 설계자가 활동 정의에 대한 AI 피드백을 받고, 작업(task) 정의의 버전 간 변경 내역을 확인하는 피쳐.
- E2E 단위 판단: 활동 피드백 요청 → 피드백 목록 확인, 작업 버전 변경 요청 → 변경 요약 확인을 하나의 보조 흐름으로 검증할 수 있다.
- 백엔드/제품 계약 연결:
  - `POST /get-feedback`: 요청 `processDefinitionId`/`activityId`/`taskId`, 응답은 피드백 문자열 배열
  - `POST /get-feedback-diff`: 요청 `taskId`, 응답 `{modifications, summary}`
- 포함 유즈 케이스:
  - 활동 정의에 대한 개선 피드백 목록 조회
  - 작업 정의의 `inputData`/`checkpoints`/`description`/`instruction`/`conditionExamples` 변경 전후 비교
- 주요 관측 계약:
  - 워크아이템/활동 미존재 시 `400`(`No workitem found`, `No activity found`)
  - `modifications`의 각 항목은 `before`/`after`/`changed` 구조
- 다른 spec으로 분리할 범위:
  - 없음
- 제외할 구현 세부:
  - LLM 피드백 프롬프트 구조
- frontend evidence:
  - 활동 편집 화면의 피드백 패널, 변경 비교 화면
- 근거 유형:
  - routes, 응답 스키마
- 위험 또는 열린 질문:
  - 없음

### `completion_process-data-query`
- Service prefix: `completion`
- Domain discriminator: `process`
- Naming 결정 근거: `services/completion` 입력, 프로세스 데이터 조회 도메인 피쳐.
- Feature: `data-query` (프로세스 데이터 자연어 조회 및 변수 SQL 생성)
- 목적: 사용자가 자연어로 프로세스 실행 데이터를 조회하고, 프로세스 변수에 대한 SQL 스키마를 생성받는 피쳐.
- E2E 단위 판단: 데이터 질의 입력 → HTML 표 결과 확인, 변수 규칙 입력 → SQL 스키마 확인을 하나의 흐름으로 검증할 수 있다.
- 백엔드/제품 계약 연결:
  - `POST /process-data-query`: 요청 `{input:{query,user_id,chat_room_id}}`, 응답은 HTML `<table>` 문자열
  - `POST /process-var-sql`: 요청 `{input:{var_name,resolution_rule}}`, 응답은 SQL 텍스트
  - 벡터 저장소 및 인스턴스/할 일 데이터 읽기
- 포함 유즈 케이스:
  - 사용자 이메일 기준 프로세스 데이터 자연어 질의 → HTML 표 응답
  - 프로세스 변수 정의로부터 CREATE TABLE 스키마 SQL 생성
- 주요 관측 계약:
  - 응답은 정제된 HTML 표 문자열(추출 실패 시 `null` 가능)
  - 테넌트 격리: subdomain 필터
- 다른 spec으로 분리할 범위:
  - `completion_process-definition-search`: 정의 검색은 별도
- 제외할 구현 세부:
  - LLM 표/스키마 생성 체인 구조, 비활성 LangServe 블록
- frontend evidence:
  - 데이터 질의 입력창, 표 결과 화면
- 근거 유형:
  - routes, 벡터 저장소 필터
- 위험 또는 열린 질문:
  - `user_id`가 이메일로 취급되며 소유권 검증이 없음

### `completion_llm-chat-gateway`
- Service prefix: `completion`
- Domain discriminator: `llm`
- Naming 결정 근거: `services/completion` 입력, LLM 게이트웨이 도메인 피쳐.
- Feature: `chat-gateway` (OpenAI 호환 채팅·임베딩·토큰 계산 게이트웨이)
- 목적: 클라이언트가 OpenAI 호환 인터페이스로 채팅 완성(스트리밍 포함), 토큰 수 계산, 임베딩 벡터 생성을 요청하는 피쳐.
- E2E 단위 판단: 채팅 메시지 요청(스트리밍/비스트리밍), 토큰 계산, 임베딩 생성을 하나의 게이트웨이 suite로 검증할 수 있다.
- 백엔드/제품 계약 연결:
  - `GET /langchain-chat/sanity-check`: `{is_sanity_check:true}`
  - `POST /langchain-chat/messages`: 요청 `{model,messages,stream,modelConfig}`, 응답 `{id,choices}` 또는 `text/event-stream`
  - `POST /langchain-chat/count-tokens`: 응답 `{input_tokens}`
  - `POST /langchain-chat/embeddings`: 응답 `{embedding}`
- 포함 유즈 케이스:
  - 비스트리밍 채팅 완성 응답
  - `stream=true` SSE 스트리밍 응답(`data:` 프레임, `[DONE]` 종료)
  - 메시지 토큰 수 계산
  - 텍스트 임베딩 벡터 생성
- 주요 관측 계약:
  - `model` 미해소 시 `400`, 임베딩 미구현 시 `501`
  - SSE 청크는 `{id,choices:[{delta:{content}}]}`, 종료 프레임 `data: [DONE]`
- 다른 spec으로 분리할 범위:
  - `completion_agent-memory-chat`: 메모리 에이전트 대화는 별도
- 제외할 구현 세부:
  - LangChain 캐시 동작, 환경별 캐시 분기
- frontend evidence:
  - 채팅 입력창, 스트리밍 출력 화면
- 근거 유형:
  - routes, 요청/응답 스키마, SSE 프레임 형식
- 위험 또는 열린 질문:
  - 토큰 사용량 기록이 비활성화되어 있어 과금 계약 여부 불확실

### `completion_agent-memory-chat`
- Service prefix: `completion`
- Domain discriminator: `agent`
- Naming 결정 근거: `services/completion` 입력, 에이전트 메모리 도메인 피쳐.
- Feature: `memory-chat` (메모리 기반 멀티 에이전트 대화)
- 목적: 사용자가 학습 모드로 정보를 에이전트 메모리에 저장하고, 질의 모드로 저장된 메모리를 검색·활용한 답변을 받는 피쳐.
- E2E 단위 판단: 학습 모드 메시지 저장 → 질의 모드 메시지로 메모리 활용 답변 확인을 하나의 흐름으로 검증할 수 있다.
- 백엔드/제품 계약 연결:
  - `POST /multi-agent/chat`: 요청 `{text,chat_room_id,options}`, 응답 `{task_id,response}`
  - `GET /multi-agent/health-check`: `{status:"healthy"}`
  - `GET /multi-agent/fetch-data`: 원격 에이전트 디스크립터 패스스루
  - 메모리 영속화: `memories` 벡터 컬렉션
- 포함 유즈 케이스:
  - 학습 모드 정보 저장 및 중복(유사도 임계값) 시 미저장
  - 질의 모드 메모리 검색 기반 답변(`content`/`html_content`/`search_results`)
  - 원격 에이전트 `/.well-known/agent.json` 조회
- 주요 관측 계약:
  - `agent_id` 누락 시 `400 agent_id is required for Mem0 agent`
  - 응답 `response.type`은 `information` 또는 `query`
- 다른 spec으로 분리할 범위:
  - `completion_llm-chat-gateway`: 일반 채팅 게이트웨이는 별도
- 제외할 구현 세부:
  - mem0 임베딩 패치, DB 연결 문자열 조립
- frontend evidence:
  - 학습/질의 모드 토글, 대화 화면
- 근거 유형:
  - routes, mem0 영속화 동작
- 위험 또는 열린 질문:
  - `fetch-data`가 임의 URL을 검증 없이 요청하므로 SSRF 위험이 있음(계약상 의도 불명확)

### `completion_mcp-server-config`
- Service prefix: `completion`
- Domain discriminator: `mcp`
- Naming 결정 근거: `services/completion` 입력, MCP 도구 설정 도메인 피쳐.
- Feature: `server-config` (MCP 서버 카탈로그 제공)
- 목적: 클라이언트가 사용 가능한 MCP 서버/도구 카탈로그를 조회하는 피쳐.
- E2E 단위 판단: 카탈로그 조회 → 서버 항목 구조 확인 → 설정 누락 시 오류 확인을 하나의 흐름으로 검증할 수 있다.
- 백엔드/제품 계약 연결:
  - `GET /mcp-tools`: 응답은 `mcpServers` 객체(서버명 키)
- 포함 유즈 케이스:
  - MCP 서버 카탈로그 조회
  - 설정 파일 누락/손상 시 오류 응답
- 주요 관측 계약:
  - 설정 로드 실패 시 `404 Failed to load MCP config`
  - 각 서버 항목은 stdio command 형식 또는 url/sse 형식
- 다른 spec으로 분리할 범위:
  - 없음
- 제외할 구현 세부:
  - 설정 파일 경로
- frontend evidence:
  - 도구 선택 화면
- 근거 유형:
  - routes, 설정 파일 구조
- 위험 또는 열린 질문:
  - 카탈로그에 평문 자격증명이 포함되어 인증 없이 노출됨(보안 위험, 계약 의도 확인 필요)

### `completion_tenant-user-administration`
- Service prefix: `completion`
- Domain discriminator: `tenant`
- Naming 결정 근거: `services/completion` 입력, 테넌트/사용자 관리 도메인 피쳐.
- Feature: `user-administration` (사용자 생성·초대·초기 설정 및 테넌트 지정)
- 목적: 운영자가 사용자 계정을 생성·초대하고, 초기 정보를 설정하며, 사용자/테넌트 관리 정보를 갱신하는 피쳐.
- E2E 단위 판단: 사용자 생성 → 초대 → 초기 설정 → 테넌트/관리 정보 갱신을 하나의 관리 흐름으로 검증할 수 있다.
- 백엔드/제품 계약 연결:
  - `POST /create-user`, `POST /invite-user`, `POST /set-initial-info`, `POST /set-tenant`, `POST /update-user`: 모두 `{input}` 봉투
  - `users`, `tenants` 영속화, 초대 이메일(SMTP) 발송
- 포함 유즈 케이스:
  - 신규 사용자 생성
  - 사용자 초대 및 초대 이메일 발송
  - 초기 정보 설정
  - 사용자/테넌트 관리 정보 갱신
- 주요 관측 계약:
  - 모든 라우트는 `{input}` 봉투를 받음
  - 초대 이메일은 `https://{tenant_id}.process-gpt.io/auth/initial-setting` 링크 포함
- 다른 spec으로 분리할 범위:
  - 없음
- 제외할 구현 세부:
  - `database` 함수 내부 필드 구성
- frontend evidence:
  - 사용자 관리 화면, 초대 폼
- 근거 유형:
  - routes, SMTP 발송, 영속화 테이블
- 위험 또는 열린 질문:
  - 인증/인가 검사가 코드상 관측되지 않음(민감 작업이 보호 없이 노출). 입력 필드 상세는 `database` 모듈에 있어 외부 계약 확정 곤란

### `completion_callbot-task-management`
- Service prefix: `completion`
- Domain discriminator: `callbot`
- Naming 결정 근거: `services/completion` 입력, 음성 콜봇 연동 도메인 피쳐.
- Feature: `task-management` (콜봇용 할 일 조회·수정·제출)
- 목적: Twilio 기반 음성 콜봇 클라이언트가 발신자 정보와 사용자 할 일을 조회하고, 작업 필드를 수정하고, 작업을 제출하는 피쳐.
- E2E 단위 판단: 발신자 식별 → 할 일 목록 조회 → 작업 상세 조회 → 필드 수정 → 제출을 하나의 콜봇 흐름으로 검증할 수 있다.
- 백엔드/제품 계약 연결:
  - `GET /complete-callbot/caller-info`, `GET /complete-callbot/user-todolist`, `GET /complete-callbot/tasks`
  - `GET /complete-callbot/task/{task_id}`, `PATCH /complete-callbot/task/{task_id}`, `POST /complete-callbot/task/{task_id}/submit`
  - `todolist` 읽기/수정, 제출 시 `status='SUBMITTED'`
- 포함 유즈 케이스:
  - 발신 번호/사용자 식별 및 인사말 생성
  - 사용자 할 일 목록 및 상태 필터 조회
  - 작업 상세(폼 스키마/참조 폼) 조회
  - 작업 필드 수정 및 작업 제출
- 주요 관측 계약:
  - 대부분 오류는 HTTP 200 + `{success:false,error}`
  - 작업 미존재 시 `404 Task not found`
  - 제출은 `status='SUBMITTED'`로 전이하여 폴링 워커가 처리
- 다른 spec으로 분리할 범위:
  - `completion_workitem-polling-execution`: 제출 후 처리
- 제외할 구현 세부:
  - 하드코딩된 기본 user_id
- frontend evidence:
  - 음성 콜봇 대화(화면 없음, 음성 응답이 사용자 표면)
- 근거 유형:
  - routes, 영속화 테이블, 상태 enum
- 위험 또는 열린 질문:
  - 익명 발신자에게 실제 사용자 정보가 반환되는 하드코딩 fallback이 의도된 계약인지 불확실

### `completion_notification-push-delivery`
- Service prefix: `completion`
- Domain discriminator: `notification`
- Naming 결정 근거: `services/completion` 입력, `fcm_service/` 알림 워커 피쳐.
- Feature: `push-delivery` (FCM 푸시 알림 전달)
- 목적: 시스템이 미처리 알림을 주기적으로 감지하여 사용자 기기로 FCM 푸시를 전달하고, 온디맨드 알림 전송과 기기 토큰 조회를 제공하는 피쳐.
- E2E 단위 판단: 알림 행 생성 → 워커 폴링·전송 → 기기 토큰 조회/온디맨드 전송을 하나의 알림 전달 suite로 검증할 수 있다.
- 백엔드/제품 계약 연결:
  - `POST /send-notification`: 요청 `{user_id,title,body,type,url,from_user_id,data}`, 응답 `{success,message}`
  - `GET /device-token/{user_id}`: 응답 `{user_id,device_token}`
  - `GET /health`: 응답 `{status:"healthy",service:"fcm-service"}`
  - 15초 주기 `notifications` 폴링, `user_devices` 읽기
- 포함 유즈 케이스:
  - 미처리 알림(`consumer IS NULL`) 폴링 및 pod 클레임
  - 폴링 행 기반 FCM 푸시 전달
  - 온디맨드 알림 전송 및 기기 토큰 조회
- 주요 관측 계약:
  - 알림 메시지 표시 규칙(`from_user_id` 존재 시 제목/본문 구성)
  - `data`에 `type`/`url`/`title`/`body` 보강, `notification_id` 포함
  - `ENV=dev` 시 테넌트 필터 분기
- 다른 spec으로 분리할 범위:
  - `completion_workitem-polling-execution`: 워크아이템 처리는 별도
- 제외할 구현 세부:
  - Firebase 초기화 경로
- frontend evidence:
  - 모바일/웹 푸시 알림 표시
- 근거 유형:
  - routes, 폴링 주기, 알림 페이로드 필드
- 위험 또는 열린 질문:
  - FCM 전송 실패 시 클레임된 행이 되돌려지지 않아 at-most-once 전달(계약상 보장 수준 확인 필요)

### `completion_workitem-polling-execution`
- Service prefix: `completion`
- Domain discriminator: `workitem`
- Naming 결정 근거: `services/completion` 입력, `polling_service/` 워크아이템 폴링 워커의 핵심 처리 피쳐.
- Feature: `polling-execution` (제출된 워크아이템 자동 처리 및 프로세스 진행)
- 목적: 시스템이 제출/대기 상태 워크아이템을 주기적으로 감지하여 완료 여부를 판정하고, 다음 활동 워크아이템을 생성하며, 프로세스 인스턴스 상태를 전이시키는 피쳐.
- E2E 단위 판단: `SUBMITTED` 워크아이템 투입 → 워커 처리 → 다음 활동 워크아이템 생성 및 인스턴스 상태 전이를 하나의 진행 suite로 검증할 수 있다.
- 백엔드/제품 계약 연결:
  - 5초 주기 `todolist` 폴링(`SUBMITTED`/`PENDING`), pod `consumer` 클레임
  - `todolist`/`bpm_proc_inst` 상태 전이, `chats` 시스템 메시지 upsert
  - 타이머 이벤트 cron 등록 RPC `register_cron_intermidiated`
- 포함 유즈 케이스:
  - 워크아이템 폴링·클레임 및 동시 처리
  - 완료 판정 및 `DONE`/`PENDING` 전이, 다음 활동(`IN_PROGRESS`) 생성
  - 서브프로세스 자식 인스턴스 생성 및 부모 재개
  - 재시도 카운터 처리 및 3회 초과 시 강제 종료
  - 외부 고객(`external_customer`) 대상 이메일 발송
  - 30분 초과 stale `consumer` 회수
- 주요 관측 계약:
  - 워크아이템 상태 enum: `SUBMITTED`, `PENDING`, `IN_PROGRESS`, `DONE`, `CANCELLED`
  - 인스턴스 상태 enum: `RUNNING`, `COMPLETED`
  - LLM 출력 파싱 실패 시 `PENDING` 전이 + 시스템 채팅 메시지
- 다른 spec으로 분리할 범위:
  - `completion_automated-task-execution`: serviceTask/scriptTask 자동 실행은 별도
  - `completion_process-instance-file-cleanup`: 파일 정리는 별도
- 제외할 구현 세부:
  - 폴링 루프 구현, BPMN 조건 `eval` 처리
- frontend evidence:
  - 할 일 목록 상태 변화, 프로세스 진행 표시
- 근거 유형:
  - 폴링 트리거, 상태 전이, 영속화 테이블, 워커 README
- 위험 또는 열린 질문:
  - 다중 replica 동시 폴링의 정합성은 조건부 클레임에 의존

### `completion_automated-task-execution`
- Service prefix: `completion`
- Domain discriminator: `workitem`
- Naming 결정 근거: `services/completion` 입력, `polling_service/`의 자동 작업(서비스/스크립트) 실행 피쳐.
- Feature: `automated-task-execution` (serviceTask MCP 도구 실행 및 scriptTask 코드 실행)
- 목적: 시스템이 사람이 개입하지 않는 활동을 자동 실행한다. 서비스 작업은 테넌트 MCP 도구로, 스크립트 작업은 파이썬 코드로 실행하고 결과를 워크아이템에 기록한다.
- E2E 단위 판단: serviceTask 워크아이템 투입 → MCP 도구 실행 결과 확인, scriptTask 워크아이템 투입 → 코드 실행 결과 확인을 하나의 자동 실행 suite로 검증할 수 있다.
- 백엔드/제품 계약 연결:
  - serviceTask: 테넌트 MCP 설정(`tenants.mcp`) 기반 도구 실행, 결과 `{tool_name:{status,connection_type,error?}}`
  - scriptTask: `pythonCode` 실행, 종료 코드에 따른 `stdout`/`stderr` 결과
  - 실행 후 워크아이템 `status='DONE'`, `output` 기록
- 포함 유즈 케이스:
  - serviceTask의 MCP 도구 자동 실행 및 결과 기록
  - scriptTask의 파이썬 코드 자동 실행
  - 자동 실행 후 다음 활동 자동 진행
- 주요 관측 계약:
  - 도구 실행 성공/실패가 워크아이템 로그와 `output`에 반영
  - 코드 실행 종료 코드 0이면 `stdout`이 결과·`DONE`, 비0이면 `stderr`로 진행
- 다른 spec으로 분리할 범위:
  - `completion_workitem-polling-execution`: 폴링/사람 작업 완료 판정은 별도
- 제외할 구현 세부:
  - MCP 클라이언트 구성, 임시 파일 실행 방식
- frontend evidence:
  - 자동 활동 결과 표시
- 근거 유형:
  - 워커 처리 분기, 도구 결과 구조, 영속화
- 위험 또는 열린 질문:
  - scriptTask 코드가 샌드박스 없이 실행됨(보안 위험, 계약상 격리 보장 여부 확인 필요)

### `completion_process-instance-file-cleanup`
- Service prefix: `completion`
- Domain discriminator: `process`
- Naming 결정 근거: `services/completion` 입력, `polling_service/`의 완료 인스턴스 파일 정리 피쳐.
- Feature: `instance-file-cleanup` (완료된 프로세스 인스턴스의 첨부 파일 정리)
- 목적: 시스템이 완료된 프로세스 인스턴스에 연결된 스토리지 파일을 주기적으로 정리하는 피쳐.
- E2E 단위 판단: 완료 인스턴스 + 소스 파일 준비 → 정리 워커 주기 실행 → 스토리지 파일 삭제 확인을 하나의 흐름으로 검증할 수 있다.
- 백엔드/제품 계약 연결:
  - 300초 주기로 `bpm_proc_inst`(`status='COMPLETED'`, `is_clean_up=false`) 스캔
  - `proc_inst_source` 조회 후 스토리지 파일 삭제
- 포함 유즈 케이스:
  - 완료 인스턴스의 첨부 파일 삭제
- 주요 관측 계약:
  - 정리 대상은 완료 상태이며 아직 정리되지 않은 인스턴스
  - 정리 주기는 5분
- 다른 spec으로 분리할 범위:
  - `completion_workitem-polling-execution`: 워크아이템 처리는 별도
- 제외할 구현 세부:
  - 스토리지 버킷 이름 결정 로직
- frontend evidence:
  - 없음(운영자 관점 백그라운드 동작)
- 근거 유형:
  - 정리 주기, 영속화 테이블
- 위험 또는 열린 질문:
  - `is_clean_up=true` 기록이 코드상 비활성화되어 완료 인스턴스가 매 주기 재처리됨. 정리 멱등성 보장이 계약인지 확인 필요

## 추적표

| 소스 범위 | 관측된 외부 행위 | 백엔드/제품 계약 | Service prefix | Domain discriminator | Feature | 제안 스펙 폴더 | E2E 단위 | 처리 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `process_engine.py` (`/complete`,`/initiate`,`/role-binding`) | 인스턴스 시작·워크아이템 제출·역할 바인딩 | POST API + `bpm_proc_inst`/`todolist` upsert | `completion` | `process` | `workitem-submission` | `completion_process-workitem-submission` | 적절 | 포함 |
| `process_engine.py` (`/get-rework-activities`,`/rework-complete`), `compensation_handler.py` | 재작업 활동 조회·시작·보상 코드 생성 | POST API + `mcp_python_code` | `completion` | `process` | `activity-rework` | `completion_process-activity-rework` | 적절 | 포함 |
| `process_def_search.py` | 자연어 프로세스 정의 검색 | POST API + 벡터 저장소 | `completion` | `process` | `definition-search` | `completion_process-definition-search` | 적절 | 포함 |
| `process_engine.py` (`/get-feedback`,`/get-feedback-diff`) | 활동 피드백·버전 변경 비교 | POST API | `completion` | `process` | `definition-feedback` | `completion_process-definition-feedback` | 적절 | 포함 |
| `process_var_sql_gen.py` | 데이터 자연어 조회·변수 SQL 생성 | POST API + 벡터 저장소 | `completion` | `process` | `data-query` | `completion_process-data-query` | 적절 | 포함 |
| `process_chat.py`, `features/process_chat/` | OpenAI 호환 채팅/임베딩/토큰 | `/langchain-chat/*` + SSE | `completion` | `llm` | `chat-gateway` | `completion_llm-chat-gateway` | 적절 | 포함 |
| `agent_chat.py`, `mem0_agent_client.py` | 메모리 학습·질의 대화 | `/multi-agent/*` + `memories` | `completion` | `agent` | `memory-chat` | `completion_agent-memory-chat` | 적절 | 포함 |
| `mcp_config_api.py`, `mcp.json` | MCP 서버 카탈로그 조회 | `GET /mcp-tools` | `completion` | `mcp` | `server-config` | `completion_mcp-server-config` | 적절 | 포함 |
| `process_db_manager.py` | 사용자 생성·초대·초기설정·테넌트 지정 | POST API + `users`/`tenants` + SMTP | `completion` | `tenant` | `user-administration` | `completion_tenant-user-administration` | 적절 | 포함 |
| `callbot_api.py` | 콜봇 할 일 조회·수정·제출 | `/complete-callbot/*` + `todolist` | `completion` | `callbot` | `task-management` | `completion_callbot-task-management` | 적절 | 포함 |
| `fcm_service/`, `fcm_client.py` | 미처리 알림 폴링·FCM 전송 | `/send-notification` 등 + `notifications` | `completion` | `notification` | `push-delivery` | `completion_notification-push-delivery` | 적절 | 포함 |
| `polling_service/` (핵심 폴링) | 워크아이템 자동 처리·프로세스 진행 | `todolist`/`bpm_proc_inst` 전이 | `completion` | `workitem` | `polling-execution` | `completion_workitem-polling-execution` | 적절 | 포함 |
| `polling_service/` (serviceTask/scriptTask) | MCP 도구·코드 자동 실행 | 도구 결과·코드 출력 기록 | `completion` | `workitem` | `automated-task-execution` | `completion_automated-task-execution` | 적절 | 포함 |
| `polling_service/` (파일 정리) | 완료 인스턴스 파일 정리 | `bpm_proc_inst`/`proc_inst_source` + 스토리지 | `completion` | `process` | `instance-file-cleanup` | `completion_process-instance-file-cleanup` | 적절 | 포함 |
| `min.py` (`/generate_joke/*`) | 라우트명/동작 불일치 실험성 체인 | LangServe 라우트 | - | - | - | - | - | 제외(열린 질문) |
| `frontend/` | Vue UI | - | - | - | - | - | - | 제외(evidence로만 사용) |
| `app.py`, `Usage.py`, `migration_script.py`, 비활성 LangServe 블록 | 스텁/일회성 CLI/도달 불가 코드 | - | - | - | - | - | - | 제외 |

## 진행 체크리스트
- [x] 모든 입력 폴더가 확인되었다.
- [x] 각 스펙 폴더가 `<microservice>_<domain>-<feature>` 형식을 따른다.
- [x] 마이크로서비스/서비스 폴더 입력에서 생성된 모든 스펙 ID가 `completion` 폴더명으로 시작한다.
- [x] 여러 업무 도메인에 걸친 서비스이므로 도메인 구분자(`process`,`llm`,`agent`,`mcp`,`tenant`,`callbot`,`notification`,`workitem`)를 사용했다.
- [x] 서비스 접두어와 도메인 구분자가 백엔드/제품 기능 경계이며 `frontend`,`ui`,`react`,`page`,`component`가 아니다.
- [x] 스펙 폴더가 구현 구조가 아니라 피쳐 기준으로 나뉘었다.
- [x] 프론트엔드 입력은 evidence로만 사용했고 프론트엔드 단독 스펙은 생성하지 않았다.
- [x] 어떤 스펙도 마이크로서비스 전체, route inventory, controller/service/repository 계층을 요약하지 않는다.
- [x] 각 스펙 폴더의 유즈 케이스가 하나의 E2E suite로 자연스럽게 검증 가능한 범위다.
- [x] 불확실한 행위가 요구사항으로 단정되지 않고 열린 질문으로 남았다.
- [x] `openspec/specs` 작성 전에 이 계획이 저장되었다.
