# CrewAI Deep Research Runner Specification

## Purpose
ProcessGPT 작업 큐에서 `agent_orch='crewai-deep-research'` 작업을 처리하기 위한 워커로서, CrewAI 멀티 에이전트와 MCP 도구를 활용한 심층 연구를 수행하고, 드래프트/최종 산출을 표준 위치에 저장한다. 또한 사용자 피드백을 통한 재실행 흐름을 지원한다.

## Requirements

### Requirement: 자신의 작업 폴링과 클레임
The system SHALL poll for tasks targeted at `agent_orch='crewai-deep-research'` approximately every seven seconds, using a dedicated RPC that selects only items eligible for processing.

#### Scenario: 정상 작업 클레임
- **GIVEN** `todolist`에 `status='IN_PROGRESS'`, `agent_orch='crewai-deep-research'`, `agent_mode in ('DRAFT','COMPLETE')`, `draft_status IS NULL` 인 행이 존재한다
- **WHEN** 워커가 RPC `crewai_deep_fetch_pending_task` 또는 그 테넌트 변형 `_dev`를 호출한다
- **THEN** 시스템은 그 행 하나를 단독으로 반환하며 `draft_status='STARTED'`, `consumer='<pod_id>'`로 갱신한다

#### Scenario: 피드백 재실행 진입
- **GIVEN** 어떤 작업이 사용자 피드백에 의해 `draft_status='FB_REQUESTED'`로 표시되어 있다
- **WHEN** 워커가 폴링한다
- **THEN** 해당 행도 다시 반환되어 재처리에 들어간다

### Requirement: 중간 산출과 최종 산출 분리 저장
The system SHALL save intermediate drafts and final outputs using the standard save RPC, distinguishing them via a `final` flag.

#### Scenario: 드래프트 저장
- **WHEN** 워커가 `save_task_result(todo_id, payload, final=false)`를 호출한다
- **THEN** `draft` 필드가 갱신되고 상태는 아직 완료로 표시되지 않는다

#### Scenario: 최종 저장과 모드별 위치
- **WHEN** 워커가 `save_task_result(todo_id, payload, final=true)`를 호출한다
- **THEN** `agent_mode='COMPLETE'`이면 `output`과 `status='SUBMITTED'`, `draft_status='COMPLETED'`로 전이되고, `agent_mode='DRAFT'`이면 `draft`와 `draft_status='COMPLETED'`로 전이된다

### Requirement: 처리 결과의 외부 가시화
The system SHALL ensure that observers monitoring `todolist` can see the worker's lifecycle through column transitions.

#### Scenario: 컬럼 전이
- **WHEN** 워커가 한 작업을 시작·완료한다
- **THEN** 외부 관측자에게 `draft_status`는 `NULL → STARTED → COMPLETED`, `status`는 처리 모드에 따라 `IN_PROGRESS → SUBMITTED/DONE`, `consumer`는 `NULL → '<pod_id>' → NULL`로 보인다

### Requirement: 외부 도구 및 메모리 활용
The system SHALL leverage external MCP-served tools and a long-term memory store during execution so that operators can observe their inclusion in agent runs.

#### Scenario: 외부 도구 사용
- **GIVEN** 작업 컨텍스트가 MCP 도구를 명시한다
- **WHEN** 워커가 크루 실행을 진행한다
- **THEN** 시스템은 해당 도구를 통해 외부 검색/연산을 수행한다

### Requirement: 환경 변수와 자격 증명
The system SHALL require `OPENAI_API_KEY` and `SUPABASE_URL`, and SHALL optionally use `SUPABASE_SERVICE_ROLE_KEY` for elevated operations.

#### Scenario: 자격 증명 부재 시 실패
- **GIVEN** `SUPABASE_URL`이 비어 있다
- **WHEN** 워커가 기동된다
- **THEN** 워커는 즉시 실패한다

### Requirement: 폴링 지속성과 안전 실패
The system SHALL keep polling even when individual jobs raise exceptions, and SHALL not silently mutate task rows on failure beyond what is required.

#### Scenario: 단일 작업 오류 후 폴링 지속
- **WHEN** 한 작업의 처리가 예외로 종료된다
- **THEN** 시스템은 오류를 로깅하고 다음 폴링 주기에 새로운 작업을 시도한다
