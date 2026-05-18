# Code To Spec 계획: services/ 전체 역공학

## 입력 범위
- 소스 폴더:
  - `services/execution`
  - `services/completion` (코드 베이스가 `execution`과 사실상 동일하므로 같은 능력 스펙으로 다룬다)
  - `services/agent-feedback`
  - `services/memento`
  - `services/a2a-orch`
  - `services/autonomous-execution`
  - `services/crewai-action`
  - `services/crewai-deep-research`
  - `services/openai-deep-research`
  - `services/deep-research`
  - `services/langchain-react`
  - `services/generic-agent`
  - `services/bpmn-extractor`
  - `services/react-voice-agent`
  - `services/computer-use`
  - `services/office-mcp`
  - `services/mcp-validator`
  - `services/claude-skills`
  - `services/agent-sdk`
  - `services/agent-utils`
  - `services/frontend`
  - `services/agents.github.io`
  - `services/docs`

- 제외 범위:
  - `services/*-service.yaml` (Kubernetes Service 매니페스트; 인프라 산출물이며 외부 행위 계약 아님)
  - `compose/`, `gateway/`, `infra/`, `scripts/`, `start-all-services.*` (저장소 최상위 인프라; `/services` 범위 밖)
  - 각 서브모듈의 `tests/`, `examples/`, `benchmark/` 등 데모 자료 (스펙 평가에는 근거로만 사용)
  - `services/execution`과 `services/completion`의 동일 코드 중복 — 단일 능력 스펙으로 통합 기술

## 분석 기준
- 스펙은 구현 요약이 아니라 외부에서 관측 가능한 행위 계약으로 작성한다.
- 내부 함수명, 클래스명, private helper, 모듈 경로, 파일 경로, 라인 번호는 스펙에 쓰지 않는다.
- 공개 API 경로, HTTP method, 요청/응답 필드명, MCP tool 이름, 스트리밍 이벤트명, 환경 변수명, SQL 키워드/RPC 이름, DB 컬럼 키 (status, draft_status, agent_orch, output, draft 등)는 계약인 경우 원문을 유지한다.
- 공개 Python 패키지의 import 표면(클래스/데코레이터 이름)은 라이브러리 사용자가 호출하는 계약이므로 보존한다.
- 폴링 기반 워커들이 공유하는 `todolist` 작업 수명주기 계약은 별도의 능력 스펙으로 추출하고, 각 워커 능력 스펙에서는 자기 도메인의 차별 계약만 기술한다.

## 제안 스펙 분할

### `process-workflow-execution`
- 목적: BPM 프로세스 정의/인스턴스 진행, 워크아이템 완료, 역할 배정, 멀티에이전트 채팅, MCP 도구 노출, 콜봇 통합을 통해 사용자가 업무 흐름을 시작/완료/추적할 수 있게 한다.
- 포함 유즈 케이스:
  - 프로세스 인스턴스 시작/재시작
  - 사용자 또는 시스템이 워크아이템을 완료(`POST /complete`, `/vision-complete`, `/rework-complete`)
  - 역할 배정(`POST /role-binding`) 및 이메일 알림
  - 피드백/재작업 조회 및 처리(`/get-feedback*`, `/get-rework-activities`)
  - 프로세스 검색·데이터 조회(`/process-search`, `/process-data-query`, `/process-var-sql`)
  - 멀티에이전트 채팅 API(`/multi-agent/chat`, `/multi-agent/fetch-data`, `/multi-agent/health-check`)
  - MCP 도구 목록 노출(`/mcp-tools`)
  - 콜봇 / Twilio 통합(`/complete-callbot/*`)
  - `SUBMITTED → IN_PROGRESS → DONE` 백그라운드 폴링 처리 (userTask/scriptTask/serviceTask)
  - 모바일 알림(FCM 서비스 위임) 및 문서 RAG(Memento 위임)
- 주요 관측 계약:
  - X-Forwarded-Host 헤더 기반 멀티테넌트 식별
  - 응답 코드 정책(필수 필드 누락 400, 부재 404, 외부 의존 실패 500)
  - 환경 변수 `SUPABASE_URL/KEY`, `LLM_MODEL`, `LLM_PROXY_URL/_API_KEY`, `OPENAI_API_KEY`, `SMTP_*`, `MCP_CONFIG`, `FCM_SERVICE_URL`, `MEMENTO_SERVICE_URL`, `WORKITEM_CONSUMER`, `ENV`
  - 영속 상태: `proc_def`, `proc_inst`, `todolist`, `chat_history`, `users`, `organization_chart`, `events`
