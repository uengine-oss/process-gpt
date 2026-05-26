# 프로세스 데이터 조회 명세

## Purpose
사용자가 자연어로 자신의 프로세스 실행 데이터를 조회하고, 프로세스 변수 정의로부터 SQL 스키마를 생성받는 능력을 보장한다.

## Requirements

### Requirement: 자연어 프로세스 데이터 조회
시스템은 `POST /process-data-query`로 자연어 `query`와 사용자 식별 정보를 받으면 조회 결과를 HTML 표 형태로 SHALL 반환한다.

#### Scenario: 데이터 조회 성공
- **GIVEN** 클라이언트가 `{input:{query, user_id, chat_room_id}}`를 제공하고 `user_id`는 사용자 이메일이다
- **WHEN** 클라이언트가 `POST /process-data-query`를 호출한다
- **THEN** 시스템은 조회 결과를 담은 HTML `<table>` 문자열을 반환한다

#### Scenario: 표로 만들 결과가 없음
- **GIVEN** 질의에 해당하는 데이터가 없다
- **WHEN** 클라이언트가 `POST /process-data-query`를 호출한다
- **THEN** 시스템은 표를 구성할 수 없을 때 빈 결과(`null`)를 반환한다

### Requirement: 프로세스 변수 SQL 스키마 생성
시스템은 `POST /process-var-sql`로 변수 이름과 해소 규칙을 받으면 해당 변수를 담을 수 있는 SQL 스키마 텍스트를 SHALL 반환한다.

#### Scenario: 변수 SQL 생성 성공
- **GIVEN** 클라이언트가 `{input:{var_name, resolution_rule}}`를 제공한다
- **WHEN** 클라이언트가 `POST /process-var-sql`을 호출한다
- **THEN** 시스템은 프로세스 정의에 기반한 CREATE TABLE 형태의 SQL 텍스트를 반환한다

### Requirement: 조회 범위의 테넌트 격리
시스템은 프로세스 데이터 조회를 요청 subdomain이 가리키는 테넌트 범위로 SHALL 한정한다.

#### Scenario: 테넌트별 데이터 조회 제한
- **GIVEN** 요청이 특정 테넌트 subdomain으로 들어온다
- **WHEN** 클라이언트가 프로세스 데이터 조회를 호출한다
- **THEN** 시스템은 해당 테넌트의 프로세스 정의와 인스턴스 데이터만 조회 대상으로 삼는다
