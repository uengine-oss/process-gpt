# 에이전트 메모리 대화 명세

## Purpose
사용자가 학습 모드로 정보를 에이전트 메모리에 저장하고, 질의 모드로 저장된 메모리를 검색·활용한 답변을 받는 능력을 보장한다.

## Requirements

### Requirement: 학습 모드 메모리 저장
시스템은 `POST /multi-agent/chat`을 학습 모드로 받으면 입력 정보를 에이전트별 메모리에 저장하고 저장 결과를 SHALL 반환한다.

#### Scenario: 학습 정보 저장 성공
- **GIVEN** 클라이언트가 `{text, chat_room_id, options:{agent_id, is_learning_mode:true}}`를 제공한다
- **WHEN** 클라이언트가 `POST /multi-agent/chat`을 호출한다
- **THEN** 시스템은 `task_id`와 `response`를 반환하며 `response.type`은 `information`이다
- **AND** 저장된 정보는 동일 `agent_id`의 이후 질의에서 검색 대상이 된다

#### Scenario: 유사 정보 중복 저장 방지
- **GIVEN** 동일 `agent_id` 메모리에 입력과 충분히 유사한 정보가 이미 존재한다
- **WHEN** 클라이언트가 학습 모드로 `POST /multi-agent/chat`을 호출한다
- **THEN** 시스템은 중복으로 판단하여 새 정보를 저장하지 않는다

### Requirement: 질의 모드 메모리 검색 답변
시스템은 `POST /multi-agent/chat`을 질의 모드로 받으면 에이전트 메모리를 검색하여 답변을 SHALL 반환한다.

#### Scenario: 메모리 기반 답변 성공
- **GIVEN** 클라이언트가 `{text, chat_room_id, options:{agent_id}}`를 제공한다
- **WHEN** 클라이언트가 `POST /multi-agent/chat`을 호출한다
- **THEN** 시스템은 `task_id`와 `response`를 반환하며 `response.type`은 `query`이고 검색 결과를 활용한 답변을 포함한다

#### Scenario: agent_id 누락
- **GIVEN** 요청 `options`에 `agent_id`가 없다
- **WHEN** 클라이언트가 `POST /multi-agent/chat`을 호출한다
- **THEN** 시스템은 `400` 상태와 `agent_id is required for Mem0 agent` 메시지를 반환한다

### Requirement: 에이전트 서비스 상태 점검
시스템은 `GET /multi-agent/health-check` 요청에 대해 서비스 정상 동작 여부를 SHALL 반환한다.

#### Scenario: 상태 점검 응답
- **WHEN** 클라이언트가 `GET /multi-agent/health-check`를 호출한다
- **THEN** 시스템은 `{status: "healthy"}`를 반환한다

### Requirement: 원격 에이전트 디스크립터 조회
시스템은 `GET /multi-agent/fetch-data`로 에이전트 URL을 받으면 해당 에이전트의 디스크립터 정보를 SHALL 반환한다.

#### Scenario: 원격 에이전트 정보 조회
- **GIVEN** 클라이언트가 `agent_url` 질의 파라미터를 제공한다
- **WHEN** 클라이언트가 `GET /multi-agent/fetch-data`를 호출한다
- **THEN** 시스템은 해당 에이전트의 `/.well-known/agent.json` 디스크립터 내용을 반환한다
