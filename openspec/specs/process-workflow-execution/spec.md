# Process Workflow Execution Specification

## Purpose
ProcessGPT의 핵심 BPM 실행 서비스로서, 외부 클라이언트가 프로세스 정의를 검색·조회하고, 프로세스 인스턴스를 시작·진행·완료하며, 사용자 또는 시스템 워크아이템을 폴링·완료·재작업할 수 있게 한다. 또한 멀티에이전트 채팅, MCP 도구 노출, 콜봇/모바일 알림/이메일/RAG 같은 외부 통합을 통해 업무 흐름의 진행을 보장한다.

## Requirements

### Requirement: 멀티테넌트 식별
The system SHALL identify the calling tenant for every HTTP request using forwarding metadata, and the same identifier SHALL apply to all subsequent data reads and writes for that request.

#### Scenario: 테넌트 식별자 전달
- **GIVEN** 클라이언트 요청이 `X-Forwarded-Host` 헤더를 포함한다
- **WHEN** 시스템이 요청을 처리한다
- **THEN** 모든 데이터 접근은 해당 헤더에서 도출된 테넌트로 한정된다

#### Scenario: 헤더 부재 시 기본 동작
- **GIVEN** 요청이 `X-Forwarded-Host` 헤더를 포함하지 않는다
- **WHEN** 시스템이 요청을 처리한다
- **THEN** 시스템은 기본 로컬 테넌트로 동작한다

### Requirement: 프로세스 인스턴스 시작
The system SHALL accept a request to initiate a new process instance and SHALL return identifiers that allow the client to subsequently complete or query that instance.

#### Scenario: 정상 시작
- **WHEN** 클라이언트가 `POST /initiate`로 프로세스 정의 식별자와 시작 입력을 전달한다
- **THEN** 시스템은 새로운 프로세스 인스턴스를 생성하고 후속 호출에 사용할 식별자를 응답으로 반환한다
- **AND** 새 인스턴스는 외부 조회에서 진행 중 상태로 나타난다

### Requirement: 활동 완료
The system SHALL accept activity completion requests and SHALL advance the underlying process instance, generating the next set of work items as defined by the process model.

#### Scenario: 사용자 활동 완료
- **GIVEN** 진행 중인 프로세스 인스턴스의 활동에 대해 답변이 준비되었다
- **WHEN** 클라이언트가 `POST /complete`로 `process_instance_id`, `activity_id`, `answer`를 전송한다
- **THEN** 시스템은 해당 활동을 완료 처리하고 다음 활동 목록을 응답으로 반환한다

#### Scenario: 비전(이미지 기반) 활동 완료
- **GIVEN** 활동이 이미지 입력 기반이다
- **WHEN** 클라이언트가 `POST /vision-complete`를 호출한다
- **THEN** 시스템은 이미지 기반 답변을 처리하고 다음 활동 정보를 반환한다

#### Scenario: 필수 입력 누락
- **WHEN** 완료 요청에서 `process_instance_id`, `activity_id`, `answer` 중 하나라도 누락된다
- **THEN** 시스템은 400 응답으로 거부한다

#### Scenario: 존재하지 않는 인스턴스
- **WHEN** 요청에 명시된 프로세스 인스턴스 또는 정의가 존재하지 않는다
- **THEN** 시스템은 404 응답으로 거부한다

### Requirement: 재작업 처리
The system SHALL allow clients to discover and complete activities that require rework after feedback.

#### Scenario: 재작업 활동 조회
- **WHEN** 클라이언트가 `POST /get-rework-activities`를 호출한다
- **THEN** 시스템은 재작업이 필요한 활동 목록을 반환한다

#### Scenario: 재작업 완료
- **WHEN** 클라이언트가 `POST /rework-complete`로 답변을 전송한다
- **THEN** 시스템은 재작업 활동을 완료 처리하고 다음 진행 상태를 반환한다

### Requirement: 피드백 조회
The system SHALL allow clients to retrieve user feedback and change-diff information associated with a work item or activity.

#### Scenario: 피드백 조회
- **WHEN** 클라이언트가 `POST /get-feedback` 또는 `POST /get-feedback-diff`를 호출한다
- **THEN** 시스템은 해당 피드백 페이로드를 반환한다

### Requirement: 역할 배정과 알림
The system SHALL accept role-to-user binding requests, persist the resulting assignment, and SHALL notify assignees through email when configured.

