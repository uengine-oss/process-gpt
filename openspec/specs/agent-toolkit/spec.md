# Agent Toolkit Specification

## Purpose
ProcessGPT 에이전트 구현자가 외부 도구·메모리·의사결정 규칙·사용자 질의·이벤트 로깅을 안전하고 일관되게 사용할 수 있도록, 파이썬 라이브러리 형태의 도구 모음과 컨텍스트 API를 제공한다. 사용자가 의존하는 공개 import 표면, 환경 변수, 데이터베이스 위치는 안정 계약이다.

## Requirements

### Requirement: 패키지 배포와 설치
The system SHALL be distributed as a Python package installable via PyPI under the name `process-gpt-agent-utils`, requiring Python 3.10 or higher.

#### Scenario: 표준 설치
- **WHEN** 사용자가 `pip install process-gpt-agent-utils` 를 실행한다
- **THEN** 패키지가 설치되고 공개 도구를 즉시 import할 수 있다

### Requirement: 공개 도구 import 표면
The system SHALL expose at the package top level the following importable names: `SafeToolLoader`, `Mem0Tool`, `MementoTool`, `HumanQueryTool`, `DMNRuleTool`, `DeterministicCodeTool`, `CrewAIEventLogger`, `CrewConfigManager`, `initialize_db`, `fetch_human_response`, `save_notification`, `save_event`, `set_context`, `reset_context`, `get_context_snapshot`.

#### Scenario: 공개 이름 import
- **WHEN** 사용자가 `from processgpt_agent_utils import SafeToolLoader, Mem0Tool, DMNRuleTool` 등을 수행한다
- **THEN** 위 모든 이름이 import 가능하다

### Requirement: MCP 도구 안전 로딩
The system SHALL load CrewAI-compatible tools dynamically by name, accepting an MCP server configuration and applying a name-based allow list, so that callers can request only the tools they explicitly need.

#### Scenario: 도구 이름 목록으로 로드
- **GIVEN** 사용자가 `SafeToolLoader`에 `tenant_id`, `user_id`, `agent_name`, `mcp_config`를 제공한다
- **WHEN** 사용자가 `create_tools_from_names(["mem0", "memento", "human_asked", "github"])`을 호출한다
- **THEN** 로더는 요청된 이름에 해당하는 CrewAI 호환 도구만 생성해 반환한다

#### Scenario: MCP 패키지 워밍업
- **GIVEN** MCP 설정이 npx 기반 서버 명령을 포함한다
- **WHEN** 로더가 도구를 생성한다
- **THEN** 로더는 해당 MCP 서버 어댑터를 초기화하고, 필요한 경우 패키지 워밍업을 수행할 수 있다

### Requirement: 메모리·문서·사용자 질의 도구
The system SHALL provide tools that wrap personal-knowledge memory (`Mem0Tool`), enterprise document search (`MementoTool`), and user-approval/extra-information requests (`HumanQueryTool`), each callable as a CrewAI BaseTool.

#### Scenario: 메모리 검색
- **WHEN** 사용자 또는 에이전트가 `Mem0Tool`을 호출한다
- **THEN** 호출자에게 매핑된 개인지식 결과가 반환된다

#### Scenario: 사내 문서 검색
- **WHEN** 사용자 또는 에이전트가 `MementoTool`을 호출한다
- **THEN** Memento 서비스에서 조회한 사내 문서 결과가 반환된다

#### Scenario: 사용자 질의
- **WHEN** 사용자 또는 에이전트가 `HumanQueryTool`을 호출한다
- **THEN** 시스템은 사용자 응답을 비동기적으로 받기 위한 알림을 발행하고 응답이 도착하면 `fetch_human_response`로 회수할 수 있다

### Requirement: DMN 규칙 도구
The system SHALL load DMN 1.3 rules owned by the calling user from the `proc_def` table (where `type='dmn'`), parse the rule XML, and evaluate a free-form query against those rules to return a decision result.

