# 프로세스 정의 검색 명세

## Purpose
사용자가 자연어 질의로 시작하거나 참고할 프로세스 정의를 의미 기반으로 검색하는 능력을 보장한다.

## Requirements

### Requirement: 자연어 프로세스 정의 검색
시스템은 `POST /process-search` 또는 `POST /vision-process-search`로 자연어 `query`를 받으면 의미적으로 유사한 프로세스 정의 후보 목록을 SHALL 반환한다.

#### Scenario: 유사 프로세스 정의 검색 성공
- **GIVEN** 현재 테넌트에 프로세스 정의가 등록되어 있다
- **WHEN** 클라이언트가 `query`를 담아 `POST /process-search`를 호출한다
- **THEN** 시스템은 질의와 유사한 프로세스 정의 후보를 최대 3건까지 반환한다

#### Scenario: 검색 결과 없음
- **GIVEN** 질의와 유사한 프로세스 정의가 없거나 검색이 실패한다
- **WHEN** 클라이언트가 `POST /process-search`를 호출한다
- **THEN** 시스템은 `200` 상태와 빈 목록을 반환한다

### Requirement: 검색 범위의 테넌트 격리
시스템은 프로세스 정의 검색을 요청 subdomain이 가리키는 테넌트의 프로세스 정의로 SHALL 한정한다.

#### Scenario: 테넌트별 검색 범위 제한
- **GIVEN** 요청이 특정 테넌트 subdomain으로 들어온다
- **WHEN** 클라이언트가 프로세스 정의 검색을 호출한다
- **THEN** 시스템은 해당 테넌트의 프로세스 정의만 검색 대상으로 삼는다
