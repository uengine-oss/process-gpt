# Agent SDK Specification

## Purpose
ProcessGPT 플랫폼 외부의 파이썬 개발자가 새로운 에이전트 워커를 직접 구현·배포할 수 있도록, 작업 폴링 서버·요청 컨텍스트·이벤트 큐·시뮬레이션 도구를 패키지화한 공개 라이브러리의 표면을 제공한다. SDK 사용자가 의존하는 클래스 이름, 시뮬레이터 출력, 환경 변수, CLI 옵션은 후속 릴리스에서도 호환 보장 대상이다.

## Requirements

### Requirement: 패키지 배포와 설치
The system SHALL be distributed as a Python package installable via PyPI, and SHALL support Python 3.10 or higher.

#### Scenario: 표준 설치
- **WHEN** 사용자가 `pip install process-gpt-agent-sdk` 를 실행한다
- **THEN** 패키지가 설치되고 공개 import 표면을 통해 즉시 사용 가능하다

### Requirement: 공개 import 표면 안정성
The system SHALL expose a documented public surface that includes `ProcessGPTAgentServer`, `ProcessGPTRequestContext`, `ProcessGPTEventQueue`, `ProcessGPTAgentSimulator`, `SimulatorRequestContext`, and `SimulatorEventQueue`, all importable from the package top level.

#### Scenario: 공개 클래스 import
- **WHEN** 사용자가 `from processgpt_agent_sdk import ProcessGPTAgentServer, ProcessGPTAgentSimulator`를 수행한다
- **THEN** 두 클래스 모두 import 가능하다

### Requirement: 폴링 기반 에이전트 서버
The system SHALL provide a server class that, when started, polls the platform task queue at a configurable interval and dispatches each claimed work item to a user-provided executor while wiring the request context and event queue.

#### Scenario: 워커 등록 후 폴링 실행
- **GIVEN** 사용자가 `ProcessGPTAgentServer`에 자신의 실행기와 `agent_orch` 식별자를 구성한다
- **WHEN** 서버를 실행한다
- **THEN** 서버는 설정된 주기로 작업 큐를 폴링하고, 클레임된 작업마다 실행기에 컨텍스트/이벤트 큐 한 쌍을 전달한다

#### Scenario: 취소 요청 감시
- **GIVEN** 작업이 실행 중이다
- **WHEN** 외부에서 해당 작업에 대한 취소 신호가 발생한다
- **THEN** 서버는 짧은 주기로 취소 여부를 검사하고 실행기에게 취소를 통지할 수 있다

### Requirement: 시뮬레이터 표준 출력 이벤트
The system SHALL provide a simulator that runs without database connectivity and emits a stable set of lifecycle events to standard output, each containing at least a task identifier, a process instance identifier, an event type, and an ISO 8601 timestamp.

#### Scenario: 시뮬레이션 실행과 이벤트 방출
- **WHEN** 사용자가 `python simulate_standalone.py "<prompt>" --steps 5 --delay 1.0` 같은 명령을 실행한다
- **THEN** 표준 출력에는 `task_started`, `progress`, `output`, `done` 중 시나리오에 맞는 이벤트들이 순서대로 출력된다
- **AND** 비정상 흐름에서는 `cancelled` 또는 `error` 이벤트가 방출되고, 정상 종료 시 `queue_closed`가 발생한다
- **AND** 모든 이벤트는 `task_id`, `proc_inst_id`, ISO 8601 형식의 타임스탬프 필드를 포함한다

#### Scenario: 데이터베이스 없이 동작
- **GIVEN** Supabase 환경 변수가 설정되어 있지 않다
- **WHEN** 사용자가 시뮬레이터를 실행한다
- **THEN** 시뮬레이터는 외부 연결 없이 진행 이벤트를 생성한다

### Requirement: 시뮬레이터 CLI 옵션
The system SHALL provide CLI flags on the simulator that allow callers to configure the agent identifier, activity name, user/tenant identifiers, tool list, feedback content, total step count, inter-step delay, and verbose logging.

#### Scenario: CLI 옵션 사용
- **WHEN** 사용자가 `--agent-orch`, `--activity-name`, `--user-id`, `--tenant-id`, `--tool`, `--feedback`, `--steps`, `--delay`, `--verbose` 등의 옵션과 함께 시뮬레이터를 실행한다
- **THEN** 시뮬레이터는 해당 옵션을 적용한 시나리오를 실행한다

### Requirement: 작업 큐 RPC 계약
The system SHALL ship database RPC definitions that the server uses for task claim, completion query, and result save; these RPC names and semantics SHALL be considered part of the public contract.

#### Scenario: 클레임/조회/저장 RPC 호출 가능
- **WHEN** 운영자가 SDK가 동작할 데이터베이스 환경에 SDK 제공 RPC 정의(`fetch_pending_task`, `fetch_pending_task_dev`, `fetch_done_data`, `save_task_result`)를 적용한다
- **THEN** 서버는 이들 RPC를 통해 표준 워크플로우(클레임, 완료 데이터 조회, 결과 저장)를 수행할 수 있다

#### Scenario: 익명 역할 실행 가능
- **GIVEN** RPC가 anon 역할에 EXECUTE 권한이 부여된 상태로 배포된다
- **WHEN** Supabase anon 키를 가진 클라이언트가 RPC를 호출한다
- **THEN** 호출은 허용된다

### Requirement: 환경 변수와 로깅 제어
The system SHALL accept Supabase credentials via environment variables and SHALL allow operators to control logging verbosity through additional variables.

#### Scenario: Supabase 자격 증명 구성
- **GIVEN** 환경 변수 `SUPABASE_URL`(또는 `SUPABASE_KEY_URL`)과 `SUPABASE_ANON_KEY`(또는 `SUPABASE_KEY`)가 설정되어 있다
- **WHEN** 서버 또는 라이브러리 코드가 초기화된다
- **THEN** 정상적으로 데이터베이스에 연결된다

#### Scenario: 디버그 레벨 제어
- **GIVEN** `DEBUG_LEVEL`이 0/1/2/3 중 하나로 설정된다 (미설정 시 1)
- **WHEN** 서버가 동작한다
- **THEN** 출력 상세도가 설정 값에 맞게 조정된다(0=없음, 1=기본, 2=상세, 3=폴링 루프와 이벤트 처리까지)

#### Scenario: 로깅 레벨과 간격
- **WHEN** 사용자가 `LOG_LEVEL`을 `DEBUG`/`INFO`/`WARNING`/`ERROR` 중 하나로, `LOG_SPACED`를 `0` 또는 `1`로 설정한다
- **THEN** 라이브러리 로그 출력이 설정에 따른다(`LOG_LEVEL` 기본값 `INFO`, `LOG_SPACED` 기본값 `1`)

#### Scenario: 비프로덕션 환경 .env 자동 로드
- **GIVEN** 환경 변수 `ENV`가 `production`이 아니다
- **WHEN** 라이브러리가 초기화된다
- **THEN** 작업 디렉터리의 `.env` 파일이 자동으로 적재된다