- 제외할 구현 세부: 라우터 파일 구조, FastAPI 라우터 분리 방식, 내부 헬퍼 함수명
- 근거 유형: 라우트 모듈, README, k8s manifest, mcp.json, migration sql, function.sql
- 위험 또는 열린 질문:
  - `execution`과 `completion` 서브모듈의 실질적 차이(런타임 설정만 다른지, 일부 엔드포인트가 한쪽에만 있는지) — 코드 비교로 확정 필요
  - `/complete` 응답 본문 정확한 필드 스키마 (탐색 단계에서 미확정)
  - 콜봇 엔드포인트의 인증 경로

### `agent-task-protocol`
- 목적: 모든 에이전트 워커가 공통으로 따르는 작업 수명주기 계약을 정의한다. 작업 큐, 클레임, 상태 전이, 드래프트/최종 산출, 피드백 재진입, 동시성, 이벤트 기록의 외부 가시 행위를 보장한다.
- 포함 유즈 케이스:
  - 워커가 `agent_orch` 키로 자기 작업을 한정 폴링
  - 동시 워커 환경에서 `FOR UPDATE SKIP LOCKED` 기반 단독 클레임
  - `draft_status`의 정상 전이(`NULL → STARTED → COMPLETED`)
  - 사용자 피드백 후 재실행(`FB_REQUESTED → STARTED → COMPLETED`)
  - 작업 최종 제출(`status: IN_PROGRESS → SUBMITTED/DONE`)
  - 중간 저장(드래프트) vs 최종 저장 구분
  - 실행 이벤트의 영속 기록과 외부 관측
  - 컨슈머 식별 및 해제(`consumer` 컬럼)
- 주요 관측 계약:
  - RPC `fetch_pending_task`, `fetch_pending_task_dev` (테넌트 한정), `fetch_done_data`, `save_task_result`
  - `todolist` 컬럼 스키마 측면의 외부 가시 부분(`status`, `draft_status`, `output`, `draft`, `feedback`, `consumer`, `agent_orch`, `agent_mode`, `tenant_id`, `proc_inst_id`)
  - `events` 테이블에 기록되는 이벤트 항목 외부 형태(`task_id`, `proc_inst_id`, `event_type`, `timestamp`, `event_data`)
- 제외할 구현 세부: SDK 내부 폴링 루프 구조, 백그라운드 태스크 관리 방식
- 근거 유형: `services/agent-sdk/function.sql`, README, SIMULATOR_README, 각 워커의 폴링 호출
- 위험 또는 열린 질문:
  - 워커별 변형 RPC(`crewai_deep_fetch_pending_task`, `openai_deep_fetch_pending_task` 등)가 공통 계약을 완전히 만족하는지

### `agent-sdk`
- 목적: ProcessGPT 에이전트를 외부 개발자가 직접 구현할 수 있도록 폴링 서버, 컨텍스트, 이벤트 큐, 시뮬레이터의 공개 Python 표면을 보장한다.
- 포함 유즈 케이스:
  - `pip install process-gpt-agent-sdk`로 설치 가능
  - `ProcessGPTAgentServer`로 폴링 기반 에이전트 서버 구동
  - `ProcessGPTRequestContext` / `ProcessGPTEventQueue`를 통한 작업/이벤트 인터페이스
  - `ProcessGPTAgentSimulator`, `SimulatorRequestContext`, `SimulatorEventQueue`로 데이터베이스 없이 로컬 시뮬레이션
  - CLI `simulate_standalone.py` 및 `processgpt_simulator_cli.py` 실행
  - 디버그/로그 레벨 환경 변수
- 주요 관측 계약:
  - 공개 import 이름(클래스 이름은 계약)
  - 시뮬레이터 표준 출력 이벤트 타입(`task_started`, `progress`, `output`, `done`, `cancelled`, `error`, `queue_closed`)과 필수 필드(`task_id`, `proc_inst_id`, ISO 8601 타임스탬프)
  - 환경 변수(`SUPABASE_URL/KEY`, `DEBUG_LEVEL`, `LOG_LEVEL`, `LOG_SPACED`, `ENV`)
- 제외할 구현 세부: 내부 폴링 알고리즘, 백그라운드 태스크 트리, 라이브러리 내부 디렉터리 구조
- 근거 유형: README, DEBUG_LEVELS.md, SIMULATOR_README.md, SIMULATION_TOOLKIT_SUMMARY.md, pyproject.toml, examples, function.sql
- 위험 또는 열린 질문:
  - A2A SDK 이벤트 타입(TaskArtifactUpdateEvent 등)의 외부 노출 범위

### `agent-toolkit`
- 목적: 에이전트 구현자가 보안된 도구·메모리·규칙·사용자 질의 인터페이스에 일관된 방식으로 접근할 수 있도록 공개 도구 라이브러리의 표면을 보장한다.
- 포함 유즈 케이스:
  - `pip install process-gpt-agent-utils`
  - `SafeToolLoader`로 MCP 도구를 이름 기반 허용 목록으로 로드
  - `Mem0Tool` / `MementoTool` / `HumanQueryTool` / `DMNRuleTool` / `DeterministicCodeTool` 사용
  - 컨텍스트 변수 API(`set_context`/`reset_context`/`get_context_snapshot`)
  - CrewAI 이벤트 → `events` 테이블 자동 기록(`CrewAIEventLogger`)
  - 알림/이벤트/사용자 응답 저장 유틸(`save_notification`, `save_event`, `fetch_human_response`, `initialize_db`)
