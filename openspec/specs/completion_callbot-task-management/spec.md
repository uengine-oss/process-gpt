# 콜봇 할 일 관리 명세

## Purpose
음성 콜봇 클라이언트가 발신자를 식별하고, 사용자의 할 일을 조회하며, 작업 필드를 수정하고 작업을 제출하는 능력을 보장한다.

## Requirements

### Requirement: 발신자 식별
시스템은 `GET /complete-callbot/caller-info`로 발신 번호 또는 사용자 식별자를 받으면 발신자 정보와 인사말을 SHALL 반환한다.

#### Scenario: 등록 사용자 발신자 식별
- **GIVEN** 발신자에 해당하는 사용자가 존재한다
- **WHEN** 콜봇이 `GET /complete-callbot/caller-info`를 호출한다
- **THEN** 시스템은 `success: true`와 함께 `username`, `user_id`, `email`, `tenant_id`, `greeting`을 반환한다

#### Scenario: 식별 실패 시 기본 응답
- **GIVEN** 발신자를 특정할 수 없다
- **WHEN** 콜봇이 `GET /complete-callbot/caller-info`를 호출한다
- **THEN** 시스템은 `200` 상태로 기본 인사말이 담긴 응답을 반환한다

### Requirement: 사용자 할 일 목록 조회
시스템은 `GET /complete-callbot/user-todolist` 또는 `GET /complete-callbot/tasks`로 사용자 식별자를 받으면 해당 사용자의 할 일 목록을 SHALL 반환한다.

#### Scenario: 할 일 목록 조회 성공
- **GIVEN** 클라이언트가 `user_id` 질의 파라미터를 제공한다
- **WHEN** 콜봇이 `GET /complete-callbot/tasks`를 호출한다
- **THEN** 시스템은 `success: true`와 함께 `tasks` 목록, `count`, `overdue_count`를 반환한다

#### Scenario: 상태 필터 적용
- **GIVEN** 클라이언트가 `status_filter`로 `active`, `todo`, `in_progress`, `all` 중 하나를 제공한다
- **WHEN** 콜봇이 `GET /complete-callbot/tasks`를 호출한다
- **THEN** 시스템은 해당 상태 조건에 맞는 할 일만 반환한다

#### Scenario: 사용자 식별자 누락
- **WHEN** 콜봇이 `user_id` 없이 할 일 목록 조회를 호출한다
- **THEN** 시스템은 `422` 상태로 필수 파라미터 누락 오류를 반환한다

### Requirement: 작업 상세 조회
시스템은 `GET /complete-callbot/task/{task_id}`로 작업 식별자를 받으면 작업 상세, 폼 스키마, 현재 데이터, 참조 폼을 SHALL 반환한다.

#### Scenario: 작업 상세 조회 성공
- **GIVEN** 유효한 `task_id`가 존재한다
- **WHEN** 콜봇이 `GET /complete-callbot/task/{task_id}`를 호출한다
- **THEN** 시스템은 `task`, `form_schema`, `current_data`, `reference_forms`를 반환한다

#### Scenario: 작업을 찾을 수 없음
- **WHEN** 콜봇이 존재하지 않는 `task_id`로 작업 상세를 조회한다
- **THEN** 시스템은 `404` 상태와 `Task not found` 메시지를 반환한다

### Requirement: 작업 필드 수정
시스템은 `PATCH /complete-callbot/task/{task_id}`로 필드 값을 받으면 작업의 데이터를 SHALL 갱신한다.

#### Scenario: 작업 필드 수정 성공
- **GIVEN** 유효한 `task_id`가 존재하고 클라이언트가 수정할 필드 값을 제공한다
- **WHEN** 콜봇이 `PATCH /complete-callbot/task/{task_id}`를 호출한다
- **THEN** 시스템은 `success: true`와 함께 `updated_fields`, 병합된 `output`을 반환한다

### Requirement: 작업 제출
시스템은 `POST /complete-callbot/task/{task_id}/submit` 요청을 받으면 작업을 `status` `SUBMITTED`로 전이하여 후속 자동 처리 대상으로 SHALL 만든다.

#### Scenario: 작업 제출 성공
- **GIVEN** 유효한 `task_id`가 존재한다
- **WHEN** 콜봇이 `POST /complete-callbot/task/{task_id}/submit`을 호출한다
- **THEN** 시스템은 작업 상태를 `SUBMITTED`로 전이하고 `success: true`와 제출 결과를 반환한다
- **AND** 제출된 작업은 폴링 워커가 다음 활동으로 진행시킨다
