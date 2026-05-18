# Conversational Research Assistant Specification

## Purpose
사용자가 자연어 채팅으로 심층 연구 보고서를 요청하고, 명확화 질문 흐름·스트리밍 진행·보고서 자산 관리(조회, 수정, 삭제, 이미지 생성, 블록 재작성)를 단일 REST API로 사용할 수 있게 한다.

## Requirements

### Requirement: 보고서 생성 채팅
The system SHALL accept a chat-style request that produces a research report and SHALL allow clients to skip the clarification stage.

#### Scenario: 비스트리밍 채팅
- **WHEN** 클라이언트가 `POST /api/chat`로 `message`(필수), `session_id`(선택), `skip_clarification`(선택)을 전송한다
- **THEN** 시스템은 응답으로 단일 본문을 반환하며, `session_id`가 비어 있으면 새로 생성한다

#### Scenario: 명확화 흐름
- **GIVEN** `skip_clarification`이 거짓이며 첫 요청만으로 의도가 모호하다
- **WHEN** 시스템이 처리를 시작한다
- **THEN** 시스템은 후속 질문(또는 선택지)을 응답하여 사용자 입력을 대기한다

#### Scenario: 명확화 건너뛰기
- **GIVEN** `skip_clarification`이 참이다
- **WHEN** 시스템이 처리를 시작한다
- **THEN** 시스템은 합리적 가정으로 진행하고 즉시 보고서 생성으로 들어간다

### Requirement: 진행 스트리밍
The system SHALL provide a streaming variant of the chat endpoint that emits Server-Sent Events for each stage of report generation.

#### Scenario: SSE 스트리밍
- **WHEN** 클라이언트가 `POST /api/chat/stream`을 호출한다
- **THEN** 응답 채널을 통해 단계별 이벤트가 순서대로 전송된다

### Requirement: 보고서와 히스토리 조회
The system SHALL expose endpoints to list reports and to read a single report's markdown.

#### Scenario: 히스토리와 단일 조회
- **WHEN** 클라이언트가 `GET /api/history` 또는 `GET /api/report/{report_id}`를 호출한다
- **THEN** 시스템은 각각 보고서 목록과 단일 보고서 마크다운을 반환한다

### Requirement: 보고서 수정과 삭제
The system SHALL allow callers to overwrite a report's markdown and to delete a report.

#### Scenario: 마크다운 갱신
- **WHEN** 클라이언트가 `PUT /api/report/{report_id}`로 새 `markdown` 본문을 전송한다
- **THEN** 시스템은 해당 보고서의 마크다운을 갱신한다

#### Scenario: 삭제
- **WHEN** 클라이언트가 `DELETE /api/report/{report_id}`를 호출한다
- **THEN** 시스템은 보고서와 관련 자산을 제거한다

### Requirement: 자산 조회와 이미지 생성
The system SHALL expose endpoints to download generated assets, to request new image generation, and to suggest images for a report.

#### Scenario: 자산 다운로드
- **WHEN** 클라이언트가 `GET /api/report/{report_id}/asset/{filename}`을 호출한다
- **THEN** 시스템은 자산 파일을 반환한다

#### Scenario: 이미지 생성 요청
- **WHEN** 클라이언트가 `POST /api/report/{report_id}/image`로 `id`, `prompt`, `title`, `caption`을 전송한다
- **THEN** 시스템은 새 이미지를 생성하고 보고서 자산에 추가한다

#### Scenario: 이미지 제안
- **WHEN** 클라이언트가 `POST /api/report/{report_id}/image-suggest`를 호출한다
- **THEN** 시스템은 이미지 후보 제안을 반환한다

### Requirement: 블록 재작성
The system SHALL allow callers to request a rewrite of a specific markdown block with an instruction.

#### Scenario: 블록 재작성
- **WHEN** 클라이언트가 `POST /api/report/{report_id}/rewrite`로 `block_markdown`과 `instruction`을 전송한다
- **THEN** 시스템은 재작성된 블록 마크다운을 반환한다

### Requirement: 외부 의존 의 부분 실패 허용
The system SHALL degrade gracefully when optional integrations are unavailable: searches return empty, image generation leaves placeholders, internal-document search proceeds with Tavily only.

#### Scenario: 이미지 생성 실패
- **WHEN** 이미지 생성이 실패한다
- **THEN** 보고서 마크다운에는 자리표시자가 유지되고 텍스트 생성은 계속된다

#### Scenario: 내부 문서 검색 불가
- **GIVEN** `MEMENTO_SERVICE_URL`이 응답하지 않는다
- **WHEN** 검색 단계가 진행된다
- **THEN** 외부 검색만으로 보고서를 계속 생성한다

### Requirement: LLM 프로바이더 선택
The system SHALL select the LLM provider via `DEEP_RESEARCH_LLM_PROVIDER` and SHALL support custom endpoints for closed-network deployments.

#### Scenario: 프로바이더 구성
- **GIVEN** `DEEP_RESEARCH_LLM_PROVIDER`가 `openai`/`openrouter`/`custom` 중 하나로 설정된다 (기본 `openrouter`)
- **WHEN** 시스템이 LLM을 호출한다
- **THEN** 선택된 프로바이더의 자격 증명과 베이스 URL이 사용된다

### Requirement: 외부 통합 구성
The system SHALL support optional integrations whose hosts can be configured via environment variables: `MEMENTO_SERVICE_URL`, `PROCESS_GPT_OFFICE_MCP_URL`.

#### Scenario: 사내 문서 검색 활성화
- **GIVEN** `MEMENTO_SERVICE_URL`이 설정되어 있다
- **WHEN** 시스템이 검색을 수행한다
- **THEN** 사내 문서 검색이 추가로 사용된다

### Requirement: 환경 변수와 운영
The system SHALL accept configuration via `OPENAI_API_KEY`, `TAVILY_API_KEY`, `GOOGLE_API_KEY`, `SUPABASE_URL`, `SUPABASE_KEY`, `PORT`, `ENV`, `POLLING_TENANT_ID`.

#### Scenario: 포트 설정
- **GIVEN** `PORT`(기본 `3000`)가 설정된다
- **WHEN** 서버가 기동된다
- **THEN** 해당 포트에서 수신한다

### Requirement: 헬스 표시
The system SHALL expose a basic root endpoint that returns service liveness information.

#### Scenario: 루트 헬스
- **WHEN** 운영자가 `GET /`를 호출한다
- **THEN** 시스템은 상태 정보를 반환한다
