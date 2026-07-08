# 피벗 다차원 분석 명세

## Purpose
분석 서비스가 사용자가 선택한 행 차원·열 차원·측정값·집계함수·필터에 따라 태스크 팩트 데이터를 동적으로 집계한 피벗 결과를 제공함을 보장한다. 생성된 SQL을 함께 노출하여 결과의 투명성을 보장한다.

## Requirements

### Requirement: 동적 피벗 집계
시스템은 `POST /api/pivot`으로 행 차원(`rows`), 열 차원(`columns`), 측정값·집계함수(`values`), 필터(`filters`)를 받아 태스크 팩트를 동적으로 집계한 결과를 SHALL 반환한다.

#### Scenario: 행 차원과 측정값으로 집계
- **GIVEN** 클라이언트가 `{rows, columns, values:[{field, aggregation, alias}], filters}`를 제공한다
- **WHEN** 클라이언트가 `POST /api/pivot`을 호출한다
- **THEN** 시스템은 선택한 차원으로 그룹화하고 지정한 집계함수(COUNT/SUM/AVG/MAX/MIN)를 적용한 결과 행 배열을 반환한다

#### Scenario: 필터 적용 집계
- **GIVEN** 클라이언트가 특정 연도·수행자 유형 등의 필터를 지정한다
- **WHEN** 피벗을 호출한다
- **THEN** 시스템은 필터 조건에 해당하는 태스크만 집계 대상으로 삼는다

### Requirement: 생성 SQL 투명성
시스템은 피벗 응답에 실제 실행된 집계 SQL 문자열을 SHALL 함께 포함하여, 사용자가 결과의 근거 쿼리를 확인할 수 있게 한다.

#### Scenario: 응답에 SQL 포함
- **WHEN** 클라이언트가 피벗을 호출한다
- **THEN** 응답은 결과 행과 함께 실행된 `sql` 문자열, 결과 행 수(`total_rows`)를 포함한다

### Requirement: 필수 파라미터 검증
시스템은 피벗 요청에 측정값(`values`)이 누락되면 요청을 거부하고 검증 오류를 SHALL 반환한다.

#### Scenario: 측정값 누락 시 오류
- **GIVEN** 요청에 `values` 필드가 없다
- **WHEN** 클라이언트가 `POST /api/pivot`을 호출한다
- **THEN** 시스템은 422 검증 오류로 필수 필드 누락을 알린다