- 주요 관측 계약:
  - 공개 import 이름과 호출 시그니처의 안정성
  - 환경 변수(`SUPABASE_URL/KEY`, `DB_USER/PASSWORD/HOST/PORT/NAME`)
  - DMN 규칙 저장 위치(`proc_def` 테이블, `type='dmn'`)
- 제외할 구현 세부: 내부 helper 분기, vecs/pgvector lock 전략 세부, mem0 호출 내부
- 근거 유형: pyproject.toml, README, processgpt_agent_utils/__init__.py 재노출, function.sql 부재 확인
- 위험 또는 열린 질문:
  - 도구 보안 정책 파일 위치/형식, CrewAI 버전 호환 범위 외부 노출 여부

### `agent-feedback-learning`
- 목적: 에이전트의 초기 지식 셋팅과 운영 피드백을 받아 메모리(MEMORY), 의사결정 규칙(DMN_RULE), 절차 스킬(SKILL)로 자동 반영하여 차후 작업에 활용되도록 한다.
- 포함 유즈 케이스:
  - `POST /setup-agent-knowledge`로 에이전트 초기 지식 셋팅
  - 7초 폴링으로 피드백 큐 처리(IN_PROGRESS → COMPLETED/FAILED)
  - merge_mode(REPLACE/EXTEND/REFINE) 기반 지식 병합
  - MCP 서버를 통한 SKILL CRUD
  - mem0 기반 MEMORY 저장, `proc_def` DMN 규칙 저장
- 주요 관측 계약:
  - 상태 전이(STARTED → DONE/FAILED) 가시화 (`agent_knowledge_setup_log`, `agent_feedback_tasks`)
  - 환경 변수(`MCP_SERVER_URL`, `MCP_SERVER_NAME`, `USE_SKILL_CREATOR_WORKFLOW`, `LLM_MODEL`, `LLM_TRANSLATOR_MODEL` 등)
  - 응답 코드 정책(400/404/500), 인증 헤더 정책
- 제외할 구현 세부: ReAct 추론 5단계의 내부 프롬프트, 도구 호출 순서
- 근거 유형: FEEDBACK_PROCESSING_ARCHITECTURE.md, main.py, function.sql
- 위험 또는 열린 질문:
  - 피드백 재시도 정책 / 데드레터 처리 명시 여부

### `knowledge-memory`
- 목적: 문서 수집·인덱싱·검색·RAG 응답을 단일 외부 API로 제공하고, Google Drive와 Supabase Storage를 지식 소스로 통합하며, 지식 파일과 폴더의 외부 조작을 제공한다.
- 포함 유즈 케이스:
  - 파일/Drive/Storage/DB 레코드 수집(`POST /process`, `/process/database`, `/process-output`, `/save-to-storage`, `/save-to-drive`)
  - 유사도 검색·청크 회수·RAG 응답(`GET /search`, `/retrieve`, `/retrieve-images`, `/query`, `POST /retrieve-by-indices`)
  - 문서/청크/이미지 조회(`/documents/*`, `/preview/pdf-highlight`)
  - 지식 파일/폴더 CRUD(`/knowledge/files/*`, `/knowledge/folders/*`)
  - Google OAuth 인증(`/auth/google/*`)
  - 백그라운드 인덱싱 상태(`/process/drive/status`), 메모리 디버그(`/debug/memory`)
- 주요 관측 계약:
  - 멀티테넌트 식별(요청 `tenant_id`)
  - 응답 코드 정책(필수값 누락 400, 인증 필요 401, 부재 404, 외부 의존 실패 500)
  - 환경 변수(`MEMENTO_LLM_PROVIDER`, `MEMENTO_EMBEDDING_PROVIDER`, `CHROMA_PERSIST_DIRECTORY`, `CHROMA_COLLECTION_NAME`, `SUPABASE_WRITE_EMBEDDING`, `PDF_STRATEGY`, `SYNAP_*`, `MEMENTO_DRIVE_FOLDER_ID` 등)
  - 영속 상태: `documents`, `document_images`, `processed_files`, `knowledge_files`, Chroma 컬렉션
- 제외할 구현 세부: 청크 분할 알고리즘, 파서 선택 분기
- 근거 유형: main.py, README, 라우트, 환경변수 예시
- 위험 또는 열린 질문:
  - Chroma 임베딩 모델의 외부 공시 여부
  - `/process-output` 응답 스키마

