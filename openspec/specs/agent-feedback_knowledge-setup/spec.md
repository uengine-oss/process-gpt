# 에이전트 초기 지식 셋팅 명세

## Purpose
클라이언트 또는 폴링 잡이 에이전트를 지정하면, 시스템이 그 에이전트의 목표(goal)와 페르소나(persona)를 분석하여 규칙(DMN_RULE)·절차(SKILL)·선호도(MEMORY) 형태의 초기 지식을 자동 생성하고, 셋팅 진행 상태를 추적 가능하게 보장하는 능력을 다룬다.

## Requirements

### Requirement: 초기 지식 셋팅 API
시스템은 `POST /setup-agent-knowledge` 요청을 받으면 지정된 에이전트의 목표와 페르소나를 분석하여 초기 지식을 생성하고, 처리 결과를 반환해야 한다. 요청 본문은 `agent_id`(필수), `goal`(선택), `persona`(선택)를 가지며, 응답은 `output`, `intermediate_steps`, `agent_id`, `used_tools`, `did_commit`, `commit_successes`를 SHALL 포함한다.

#### Scenario: 초기 지식 셋팅 성공
- **GIVEN** 존재하는 `agent_id`와 사용 가능한 `goal`이 확보된다
- **WHEN** 클라이언트가 `POST /setup-agent-knowledge`를 호출한다
- **THEN** 시스템은 초기 지식 생성 결과와 함께 `did_commit`, `commit_successes`를 포함한 응답을 반환한다
- **AND** 해당 에이전트의 셋팅 상태를 `DONE`으로 기록한다

#### Scenario: 요청에 goal/persona가 없는 경우 보완
- **GIVEN** 요청 본문에 `goal` 또는 `persona`가 생략되었다
- **WHEN** 클라이언트가 `POST /setup-agent-knowledge`를 호출한다
- **THEN** 시스템은 에이전트 정보에 등록된 `goal`/`persona` 값으로 누락된 항목을 보완하여 처리한다

#### Scenario: 존재하지 않는 에이전트
- **GIVEN** 요청의 `agent_id`에 해당하는 에이전트가 없다
- **WHEN** 클라이언트가 `POST /setup-agent-knowledge`를 호출한다
- **THEN** 시스템은 `404` 응답을 반환한다

#### Scenario: 목표를 확보할 수 없는 경우
- **GIVEN** 요청과 에이전트 정보 어디에도 사용 가능한 `goal`이 없다
- **WHEN** 클라이언트가 `POST /setup-agent-knowledge`를 호출한다
- **THEN** 시스템은 `400` 응답을 반환한다

#### Scenario: 처리 오류 또는 미커밋
- **GIVEN** 초기 지식 셋팅 처리 중 오류가 발생하거나 실제 저장(commit)이 수행되지 않는다
- **WHEN** 클라이언트가 `POST /setup-agent-knowledge`를 호출한다
- **THEN** 시스템은 `500` 응답을 반환한다
- **AND** 해당 에이전트의 셋팅 상태를 `FAILED`로 기록한다

### Requirement: 셋팅 대상 자동 폴링
시스템은 목표가 등록되어 있으면서 아직 초기 지식 셋팅 로그가 없는 에이전트를 폴링 주기마다 한 건씩 자동으로 셋팅해야 하며, 이미 셋팅 로그가 있는 에이전트는 폴링 대상에서 SHALL 제외한다.

#### Scenario: 미셋팅 에이전트 자동 셋팅
- **GIVEN** `goal`이 비어 있지 않고 셋팅 로그가 없는 에이전트가 존재한다
- **WHEN** 폴링 주기가 도래한다
- **THEN** 시스템은 해당 에이전트 한 건에 대해 초기 지식 셋팅을 수행한다

#### Scenario: 이미 셋팅된 에이전트 제외
- **GIVEN** 에이전트에 대한 초기 지식 셋팅 로그가 이미 존재한다
- **WHEN** 폴링 주기가 도래한다
- **THEN** 시스템은 해당 에이전트를 셋팅 대상으로 다시 선택하지 않는다

#### Scenario: 목표 없는 폴링 대상 처리
- **GIVEN** 폴링으로 선택된 에이전트에 사용 가능한 `goal`이 없다
- **WHEN** 시스템이 초기 지식 셋팅을 시도한다
- **THEN** 시스템은 셋팅을 건너뛰고 해당 에이전트의 셋팅 상태를 `FAILED`로 기록한다

### Requirement: 셋팅 상태 추적
시스템은 초기 지식 셋팅의 진행 상태를 에이전트별로 추적해야 하며, 셋팅 시작 시 `STARTED`, 성공 종료 시 `DONE`, 실패 시 `FAILED`로 SHALL 기록한다. 상태는 API 경로와 폴링 경로 모두에서 동일하게 갱신된다.

#### Scenario: 셋팅 시작 시 상태 기록
- **GIVEN** API 요청 또는 폴링으로 초기 지식 셋팅이 트리거된다
- **WHEN** 시스템이 셋팅 처리를 시작한다
- **THEN** 시스템은 해당 에이전트의 셋팅 상태를 `STARTED`로 기록한다

#### Scenario: 셋팅 결과에 따른 상태 갱신
- **GIVEN** 에이전트 초기 지식 셋팅 처리가 종료되었다
- **WHEN** 처리가 오류 없이 완료되면
- **THEN** 시스템은 셋팅 상태를 `DONE`으로 갱신하고, 오류가 있으면 `FAILED`로 갱신한다

### Requirement: 초기 지식 생성 범위
시스템은 에이전트의 목표와 페르소나에서 도출된 구체적인 조건-결과 규칙(DMN_RULE), 단계별 절차(SKILL), 선호도·맥락(MEMORY)을 초기 지식으로 생성해야 하며, 목표나 페르소나 자체의 단순 설명을 그대로 지식으로 SHALL 저장하지 않는다. 생성된 지식의 저장·병합·변경 이력 계약은 `agent-feedback_knowledge-commit` 명세를 따른다.

#### Scenario: 목표/페르소나 기반 지식 도출
- **GIVEN** 에이전트에 목표와 페르소나가 주어진다
- **WHEN** 시스템이 초기 지식을 생성한다
- **THEN** 시스템은 목표/페르소나에서 도출한 규칙·절차·선호도를 적절한 저장소에 저장한다
- **AND** 목표/페르소나 문장 자체의 설명은 지식으로 저장하지 않는다