#### Scenario: 규칙 평가
- **GIVEN** `proc_def`에 호출자의 `user_id`로 등록된 DMN 규칙이 존재한다
- **WHEN** 사용자가 `DMNRuleTool`을 인스턴스화하고 자연어 질의로 호출한다
- **THEN** 도구는 규칙의 입력/출력 변수와 결정 테이블을 해석하여 일치하는 규칙의 결과를 반환한다

### Requirement: 결정론적 코드 실행
The system SHALL provide a tool that runs deterministic code blocks so agents can perform reproducible transformations.

#### Scenario: 코드 실행 결과 반환
- **WHEN** 에이전트가 `DeterministicCodeTool`로 코드 블록을 실행한다
- **THEN** 실행 결과가 도구 응답으로 반환된다

### Requirement: 실행 컨텍스트 변수 API
The system SHALL provide `set_context`, `reset_context`, and `get_context_snapshot` so that downstream calls (event logging, tools) can read task identifiers and the calling user's email without explicit argument passing.

#### Scenario: 컨텍스트 설정과 스냅샷
- **WHEN** 사용자가 `set_context(task_id=..., proc_inst_id=..., users_email=..., crew_type=...)`을 호출한 뒤 `get_context_snapshot()`을 호출한다
- **THEN** 스냅샷에는 마지막으로 설정된 값들이 dict로 포함된다

#### Scenario: 컨텍스트 초기화
- **WHEN** 사용자가 `reset_context()`를 호출한다
- **THEN** 모든 컨텍스트 변수가 초기화된다

### Requirement: CrewAI 이벤트 자동 기록
The system SHALL listen to CrewAI runtime events and persist them to the platform's `events` table with appropriate task and process instance identifiers drawn from the active execution context.

#### Scenario: 작업 시작/완료 이벤트 기록
- **GIVEN** 에이전트가 `CrewAIEventLogger`를 활성화한 상태이다
- **WHEN** CrewAI가 Task 시작/완료, Tool 사용 시작/완료 이벤트를 발행한다
- **THEN** 각 이벤트는 JSON 정제 후 `events` 테이블에 저장되며, 실패 시 3회 재시도 + 지수 백오프를 따른다

### Requirement: 알림·이벤트·사용자 응답 저장 유틸
The system SHALL expose public utility functions (`initialize_db`, `save_notification`, `save_event`, `fetch_human_response`) that perform standard platform-side reads/writes for agent integration.

#### Scenario: 알림 저장
- **WHEN** 에이전트가 `save_notification(...)`을 호출한다
- **THEN** `notifications` 테이블에 알림 행이 추가된다

#### Scenario: 사용자 응답 회수
- **GIVEN** 이전에 사용자 질의가 발행되어 사용자가 응답했다
- **WHEN** 에이전트가 `fetch_human_response(...)`을 호출한다
- **THEN** 해당 응답 본문이 반환된다

### Requirement: 환경 변수와 데이터베이스 자격 증명
The system SHALL accept Supabase credentials and direct PostgreSQL credentials via environment variables so that the same library code works in both managed and self-hosted database environments.

#### Scenario: Supabase 자격 증명
- **GIVEN** `SUPABASE_URL`(또는 `SUPABASE_KEY_URL`)과 `SUPABASE_KEY`(또는 `SUPABASE_ANON_KEY`)가 설정되어 있다
- **WHEN** 라이브러리가 데이터베이스 호출을 수행한다
- **THEN** 설정된 자격 증명을 사용해 정상적으로 접근한다

#### Scenario: 벡터 DB 자격 증명
- **GIVEN** `DB_USER`, `DB_PASSWORD`, `DB_HOST`, `DB_PORT`, `DB_NAME`이 설정되어 있다
- **WHEN** 라이브러리가 벡터 저장소에 접근한다
- **THEN** 해당 자격 증명을 사용해 직접 PostgreSQL에 연결한다

#### Scenario: 비프로덕션 .env 자동 로드
- **GIVEN** `ENV`가 `production`이 아니다
- **WHEN** 라이브러리가 초기화된다
- **THEN** 작업 디렉터리의 `.env` 파일이 자동으로 적재된다