### `a2a-agent-bridge`
- 목적: 외부 A2A 프로토콜 에이전트가 ProcessGPT의 작업을 처리할 수 있도록 동기/비동기(웹훅) 두 경로로 연결하고, 작업 상태와 폼 산출을 표준 todolist 수명주기로 반영한다.
- 포함 유즈 케이스:
  - A2A 에이전트 카드 조회 후 push_notifications 지원 여부에 따른 동기/비동기 모드 자동 선택
  - 웹훅 콜백 수신(`POST /webhook/a2a/todolist/{todolist_id}`)
  - 헬스 체크(`GET /health`)
  - 폼 처리 흐름과 산출 저장
  - 웹훅 수신 시 todolist 정보 조회 후 폼 후처리 및 이벤트 발행
- 주요 관측 계약:
  - 이벤트 타입(working/task_started, completed/task_completed, webhook_accepted, webhook_callback_waiting, TaskArtifactUpdateEvent)
  - 외부 콜백 본문 처리(COMPLETED, INPUT_REQUIRED, WORKING, FAILED, CANCELED, OTHER)
  - 환경 변수(`WEBHOOK_PUBLIC_BASE_URL`, `WEBHOOK_RECEIVER_HOST/PORT/LOG_LEVEL`)
- 제외할 구현 세부: A2A SDK 내부 호출 시퀀스
- 근거 유형: README, 두 개의 Dockerfile(executor / webhook receiver), src/, function.sql
- 위험 또는 열린 질문:
  - 폼 프로세서가 생성하는 JSON 스키마, 실패 폼의 재처리 정책

### `presentation-streaming`
- 목적: 클라이언트가 WebSocket을 통해 주제어를 보내면 에이전트가 단계별 진행을 실시간으로 알리고, PowerPoint 등 산출물을 생성해 다운로드할 수 있게 한다.
- 포함 유즈 케이스:
  - WebSocket 연결로 토픽 문자열 전송 → 단계별 메시지 수신
  - `request_file:output/{filename}` 형식으로 산출 파일 다운로드
  - 생성 산출물은 `output/` 디렉터리에 영속
- 주요 관측 계약:
  - WebSocket 엔드포인트(`ws://0.0.0.0:6789`)
  - 진행 메시지 카테고리(Chain 시작/종료, Agent 액션, Tool 실행, Chain 에러 등)
  - 환경 변수(`OPENAI_API_KEY`)
- 제외할 구현 세부: CrewAI/LangChain 콜백 구현 세부
- 근거 유형: main.py, server.py, README, requirements.txt, static/
- 위험 또는 열린 질문:
  - 산출 파일 보존 기간/명명 규칙, 인증/권한 모델

### `crewai-action-runner`
- 목적: ProcessGPT 작업 큐에서 CrewAI 기반 단일 작업을 실행하고, 폼 데이터/멀티 에이전트 산출을 todolist 표준 산출 위치에 반영한다.
- 포함 유즈 케이스:
  - 헬스 체크(`GET /health`)
  - 5초 폴링으로 자신의 `agent_orch` 작업 클레임
  - DynamicPromptGenerator + Mem0 통합으로 프롬프트 최적화
  - SafeToolLoader 허용 목록 정책으로 도구 사용
  - 폼 데이터 JSON 변환 및 최종 산출 기록
- 주요 관측 계약:
  - 환경 변수(`LLM_MODEL`, `LLM_PROXY_URL/_API_KEY`, `OPENAI_API_KEY`, `LANGSMITH_*`, `SUPABASE_URL/KEY`)
  - 작업 이벤트(working/task_started, working/completed, TaskArtifactUpdateEvent)
- 제외할 구현 세부: 크루 객체 구성, DynamicPromptGenerator 내부 알고리즘
- 근거 유형: README, requirements.txt, Dockerfile, smoke_test.py
- 위험 또는 열린 질문:
  - 폼 데이터 정규화 결과 JSON 스키마, 도구 보안 정책 외부 공시 여부

### `crewai-deep-research-runner`
- 목적: ProcessGPT 작업 큐에서 `agent_orch='crewai-deep-research'` 작업을 받아 CrewAI 멀티 에이전트 심층 연구를 수행하고, 드래프트/최종 산출을 표준 위치에 저장한다.
- 포함 유즈 케이스:
  - 7초 폴링(`crewai_deep_fetch_pending_task` / `_dev`)
  - 피드백 재진입(`FB_REQUESTED`) 처리
  - 중간 저장(드래프트) 및 최종 저장 (`save_task_result`)
  - MCP 기반 외부 도구 사용
- 주요 관측 계약:
  - 환경 변수(`OPENAI_API_KEY`, `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`)
  - 상태 전이(`draft_status`, `consumer`, `output`, `draft`)
- 제외할 구현 세부: 크루 노드/엣지, Mem0 통합 세부
- 근거 유형: README, function.sql, main.py, requirements.txt
- 위험 또는 열린 질문:
  - 최종 산출 JSON 스키마

