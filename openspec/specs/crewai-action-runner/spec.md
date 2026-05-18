# CrewAI Action Runner Specification

## Purpose
ProcessGPT 작업 큐에서 자신을 대상으로 하는 작업을 클레임해 CrewAI 기반 다중 에이전트로 처리하고, 폼/액션 산출을 표준 todolist 위치에 반영하는 워커 서비스를 제공한다. 외부 호출자는 큐를 통해 작업을 의뢰하고 표준 산출 필드를 통해 결과를 확인한다.

## Requirements

### Requirement: 헬스 체크
The system SHALL expose a liveness endpoint suitable for orchestrator probes.

#### Scenario: 헬스 응답
- **WHEN** 운영자가 `GET /health`를 호출한다
- **THEN** 시스템은 `{"status": "ok"}` 본문으로 응답한다

### Requirement: 자신의 작업 폴링과 클레임
The system SHALL poll the platform task queue approximately every five seconds for items targeted at this worker's `agent_orch` identifier and SHALL claim each item atomically.

#### Scenario: 작업 클레임
- **GIVEN** 큐에 자신의 `agent_orch` 작업이 존재한다
- **WHEN** 폴링 주기가 도래한다
- **THEN** 워커는 하나의 작업을 클레임하고 `draft_status=STARTED`로 표시한다

### Requirement: 도구 안전 정책
The system SHALL load tools through an allow-list policy so that an agent run can only access tools explicitly granted.

#### Scenario: 허용된 도구만 사용
- **GIVEN** 도구 허용 목록이 작업 컨텍스트에 정의되어 있다
- **WHEN** 워커가 도구를 로드한다
- **THEN** 허용 목록에 없는 이름은 로드되지 않는다

#### Scenario: 도구 연결 실패
- **WHEN** 허용 목록의 도구 중 일부가 외부 시스템 부재로 연결되지 않는다
- **THEN** 시스템은 경고를 기록하고 가능한 도구만으로 작업을 계속한다

### Requirement: 표준 실행 이벤트 발행
The system SHALL publish lifecycle events that allow external observers to track progress, including agent and tool sub-events.

#### Scenario: 시작/완료 이벤트
- **WHEN** 워커가 작업을 시작하고 완료한다
- **THEN** 각각 `working/task_started`와 `working/completed/task_completed` 이벤트가 발행되며, 최종 산출에 대해 `TaskArtifactUpdateEvent`가 발행된다

#### Scenario: 단계별 세부 이벤트
- **WHEN** 크루의 개별 에이전트 또는 도구가 시작/종료된다
- **THEN** 각 단계에 대응하는 이벤트가 발행된다

### Requirement: 결과 저장과 폼 데이터 변환
The system SHALL save final outputs through the standard task save flow and SHALL transform crew outputs into form-shaped JSON when the work item declares a form.

#### Scenario: 표준 산출 저장
- **WHEN** 작업이 완료된다
- **THEN** 산출은 표준 저장 절차를 통해 `output`(또는 `draft`) 필드에 기록되고, `draft_status=COMPLETED`, `consumer=NULL`, `status=SUBMITTED`로 전이된다

#### Scenario: 폼 변환
- **GIVEN** 작업이 폼 정의를 포함한다
- **WHEN** 워커가 결과를 저장한다
- **THEN** 결과는 폼 정의에 맞춘 JSON으로 변환되어 저장된다

### Requirement: LLM 프로바이더 구성
The system SHALL allow operators to route LLM calls through an LLM proxy and SHALL fall back to OpenAI when the proxy is not configured.

#### Scenario: 프록시 사용
- **GIVEN** `LLM_PROXY_URL`과 `LLM_PROXY_API_KEY`가 설정되어 있다
- **WHEN** LLM 호출이 필요하다
- **THEN** 프록시로 호출한다

#### Scenario: 폴백
- **GIVEN** 프록시가 비어 있고 `OPENAI_API_KEY`가 설정되어 있다
- **WHEN** LLM 호출이 필요하다
- **THEN** OpenAI를 직접 호출한다

### Requirement: 환경 변수 계약
The system SHALL accept configuration via environment variables including `LLM_MODEL` (default `gpt-4o`), `LLM_PROXY_URL`, `LLM_PROXY_API_KEY`, `OPENAI_API_KEY`, `LANGSMITH_API_KEY`, `LANGSMITH_PROJECT`, `LANGSMITH_ENDPOINT`, `SUPABASE_URL`, `SUPABASE_KEY`.

#### Scenario: 추적 활성화
- **GIVEN** `LANGSMITH_*` 변수들이 설정된다
- **WHEN** 워커가 동작한다
- **THEN** 추적이 LangSmith로 전송된다

### Requirement: 실패 복원
The system SHALL retry transient failures using exponential backoff so that flaky external dependencies do not abort the worker.

#### Scenario: 일시적 외부 실패
- **WHEN** LLM 호출 또는 데이터베이스 갱신이 일시적으로 실패한다
- **THEN** 시스템은 지수 백오프로 재시도하고 최대 시도 이후에도 실패 시 작업 단위 오류로 보고한다
