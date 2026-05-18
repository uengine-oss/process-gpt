# Skill Library Lookup Specification

## Purpose
MCP 클라이언트가 사용자 작업 설명에 기반해 적절한 스킬을 검색하고 그 스킬 문서/스크립트/참고자료를 열람할 수 있도록, 외부 스킬 저장소를 통합 인덱싱한 라이브러리를 제공한다. 가벼운 프론트엔드가 즉시 응답하고, 무거운 백엔드 검색 엔진은 백그라운드 로드된다.

## Requirements

### Requirement: 빠른 도구 광고와 백엔드 지연 로드
The system SHALL register its MCP tools immediately at startup so that callers can list them within seconds, while the heavy backend index is loaded asynchronously in the background.

#### Scenario: 즉시 시작 시 도구 표시
- **WHEN** MCP 클라이언트가 서버 시작 직후 도구 목록을 조회한다
- **THEN** 시스템은 5초 이내에 도구 목록을 반환하고, 첫 호출 시 백엔드 로드 진행 중임을 경고로 노출할 수 있다

#### Scenario: 백엔드 로드 실패에도 프론트엔드 유지
- **WHEN** 백엔드 인덱스 로드가 실패한다
- **THEN** 프론트엔드는 계속 동작하며 사용자에게 경고를 노출한다

### Requirement: 스킬 검색
The system SHALL expose a tool that takes a free-form task description and returns the most relevant skills with relevance scores.

#### Scenario: 검색 응답 형식
- **WHEN** 클라이언트가 `find_helpful_skills(task_description, max_results)`를 호출한다
- **THEN** 시스템은 `[{skill_id, name, description, relevance_score}]` 형태의 목록을 반환한다

#### Scenario: 결과 없음
- **WHEN** 검색 결과가 임계치에 미달한다
- **THEN** 시스템은 빈 목록을 반환한다

### Requirement: 스킬 문서/자산 조회
The system SHALL allow callers to read individual files inside a skill (scripts, data, references).

#### Scenario: 파일 조회
- **WHEN** 클라이언트가 `read_skill_document(skill_id, file_path)`를 호출한다
- **THEN** 시스템은 해당 파일의 본문 또는 메타를 반환한다

### Requirement: 스킬 목록 조회 (디버깅용)
The system SHALL allow callers to list all known skills, optionally filtered by a search pattern.

#### Scenario: 전체 목록
- **WHEN** 클라이언트가 `list_skills(search_pattern)`를 호출한다
- **THEN** 시스템은 해당 패턴과 일치하는 스킬 목록을 반환한다 (패턴 비어 있으면 전체)

### Requirement: 다중 스킬 소스 통합
The system SHALL combine skills from configured GitHub repositories and a local directory into a single searchable corpus.

#### Scenario: GitHub과 로컬 소스 동시 사용
- **GIVEN** 설정 파일이 GitHub 저장소와 로컬 디렉터리를 모두 `skill_sources`에 포함한다
- **WHEN** 시스템이 인덱싱을 수행한다
- **THEN** 두 소스의 스킬이 모두 검색 대상에 포함된다

### Requirement: 캐시와 외부 호출 제한
The system SHALL cache external skill content locally to reduce repeated downloads and SHALL surface partial failures rather than aborting indexing.

#### Scenario: 로컬 캐시 사용
- **WHEN** 외부 GitHub 소스에서 콘텐츠를 가져온 적이 있다
- **THEN** 동일 콘텐츠 재요청은 로컬 캐시에서 응답한다

#### Scenario: 일부 스킬 로드 실패
- **WHEN** 일부 스킬 로드가 실패한다
- **THEN** 시스템은 오류를 누적하고 가능한 스킬들로 인덱싱을 계속한다

### Requirement: CLI 설정 인자
The system SHALL accept command-line arguments to specify a configuration file or print an example configuration.

#### Scenario: 설정 적용
- **WHEN** 사용자가 `--config <config.json>`로 기동한다
- **THEN** 시스템은 해당 파일의 `skill_sources`, `top_k`, `max_content_chars`, `models.embedding_model` 등을 적용한다

#### Scenario: 예시 설정 출력
- **WHEN** 사용자가 `--example-config`로 기동한다
- **THEN** 시스템은 기본 설정을 표준 출력으로 인쇄한 뒤 종료한다
