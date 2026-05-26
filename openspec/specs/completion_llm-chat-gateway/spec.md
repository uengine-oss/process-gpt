# LLM 채팅 게이트웨이 명세

## Purpose
클라이언트가 OpenAI 호환 인터페이스로 채팅 완성(스트리밍 포함), 메시지 토큰 수 계산, 텍스트 임베딩 벡터 생성을 요청하는 능력을 보장한다.

## Requirements

### Requirement: 상태 점검
시스템은 `GET /langchain-chat/sanity-check` 요청에 대해 게이트웨이가 동작 중임을 나타내는 응답을 SHALL 반환한다.

#### Scenario: 상태 점검 응답
- **WHEN** 클라이언트가 `GET /langchain-chat/sanity-check`를 호출한다
- **THEN** 시스템은 `{is_sanity_check: true}`를 반환한다

### Requirement: 채팅 완성 응답
시스템은 `POST /langchain-chat/messages`로 메시지 목록을 받으면 모델 응답을 OpenAI 호환 형식으로 SHALL 반환한다.

#### Scenario: 비스트리밍 채팅 완성
- **GIVEN** 클라이언트가 `{model, messages}`를 제공하고 `stream`이 거짓이다
- **WHEN** 클라이언트가 `POST /langchain-chat/messages`를 호출한다
- **THEN** 시스템은 `id`와 `choices`를 포함하고 `choices[0].message`에 응답 내용을 담은 JSON을 반환한다

#### Scenario: 스트리밍 채팅 완성
- **GIVEN** 클라이언트가 `{model, messages, stream: true}`를 제공한다
- **WHEN** 클라이언트가 `POST /langchain-chat/messages`를 호출한다
- **THEN** 시스템은 `text/event-stream` 응답으로 `choices[].delta.content`를 담은 `data:` 프레임을 순차 전송한다
- **AND** 마지막에 `data: [DONE]` 프레임으로 스트림 종료를 알린다

#### Scenario: 모델을 해소할 수 없음
- **GIVEN** 요청에 `model`이 없고 기본 모델 환경 설정도 없다
- **WHEN** 클라이언트가 `POST /langchain-chat/messages`를 호출한다
- **THEN** 시스템은 `400` 상태와 `model`이 필요하다는 메시지를 반환한다

### Requirement: 토큰 수 계산
시스템은 `POST /langchain-chat/count-tokens`로 메시지 목록을 받으면 입력 토큰 수를 SHALL 반환한다.

#### Scenario: 토큰 수 계산 성공
- **WHEN** 클라이언트가 `{model, messages}`로 `POST /langchain-chat/count-tokens`를 호출한다
- **THEN** 시스템은 `{input_tokens: <정수>}`를 반환한다

### Requirement: 임베딩 벡터 생성
시스템은 `POST /langchain-chat/embeddings`로 텍스트를 받으면 임베딩 벡터를 SHALL 반환한다.

#### Scenario: 임베딩 생성 성공
- **WHEN** 클라이언트가 `{model, text}`로 `POST /langchain-chat/embeddings`를 호출한다
- **THEN** 시스템은 `{embedding: <실수 배열>}`을 반환한다

#### Scenario: 임베딩을 지원하지 않는 모델 구성
- **GIVEN** 현재 모델/제공자 구성이 임베딩을 지원하지 않는다
- **WHEN** 클라이언트가 `POST /langchain-chat/embeddings`를 호출한다
- **THEN** 시스템은 `501` 상태와 임베딩 미구현 메시지를 반환한다
