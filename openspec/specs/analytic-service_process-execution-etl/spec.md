# 프로세스 실행 데이터 ETL 명세

## Purpose
분석 서비스가 운영(OLTP) 스키마의 프로세스 실행 데이터를 OLAP 스타 스키마(`dw`)로 주기적으로 변환·적재하여, 대시보드와 분석 API가 조회할 수 있는 차원/팩트 데이터를 보장한다. 원본 테이블이 없거나 컬럼이 비어 있어도 파이프라인이 중단되지 않고 부분 적재를 완료하는 견고성을 보장한다.

## Requirements

### Requirement: OLAP 스키마 및 차원/팩트 테이블 생성
시스템은 ETL 실행 시 `dw` 스키마와 차원 테이블(`dim_date`, `dim_time`, `dim_tenant`, `dim_department`, `dim_user`, `dim_process_def`, `dim_activity`, `dim_tool` 등) 및 팩트 테이블(`fact_process_instance`, `fact_task`, `fact_usage`)을 존재하지 않을 때 SHALL 생성한다.

#### Scenario: 최초 실행 시 스키마 구성
- **GIVEN** `dw` 스키마가 존재하지 않는다
- **WHEN** 운영자가 ETL을 실행한다
- **THEN** 시스템은 `dw` 스키마와 모든 차원·팩트 테이블을 생성하고 날짜/시간 차원을 채운다

#### Scenario: 재실행 시 기존 스키마 보존
- **GIVEN** `dw` 스키마와 테이블이 이미 존재한다
- **WHEN** 운영자가 ETL을 다시 실행한다
- **THEN** 시스템은 테이블을 재생성하지 않고 데이터만 갱신한다

### Requirement: OLTP 프로세스 실행 데이터의 차원·팩트 적재
시스템은 운영 스키마(`public.tenants`, `public.users`, `public.proc_def`, `public.bpm_proc_inst`, `public.todolist` 등)의 프로세스 실행 데이터를 읽어 차원과 팩트 테이블에 SHALL 적재하며, 자연키 충돌 시 갱신(upsert)한다.

#### Scenario: 프로세스 인스턴스와 태스크 적재
- **GIVEN** 운영 스키마에 프로세스 인스턴스와 할 일(todolist) 데이터가 존재한다
- **WHEN** ETL이 실행된다
- **THEN** 시스템은 각 인스턴스를 `fact_process_instance`에, 각 태스크를 `fact_task`에 적재하고 태스크 건수·수행자 유형(agent/human)·처리시간을 집계한다

#### Scenario: 재실행 시 중복 없이 갱신
- **GIVEN** 동일한 인스턴스가 이전 실행에서 이미 적재되었다
- **WHEN** ETL이 다시 실행된다
- **THEN** 시스템은 동일 자연키 행을 새로 추가하지 않고 변경된 값으로 갱신한다

### Requirement: 누락 원본에 대한 견고한 부분 적재
시스템은 특정 원본 테이블이나 컬럼이 존재하지 않으면 해당 적재 단계를 건너뛰고 경고를 기록하되, 전체 ETL은 SHALL 계속 진행하여 완료한다.

#### Scenario: 원본 테이블 부재 시 건너뜀
- **GIVEN** 운영 스키마에 `public.usage` 테이블이 존재하지 않는다
- **WHEN** ETL이 실행된다
- **THEN** 시스템은 사용량 팩트 적재를 건너뛰고 나머지 차원·팩트 적재를 정상 완료한다

### Requirement: ETL 실행 트리거 및 상태 조회
시스템은 `POST /api/etl/run`으로 ETL을 백그라운드 실행하고, `GET /api/etl/status`로 실행 여부·마지막 실행 시각·마지막 결과를 SHALL 반환한다.

#### Scenario: 온디맨드 ETL 실행
- **WHEN** 클라이언트가 `POST /api/etl/run`을 호출한다
- **THEN** 시스템은 ETL을 백그라운드로 시작하고 접수 응답을 반환한다

#### Scenario: 실행 상태 조회
- **WHEN** 클라이언트가 `GET /api/etl/status`를 호출한다
- **THEN** 시스템은 `running`, `last_run`, `last_status` 필드를 포함한 상태를 반환한다

### Requirement: 주기적 ETL 스케줄러
시스템은 `POST /api/etl/scheduler/start`와 `POST /api/etl/scheduler/stop`으로 주기적 ETL 실행을 시작·중지할 수 있어야 하며(SHALL), 스케줄러 활성 여부를 상태에 노출한다.

#### Scenario: 스케줄러 시작과 중지
- **WHEN** 클라이언트가 스케줄러를 시작한다
- **THEN** 시스템은 정해진 간격으로 ETL을 반복 실행하고, 중지 요청 시 반복을 멈춘다
