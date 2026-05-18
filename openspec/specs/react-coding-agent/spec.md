# ReAct Coding Agent Specification

## Purpose
사용자가 자연어로 코드 실행 환경의 파일과 패키지를 조작하고 Python 코드를 실행할 수 있도록, MCP 코드 인터프리터와 결합된 ReAct 에이전트 인터페이스를 제공한다. 운영자는 헬스 체크로 가용성을 확인하고, 최종 사용자는 CLI나 API를 통해 도구를 호출할 수 있다.

## Requirements

### Requirement: 헬스 체크
The system SHALL expose a liveness endpoint suitable for orchestrator probes.

#### Scenario: 헬스 응답
- **WHEN** 운영자가 `GET /health`를 호출한다
- **THEN** 시스템은 정상 상태 응답을 반환한다

### Requirement: 자연어 입력 진입점
The system SHALL accept user instructions in natural language via an interactive CLI session that interprets the input as goals for the underlying ReAct agent.

#### Scenario: CLI 대화 입력
- **WHEN** 사용자가 CLI에서 자연어 명령을 입력한다
- **THEN** 에이전트는 적절한 도구를 선택해 실행하고 결과를 반환한다

### Requirement: 노출되는 코드/파일 도구 집합
The system SHALL expose exactly the following toolset to the agent: `read_file`, `write_file`, `list_directory`, `list_python_environments`, `list_installed_packages`, `run_python_code`, `install_package`, `write_python_file`, `run_python_file`.

#### Scenario: 도구 호출 결과
- **WHEN** 에이전트가 위 도구 중 하나를 호출한다
- **THEN** 도구는 자신의 책임(파일 조작, 환경 조회, 패키지 설치, 코드 실행)에 따라 결과 또는 오류 메시지를 반환한다

### Requirement: 시스템 접근 제한
The system SHALL run the underlying MCP code interpreter with system access disabled by default and SHALL surface this constraint to callers.

#### Scenario: 시스템 접근 기본 비활성
- **GIVEN** `MCP_ALLOW_SYSTEM_ACCESS`가 `0`이다
- **WHEN** 에이전트가 시스템 자원에 접근하려는 도구를 호출한다
- **THEN** MCP 인터프리터는 접근을 차단한다

### Requirement: 외부 LLM 자격 증명
The system SHALL require `OPENAI_API_KEY` and SHALL surface a failure when calling the LLM without one.

#### Scenario: 자격 증명 부재
- **GIVEN** `OPENAI_API_KEY`가 비어 있다
- **WHEN** 에이전트가 LLM을 호출한다
- **THEN** 시스템은 오류를 보고한다

### Requirement: 의존 MCP 서버의 초기화 실패 보고
The system SHALL fail fast at startup when the underlying MCP server cannot be initialized so that operators know the agent is unusable.

#### Scenario: MCP 서버 부재
- **GIVEN** 코드 인터프리터 MCP 서버가 기동되지 않는다
- **WHEN** 에이전트 프로세스가 시작된다
- **THEN** 시스템은 초기화에 실패하고 오류를 보고한다

### Requirement: 도구 실행 실패의 대안 시도
The system SHALL allow the agent to attempt alternative tools when a tool invocation fails so that user-visible failures are minimized.

#### Scenario: 일부 도구 실패 시 대안
- **WHEN** 한 도구의 실행이 실패한다
- **THEN** 에이전트는 같은 사용자 의도를 만족하는 다른 도구를 시도하거나 실패 사유를 보고할 수 있다
