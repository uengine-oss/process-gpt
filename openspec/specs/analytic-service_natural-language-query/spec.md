# 자연어 질의(Text2SQL) 명세

## Purpose
분석 서비스가 사용자의 자연어 질문을 OLAP 스키마에 대한 SQL로 변환·실행하고, 실행 결과와 AI 설명을 제공함을 보장한다. 스키마 정보 조회와 직접 SQL 실행 경로도 함께 제공한다.

## Requirements

### Requirement: 자연어 질문의 SQL 변환 및 실행
시스템은 `POST /api/query/natural`로 자연어 `question`을 받으면 LLM 기반 Text2SQL로 SQL을 생성·실행하고 결과와 설명을 SHALL 반환한다.

#### Scenario: 자연어 질의 성공
- **GIVEN** 클라이언트가 `{question}`을 제공한다
- **WHEN** 클라이언트가 `POST /api/query/natural`을 호출한다
- **THEN** 시스템은 생성된 SQL, 실행 결과 행, 결과에 대한 설명을 포함한 응답을 반환한다

#### Scenario: 질의 처리 실패
- **GIVEN** 자연어 질문을 유효한 SQL로 변환하거나 실행할 수 없다
- **WHEN** 클라이언트가 자연어 질의를 호출한다
- **THEN** 시스템은 400 오류와 실패 원인을 반환한다

### Requirement: OLAP 스키마 정보 제공
시스템은 `GET /api/schema`로 `dw` 스키마의 테이블·컬럼·타입 정보를 텍스트 형태로 SHALL 반환하여, 자연어 질의의 컨텍스트와 사용자 참조를 지원한다.

#### Scenario: 스키마 조회
- **WHEN** 클라이언트가 `GET /api/schema`를 호출한다
- **THEN** 시스템은 각 테이블과 컬럼, NULL 허용 여부를 담은 스키마 설명 텍스트를 반환한다

### Requirement: 직접 SQL 실행
시스템은 `POST /api/query/sql`로 전달된 SQL을 실행하고 결과 행과 행 수를 SHALL 반환하며, 실행 오류 시 오류 메시지를 반환한다.

#### Scenario: 직접 SQL 실행 성공
- **GIVEN** 클라이언트가 `{sql}`을 제공한다
- **WHEN** 클라이언트가 `POST /api/query/sql`을 호출한다
- **THEN** 시스템은 `results`와 `total_rows`를 포함한 응답을 반환한다
