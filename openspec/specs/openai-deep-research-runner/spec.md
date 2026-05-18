# OpenAI Deep Research Runner Specification

## Purpose
ProcessGPT 작업 큐에서 `agent_orch='openai-deep-research'` 작업을 클레임하여, OpenAI 웹 검색 도구 기반 심층 연구 파이프라인으로 결과를 만들고, 드래프트/최종 산출을 표준 위치에 저장하는 워커를 제공한다. 워커 비정상 종료에도 큐 폴링은 지속된다.

## Requirements

### Requirement: 자신의 작업 폴링과 클레임
The system SHALL poll for tasks targeted at `agent_orch='openai-deep-research'` approximately every seven seconds and SHALL claim eligible rows using a dedicated RPC.

#### Scenario: 정상 작업 클레임
- **GIVEN** `todolist`에 `status='IN_PROGRESS'`, `agent_orch='openai-deep-research'`, `draft_status IS NULL` 인 행이 존재한다
- **WHEN** 워커가 RPC `openai_deep_fetch_pending_task` 또는 테넌트 변형 `_dev`를 호출한다
- **THEN** 시스템은 그 행을 단독으로 반환하고 `draft_status='STARTED'`로 갱신한다

#### Scenario: 멀티테넌트 환경 한정 폴링
- **GIVEN** `ENV='dev'`이고 `POLLING_TENANT_ID`가 설정되어 있다
- **WHEN** 워커가 폴링한다
- **THEN** 반환되는 작업은 모두 해당 테넌트로 한정된다

### Requirement: 진행 중 상태 가시화
The system SHALL update task columns so that observers can see progress and final results from outside the worker.

#### Scenario: 컬럼 전이와 최종 저장
- **WHEN** 워커가 작업을 시작·완료한다
- **THEN** `draft_status`는 `NULL → STARTED → COMPLETED`로, 산출은 `draft`(중간) 및 `output`(최종) 필드에 저장된다

### Requirement: 워커 비정상 종료에 대한 안전성
The system SHALL ensure that an abnormal worker exit on a single task does not stop subsequent polling.

#### Scenario: 단일 작업 실패 후 진행
- **WHEN** 한 작업의 처리 프로세스가 비정상 종료된다
- **THEN** 메인 폴링은 계속되고, 다음 주기에 다른 작업을 클레임 시도한다

### Requirement: 초기화 실패의 즉시 보고
The system SHALL fail fast on startup when required database connectivity is not satisfied.

#### Scenario: DB 초기화 실패
- **GIVEN** Supabase 자격 증명이 잘못되었거나 RPC가 부재하다
- **WHEN** 서버가 기동된다
- **THEN** 서버는 시작에 실패하고 운영자가 인식 가능한 오류를 보고한다

### Requirement: 일시적 실패의 재시도
The system SHALL retry transient database errors with a small number of attempts and a short exponential backoff before surfacing the error.

#### Scenario: DB 일시 오류
- **WHEN** 데이터베이스 호출이 일시적으로 실패한다
- **THEN** 시스템은 최대 3회 재시도와 약 0.8초의 백오프를 적용한 뒤에도 실패하면 작업 단위 오류로 보고한다

### Requirement: 환경 변수 계약
The system SHALL accept configuration via `OPENAI_API_KEY`, `SUPABASE_URL`, `SUPABASE_KEY`, `ENV`, `POLLING_TENANT_ID`, and `PORT`.

#### Scenario: 포트와 환경 설정
- **GIVEN** `PORT`(기본 `8000`)와 `ENV`가 설정된다
- **WHEN** 서버가 기동된다
- **THEN** 서버는 지정 포트에서 수신하고, `ENV` 값에 따라 테넌트 한정 폴링을 적용한다
