# 요청 유형 Top List 순위 명세

## Purpose
`instance-classifier` 서비스가 프로세스 정의별로 어떤 요청 유형이 얼마나 자주 발생하는지 **건수 기준 순위(Top List)** 로 제공하고, **기간(주/월/년/전체)** 으로 순위를 좁혀 볼 수 있는 능력을 보장한다. 순위 산정 단위는 인스턴스 건수이며, 기간 필터는 인스턴스 생성 시각(`occurred_at`)을 기준으로 한다.

## Requirements

### Requirement: 유형 순위 집계
시스템은 `GET /toplist` 요청에 대해 지정한 프로세스 정의의 유형별 인스턴스 건수를 내림차순으로 SHALL 반환한다.

#### Scenario: 전체 기간 순위 조회
- **GIVEN** 어떤 프로세스 정의에 분류된 인스턴스들이 있다
- **WHEN** 클라이언트가 `GET /toplist?proc_def_id=<id>`를 호출한다
- **THEN** 시스템은 각 유형의 `topic_name`, `count`, `pct`, `keywords`, `first_seen`, `last_seen`을 건수 내림차순으로 반환하고 `total`과 `noise_ratio`를 포함한다

#### Scenario: 미분류 유형 구분
- **WHEN** 시스템이 순위를 반환한다
- **THEN** 미분류(신종 후보) 유형은 `is_noise = true`로 표시되어 실제 유형과 구분된다

### Requirement: 기간별 순위 필터
시스템은 `GET /toplist`의 `period` 파라미터로 집계 대상을 최근 기간으로 제한 SHALL 하며, 값은 `all`, `week`, `month`, `year` 를 지원한다. `week`/`month`/`year`는 각각 최근 7일/30일/365일(롤링)을 의미하고 `all`은 제한 없음을 의미한다.

#### Scenario: 최근 1주 순위
- **GIVEN** 인스턴스들의 생성 시각이 여러 날에 걸쳐 있다
- **WHEN** 클라이언트가 `GET /toplist?proc_def_id=<id>&period=week`를 호출한다
- **THEN** 시스템은 최근 7일 이내(`occurred_at` 기준) 인스턴스만으로 순위와 비율을 다시 계산해 반환한다

#### Scenario: 기간 미지정 시 기본값
- **WHEN** 클라이언트가 `period`를 생략한다
- **THEN** 시스템은 전체 기간(`all`)으로 집계한다

### Requirement: 유형 상세 인스턴스 조회
시스템은 `GET /topics/{proc_def_id}/{topic_id}/instances` 요청에 대해 특정 유형에 속한 인스턴스 목록을 SHALL 반환하며, 같은 `period` 필터를 지원 SHALL 한다.

#### Scenario: 유형 드릴다운(기간 적용)
- **WHEN** 클라이언트가 `GET /topics/<def>/<topic>/instances?period=week&limit=<n>`를 호출한다
- **THEN** 시스템은 그 유형에 속하면서 최근 7일 이내인 인스턴스들의 요청 내용과 발생 시각을 최신순으로 반환한다

### Requirement: 정의 화면의 Top 3 요약
사용자는 프로세스 정의 상세 화면 우측에서 상위 3개 요청 유형을 비율에 비례한 길이의 막대로 확인할 수 있어야 SHALL 하며, 기본 집계 기준은 최근 1주 이다. 막대는 값이 커질수록 길어지고 비율 수치가 함께 표시된다.

#### Scenario: Top 3 막대 요약
- **GIVEN** 사용자가 요청 유형이 분류된 프로세스 정의 상세 화면을 연다
- **WHEN** 화면이 열린다
- **THEN** 우측에 최근 1주 기준 상위 3개 유형이 유형명과 비율(%)로 표시되고, 각 막대 길이는 해당 유형의 비율에 비례한다

#### Scenario: 분석 화면으로 이동
- **WHEN** 사용자가 Top 3 요약의 "자세히" 를 선택한다
- **THEN** 시스템은 요청 Top List 분석 화면으로 이동한다

### Requirement: 분석 화면
사용자는 요청 Top List 분석 화면에서 프로세스 정의를 선택하고, 기간(전체/주/월/년)을 전환하며, 순위를 목록 또는 트리맵으로 볼 수 있어야 SHALL 한다.

#### Scenario: 분석 화면에서 기간 전환
- **GIVEN** 사용자가 요청 Top List 분석 화면을 연다
- **WHEN** 사용자가 기간을 `주`로 전환한다
- **THEN** 순위와 비율이 최근 1주 기준으로 갱신된다

#### Scenario: 트리맵 보기
- **WHEN** 사용자가 트리맵 보기로 전환한다
- **THEN** 화면은 유형별 비율을 면적으로 보여주고 각 영역에 유형명·건수·비율을 표시하며, 대표 키워드와 최근 발생 정보를 함께 제공한다
