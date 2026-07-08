# 대시보드 및 분석 지표 명세

## Purpose
분석 서비스가 OLAP 스타 스키마에 적재된 프로세스 실행 데이터를 기반으로, 대시보드 요약 통계와 다양한 분석 지표(Agent 대 Human 성능, 프로세스 성능, 병목, 재작업, 작업량, 월별 추이, 부서별 작업량)를 조회용 API로 제공함을 보장한다.

## Requirements

### Requirement: 대시보드 요약 통계 조회
시스템은 `GET /api/dashboard/summary`로 프로세스 인스턴스·태스크·사용량에 대한 요약 통계를 SHALL 반환한다. 인스턴스 요약에는 전체/완료/진행 건수와 평균 처리시간, 태스크 요약에는 전체 건수·평균 처리시간·평균 대기시간·수행자 유형별 건수가 포함된다.

#### Scenario: 요약 통계 반환
- **WHEN** 클라이언트가 `GET /api/dashboard/summary`를 호출한다
- **THEN** 시스템은 `instances`, `tasks`, `usage` 섹션을 포함한 집계 통계를 반환한다

#### Scenario: 데이터가 없을 때
- **GIVEN** 적재된 팩트 데이터가 없다
- **WHEN** 클라이언트가 요약을 호출한다
- **THEN** 시스템은 오류 없이 0 또는 null 집계값을 반환한다

### Requirement: Agent 대 Human 성능 비교
시스템은 `GET /api/analytics/agent-vs-human`으로 수행자 유형(AGENT/HUMAN)별 태스크 건수·완료 건수·처리시간 통계·오류율·재작업율·한번에 완료율(first-time-right)을 SHALL 반환한다.

#### Scenario: 수행자 유형별 성능 반환
- **WHEN** 클라이언트가 `GET /api/analytics/agent-vs-human`을 호출한다
- **THEN** 시스템은 AGENT와 HUMAN 각각에 대한 성능 지표 배열을 반환한다

### Requirement: 프로세스 성능 및 사이클 타임 분석
시스템은 `GET /api/analytics/process-performance`로 프로세스 정의별 인스턴스 건수·완료/진행 건수·평균/최소/최대/중앙값/95퍼센타일 사이클 타임·인스턴스당 평균 태스크 수를 SHALL 반환한다.

#### Scenario: 프로세스별 성능 반환
- **WHEN** 클라이언트가 `GET /api/analytics/process-performance`를 호출한다
- **THEN** 시스템은 각 프로세스 정의에 대한 사이클 타임 및 태스크 통계를 반환한다

### Requirement: 병목·재작업·작업량 분석
시스템은 활동별 병목(`GET /api/analytics/bottleneck`), 활동별 재작업(`GET /api/analytics/rework`), 부서/사용자별 작업량(`GET /api/analytics/workload`, `GET /api/dashboard/tasks-by-department`)을 조회하는 분석 지표를 SHALL 제공한다.

#### Scenario: 병목 활동 조회
- **WHEN** 클라이언트가 `GET /api/analytics/bottleneck`을 호출한다
- **THEN** 시스템은 처리·대기 시간이 큰 활동을 지표와 함께 반환한다

#### Scenario: 부서별 작업량 조회
- **WHEN** 클라이언트가 `GET /api/dashboard/tasks-by-department`를 호출한다
- **THEN** 시스템은 부서별 태스크 건수와 수행자 유형별 분포를 반환한다

### Requirement: 월별 처리량 추이 분석
시스템은 `GET /api/analytics/monthly-trend`로 연·월 단위 태스크 처리량과 수행자 유형별·완료 건수 추이를 SHALL 반환한다.

#### Scenario: 월별 추이 반환
- **WHEN** 클라이언트가 `GET /api/analytics/monthly-trend`를 호출한다
- **THEN** 시스템은 연·월별 태스크 건수(agent/human/completed 포함) 시계열을 반환한다

### Requirement: 인스턴스 목록 및 차원 조회
시스템은 `GET /api/instances`로 최근 프로세스 인스턴스 목록을, `GET /api/dimensions/{processes|users|activities|dates|departments}`로 필터용 차원 값을 SHALL 제공한다.

#### Scenario: 최근 인스턴스 목록 조회
- **WHEN** 클라이언트가 `GET /api/instances`를 호출한다
- **THEN** 시스템은 인스턴스별 프로세스명·상태·시작시각·처리시간·태스크 분포를 담은 목록을 반환한다
