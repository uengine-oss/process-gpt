# Knowledge Memory Specification

## Purpose
ProcessGPT의 사내 지식 베이스 서비스로서, 다양한 소스(로컬 파일, Google Drive, Supabase Storage, 데이터베이스 레코드)로부터 문서를 수집·인덱싱하고, 임베딩 기반 유사도 검색과 RAG 응답을 단일 API로 제공한다. 또한 지식 파일과 폴더의 외부 조작과 Google OAuth 기반 자격 증명을 안전하게 처리한다.

## Requirements

### Requirement: 문서 수집과 처리
The system SHALL accept document ingestion requests from multiple sources and persist both the original content and metadata for later search.

#### Scenario: 일반 문서 처리
- **WHEN** 클라이언트가 `POST /process`로 문서 소스를 전달한다
- **THEN** 시스템은 본문을 파싱·청크 분할·임베딩하고 `documents`/`document_images`에 영속하며, 중복 처리는 `processed_files`로 방지한다

#### Scenario: 데이터베이스 레코드를 문서로 변환
- **WHEN** 클라이언트가 `POST /process/database`를 호출한다
- **THEN** 시스템은 DB 행들을 문서 형태로 변환하여 인덱싱한다

#### Scenario: 워크아이템 산출물의 DOCX 변환과 업로드
- **WHEN** 클라이언트가 `POST /process-output`을 호출한다
- **THEN** 시스템은 DOCX 산출물을 생성하고 Google Drive에 업로드한 뒤 검색 가능한 지식으로 저장한다

#### Scenario: 백그라운드 인덱싱 상태 확인
- **WHEN** 클라이언트가 `GET /process/drive/status`를 호출한다
- **THEN** 시스템은 현재 Drive 인덱싱 작업의 상태를 반환한다

### Requirement: 검색과 조회
The system SHALL provide vector similarity search, raw chunk retrieval, image retrieval, and RAG answer endpoints scoped by tenant.

#### Scenario: 유사도 검색
- **WHEN** 클라이언트가 `GET /search`를 호출한다
- **THEN** 시스템은 검색 결과의 청크 메타데이터 목록을 반환한다

#### Scenario: 원문 청크 회수
- **WHEN** 클라이언트가 `GET /retrieve`로 `top_k`와 `tenant_id`를 전달한다
- **THEN** 시스템은 유사도 상위 `top_k`개의 원문 청크를 반환한다

#### Scenario: 인덱스 기반 직접 조회
- **WHEN** 클라이언트가 `POST /retrieve-by-indices`로 `chunk_index` 목록을 전달한다
- **THEN** 시스템은 해당 청크들을 직접 반환한다

#### Scenario: 이미지 조회
- **WHEN** 클라이언트가 `GET /retrieve-images`를 호출한다
- **THEN** 시스템은 문서에서 추출된 이미지 메타 목록을 반환한다

#### Scenario: RAG 응답
- **WHEN** 클라이언트가 `GET /query`로 자연어 질의를 전달한다
- **THEN** 시스템은 LLM 기반 최종 답변과 소스 메타데이터를 함께 반환한다

#### Scenario: PDF 하이라이트 미리보기
- **WHEN** 클라이언트가 `GET /preview/pdf-highlight`를 호출한다
- **THEN** 시스템은 청크 위치 하이라이트가 적용된 PDF 미리보기를 반환한다

### Requirement: 문서·청크 메타 조회
The system SHALL expose endpoints to list documents and their chunk metadata, including queries by file name and by file path, with optional embedding inclusion.

#### Scenario: 문서 목록과 청크 메타
- **WHEN** 클라이언트가 `GET /documents/list`, `GET /documents/chunks-metadata`, `GET /documents/chunks-by-file-path`, `GET /documents/chunks-by-file-name`, `GET /documents/chunks-with-embeddings` 중 하나를 호출한다
- **THEN** 시스템은 요청된 범위와 형식으로 결과를 반환한다

### Requirement: 지식 파일 관리
The system SHALL provide upload, deduplication-by-hash, URL retrieval, and deletion endpoints for knowledge files, and SHALL provide create/rename/delete endpoints for folders.

#### Scenario: 파일 업로드와 중복 회피
- **WHEN** 클라이언트가 `GET /knowledge/files/check-hash`로 파일 해시를 확인한 뒤 `POST /knowledge/files/upload`를 호출한다
- **THEN** 시스템은 중복이면 기존 파일을 재사용하고, 신규이면 업로드 후 처리한다

