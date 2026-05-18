# A2A Agent Bridge Specification

## Purpose
외부 A2A 프로토콜 에이전트가 ProcessGPT의 작업을 처리할 수 있도록, 작업 큐 워커와 웹훅 수신기를 한 쌍으로 운용한다. 시스템은 외부 A2A 에이전트의 푸시 알림 지원 여부에 따라 동기 또는 비동기 콜백 경로를 자동 선택하고, 작업 진행과 폼 산출을 표준 todolist 수명주기로 반영한다.

## Requirements

### Requirement: 외부 A2A 에이전트 모드 자동 선택
The system SHALL inspect each external A2A agent's capability advertisement and SHALL dispatch work synchronously when the agent does not support push notifications and asynchronously with a webhook callback when it does.

#### Scenario: 푸시 알림 지원 에이전트
- **GIVEN** 외부 A2A 에이전트가 `push_notifications` 기능을 광고한다
- **WHEN** 워커가 작업을 그 에이전트에 위임한다
- **THEN** 시스템은 외부에서 접근 가능한 콜백 URL을 메시지에 동봉하여 에이전트에 송신하고, 즉시 다음 이벤트들을 발행한다: `working/task_started`, `webhook_accepted`, `webhook_callback_waiting`
- **AND** 동일 작업의 실행 흐름은 외부 콜백 도착 시점까지 더 이상 진행되지 않는다

#### Scenario: 푸시 알림 미지원 에이전트
- **GIVEN** 외부 A2A 에이전트가 푸시 알림을 광고하지 않는다
- **WHEN** 워커가 작업을 위임한다
- **THEN** 시스템은 동기 모드로 메시지를 송신하고 결과 수신까지 대기하며, 다음 이벤트 순서를 발행한다: `working/task_started` → `completed/task_completed` → `TaskArtifactUpdateEvent`

### Requirement: 비동기 콜백 수신
The system SHALL accept HTTP webhook callbacks from external A2A agents and SHALL translate the incoming notification into the standard task lifecycle.

#### Scenario: 콜백 수신과 상태 반영
- **WHEN** 외부 에이전트가 `POST /webhook/a2a/todolist/{todolist_id}`로 콜백을 전송한다
- **THEN** 시스템은 `{"status": "received", "todolist_id": "...", "a2a_task_id": "...", "notification_type": "..."}` 형태로 즉시 수신 확인을 반환한다
- **AND** 콜백 본문에서 알림 유형(`COMPLETED`, `INPUT_REQUIRED`, `WORKING`, `FAILED`, `CANCELED`, `OTHER`)과 결과/히스토리를 추출하여 작업 상태와 이벤트 큐에 반영한다

#### Scenario: 잘못된 콜백 본문
- **WHEN** 콜백 본문이 잘못된 형식이다
- **THEN** 시스템은 오류를 로깅하지만 수신 확인은 정상 응답하여 외부 에이전트가 재시도 폭주를 일으키지 않게 한다

### Requirement: 헬스 체크
The system SHALL expose a liveness endpoint usable for orchestration probes.

#### Scenario: 헬스 응답
- **WHEN** 운영자 또는 오케스트레이터가 `GET /health`를 호출한다
- **THEN** 시스템은 `{"status": "healthy", "timestamp": "..."}` 형태로 응답한다

### Requirement: 작업 큐 폴링 워커
The system SHALL include a worker process that polls the platform task queue for items targeted at this bridge agent and SHALL invoke the external A2A agent for each claimed item.

#### Scenario: 작업 위임 흐름
- **GIVEN** 작업 큐에 해당 워커의 `agent_orch` 작업이 존재한다
- **WHEN** 워커가 작업을 클레임한다
- **THEN** 워커는 외부 A2A 에이전트로 메시지를 송신하고, 동기/비동기 모드에 맞는 이벤트를 발행하며 표준 todolist 수명주기로 결과를 저장한다

### Requirement: 폼 산출 처리
The system SHALL accept a form identifier in the work context and SHALL publish a `working` / `completed` event pair for form processing in addition to the main task lifecycle.

#### Scenario: 폼 처리 이벤트
- **GIVEN** 작업 컨텍스트에 `form_id`가 포함되어 있다
- **WHEN** 시스템이 외부 에이전트의 결과를 받아 폼을 생성한다
- **THEN** 시스템은 폼 처리에 대한 `working` 이벤트와 이어지는 `completed` 이벤트를 발행한다

### Requirement: 외부 콜백 베이스 URL 구성
The system SHALL accept a publicly reachable webhook base URL configuration so that external agents can deliver callbacks to the receiver pod.

#### Scenario: 콜백 URL 생성
- **GIVEN** 환경 변수 `WEBHOOK_PUBLIC_BASE_URL`이 설정되어 있다
- **WHEN** 워커가 비동기 모드 메시지를 송신한다
- **THEN** 메시지에 동봉되는 콜백 URL은 `{WEBHOOK_PUBLIC_BASE_URL}/webhook/a2a/todolist/{todolist_id}` 형태로 구성된다

### Requirement: 수신기 바인딩과 운영
The system SHALL bind the webhook receiver to configurable host, port, and log level so operators can place it appropriately in their network.

#### Scenario: 수신기 바인딩
- **GIVEN** 환경 변수 `WEBHOOK_RECEIVER_HOST`, `WEBHOOK_RECEIVER_PORT`, `WEBHOOK_RECEIVER_LOG_LEVEL`이 설정될 수 있다 (기본값 `0.0.0.0`, `9000`, `info`)
- **WHEN** 수신기 프로세스가 기동된다
- **THEN** 해당 호스트/포트로 바인딩되고 지정된 로그 레벨로 동작한다

### Requirement: 외부 에이전트 통신 실패 처리
The system SHALL surface failures during external agent communication as task-level errors rather than silently dropping work.

#### Scenario: 메시지/카드 누락
- **WHEN** 외부 에이전트의 카드 조회 또는 필수 메시지 입력이 누락된다
- **THEN** 시스템은 즉시 오류를 발생시키고 작업 처리는 그 단계에서 중단된다

#### Scenario: 카드 조회 실패 시 폴백
- **GIVEN** 외부 에이전트 카드 조회가 실패한다
- **WHEN** 워커가 모드 선택을 시도한다
- **THEN** 시스템은 동기 모드로 폴백하여 처리한다
