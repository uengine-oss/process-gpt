# Presentation Streaming Specification

## Purpose
클라이언트가 자연어 주제를 보내면 에이전트가 실시간으로 처리 진행을 알리며 PowerPoint 등 산출물을 생성하고, 동일 채널로 산출물을 다운로드할 수 있는 WebSocket 기반 인터페이스를 제공한다.

## Requirements

### Requirement: WebSocket 진입점
The system SHALL accept WebSocket connections on a configured endpoint and SHALL treat the first text frame as the topic to plan and produce.

#### Scenario: 토픽 송신과 진행 수신
- **GIVEN** 클라이언트가 `ws://<host>:6789` 에 연결한다
- **WHEN** 클라이언트가 토픽 문자열을 송신한다
- **THEN** 서버는 해당 토픽에 대한 작업 세션을 생성하고, 진행 메시지들을 WebSocket으로 스트림한다

### Requirement: 실시간 진행 메시지 카테고리
The system SHALL emit progress messages that allow the client to distinguish chain start/end, agent actions, tool invocations and their outputs, and chain-level errors.

#### Scenario: 정상 흐름
- **WHEN** 에이전트 체인이 시작·진행·종료된다
- **THEN** 클라이언트는 Chain 시작, Agent 액션, Tool 실행 시작/종료/출력, Chain 종료를 식별 가능한 메시지로 수신한다

#### Scenario: 체인 오류
- **WHEN** 체인 실행 중 오류가 발생한다
- **THEN** 클라이언트는 오류 메시지를 수신하고 세션은 정리된다

### Requirement: 산출 파일 다운로드
The system SHALL allow the client to request a generated artifact through the same WebSocket channel by sending a `request_file:output/<filename>` message.

#### Scenario: 파일 다운로드 요청
- **GIVEN** 이전 실행으로 `output/` 디렉터리에 산출물이 저장되었다
- **WHEN** 클라이언트가 `request_file:output/<filename>`을 송신한다
- **THEN** 서버는 해당 파일을 바이너리로 전송한다

#### Scenario: 존재하지 않는 파일 요청
- **WHEN** 요청한 파일이 존재하지 않는다
- **THEN** 서버는 오류 메시지로 응답하고 연결은 유지된다

### Requirement: LLM 자격 증명 구성
The system SHALL require `OPENAI_API_KEY` to operate and SHALL surface a failure if it is missing.

#### Scenario: 자격 증명 미설정
- **GIVEN** `OPENAI_API_KEY`가 비어 있다
- **WHEN** 서버가 LLM 호출을 시도한다
- **THEN** 시스템은 오류를 발생시키고 진행 메시지로 알린다

### Requirement: 클라이언트 메시지 안전 처리
The system SHALL parse client messages defensively so that malformed input does not terminate the server process.

#### Scenario: 잘못된 메시지
- **WHEN** 클라이언트가 비정상 형식의 메시지를 전송한다
- **THEN** 서버는 예외를 캡처하고 로깅하며 연결을 유지한다