### `openai-deep-research-runner`
- 목적: ProcessGPT 작업 큐에서 `agent_orch='openai-deep-research'` 작업을 받아 OpenAI 웹 검색 도구 기반 심층 연구 워크플로우를 수행하고, 결과 마크다운을 표준 위치에 저장한다.
- 포함 유즈 케이스:
  - 7초 폴링(`openai_deep_fetch_pending_task` / `_dev`)
  - 피드백 재진입 처리
  - 워커 비정상 종료에도 폴링 지속
- 주요 관측 계약:
  - 환경 변수(`OPENAI_API_KEY`, `SUPABASE_URL/KEY`, `ENV`, `POLLING_TENANT_ID`, `PORT`)
  - 재시도 정책(3회 + 지수 백오프)
- 제외할 구현 세부: subprocess 워커 호출 방식
- 근거 유형: main.py, function.sql, requirements.txt
- 위험 또는 열린 질문:
  - 섹션 병렬 처리 여부, 다중 도구 전환 정책

### `conversational-research-assistant`
- 목적: 사용자가 자연어 채팅으로 심층 연구 보고서를 요청·수정·관리할 수 있는 대화형 API를 제공하며, 보고서 자산(마크다운, 이미지, 차트)을 외부에서 조회·재작성할 수 있게 한다.
- 포함 유즈 케이스:
  - 보고서 생성 요청(`POST /api/chat`, `/api/chat/stream`)
  - 명확화 질의 응답 흐름(`skip_clarification`)
  - 보고서 히스토리/조회/업데이트/삭제(`GET/PUT/DELETE /api/report/{id}`, `GET /api/history`)
  - 자산 조회 및 생성(`GET /api/report/{id}/asset/{filename}`, `POST /api/report/{id}/image`, `/image-suggest`)
  - 블록 재작성(`POST /api/report/{id}/rewrite`)
- 주요 관측 계약:
  - 스트리밍 SSE 이벤트로 단계별 진행 전송
  - 환경 변수(`DEEP_RESEARCH_LLM_PROVIDER`, `TAVILY_API_KEY`, `GOOGLE_API_KEY`, `MEMENTO_SERVICE_URL`, `PROCESS_GPT_OFFICE_MCP_URL`, `PORT`)
  - 영속 상태: Supabase 보고서/세션/자산 메타
- 제외할 구현 세부: 검색 플랜 알고리즘
- 근거 유형: src/, README, function.sql, requirements.txt
- 위험 또는 열린 질문:
  - `clarification_options` 형식, 스트리밍 청크 정책

### `react-coding-agent`
- 목적: 사용자가 자연어 지시로 안전한 코드 실행 환경에서 파일/패키지/Python 실행을 수행할 수 있게 한다.
- 포함 유즈 케이스:
  - 헬스 체크(`GET /health`)
  - CLI 대화형 입력
  - 9개 코딩/파일 도구 제공(`read_file`, `write_file`, `list_directory`, `list_python_environments`, `list_installed_packages`, `run_python_code`, `install_package`, `write_python_file`, `run_python_file`)
- 주요 관측 계약:
  - 환경 변수(`OPENAI_API_KEY`, `MCP_ALLOW_SYSTEM_ACCESS=0`)
  - 작업 결과 형식(stdout, 파일 변경, 이미지 산출)
- 제외할 구현 세부: MCP StdioServer 부팅 시퀀스
- 근거 유형: main.py, README, requirements.txt
- 위험 또는 열린 질문:
  - ProcessGPT 통합 시 결과 저장 방식 (`agent_orch='langchain-react'`)

### `generic-multi-agent-cli`
- 목적: 운영자가 자연어 목표를 입력하면 설정 파일에 정의된 에이전트들과 MCP 도구가 협력하여 목표를 수행하고, 결과 텍스트를 표준 출력으로 반환하는 CLI 진입점을 제공한다.
- 포함 유즈 케이스:
  - CLI 실행 및 목표 입력
  - 설정 파일 기반 에이전트/도구 구성
  - 메모리(mem0) 기반 지식 누적
- 주요 관측 계약:
  - 설정 파일 위치(`config/agents.yaml`, `config/mcp.json`)
  - 환경 변수(`OPENAI_API_KEY`, `PERPLEXITY_API_KEY`, `MEM_ZERO_API_KEY` 등)
  - 정상 종료 시그널 처리
- 제외할 구현 세부: Task 플래닝 알고리즘
- 근거 유형: README, src/, config/
- 위험 또는 열린 질문:
  - 캐시 관리 CLI 플래그의 정확한 동작

