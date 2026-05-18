# BPMN Document Extraction Specification

## Purpose
사용자가 업로드한 PDF 문서를 분석해 BPMN 2.0 프로세스 정의, DMN 규칙, 태스크별 스킬 마크다운, Neo4j 그래프 시각화를 산출하는 REST API와 작업 추적 채널을 제공한다. 사용자는 업로드 → 작업 시작 → 진행 추적 → 결과 다운로드 흐름으로 변환물을 활용한다.

## Requirements

### Requirement: 파일 업로드와 작업 등록
The system SHALL accept document uploads and SHALL return a job identifier that uniquely tracks the conversion.

#### Scenario: PDF 업로드
- **WHEN** 클라이언트가 `POST /api/upload`로 파일을 전송한다
- **THEN** 시스템은 `uploaded` 상태의 작업을 생성하고 `job_id`를 반환한다

### Requirement: 변환 작업 실행
The system SHALL begin processing for a specific job upon explicit request and SHALL transition its status accordingly.

#### Scenario: 처리 시작
- **WHEN** 클라이언트가 `POST /api/process/{job_id}`를 호출한다
- **THEN** 작업은 `processing` 상태로 전이하고, 정상 종료 시 `completed`로, 실패 시 `error`로 전이한다

#### Scenario: 이미 진행 중인 작업 재시작 거부
- **WHEN** 이미 진행 중인 작업에 대해 재시작 요청이 들어온다
- **THEN** 시스템은 400으로 거부한다

### Requirement: 작업 상태 조회와 스트리밍
The system SHALL allow clients to poll job status and SHALL provide a server-sent event stream of progress.

#### Scenario: 단일 폴링
- **WHEN** 클라이언트가 `GET /api/jobs/{job_id}`를 호출한다
- **THEN** 시스템은 현재 상태와 진행 정보를 반환한다

#### Scenario: 실시간 스트림
- **WHEN** 클라이언트가 `GET /api/jobs/{job_id}/stream`을 호출한다
- **THEN** 시스템은 SSE로 단계별 진행 이벤트를 전송한다

### Requirement: 결과 산출 조회
The system SHALL expose endpoints to list extracted processes and to fetch their detail, graph, and downstream entities.

#### Scenario: 프로세스 목록과 상세
- **WHEN** 클라이언트가 `GET /api/processes` 또는 `GET /api/processes/{proc_id}`를 호출한다
- **THEN** 시스템은 각각 목록과 상세 정보를 반환한다

#### Scenario: 그래프 시각화
- **WHEN** 클라이언트가 `GET /api/processes/{proc_id}/graph`를 호출한다
- **THEN** 시스템은 Neo4j 기반 노드/엣지 시각화 데이터를 반환한다

#### Scenario: 엔티티 목록
- **WHEN** 클라이언트가 `GET /api/tasks`, `GET /api/roles`, `GET /api/decisions`를 호출한다
- **THEN** 시스템은 추출된 각 엔티티 목록을 반환한다

### Requirement: 산출 파일 다운로드
The system SHALL provide endpoints to download the generated BPMN and DMN files.

#### Scenario: 파일 다운로드
- **WHEN** 클라이언트가 `GET /api/files/bpmn` 또는 `GET /api/files/dmn`을 호출한다
- **THEN** 시스템은 산출 파일 본문을 반환한다

### Requirement: 산출 종류와 표준 명명
The system SHALL produce a fixed set of artifacts for each successful job: a BPMN 2.0 XML file, a DMN decision file, per-task skill markdown documents, and Neo4j nodes for processes/tasks/roles/decisions/skills/evidence.

#### Scenario: 산출 종류 보장
- **GIVEN** 작업이 `completed` 상태로 종료되었다
- **WHEN** 운영자가 결과를 점검한다
- **THEN** `process.bpmn`, `decisions.dmn`, `*.skill.md` 파일과 Neo4j 그래프가 함께 존재한다

### Requirement: 그래프 초기화
The system SHALL provide an administrative endpoint to clear the Neo4j graph.

#### Scenario: 그래프 초기화 요청
- **WHEN** 운영자가 `POST /api/neo4j/clear`를 호출한다
- **THEN** 시스템은 Neo4j 그래프 데이터를 초기화한다

### Requirement: OCR 구성
The system SHALL allow operators to enable OCR for scanned PDFs and to choose between supported OCR engines.

#### Scenario: OCR 엔진 선택
- **GIVEN** `OCR_ENGINE`이 `openai_vision` 또는 `synap`로 설정되어 있고 `ENABLE_OCR`이 활성이다
- **WHEN** 시스템이 스캔된 PDF를 처리한다
- **THEN** 지정된 엔진을 통해 텍스트를 추출한다

### Requirement: Neo4j 연결 의존성 표시
The system SHALL surface Neo4j connectivity through its readiness so that operators can detect outages.

#### Scenario: Neo4j 부재
- **GIVEN** Neo4j가 가용하지 않다
- **WHEN** 운영자가 가동 상태를 확인한다
- **THEN** 시스템은 비정상 상태로 응답한다

### Requirement: 외부 LLM과 Memento 통합
The system SHALL use a configured LLM for entity extraction and skill generation and SHALL optionally use Memento for knowledge retrieval.

#### Scenario: LLM과 Memento 활성
- **GIVEN** `OPENAI_API_KEY`(또는 `LLM_BASE_URL`/`LLM_MODEL` 조합) 및 `MEMENTO_URL`이 설정되어 있다
- **WHEN** 시스템이 변환 파이프라인을 실행한다
- **THEN** 시스템은 LLM 호출과 Memento 검색을 조합해 산출을 만든다

### Requirement: 오류 응답 정책
The system SHALL return predictable HTTP status codes for client-visible failure modes.

#### Scenario: 부재 / 변환 실패 / 타임아웃
- **WHEN** 자원이 부재(404), 변환 입력이 잘못됨(400), LLM/OCR이 시간 초과(타임아웃에 따른 오류 응답)된다
- **THEN** 시스템은 각각의 코드와 사용자 가시 메시지로 응답한다
