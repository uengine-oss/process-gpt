# 프로세스 타임라인 명세

## Purpose
분석 서비스가 특정 프로세스 인스턴스의 태스크 실행 흐름을 시간 순 타임라인(Gantt 형태)으로 제공하여, 활동별 수행자·처리시간·대기시간·리드타임과 도구 사용 정보를 관찰할 수 있음을 보장한다.

## Requirements

### Requirement: 인스턴스별 태스크 타임라인 조회
시스템은 `GET /api/dashboard/timeline/{proc_inst_id}`로 지정한 프로세스 인스턴스의 태스크를 시간 순으로 정렬한 타임라인을 SHALL 반환한다. 각 항목은 활동명·상태·수행자·시작/종료 시각·처리시간을 포함한다.

#### Scenario: 타임라인 조회 성공
- **GIVEN** 적재된 프로세스 인스턴스가 존재한다
- **WHEN** 클라이언트가 `GET /api/dashboard/timeline/{proc_inst_id}`를 호출한다
- **THEN** 시스템은 태스크별 `activity_name`, `status`, `username`, `start_timestamp`, `end_timestamp`, `duration_sec`를 담은 타임라인 배열을 반환한다

#### Scenario: 태스크가 없는 인스턴스
- **GIVEN** 지정한 인스턴스에 적재된 태스크가 없다
- **WHEN** 클라이언트가 타임라인을 호출한다
- **THEN** 시스템은 오류 없이 빈 타임라인을 반환한다

### Requirement: 대기시간 및 수행자 유형 표시
시스템은 타임라인 각 항목에 직전 태스크로부터의 대기시간(`wait_from_prev_sec`)과 수행자 유형 플래그(`is_human`, `is_agent`)를 SHALL 포함하여, 흐름상의 지연과 자동화 여부를 구분할 수 있게 한다.

#### Scenario: 대기시간과 수행자 구분 제공
- **WHEN** 클라이언트가 타임라인을 호출한다
- **THEN** 각 항목은 이전 태스크 대비 대기시간과 human/agent 수행 여부, 사용한 도구(`tool_name`)를 포함한다
