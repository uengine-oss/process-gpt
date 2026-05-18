# Generic Multi-Agent CLI Specification

## Purpose
운영자 또는 개발자가 자연어 목표 한 줄을 입력하면, 설정 파일에 정의된 다중 에이전트와 MCP 도구가 협력하여 결과 텍스트를 표준 출력으로 반환하는 대화형 CLI 진입점을 제공한다. 누적된 작업 기록은 외부 메모리 저장소에 반영되어 후속 실행에서 활용된다.

## Requirements

### Requirement: 자연어 목표 입력
The system SHALL accept a user goal from the CLI and SHALL substitute a default goal when no input is provided.

#### Scenario: 명시적 목표 입력
- **WHEN** 사용자가 CLI에 자연어 목표를 입력한다
- **THEN** 시스템은 그 목표를 기준으로 에이전트들을 실행한다

#### Scenario: 기본 목표 사용
- **WHEN** 사용자가 목표를 비워 둔다
- **THEN** 시스템은 사전 정의된 기본 목표로 실행을 진행한다

### Requirement: 설정 기반 에이전트 구성
The system SHALL load agent definitions from `config/agents.yaml` and MCP tool configuration from `config/mcp.json` so operators can declare roles, goals, and tool bindings without code changes.

#### Scenario: 설정 파일 로드
- **GIVEN** `config/agents.yaml`에 `role`, `goal`, `backstory` 등의 에이전트 정의가 있다
- **WHEN** 시스템이 시작된다
- **THEN** 정의된 에이전트들이 인스턴스화되고 각 에이전트가 사용하는 MCP 도구가 함께 로드된다

#### Scenario: MCP 도구 부재
- **GIVEN** 설정에서 어떤 에이전트가 MCP 도구를 사용하지 않는다
- **WHEN** 시스템이 그 에이전트를 실행한다
- **THEN** 에이전트는 LLM만으로 작업을 수행한다

### Requirement: 결과 출력
The system SHALL print the final result to standard output once the multi-agent run completes.

#### Scenario: 실행 결과 출력
- **WHEN** 에이전트 체인이 종료된다
- **THEN** 최종 결과 텍스트가 표준 출력에 기록된다

### Requirement: 외부 메모리 통합
The system SHALL integrate with a long-term memory store so that agent knowledge can accumulate across runs.

#### Scenario: 메모리 갱신
- **GIVEN** 메모리 통합이 사용 가능하다
- **WHEN** 에이전트 체인이 진행된다
- **THEN** 학습 가능한 항목이 외부 메모리에 반영된다

#### Scenario: 메모리 서비스 미응답
- **WHEN** 메모리 저장소가 응답하지 않는다
- **THEN** 시스템은 메모리 갱신을 건너뛰고 작업을 계속한다

### Requirement: 정상 종료 시그널 처리
The system SHALL exit gracefully when the user interrupts the CLI session.

#### Scenario: 사용자 인터럽트
- **WHEN** 사용자가 `Ctrl+C` 또는 `Ctrl+D`를 입력한다
- **THEN** 시스템은 정상 종료한다

### Requirement: 환경 변수 계약
The system SHALL accept configuration via environment variables including `OPENAI_API_KEY` (required) and optional `SERPER_API_KEY`, `BROWSERLESS_API_KEY`, `PERPLEXITY_API_KEY`, `MEM_ZERO_API_KEY`, `PERPLEXITY_MODEL`.

#### Scenario: 필수 자격 증명 부재
- **GIVEN** `OPENAI_API_KEY`가 비어 있다
- **WHEN** 시스템이 시작된다
- **THEN** 시스템은 LLM 호출 단계에서 실패한다