#### Scenario: 파일 URL과 삭제
- **WHEN** 클라이언트가 `GET /knowledge/files/url` 또는 `DELETE /knowledge/files`를 호출한다
- **THEN** 시스템은 각각 접근 URL을 반환하거나 파일을 삭제한다

#### Scenario: 폴더 관리
- **WHEN** 클라이언트가 `GET/POST /knowledge/folders`, `POST /knowledge/folders/rename`, `DELETE /knowledge/folders`를 호출한다
- **THEN** 시스템은 각각 폴더 조회/생성/이름 변경/삭제를 수행한다

### Requirement: 외부 저장소 업로드
The system SHALL accept file uploads destined for Supabase Storage and Google Drive and SHALL trigger downstream indexing.

#### Scenario: Supabase 스토리지에 저장
- **WHEN** 클라이언트가 `POST /save-to-storage`로 파일을 업로드한다
- **THEN** 시스템은 Supabase Storage에 저장하고 후속 처리 파이프라인에 진입시킨다

#### Scenario: Google Drive에 저장
- **WHEN** 클라이언트가 `POST /save-to-drive`로 요청한다
- **THEN** 시스템은 OAuth 자격 증명으로 Drive에 업로드한다

### Requirement: Google OAuth 자격 증명 관리
The system SHALL expose endpoints to start, check, and complete a Google OAuth flow whose tokens are persisted for later Drive operations.

#### Scenario: OAuth 흐름
- **WHEN** 클라이언트가 `GET /auth/google/url`, `GET /auth/google/status`, `POST /auth/google/save-token`, `POST /auth/google/callback`을 순차적으로 사용한다
- **THEN** 시스템은 인증 URL 발급, 현재 상태 보고, 토큰 저장, 콜백 처리를 차례로 수행한다

### Requirement: LLM 및 임베딩 프로바이더 선택
The system SHALL allow operators to choose between OpenAI, OpenRouter, and custom providers for both LLM and embedding calls, with optional routing via an LLM proxy.

#### Scenario: 프로바이더 구성
- **GIVEN** `MEMENTO_LLM_PROVIDER`와 `MEMENTO_EMBEDDING_PROVIDER`가 `openai|openrouter|custom` 중 하나로 설정된다
- **WHEN** 시스템이 LLM 또는 임베딩을 호출한다
- **THEN** 설정된 프로바이더의 자격 증명과 베이스 URL을 사용한다

#### Scenario: 임베딩 타임아웃
- **GIVEN** `EMBEDDING_TIMEOUT_SEC`가 설정되어 있다 (기본 60)
- **WHEN** 임베딩 호출이 해당 시간 안에 응답하지 않는다
- **THEN** 시스템은 호출을 중단하고 오류를 보고한다

### Requirement: 벡터 저장소 구성
The system SHALL persist vector data in a local Chroma store configured via `CHROMA_PERSIST_DIRECTORY` and `CHROMA_COLLECTION_NAME`, and SHALL allow operators to disable embedding persistence in Supabase via `SUPABASE_WRITE_EMBEDDING`.

#### Scenario: Chroma 컬렉션 사용
- **WHEN** 시스템이 인덱싱을 수행한다
- **THEN** 벡터는 `CHROMA_COLLECTION_NAME`(기본 `documents`) 컬렉션의 `CHROMA_PERSIST_DIRECTORY` 위치에 저장된다

### Requirement: 멀티테넌트 식별
The system SHALL scope reads and writes to a `tenant_id` provided in the request.

#### Scenario: 테넌트 누락 거부
- **WHEN** 검색/RAG/조회 요청에 `tenant_id`가 누락된다
- **THEN** 시스템은 400으로 거부한다

### Requirement: 오류 응답 정책
The system SHALL return predictable HTTP status codes for client-visible failure modes.

#### Scenario: 인증 / 부재 / 내부 실패
- **WHEN** Google 자원 접근이 인증되지 않거나(401), 문서가 부재하거나(404), LLM/벡터 검색/파싱이 실패한다(500)
- **THEN** 시스템은 해당 코드로 거부하고 내부 트레이스를 직접 노출하지 않는다

### Requirement: 운영 디버그 출입점
The system SHALL provide a debug endpoint that returns a memory snapshot.

#### Scenario: 메모리 스냅샷
- **WHEN** 운영자가 `GET /debug/memory`를 호출한다
- **THEN** 시스템은 현재 메모리 사용 스냅샷을 반환한다
