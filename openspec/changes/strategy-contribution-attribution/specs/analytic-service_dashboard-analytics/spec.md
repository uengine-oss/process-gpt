# 대시보드 및 분석 지표 명세

## ADDED Requirements

### Requirement: 전략 중요도 기준 성과·성장 기여도 대시보드 조회
시스템은 `GET /api/dashboard/contribution?tenant_id=`로 전략맵의 전략적 중요도 순으로 정렬된 성과·성장 기여도 요약을 SHALL 반환한다. 각 항목은 전략 목표를 기준으로, 그 목표에 기여한 성과자(사람·에이전트)의 실행 기반 기여도와, 그 목표에 연결된 스킬에 대한 사람의 기여(성장 기여) 이력을 함께 포함해야 한다(MUST). 사람과 에이전트는 `performer_type`(`HUMAN`|`AGENT`) 필드로 구분되어 같은 목록에 함께 포함되어야 한다(MUST).

#### Scenario: 중요도 순 기여도 대시보드 조회
- **WHEN** 클라이언트가 `GET /api/dashboard/contribution?tenant_id=`를 호출한다
- **THEN** 시스템은 전략 목표를 중요도 내림차순으로 정렬하고, 각 목표 아래 성과자별 기여도와 관련 스킬의 사람 기여 이력을 포함한 목록을 반환한다

#### Scenario: 특정 전략 목표로 범위를 좁힌 조회
- **WHEN** 클라이언트가 `strategy_id` 파라미터를 지정해 `GET /api/dashboard/contribution`을 호출한다
- **THEN** 시스템은 해당 전략 목표와 그 하위 범위에 대한 기여도·기여자 이력만 반환한다

#### Scenario: 데이터가 없을 때
- **GIVEN** 아직 기여도나 스킬 기여 이력이 적재되지 않았다
- **WHEN** 클라이언트가 `GET /api/dashboard/contribution`을 호출한다
- **THEN** 시스템은 오류 없이 빈 목록을 반환한다