### `bpmn-document-extraction`
- 목적: PDF 문서를 BPMN 2.0 프로세스 정의·DMN 규칙·스킬 마크다운으로 변환하고, Neo4j 그래프와 파일 산출물을 통해 외부에서 결과를 조회·시각화할 수 있게 한다.
- 포함 유즈 케이스:
  - 파일 업로드 → 작업 시작(`POST /api/upload`, `POST /api/process/{job_id}`)
  - 작업 상태 폴링/스트리밍(`GET /api/jobs/{job_id}`, `GET /api/jobs/{job_id}/stream`)
  - 프로세스/엔티티/그래프 조회(`/api/processes`, `/api/processes/{id}`, `/graph`, `/api/tasks`, `/api/roles`, `/api/decisions`)
  - 파일 다운로드(`/api/files/bpmn`, `/api/files/dmn`)
  - Neo4j 초기화(`POST /api/neo4j/clear`)
- 주요 관측 계약:
  - 작업 상태 전이(`uploaded → processing → completed/error`)
  - 산출물(`process.bpmn`, `decisions.dmn`, `*.skill.md`)
  - 환경 변수(`OPENAI_API_KEY`, `LLM_BASE_URL`, `LLM_MODEL`, `OCR_ENGINE`, `ENABLE_OCR`, `NEO4J_*`, `SUPABASE_*`, `MEMENTO_URL` 등)
- 제외할 구현 세부: 8단계 파이프라인의 내부 호출 그래프
- 근거 유형: PRD.md, README, run.py, frontend/
- 위험 또는 열린 질문:
  - REST 모드와 A2A 에이전트 모드의 동시 운용 정책

### `voice-process-assistant`
- 목적: 사용자가 실시간 음성/텍스트 WebSocket 세션으로 자신의 프로세스, 작업, 채팅 기록, 조직 정보를 자연어로 조회할 수 있게 한다.
- 포함 유즈 케이스:
  - WebSocket 연결(`/ws`) 및 초기 사용자 정보 교환
  - 9개 조회 도구(`get_process_definitions`, `get_process_definition`, `get_process_instances`, `get_chat_history`, `fetch_todolist_by_user_id_tool`, `fetch_todolist_by_user_id_and_status_tool`, `fetch_process_instance_list_tool`, `fetch_organization_chart_tool`, `fetch_ui_definition_tool`)
  - 실시간 음성-텍스트 양방향 스트림
- 주요 관측 계약:
  - 초기 핸드셰이크 필수 항목(`email`, `chat_room_id`, `tenant_id`, `conversation_history`)
  - 환경 변수(`OPENAI_API_KEY`, `SUPABASE_URL/KEY`)
  - 도구 실패 시 빈 결과 응답
- 제외할 구현 세부: Realtime API 프레임 처리
- 근거 유형: server/, README, deployment.yaml
- 위험 또는 열린 질문:
  - `conversation_history` 업데이트 메커니즘

### `sandboxed-execution-environment`
- 목적: MCP 클라이언트가 격리된 Kubernetes Pod 세션을 생성·관리하고, 그 내부에서 셸/Node.js 코드 실행과 파일 조작·외부 업로드를 수행할 수 있게 한다.
- 포함 유즈 케이스:
  - 세션 수명주기 도구(`create_session`, `delete_session`, `list_sessions`, `extend_session`, `get_session_status`)
  - 파일 도구(`list_files`, `create_file`, `delete_file`, `upload_file`)
  - 실행 도구(`run_shell`, `run_node`)
  - TTL 만료 자동 정리
- 주요 관측 계약:
  - 환경 변수(`POD_NAMESPACE`, `IN_CLUSTER`, `SUPABASE_URL/KEY/BUCKET`, `SUPABASE_PATH_PREFIX`)
  - 도구 결과 형식(`{"success": bool, ...}`)
  - 중복 업로드 시 자동 유니크 경로 재시도
- 제외할 구현 세부: Watcher 폴링 간격 정확한 값(설정 가능 변수만 노출)
- 근거 유형: README, src/, helm, k8s
- 위험 또는 열린 질문:
  - `ensure_dependencies` 의미

### `office-document-generation`
- 목적: MCP/REST 클라이언트가 LLM과 사내 지식(Memento)·실시간 웹 검색(Tavily)·이미지 생성(Gemini)을 활용해 HWPX/DOCX/슬라이드 문서를 생성·편집할 수 있게 한다.
- 포함 유즈 케이스:
  - MCP 도구 8종(`list_reference_documents`, `generate_hwpx`, `save_hwpx_from_html`, `edit_hwpx_page_html`, `generate_docx`, `edit_docx_page_html`, `save_docx_from_html`, `generate_slides`)
  - REST API 2종(`POST /api/edit-slide-image`, `POST /api/enhance-image`)
  - Supabase 업로드 및 결과 URL 반환
