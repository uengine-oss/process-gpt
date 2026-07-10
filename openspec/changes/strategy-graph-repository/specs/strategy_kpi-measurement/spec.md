# strategy_kpi-measurement — 다각적 KPI 측정과 그래프 반영

## ADDED Requirements

### Requirement: KPI를 정량·정성 방식으로 자동 측정할 수 있다
KPI는 측정 유형(`measure_type`)에 따라 자동 측정되어야 한다(SHALL): `instance_count`(연결 프로세스의 완료 인스턴스 건수), `avg_duration_hours`(완료 인스턴스 평균 처리시간), `form_value_sum`(완료 인스턴스의 지정 폼 필드 숫자값 합산 — 예: 계약 금액 총합), `survey_score`(프로세스 완료 시 발송된 설문 응답 평균 — 정성 평가), `manual`(수동 입력). `form_value_sum` 유형의 KPI는 합산할 폼 필드명(`form_field`)을 지정할 수 있어야 한다(SHALL). 자동 측정은 주기적으로 실행되며 `POST /api/measure/run`으로 즉시 실행할 수 있어야 한다(SHALL).

#### Scenario: 완료 건수 정량 측정
- **WHEN** 프로세스가 연결된 `instance_count` KPI에 대해 해당 프로세스의 완료 인스턴스가 3건인 상태에서 측정을 실행하면
- **THEN** KPI의 `current_value`가 3으로 갱신된다

#### Scenario: 폼 입력값 합산 정량 측정
- **WHEN** `form_value_sum` KPI에 `form_field`로 계약 금액 필드를 지정하고, 완료 인스턴스 2건의 해당 필드 값이 100과 200인 상태에서 측정을 실행하면
- **THEN** KPI의 `current_value`가 300으로 갱신된다

#### Scenario: 설문 기반 정성 측정
- **WHEN** `survey_score` KPI에 연결된 프로세스의 설문 응답이 제출된 뒤 측정이 실행되면
- **THEN** 응답 평점의 평균이 KPI의 `current_value`로 갱신된다

### Requirement: 측정 결과가 온톨로지 그래프와 측정 이력에 함께 반영된다
모든 측정 결과(자동/수동)는 그래프의 `KPI` 노드 속성(`current_value`, `last_measured_at`)에 반영되어야 하고(MUST), 관계형 측정 이력에 측정값·소스·시각이 기록되어야 한다(SHALL). `GET /api/kpis/{id}/measurements`는 측정 이력을 최신순으로 반환해야 한다(SHALL). 프로세스 실행 상태(완료 건수·실행 속도)가 KPI와 유기적으로 연결되도록, 측정 시점의 실행 집계가 `IMPACTS_KPI` 관계의 속성으로 갱신되어야 한다(SHALL).

#### Scenario: 측정 후 전략맵·이력 동시 반영
- **WHEN** 자동 측정이 실행된 뒤 전략맵(`GET /api/map`)과 측정 이력(`GET /api/kpis/{id}/measurements`)을 조회하면
- **THEN** 전략맵의 KPI `current_value`와 이력의 최신 기록이 같은 값으로 일치한다

#### Scenario: 수동 실적 입력과 달성률 계산
- **WHEN** 기준선 0, 목표 100인 KPI에 `POST /api/kpis/{id}/value`로 50을 입력한 뒤 전략맵을 조회하면
- **THEN** 해당 KPI의 `current_value`가 50, `achievement`가 50.0으로 반환되고 측정 이력에 `manual` 소스 기록이 추가된다

### Requirement: KPI 측정·설문 데이터는 관계형 테이블과 정합성을 유지한다
KPI 측정 이력과 설문 요청/응답 데이터는 관계형 테이블에 유지되어야 하며(SHALL), 설문 발행·응답 흐름(완료 인스턴스 감지 → 설문 워크아이템 발행 → 응답 수집)은 기존 API(`GET /api/surveys`, `GET /api/surveys/{id}`, `POST /api/surveys/{id}/respond`) 계약대로 동작해야 한다(MUST). KPI가 삭제되면 그 KPI의 측정 이력과 설문 요청도 함께 정리되어야 한다(SHALL).

#### Scenario: 설문 응답 즉시 재집계
- **WHEN** 설문 응답을 제출(`POST /api/surveys/{id}/respond`)하면
- **THEN** 응답이 저장되고 해당 `survey_score` KPI의 점수가 재집계되어 전략맵에 반영된다

#### Scenario: KPI 삭제 시 측정 이력 정리
- **WHEN** 측정 이력이 있는 KPI를 삭제한 뒤 `GET /api/kpis/{id}/measurements`를 호출하면
- **THEN** 해당 KPI의 측정 이력이 반환되지 않는다
