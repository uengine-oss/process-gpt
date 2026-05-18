# Sandboxed Execution Environment Specification

## Purpose
MCP 클라이언트가 격리된 컨테이너 세션을 생성·관리하고, 그 안에서 파일 조작·셸/Node.js 코드 실행·외부 스토리지 업로드를 수행할 수 있도록 단일 MCP 도구 모음을 제공한다. 세션은 TTL로 자동 정리된다.

## Requirements

### Requirement: 격리된 세션 생성
The system SHALL provide a tool that creates a new isolated execution session on demand and SHALL return identifiers and metadata that allow subsequent operations on it.

#### Scenario: 세션 생성
- **WHEN** 클라이언트가 `create_session(ttl, image, session_id)`을 호출한다
- **THEN** 시스템은 격리된 컨테이너 환경을 기동하고 세션 식별자를 반환한다

#### Scenario: 기본 TTL
- **GIVEN** 호출 시 `ttl`이 생략된다
- **WHEN** 세션이 생성된다
- **THEN** 시스템은 600초의 기본 수명으로 세션을 생성한다

### Requirement: 세션 수명 관리
The system SHALL allow callers to list, inspect, extend, and delete sessions.

#### Scenario: 세션 목록
- **WHEN** 클라이언트가 `list_sessions()`를 호출한다
- **THEN** 시스템은 활성 세션 목록을 반환한다

#### Scenario: 상태 조회
- **WHEN** 클라이언트가 `get_session_status(session_id)`를 호출한다
- **THEN** 시스템은 해당 세션의 상태를 반환한다

#### Scenario: 수명 연장
- **WHEN** 클라이언트가 `extend_session(session_id, extra_seconds)`를 호출한다
- **THEN** 시스템은 TTL을 연장한다

#### Scenario: 명시적 삭제
- **WHEN** 클라이언트가 `delete_session(session_id)`를 호출한다
- **THEN** 시스템은 즉시 세션을 종료하고 리소스를 회수한다

#### Scenario: TTL 만료에 의한 자동 정리
- **GIVEN** 세션의 TTL이 만료되었다
- **WHEN** 시스템이 만료를 감지한다
- **THEN** 시스템은 해당 세션을 자동으로 종료한다

### Requirement: 파일 도구
The system SHALL allow callers to list, create, delete files in the session and to upload files to external storage.

#### Scenario: 파일 목록 (스트리밍)
- **WHEN** 클라이언트가 `list_files(session_id, path)`를 호출한다
- **THEN** 시스템은 디렉터리의 파일 목록을 스트리밍으로 반환한다

#### Scenario: 파일 생성/삭제
- **WHEN** 클라이언트가 `create_file(session_id, file_path, content)` 또는 `delete_file(session_id, file_path)`를 호출한다
- **THEN** 시스템은 세션 내 파일을 생성/삭제한다

#### Scenario: Supabase 업로드
- **GIVEN** Supabase 자격 증명과 버킷이 구성되어 있다
- **WHEN** 클라이언트가 `upload_file(session_id, source_path, destination_path, bucket, overwrite)`를 호출한다
- **THEN** 시스템은 파일을 Supabase Storage에 업로드한다

#### Scenario: 업로드 시 충돌 회피
- **WHEN** 동일 경로에 파일이 이미 존재하고 `overwrite`가 비활성이다
- **THEN** 시스템은 자동으로 유니크 경로를 생성하여 재시도한다

#### Scenario: Supabase 미설정
- **GIVEN** Supabase 자격 증명이 비어 있다
- **WHEN** 클라이언트가 업로드를 시도한다
- **THEN** 시스템은 안내 메시지와 함께 실패 응답을 반환한다

### Requirement: 코드 실행 도구
The system SHALL allow callers to run shell commands and Node.js code in the session and SHALL stream stdout/stderr back.

#### Scenario: 셸 실행 (스트리밍)
- **WHEN** 클라이언트가 `run_shell(session_id, command)`을 호출한다
- **THEN** 시스템은 명령 실행 결과를 스트림으로 반환한다

#### Scenario: Node.js 실행과 의존성 보장
- **WHEN** 클라이언트가 `run_node(session_id, code, ensure_dependencies)`를 호출한다
- **THEN** 시스템은 Node.js 코드를 실행하고 결과를 반환한다

### Requirement: 결과 응답 형식
The system SHALL return a structured object that allows callers to distinguish successful and failed invocations.

#### Scenario: 성공/실패 표시
- **WHEN** 도구 호출이 완료된다
- **THEN** 응답에는 성공 여부를 포함한 구조화된 필드가 포함된다 (예: `{"success": true, ...}` 또는 `{"success": false, "error": "..."}`)

### Requirement: 세션 부재 처리
The system SHALL reject operations targeted at a non-existent session.

#### Scenario: 세션 부재
- **WHEN** 클라이언트가 존재하지 않는 `session_id`로 도구를 호출한다
- **THEN** 시스템은 `{"success": false, "error": "Session not found"}` 응답을 반환한다

### Requirement: 환경 변수 구성
The system SHALL accept configuration via `POD_NAMESPACE`, `IN_CLUSTER`, `SUPABASE_URL`, `SUPABASE_KEY`, `SUPABASE_BUCKET`, `SUPABASE_PATH_PREFIX`.

#### Scenario: 클러스터 내부 vs 외부 동작
- **GIVEN** `IN_CLUSTER`가 참이다
- **WHEN** 시스템이 컨테이너 오케스트레이션 API에 접근한다
- **THEN** 시스템은 클러스터 내부 자격 증명을 사용한다

#### Scenario: 기본 네임스페이스와 버킷
- **GIVEN** 환경 변수가 생략된다
- **WHEN** 시스템이 세션을 생성하거나 파일을 업로드한다
- **THEN** 기본값(`POD_NAMESPACE=default`, `SUPABASE_BUCKET=files`, `SUPABASE_PATH_PREFIX=/pod_mcp`)을 사용한다
