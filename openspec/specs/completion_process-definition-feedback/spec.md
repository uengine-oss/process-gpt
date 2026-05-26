# 프로세스 정의 피드백 명세

## Purpose
프로세스 설계자가 활동 정의에 대한 개선 피드백을 받고, 작업(task) 정의의 버전 간 변경 내역을 확인하는 능력을 보장한다.

## Requirements

### Requirement: 활동 정의 피드백 제공
시스템은 `POST /get-feedback`으로 프로세스 정의·활동·작업 식별자를 받으면 해당 활동 정의에 대한 개선 피드백 목록을 SHALL 반환한다.

#### Scenario: 활동 피드백 조회 성공
- **GIVEN** 유효한 `processDefinitionId`, `activityId`, `taskId`가 주어진다
- **WHEN** 설계자가 `POST /get-feedback`을 호출한다
- **THEN** 시스템은 피드백 문구로 구성된 배열을 반환한다

### Requirement: 작업 정의 버전 변경 비교
시스템은 `POST /get-feedback-diff`로 작업 식별자를 받으면 작업 정의의 버전 간 변경 항목과 요약을 SHALL 반환한다.

#### Scenario: 변경 비교 조회 성공
- **GIVEN** 유효한 `taskId`가 주어지고 해당 작업과 활동이 존재한다
- **WHEN** 설계자가 `POST /get-feedback-diff`를 호출한다
- **THEN** 시스템은 `modifications`와 `summary`를 반환하며, `modifications`의 각 항목은 `before`/`after`/`changed`를 포함한다

#### Scenario: 워크아이템 또는 활동을 찾을 수 없음
- **WHEN** 설계자가 존재하지 않는 작업으로 `POST /get-feedback-diff`를 호출한다
- **THEN** 시스템은 `400` 상태와 `No workitem found` 또는 `No activity found` 메시지를 반환한다
