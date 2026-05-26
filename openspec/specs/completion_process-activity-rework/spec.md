# 프로세스 활동 재작업 명세

## Purpose
운영자가 이미 완료된 프로세스 활동을 다시 수행 대상으로 식별하고, 선택한 활동들의 재작업을 시작하며, 이전 자동 작업을 되돌리는 보상 코드가 준비되도록 하는 능력을 보장한다.

## Requirements

### Requirement: 재작업 가능 활동 조회
시스템은 `POST /get-rework-activities`로 인스턴스와 활동 식별자를 받으면 재작업의 참조가 되는 활동 목록과 전체 활동 목록을 SHALL 반환한다.

#### Scenario: 재작업 후보 조회 성공
- **GIVEN** 유효한 `instanceId`와 `activityId`가 존재한다
- **WHEN** 운영자가 `POST /get-rework-activities`를 호출한다
- **THEN** 시스템은 `reference`와 `all` 목록을 반환하며 각 항목은 `id`와 `name`을 포함한다

#### Scenario: 워크아이템을 찾을 수 없음
- **WHEN** 운영자가 존재하지 않는 인스턴스로 `POST /get-rework-activities`를 호출한다
- **THEN** 시스템은 `400` 상태와 `No workitem found` 메시지를 반환한다

### Requirement: 활동 재작업 시작
시스템은 `POST /rework-complete`로 재작업할 활동 목록과 시작 활동을 받으면 시작 활동을 `IN_PROGRESS`로, 나머지 활동을 `TODO`로 전이한 워크아이템들을 SHALL 생성한다.

#### Scenario: 재작업 시작 성공
- **GIVEN** 유효한 `instanceId`, 시작 활동 `activityId`, 재작업할 `activities` 목록이 주어진다
- **WHEN** 운영자가 `POST /rework-complete`를 호출한다
- **THEN** 시스템은 새 워크아이템 식별자를 키로 한 결과를 반환하고 시작 활동은 `IN_PROGRESS`, 나머지는 `TODO` 상태가 된다

### Requirement: 보상 코드 생성
시스템은 활동 재작업 시 이전에 수행된 되돌릴 수 있는 자동 작업에 대해 보상(undo) 코드를 SHALL 준비한다.

#### Scenario: 되돌릴 작업이 있을 때 보상 코드 생성
- **GIVEN** 재작업 대상 활동 이전에 되돌릴 수 있는 도구 사용 이력이 존재한다
- **WHEN** 시스템이 재작업을 처리한다
- **THEN** 시스템은 보상 코드를 생성하여 보존하고, 이를 실행할 워크아이템을 `agent_orch='crewai-action'`, `status='IN_PROGRESS'`로 준비한다

#### Scenario: 되돌릴 작업이 없거나 보상 코드가 이미 있을 때 생략
- **GIVEN** 되돌릴 수 있는 작업 이력이 없거나 동일 활동의 보상 코드가 이미 존재한다
- **WHEN** 시스템이 재작업을 처리한다
- **THEN** 시스템은 보상 코드 생성을 생략하고 재작업을 계속 진행한다
