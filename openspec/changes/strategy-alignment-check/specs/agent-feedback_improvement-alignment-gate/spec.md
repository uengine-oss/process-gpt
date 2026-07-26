# agent-feedback_improvement-alignment-gate — 개선 제안 승인 전 전략 정합성 게이트

## ADDED Requirements

### Requirement: 개선 제안 생성 시 전략 정합성 확인이 수행된다
시스템은 SKILL 또는 PROCESS_DEFINITION target의 개선 제안이 승인 가능한 상태로 노출되기 전에, 제안 내용을 근거로 전략 정합성 조회를 SHALL 수행하고 그 결과를 제안 데이터에 SHALL 기록해야 한다. 정합성 조회 실패는 제안 생성 자체를 막지 않으며, 이 경우 확인 불가 사실이 근거로 SHALL 기록되어야 한다.

#### Scenario: SKILL target 제안에 텍스트 기반 근거 기록
- **WHEN** 피드백 배치가 SKILL target으로 분류되어 제안이 생성되면
- **THEN** 생성된 제안에 제안 내용 기반 정합성 조회 결과(관련 전략 목표·KPI 후보 또는 "관련 항목 없음")가 기록된다

#### Scenario: PROCESS_DEFINITION target 제안에 기존 연결과 신규 후보가 함께 기록됨
- **WHEN** 이미 KPI와 연결된 프로세스에 대한 피드백 배치가 PROCESS_DEFINITION target으로 분류되어 제안이 생성되면
- **THEN** 생성된 제안에 대상 프로세스의 기존 전략 연결과 제안 내용 기반 신규 후보가 구분되어 기록된다

#### Scenario: 정합성 조회 서비스 호출 실패
- **WHEN** 정합성 조회가 의존하는 서비스가 응답하지 않는 상태에서 제안이 생성되면
- **THEN** 제안은 정상적으로 생성되고, 정합성 확인을 수행하지 못했다는 사실이 근거로 기록된다

### Requirement: 승인자에게 정합성 근거가 노출된다
시스템은 제안 목록 조회(`GET /feedback-proposals`) 응답에 각 target의 정합성 확인 결과를 SHALL 포함해, 승인자가 승인/거절 판단 전에 근거를 확인할 수 있게 해야 한다.

#### Scenario: 제안 조회 시 정합성 근거 포함
- **WHEN** 승인자가 제안 목록을 조회하면
- **THEN** 각 SKILL/PROCESS_DEFINITION target에 정합성 확인 결과(관련 전략 요소 또는 "관련 항목 없음" 또는 확인 불가)가 포함되어 반환된다

#### Scenario: 정합성 근거가 없는 제안에 대한 명시적 표시
- **WHEN** 승인자가 정합성 확인 결과가 "관련 항목 없음"인 제안을 조회하면
- **THEN** 관련 전략 요소를 찾지 못했다는 사실이 명시적으로 표시된다

### Requirement: DMN_RULE target은 정합성 확인 대상에서 제외된다
시스템은 DMN_RULE target에 대해서는 전략 정합성 조회를 수행하지 않아야 한다(MUST NOT).

#### Scenario: DMN_RULE target만 있는 제안
- **WHEN** 피드백 배치가 DMN_RULE target으로만 분류되면
- **THEN** 해당 제안에 대해 전략 정합성 조회가 수행되지 않고, DMN_RULE target에는 정합성 근거가 기록되지 않는다