- 주요 관측 계약:
  - 환경 변수(`SUPABASE_URL/KEY`, `OPENAI_API_KEY`, `OPENROUTER_API_KEY`, `GOOGLE_API_KEY`, `MEMENTO_SERVICE_URL`, `TAVILY_API_KEY/URL`, `OFFICE_MCP_LLM_PROVIDER`)
  - 결과 응답 필수 필드(`file_url`, `html_url`, `file_name`)
  - 오류 코드(404 미지정 입력, 500 외부 LLM 실패, 502 이미지 다운로드 실패)
- 제외할 구현 세부: HTML 청크 처리 알고리즘
- 근거 유형: office_mcp/, main.py, README
- 위험 또는 열린 질문:
  - `source_chunks_json` 형식, Playwright 비전 분석 외부 노출 여부

### `mcp-server-validation`
- 목적: 사용자가 MCP 서버 설정 JSON을 제출하면 각 서버의 연결 가능성과 도구 목록을 검증해 결과를 반환하는 검증 도구를 제공한다.
- 포함 유즈 케이스:
  - 검증 요청(`POST /validate`)
  - 헬스 체크(`GET /health`)
  - 웹 UI 제공(`GET /`)
- 주요 관측 계약:
  - 요청/응답 스키마(`mcpServers`, `overall_status`, `servers`, `tools`, `connection_details`, `total_tools`, `validation_time`, `errors`)
  - stdio/streamable_http/sse 트랜스포트 지원
- 제외할 구현 세부: 내부 클라이언트 라이브러리
- 근거 유형: main.py, README, examples/
- 위험 또는 열린 질문:
  - stdio 프로세스 종료 정책

### `skill-library-lookup`
- 목적: MCP 클라이언트가 사용자 작업 설명에 기반해 적절한 스킬을 검색·열람할 수 있도록, 외부 스킬 저장소를 통합 인덱싱한 라이브러리를 제공한다.
- 포함 유즈 케이스:
  - MCP 도구 3종(`find_helpful_skills`, `read_skill_document`, `list_skills`)
  - 프론트엔드 빠른 시작(5초 이내) + 백엔드 백그라운드 로드 모델
  - 설정 파일 기반 스킬 소스 구성(`--config`, `--example-config`)
- 주요 관측 계약:
  - 결과 형식(`[{skill_id, name, description, relevance_score}]`)
  - 설정 키(`skill_sources`, `top_k`, `max_content_chars`, `models.embedding_model`)
  - 캐시 위치(`~/.cache/claude-skills-mcp/`)
- 제외할 구현 세부: 모델 로딩 순서, 벡터 라이브러리 선택
- 근경 유형: README, QUICKSTART-DOCKER.md, packages/, scripts/
- 위험 또는 열린 질문:
  - GitHub 속도 제한 도달 시 폴백, 벡터 모델 자동 업데이트 정책

### `operator-console`
- 목적: 최종 사용자와 운영자가 단일 SPA 화면을 통해 인증·프로세스 정의·인스턴스·작업·캘린더·칸반·채팅·분석·외부 폼을 사용할 수 있게 한다.
- 포함 유즈 케이스:
  - 인증 흐름(`/auth/login`, `/auth/register`, `/auth/reset-password`)
  - 프로세스/인스턴스/작업 관리 화면(`/definitions/*`, `/instancelist*`, `/todolist`, `/calendar`, `/kanban`)
  - 채팅(`/chats`, `/chat`)
  - 분석(`/analytics/*`)
  - 마크다운/슬라이드 에디터 (`/markdown-editor`, `/slide-editor`, `/present`)
  - 외부 폼(`/external-forms/:formId`, 비인증)
  - 멀티테넌트 영역(`/tenant`)
- 주요 관측 계약:
  - 인증 모델(Supabase + 선택적 Keycloak)
  - 빌드/배포 산출물(Docker 이미지 정적 호스팅)
  - 백엔드 의존(개발 프록시 기준 Memento, 워크플로우 실행 서비스, 에이전트 라우터, DeepAgents)
  - 환경 변수(`VITE_SUPABASE_URL/KEY`, `VITE_KEYCLOAK_*`)
- 제외할 구현 세부: 컴포넌트 트리, Pinia 스토어 구조
- 근거 유형: src/router, package.json, vite.config.ts, kubernetes/
- 위험 또는 열린 질문:
  - Supabase Realtime 사용 여부, 런타임 환경 변수 오버라이드 출처

### `public-marketing-site`
- 목적: 잠재 사용자가 ProcessGPT를 소개받고 마켓플레이스 콘텐츠와 연락처 폼에 접근할 수 있는 정적 랜딩 사이트를 제공한다.
- 포함 유즈 케이스:
  - 홈(`/`) 및 마켓플레이스(`/marketplace`) 페이지
  - 다국어(KO/EN) 표시
  - 연락처 폼 모달
- 주요 관측 계약:
  - 정적 사이트 배포(GitHub Pages, `agents.process-gpt.io`)
  - 인증 없음
