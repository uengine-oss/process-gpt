# MCP Server Validation Specification

## Purpose
사용자가 MCP 서버 설정 JSON을 제출하면 각 서버의 연결 가능성과 노출되는 도구 목록을 검증해 결과를 반환하는 도구를 제공한다. 검증 도구는 stdio, streamable HTTP, SSE 트랜스포트를 지원하며 결과를 구조화된 JSON으로 응답한다.

## Requirements

### Requirement: 웹 UI와 API 정보 제공
The system SHALL expose a root web UI, an API information endpoint, and a health endpoint.

#### Scenario: 루트 UI 응답
- **WHEN** 클라이언트가 `GET /`을 호출한다
- **THEN** 시스템은 웹 UI HTML을 반환한다

#### Scenario: API 정보와 헬스 체크
- **WHEN** 클라이언트가 `GET /api` 또는 `GET /health`를 호출한다
- **THEN** 시스템은 각각 API 정보와 정상 상태 응답을 반환한다

### Requirement: 검증 요청
The system SHALL accept a JSON validation request describing one or more MCP servers and SHALL return a structured result that includes per-server connection status, exposed tools, and timing.

#### Scenario: 정상 검증
- **WHEN** 클라이언트가 `POST /validate`에 `{ mcpServers: { name: { transport, command, args, url, headers } }, timeout }` 형식의 본문을 전송한다
- **THEN** 시스템은 다음 필드를 포함한 응답을 반환한다: `overall_status`, `servers[]` (각 서버에 `name`, `status`, `tools[]`, `connection_details`), `total_tools`, `validation_time`, `errors`

#### Scenario: 잘못된 JSON
- **WHEN** 요청 본문이 잘못되었다
- **THEN** 시스템은 HTTP 400으로 거부한다

### Requirement: 다중 트랜스포트 지원
The system SHALL attempt connections according to each server's declared transport, supporting stdio, streamable HTTP, and SSE.

#### Scenario: stdio 서버 검증
- **GIVEN** 서버 설정이 stdio 트랜스포트와 명령/인자를 명시한다
- **WHEN** 시스템이 검증을 수행한다
- **THEN** 시스템은 로컬 프로세스를 실행해 핸드셰이크 후 도구 목록을 조회한다

#### Scenario: HTTP 서버 검증
- **GIVEN** 서버 설정이 streamable HTTP 또는 SSE 트랜스포트를 명시한다
- **WHEN** 시스템이 검증을 수행한다
- **THEN** 시스템은 원격 엔드포인트에 HTTP 요청을 수행한다

### Requirement: 연결 실패 보고
The system SHALL report per-server connection failures in the response without aborting validation of other servers.

#### Scenario: 단일 서버 실패
- **WHEN** 어떤 서버 연결이 실패한다
- **THEN** 응답에서 해당 서버는 `status: "error"`로 표시되고 오류 메시지가 포함되며, 다른 서버 검증은 계속 진행된다

### Requirement: 타임아웃 적용
The system SHALL apply the request-supplied `timeout` value to bound how long it waits for each server.

#### Scenario: 시간 초과
- **GIVEN** 요청 본문에 `timeout`이 명시되어 있다
- **WHEN** 한 서버가 시간 내에 응답하지 않는다
- **THEN** 시스템은 해당 서버를 오류로 표시하고 다음으로 진행한다

### Requirement: 외부 상태 무영향
The system SHALL not persist any data from the validation request beyond the response and SHALL not require server-side configuration to run a validation.

#### Scenario: 무상태 동작
- **WHEN** 클라이언트가 검증을 수행한다
- **THEN** 시스템은 요청 페이로드를 영속하지 않고 응답으로만 결과를 반환한다
