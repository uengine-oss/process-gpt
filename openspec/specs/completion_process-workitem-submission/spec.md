# 프로세스 워크아이템 생성·제출 명세

## Purpose
클라이언트가 프로세스 인스턴스를 시작하고, 폼 값을 담아 워크아이템을 제출하며, 프로세스 역할을 사용자 계정으로 해소받는 능력을 보장한다. 이 명세는 프로세스 실행을 시작하고 사람이 수행한 작업을 시스템에 제출하는 외부 API 계약을 다룬다.

## Requirements

### Requirement: 프로세스 인스턴스 시작
시스템은 `POST /initiate`로 프로세스 정의 식별자를 받으면 초기 활동에 해당하는 워크아이템을 `status` `TODO`로 생성하고 해당 워크아이템 정보를 SHALL 반환한다.

#### Scenario: 신규 인스턴스 시작 성공
- **GIVEN** 유효한 `process_definition_id`가 존재하고 담당 사용자 이메일을 해소할 수 있다
- **WHEN** 클라이언트가 `POST /initiate`에 `{input:{process_definition_id, ...}}`를 제출한다
- **THEN** 시스템은 `proc_inst_id`, `proc_def_id`, `activity_id`, `status`가 `TODO`인 워크아이템 정보를 반환한다
- **AND** 생성된 인스턴스와 워크아이템은 이후 인가된 조회와 제출에서 사용할 수 있다

#### Scenario: 초기 활동을 찾을 수 없음
- **WHEN** 클라이언트가 초기 활동이 없는 프로세스 정의로 `POST /initiate`를 호출한다
- **THEN** 시스템은 `400` 상태와 `No initial activity found` 메시지를 반환한다

#### Scenario: 담당 사용자 이메일을 해소할 수 없음
- **GIVEN** 요청에 `email`이 없고 역할 기본값으로도 사용자를 정할 수 없다
- **WHEN** 클라이언트가 `POST /initiate`를 호출한다
- **THEN** 시스템은 `400` 상태와 `No default user email found` 메시지를 반환한다

### Requirement: 워크아이템 제출
시스템은 `POST /complete` 또는 `POST /vision-complete`로 프로세스 인스턴스 식별자와 폼 값을 받으면 워크아이템을 `status` `SUBMITTED`로 생성하거나 갱신하고 그 결과를 SHALL 반환한다.

#### Scenario: 폼 값을 담은 워크아이템 제출 성공
- **GIVEN** 유효한 `process_instance_id`가 존재한다
- **WHEN** 클라이언트가 `POST /complete`에 `{input:{process_instance_id, activity_id, form_values, role_mappings, ...}}`를 제출한다
- **THEN** 시스템은 `status`가 `SUBMITTED`이고 제출한 폼 값이 `output`에 반영된 워크아이템 정보를 반환한다
- **AND** 제출된 워크아이템은 이후 자동 처리 대상으로 보존된다

#### Scenario: 기존 워크아이템 갱신 제출
- **GIVEN** 요청에 기존 워크아이템을 가리키는 `task_id`가 포함된다
- **WHEN** 클라이언트가 `POST /complete`를 호출한다
- **THEN** 시스템은 동일 워크아이템을 갱신하고 `status`를 `SUBMITTED`로 전이한 결과를 반환한다

#### Scenario: 프로세스 인스턴스 식별자 누락
- **WHEN** 클라이언트가 `process_instance_id` 없이 `POST /complete`를 호출한다
- **THEN** 시스템은 `400` 상태와 `Process instance id is required` 메시지를 반환한다

### Requirement: 프로세스 역할 바인딩
시스템은 `POST /role-binding`으로 역할 매핑 정보를 받으면 각 프로세스 역할을 사용자 계정 식별자에 연결한 결과를 SHALL 반환한다.

#### Scenario: 역할 매핑 해소 성공
- **GIVEN** 클라이언트가 프로세스 정의와 역할 매핑(`roles`)을 제공한다
- **WHEN** 클라이언트가 `POST /role-binding`을 호출한다
- **THEN** 시스템은 `roleName`과 `userId` 쌍으로 구성된 `roleBindings` 결과를 반환한다

### Requirement: 프로세스 정의 버전 해소
시스템은 워크아이템 생성·제출 시 요청에 지정된 버전 정보 또는 운영 버전 규칙에 따라 적용할 프로세스 정의 버전을 SHALL 결정한다.

#### Scenario: 명시한 버전으로 처리
- **GIVEN** 요청에 `version_tag`와 `version`이 포함된다
- **WHEN** 클라이언트가 워크아이템 생성·제출 API를 호출한다
- **THEN** 시스템은 지정된 버전의 프로세스 정의를 적용하여 워크아이템을 처리한다

#### Scenario: 버전 미지정 시 운영 버전 적용
- **GIVEN** 요청에 버전 정보가 없다
- **WHEN** 클라이언트가 워크아이템 생성·제출 API를 호출한다
- **THEN** 시스템은 운영 버전 또는 최신 버전 규칙에 따라 적용할 정의를 결정한다

### Requirement: 테넌트 격리
시스템은 워크아이템 생성·제출 요청을 요청 subdomain이 가리키는 테넌트 범위로 SHALL 격리하여 처리한다.

#### Scenario: 테넌트별 데이터 분리
- **GIVEN** 요청이 특정 테넌트 subdomain으로 들어온다
- **WHEN** 클라이언트가 워크아이템 생성·제출 API를 호출한다
- **THEN** 시스템은 해당 테넌트의 프로세스 정의와 인스턴스만 사용하여 처리한다
