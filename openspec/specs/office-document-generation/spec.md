# Office Document Generation Specification

## Purpose
MCP 또는 REST 클라이언트가 LLM, 사내 지식, 실시간 웹 검색, 이미지 생성을 결합해 HWPX/DOCX 문서와 슬라이드 마크다운을 생성·편집하고, 그 산출을 외부 스토리지에 업로드해 공유할 수 있는 단일 인터페이스를 제공한다.

## Requirements

### Requirement: 참고 문서 목록 조회
The system SHALL provide a tool that lists reference documents available for a tenant.

#### Scenario: 테넌트별 참고 문서 조회
- **WHEN** 클라이언트가 `list_reference_documents(tenant_id)`를 호출한다
- **THEN** 시스템은 해당 테넌트에 가용한 참고 문서 목록을 반환한다

### Requirement: HWPX 문서 생성
The system SHALL generate a HWPX document from a template URL with topic, description, reference text, reference documents, optional image generation, and optional image-reference inclusion.

#### Scenario: 문서 생성
- **WHEN** 클라이언트가 `generate_hwpx(template_url, report_topic, report_description, reference_text, reference_documents, tenant_id, image_generation_enabled, image_reference_enabled)`를 호출한다
- **THEN** 시스템은 결과 객체를 반환하며 `file_url`, `html_url`, `file_name` 필드를 포함한다

#### Scenario: 템플릿 URL 누락
- **WHEN** 호출에 템플릿 URL이 없다
- **THEN** 시스템은 오류로 거부한다

### Requirement: HWPX 페이지 편집
The system SHALL allow callers to extract a single page of an HWPX document as HTML and SHALL accept the edited HTML to write back into the document.

#### Scenario: 페이지 HTML 추출
- **WHEN** 클라이언트가 `edit_hwpx_page_html(hwpx_url, page_number)`을 호출한다
- **THEN** 시스템은 데이터 식별자 태그를 포함한 페이지 HTML을 반환한다

#### Scenario: HTML 반영 저장
- **WHEN** 클라이언트가 `save_hwpx_from_html(hwpx_url, edited_html, output_name)`을 호출한다
- **THEN** 시스템은 편집 결과를 원본 HWPX 포맷으로 저장하고 새 산출 URL을 반환한다

### Requirement: DOCX 문서 생성과 편집
The system SHALL provide equivalent generation, page-edit, and save operations for DOCX documents.

#### Scenario: DOCX 생성
- **WHEN** 클라이언트가 `generate_docx(docx_template_url, report_topic, report_description, reference_text, image_generation_enabled)`를 호출한다
- **THEN** 시스템은 결과 객체에 `file_url`, `html_url`, `file_name`을 포함하여 반환한다

#### Scenario: DOCX 페이지 편집
- **WHEN** 클라이언트가 `edit_docx_page_html(docx_url, page_number)`을 호출한다
- **THEN** 시스템은 페이지 HTML을 반환한다

#### Scenario: DOCX HTML 반영 저장
- **WHEN** 클라이언트가 `save_docx_from_html(docx_url, edited_html, output_name)`을 호출한다
- **THEN** 시스템은 변경 사항을 DOCX로 반영하여 저장한다

### Requirement: 슬라이드 마크다운 생성
The system SHALL accept a report markdown and SHALL produce a slide-shaped markdown with image URL references.

#### Scenario: 슬라이드 생성
- **WHEN** 클라이언트가 `generate_slides(report_markdown)`을 호출한다
- **THEN** 시스템은 슬라이드 마크다운과 함께 필요한 이미지 URL을 반환한다

### Requirement: 슬라이드/이미지 편집 REST API
The system SHALL provide REST endpoints to edit and enhance images.

#### Scenario: 슬라이드 이미지 편집
- **WHEN** 클라이언트가 `POST /api/edit-slide-image`에 이미지 URL과 지시를 전달한다
- **THEN** 시스템은 편집된 이미지 결과를 반환한다

#### Scenario: 이미지 개선
- **WHEN** 클라이언트가 `POST /api/enhance-image`에 base64 이미지를 전달한다
- **THEN** 시스템은 AI 개선된 이미지를 반환한다

### Requirement: 외부 저장소 업로드와 결과 URL
The system SHALL persist generated artifacts to external object storage and SHALL return public-shareable URLs in the response.

#### Scenario: 결과 URL 보장
- **WHEN** 어떤 생성 도구든 정상 종료한다
- **THEN** 응답은 `file_url`, `html_url`, `file_name`을 포함한다

### Requirement: LLM 프로바이더 선택
The system SHALL select the LLM provider via `OFFICE_MCP_LLM_PROVIDER` from `openai`, `openrouter`, `gemini`, `custom`.

#### Scenario: 폐쇄망 사용
- **GIVEN** `OFFICE_MCP_LLM_PROVIDER='custom'`이고 `CUSTOM_LLM_BASE_URL`과 `CUSTOM_LLM_API_KEY`가 설정되어 있다
- **WHEN** 시스템이 LLM을 호출한다
- **THEN** 시스템은 커스텀 엔드포인트로 호출한다

### Requirement: 사내 지식 통합
The system SHALL use a Memento service when `MEMENTO_SERVICE_URL` is configured to enrich generated documents with tenant-scoped knowledge.

#### Scenario: 지식 통합 활성
- **GIVEN** `MEMENTO_SERVICE_URL`이 설정되어 있다
- **WHEN** 시스템이 문서를 생성한다
- **THEN** 시스템은 Memento에서 관련 청크를 회수해 본문 작성에 활용한다

### Requirement: 실시간 웹 검색 통합
The system SHALL use Tavily when `TAVILY_API_KEY` (and optionally `TAVILY_API_URL`) is configured for slide content enrichment.

#### Scenario: 검색 활성
- **GIVEN** Tavily 자격 증명이 설정되어 있다
- **WHEN** 슬라이드 생성이 실시간 정보를 필요로 한다
- **THEN** 시스템은 Tavily를 사용하여 검색 결과를 반영한다

### Requirement: 이미지 생성 통합
The system SHALL use Google Gemini (via `GOOGLE_API_KEY`) for image generation/editing when image features are enabled.

#### Scenario: 이미지 편집 실패
- **WHEN** 이미지 편집 호출이 실패한다
- **THEN** 시스템은 HTTP 500 응답으로 거부한다

### Requirement: 입력/응답 오류 정책
The system SHALL return predictable HTTP status codes for client-visible failure modes.

#### Scenario: 이미지 다운로드 실패
- **WHEN** 외부 이미지 다운로드가 실패한다
- **THEN** 시스템은 HTTP 502로 응답한다

#### Scenario: HTML 파싱 실패
- **WHEN** 편집된 HTML 파싱이 실패한다
- **THEN** 시스템은 경고를 기록하고 HWPX 결과만 반환한다