- 제외할 구현 세부: Vue 컴포넌트 구조
- 근거 유형: src/router/index.js, public/CNAME, package.json
- 위험 또는 열린 질문:
  - 연락처 폼 백엔드 엔드포인트
  - deploy 스크립트의 `gridsome build` 참조 정합성

### `documentation-portal`
- 목적: 사용자가 ProcessGPT의 설치·튜토리얼·기능·디자인 패턴 문서를 다국어로 열람할 수 있는 정적 문서 사이트를 제공한다.
- 포함 유즈 케이스:
  - 다국어 콘텐츠(`/ko/`, `/en/`, `/jp/`, `/zh/`)
  - 시작하기/튜토리얼/세부 기능/디자인 패턴 섹션
  - GitHub Pages 또는 Netlify 배포
- 주요 관측 계약:
  - 정적 사이트 산출물(`dist/`)
  - 콘텐츠 소스(`content/**/*.md`)
  - 환경 변수(`SITE_URL`, `GA_ID`)
- 제외할 구현 세부: 빌드 파이프라인 내부
- 근거 유형: gridsome.config.js, netlify.toml, content/
- 위험 또는 열린 질문:
  - JP/ZH 콘텐츠의 외부 공시 여부 (네비게이션 주석 처리됨)

## 추적표

| 소스 범위 | 관측된 외부 행위 | 제안 스펙 폴더 | 처리 |
| --- | --- | --- | --- |
| `services/execution`, `services/completion` | BPM 워크플로우 API, 워크아이템 폴링, 채팅, 콜봇 | `process-workflow-execution` | 포함(통합) |
| 모든 에이전트 워커 공통 | todolist 작업 수명주기·이벤트·드래프트/최종 산출 | `agent-task-protocol` | 포함(횡단) |
| `services/agent-sdk` | 폴링 서버·시뮬레이터 공개 라이브러리 | `agent-sdk` | 포함 |
| `services/agent-utils` | 에이전트 도구·메모리·규칙 라이브러리 | `agent-toolkit` | 포함 |
| `services/agent-feedback` | 에이전트 학습/피드백 처리 | `agent-feedback-learning` | 포함 |
| `services/memento` | 문서 처리·검색·RAG·Drive | `knowledge-memory` | 포함 |
| `services/a2a-orch` | A2A 외부 에이전트 브리지 | `a2a-agent-bridge` | 포함 |
| `services/autonomous-execution` | WebSocket 슬라이드 생성 | `presentation-streaming` | 포함 |
| `services/crewai-action` | CrewAI 단일 작업 워커 | `crewai-action-runner` | 포함 |
| `services/crewai-deep-research` | CrewAI 심층 연구 워커 | `crewai-deep-research-runner` | 포함 |
| `services/openai-deep-research` | OpenAI 웹 검색 연구 워커 | `openai-deep-research-runner` | 포함 |
| `services/deep-research` | 대화형 보고서 API | `conversational-research-assistant` | 포함 |
| `services/langchain-react` | ReAct 코드 실행 에이전트 | `react-coding-agent` | 포함 |
| `services/generic-agent` | 멀티 에이전트 CLI | `generic-multi-agent-cli` | 포함 |
| `services/bpmn-extractor` | PDF→BPMN/DMN 변환 | `bpmn-document-extraction` | 포함 |
| `services/react-voice-agent` | 실시간 음성 비서 | `voice-process-assistant` | 포함 |
| `services/computer-use` | K8s Pod MCP 세션 | `sandboxed-execution-environment` | 포함 |
| `services/office-mcp` | 문서 생성 MCP | `office-document-generation` | 포함 |
| `services/mcp-validator` | MCP 검증 도구 | `mcp-server-validation` | 포함 |
| `services/claude-skills` | 스킬 검색 라이브러리 | `skill-library-lookup` | 포함 |
| `services/frontend` | 운영자/사용자 SPA | `operator-console` | 포함 |
| `services/agents.github.io` | 마케팅/마켓플레이스 정적 사이트 | `public-marketing-site` | 포함 |
| `services/docs` | 문서 포털 정적 사이트 | `documentation-portal` | 포함 |
| `services/*-service.yaml` | k8s Service 매니페스트 | (없음) | 제외(인프라 산출물) |

## 진행 체크리스트
- [x] 모든 입력 폴더가 확인되었다.
- [x] 스펙 폴더가 구현 구조가 아니라 능력 기준으로 나뉘었다. (서비스 단위 매핑이 보이는 항목들은 각 서비스가 외부에서 독립적으로 관측 가능한 능력 단위라서 그대로 유지)
- [x] 각 스펙 폴더의 유즈 케이스가 정의되었다.
- [x] 불확실한 행위가 요구사항으로 단정되지 않고 열린 질문으로 남았다. (각 스펙 항목의 "위험 또는 열린 질문" 참조)
- [x] `openspec/specs` 작성 전에 이 계획이 저장되었다.