#### Scenario: 역할 배정 시 이메일 발송
- **GIVEN** SMTP 설정(`SMTP_SERVER`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD`)이 제공되어 있다
- **WHEN** 클라이언트가 `POST /role-binding`을 호출한다
- **THEN** 시스템은 역할-사용자 매핑을 영속시키고 대상자에게 이메일을 발송한다

### Requirement: 프로세스 정의 검색과 데이터 조회
The system SHALL provide search and query endpoints over process definitions and process data.

#### Scenario: 자연어 또는 이미지로 프로세스 검색
- **WHEN** 클라이언트가 `POST /process-search` 또는 `POST /vision-process-search`를 호출한다
- **THEN** 시스템은 관련 프로세스 정의 후보 목록을 반환한다

#### Scenario: 프로세스 변수 SQL 생성과 실행
- **WHEN** 클라이언트가 `POST /process-var-sql` 또는 `POST /process-data-query`를 호출한다
- **THEN** 시스템은 프로세스 데이터에 대한 쿼리 결과를 반환한다

### Requirement: 멀티에이전트 채팅 API
The system SHALL expose a chat-style endpoint that orchestrates multiple agents to respond to a user request, along with health and supporting data endpoints.

#### Scenario: 채팅 요청
- **WHEN** 클라이언트가 `POST /multi-agent/chat`로 메시지를 전송한다
- **THEN** 시스템은 에이전트 응답 본문을 반환한다

#### Scenario: 보조 조회
- **WHEN** 클라이언트가 `GET /multi-agent/fetch-data` 또는 `GET /multi-agent/health-check`를 호출한다
- **THEN** 시스템은 각각 보조 데이터와 건강 상태를 반환한다

### Requirement: MCP 도구 노출
The system SHALL provide a listing endpoint of MCP tools available for orchestration.

#### Scenario: MCP 도구 목록
- **WHEN** 클라이언트가 `GET /mcp-tools`를 호출한다
- **THEN** 시스템은 현재 구성된 MCP 도구 목록을 반환한다

### Requirement: 콜봇 통합
The system SHALL provide endpoints that allow a telephony/voice channel to retrieve caller context, list assigned work, and submit work items on behalf of the caller.

#### Scenario: 발신자 정보 조회
- **WHEN** 콜봇이 `GET /complete-callbot/caller-info` 또는 `GET /caller-info`를 호출한다
- **THEN** 시스템은 발신자에게 매핑된 사용자/맥락 정보를 반환한다

#### Scenario: 작업 조회와 제출
- **WHEN** 콜봇이 `GET /complete-callbot/user-todolist`, `GET /complete-callbot/tasks`, `GET /complete-callbot/task/{task_id}` 또는 그 변경/제출 메서드를 호출한다
- **THEN** 시스템은 해당 작업의 조회, 수정(`PATCH`), 제출(`POST`) 결과를 반환한다

### Requirement: 백그라운드 워크아이템 처리
The system SHALL continuously poll for submitted work items and progress them through the standard lifecycle, executing user tasks, scripted tasks, and service tasks as defined by the process model.

#### Scenario: 사용자/스크립트/서비스 작업의 진행
- **GIVEN** `todolist`에 `SUBMITTED` 상태 워크아이템이 존재한다
- **WHEN** 폴링 워커가 이를 수신한다
- **THEN** 워크아이템 종류에 따라 사용자 작업(외부 사용자 입력 대기), 스크립트 작업(코드 실행), 서비스 작업(외부 호출)을 수행하고, `IN_PROGRESS → DONE`으로 전이시킨다

#### Scenario: 조건부 활동의 PENDING 처리
- **GIVEN** 조건부 활동이 `PENDING` 상태로 존재한다
- **WHEN** 폴링 워커가 이를 평가한다
- **THEN** 조건 충족 시 진행으로, 미충족 시 보류 상태를 유지한다

### Requirement: 외부 마이크로서비스 위임
The system SHALL delegate mobile push notification and document RAG search to configured external services, and SHALL surface only the resulting effect to callers.

#### Scenario: 알림 위임
- **GIVEN** `FCM_SERVICE_URL`이 설정되어 있다
- **WHEN** 알림이 필요한 이벤트가 발생한다
- **THEN** 시스템은 FCM 서비스에 요청을 위임하고 그 결과를 자체 흐름에 반영한다

#### Scenario: 문서 RAG 위임
- **GIVEN** `MEMENTO_SERVICE_URL`이 설정되어 있다
- **WHEN** RAG 검색 또는 문서 처리가 필요하다
- **THEN** 시스템은 Memento 서비스에 호출을 위임한다

### Requirement: LLM 프로바이더 구성
The system SHALL allow operators to direct LLM calls to a proxy (`LLM_PROXY_URL`, `LLM_PROXY_API_KEY`) and fall back to a direct provider (`OPENAI_API_KEY`) when the proxy is not configured.

#### Scenario: 프록시 우선 사용
- **GIVEN** `LLM_PROXY_URL`과 `LLM_PROXY_API_KEY`가 모두 설정되어 있다
- **WHEN** LLM 호출이 필요하다
- **THEN** 시스템은 프록시 엔드포인트로 호출한다

#### Scenario: 폴백
- **GIVEN** `LLM_PROXY_URL`이 비어 있고 `OPENAI_API_KEY`가 설정되어 있다
- **WHEN** LLM 호출이 필요하다
- **THEN** 시스템은 OpenAI를 직접 호출한다

### Requirement: 오류 응답 정책
The system SHALL return predictable HTTP status codes for client-visible failure modes.

#### Scenario: 필수 입력 누락
- **WHEN** 요청에서 필수 필드가 빠진다
- **THEN** 시스템은 400을 반환한다

#### Scenario: 자원 부재
- **WHEN** 요청 대상 프로세스 정의/인스턴스/작업이 존재하지 않는다
- **THEN** 시스템은 404를 반환한다

#### Scenario: 외부 의존 실패
- **WHEN** LLM, 데이터베이스, MCP 도구 호출 등 외부 의존이 실패한다
- **THEN** 시스템은 500을 반환하고 클라이언트에게는 내부 트레이스를 직접 노출하지 않는다
