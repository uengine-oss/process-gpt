# Agent Feedback Learning Specification

## Purpose
운영 중 발생한 사용자 피드백과 신규 에이전트의 초기 지식 셋팅을 처리하여, 메모리(MEMORY), 의사결정 규칙(DMN_RULE), 절차 스킬(SKILL) 세 종류의 지식 저장소를 자동으로 갱신한다. 외부 관찰자(운영자, 학습된 에이전트 호출자)는 셋팅 호출과 피드백 큐를 통해 어떤 학습이 진행 중이며 어떤 결과로 끝났는지를 확인할 수 있다.

## Requirements

### Requirement: 초기 지식 셋팅 API
The system SHALL accept an HTTP request to set up an agent's initial knowledge from goal and persona inputs and SHALL return the resulting processing summary.

#### Scenario: 정상 셋팅 요청
- **WHEN** 클라이언트가 `POST /setup-agent-knowledge`로 `agent_id`와 선택적 `goal`/`persona`를 전송한다
- **THEN** 시스템은 처리 결과, 중간 단계, 사용된 도구 정보를 응답 본문에 포함하여 반환한다

#### Scenario: 필수 입력 누락
- **WHEN** 요청 본문에 `agent_id` 또는 `goal`이 누락된다
- **THEN** 시스템은 각각 404 또는 400으로 거부한다

### Requirement: 셋팅 상태 추적
The system SHALL persist the lifecycle of every initial-knowledge setup so that operators can observe `STARTED → DONE/FAILED` transitions.

#### Scenario: 셋팅 진행과 결과
- **GIVEN** 셋팅 요청이 접수되었다
- **WHEN** 처리가 시작/종료된다
- **THEN** `agent_knowledge_setup_log`에 상태 행이 생성되고, 진행에 따라 `STARTED → DONE` 또는 `STARTED → FAILED`로 갱신된다

### Requirement: 피드백 큐 처리
The system SHALL continuously poll a feedback queue (`agent_feedback_tasks`) and process each item using a ReAct reasoning loop that emits committed knowledge to MEMORY, DMN_RULE, and SKILL stores.

#### Scenario: 큐 폴링과 처리
- **GIVEN** `agent_feedback_tasks`에 처리 대기 항목이 존재한다
- **WHEN** 서비스가 약 7초 주기의 폴링을 실행한다
- **THEN** 시스템은 항목 하나를 클레임하여 ReAct 절차로 분석하고, 결과로 도출된 지식을 MEMORY/DMN_RULE/SKILL 저장소에 반영한다
- **AND** 처리가 완료되면 상태가 `IN_PROGRESS → COMPLETED/FAILED`로 전이된다

#### Scenario: 병합 모드
- **GIVEN** 동일 키의 기존 지식이 존재한다
- **WHEN** 시스템이 피드백을 반영한다
- **THEN** 시스템은 `REPLACE`, `EXTEND`, `REFINE` 중 호출자가 지정한 또는 기본 정책에 따른 모드로 병합한다

### Requirement: 지식 저장 위치 계약
The system SHALL store knowledge in well-defined locations: MEMORY in mem0-backed storage, DMN_RULE in `proc_def`, SKILL in an MCP server endpoint that exposes CRUD for skill documents.

#### Scenario: 메모리 저장
- **WHEN** 시스템이 MEMORY 지식을 커밋한다
- **THEN** mem0가 받는 페이로드는 호출자 식별자, 본문, 메타데이터를 포함한다

#### Scenario: DMN 규칙 저장
- **WHEN** 시스템이 DMN_RULE 지식을 커밋한다
- **THEN** `proc_def`에 `type='dmn'` 행으로 저장된다

#### Scenario: 스킬 저장
- **GIVEN** `MCP_SERVER_URL`과 `MCP_SERVER_NAME`이 구성되어 있다
- **WHEN** 시스템이 SKILL 지식을 커밋한다
- **THEN** 시스템은 해당 MCP 서버에 스킬 CRUD 호출을 수행한다

### Requirement: 외부 LLM 구성
The system SHALL allow operators to direct LLM calls through an LLM proxy (`LLM_PROXY_URL`, `LLM_PROXY_API_KEY`) with fallback to OpenAI (`OPENAI_API_KEY`), and SHALL allow a separate translator model for Korean→English translation.

#### Scenario: 프록시 우선
- **GIVEN** `LLM_PROXY_URL`이 설정되어 있다
- **WHEN** 시스템이 LLM을 호출한다
- **THEN** 프록시 엔드포인트로 호출한다

#### Scenario: 별도 번역 모델
- **GIVEN** `LLM_TRANSLATOR_MODEL`이 설정되어 있다 (기본 `gpt-4o-mini`)
- **WHEN** 시스템이 번역이 필요한 단계를 수행한다
- **THEN** 일반 추론 모델(`LLM_MODEL`, 기본 `gpt-4o`)이 아닌 번역 모델을 사용한다

### Requirement: 실행 환경 변수
The system SHALL accept configuration via environment variables including `SUPABASE_URL`, `SUPABASE_KEY`, direct PostgreSQL variables for mem0, `MCP_SERVER_URL`, `MCP_SERVER_NAME`, `USE_SKILL_CREATOR_WORKFLOW`, `COMPUTER_USE_MCP_URL`, `PORT`, and `DEBUG`.

#### Scenario: 포트 설정
- **GIVEN** `PORT` 환경 변수가 설정되어 있다 (기본 `6789`)
- **WHEN** 서버를 기동한다
- **THEN** 서버는 해당 포트에서 수신한다

#### Scenario: 스킬 생성 워크플로우 토글
- **GIVEN** `USE_SKILL_CREATOR_WORKFLOW`가 활성화되어 있다
- **WHEN** 시스템이 SKILL 지식을 처리한다
- **THEN** 스킬 생성 워크플로우 경로가 호출된다

### Requirement: 오류 응답 정책
The system SHALL return predictable HTTP status codes for client-visible failures.

#### Scenario: 식별자 부재 / 입력 누락 / 외부 의존 실패
- **WHEN** 요청 대상 `agent_id`가 존재하지 않거나, 필수 `goal`이 누락되거나, ReAct 추론/MCP 호출/데이터베이스가 실패한다
- **THEN** 시스템은 각각 404, 400, 500으로 응답한다
