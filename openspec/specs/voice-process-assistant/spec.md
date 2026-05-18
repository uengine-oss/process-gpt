# Voice Process Assistant Specification

## Purpose
사용자가 실시간 음성/텍스트 WebSocket 세션으로 자신의 프로세스 정의, 인스턴스, 작업 목록, 채팅 기록, 조직도, UI 폼 정의를 자연어로 조회할 수 있게 한다. 세션은 사용자 자격 정보로 시작되며, 에이전트는 한정된 조회 도구를 통해 데이터를 회수한다.

## Requirements

### Requirement: WebSocket 세션 시작
The system SHALL accept WebSocket connections and SHALL require an initial handshake that conveys the calling user's identity and conversational context.

#### Scenario: 초기 핸드셰이크
- **GIVEN** 클라이언트가 WebSocket 엔드포인트(`/ws`)에 연결한다
- **WHEN** 클라이언트가 초기 메시지로 `email`, `chat_room_id`, `tenant_id`, `conversation_history`를 송신한다
- **THEN** 세션이 활성화되고 에이전트가 사용자 컨텍스트 안에서 동작한다

#### Scenario: 사용자 정보 송신 실패
- **WHEN** 초기 사용자 정보 수신이 누락되거나 형식이 잘못되었다
- **THEN** 세션은 종료된다

### Requirement: 실시간 양방향 음성/텍스트 스트림
The system SHALL relay audio and text between the client and the LLM realtime endpoint so that the conversation flows in both directions.

#### Scenario: 실시간 대화
- **GIVEN** 세션이 활성화되어 있다
- **WHEN** 클라이언트가 음성 또는 텍스트 입력을 전송한다
- **THEN** 시스템은 LLM 응답을 음성 또는 텍스트로 클라이언트에 스트림한다

### Requirement: 한정된 데이터 조회 도구
The system SHALL expose to the agent exactly the following tools: `get_process_definitions`, `get_process_definition`, `get_process_instances`, `get_chat_history`, `fetch_todolist_by_user_id_tool`, `fetch_todolist_by_user_id_and_status_tool`, `fetch_process_instance_list_tool`, `fetch_organization_chart_tool`, `fetch_ui_definition_tool`.

#### Scenario: 도구 호출 결과
- **WHEN** 에이전트가 위 도구 중 하나를 호출한다
- **THEN** 시스템은 사용자 컨텍스트에 맞는 검색 결과를 반환한다

#### Scenario: 검색 결과 없음
- **WHEN** 도구의 유사도 검색이 일치 항목을 찾지 못한다
- **THEN** 시스템은 빈 목록을 반환하여 대화가 계속될 수 있게 한다

### Requirement: LLM 오류 처리
The system SHALL communicate fatal LLM errors to the client and SHALL close the session safely.

#### Scenario: LLM 오류
- **WHEN** OpenAI Realtime API가 오류를 보고한다
- **THEN** 시스템은 클라이언트에 오류 메시지를 송신하고 세션을 종료한다

### Requirement: 환경 변수 계약
The system SHALL accept configuration via `OPENAI_API_KEY` (required) and optional `SUPABASE_URL`, `SUPABASE_KEY`.

#### Scenario: 자격 증명 부재
- **GIVEN** `OPENAI_API_KEY`가 비어 있다
- **WHEN** 세션이 LLM 호출을 시도한다
- **THEN** 시스템은 오류를 클라이언트로 전송하고 세션을 닫는다
