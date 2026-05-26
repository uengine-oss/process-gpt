# Drive 폴더 일괄 인덱싱 명세

## Purpose
테넌트의 Google Drive 폴더에 있는 문서를 검색 인덱스로 일괄 수집하는 능력을 보장한다. 클라이언트는 인덱싱을 비동기 잡으로 시작하고, 신규 파일만 처리되며, 진행 상태를 폴링으로 확인할 수 있다.

## Requirements

### Requirement: Drive 폴더 비동기 인덱싱 시작
시스템은 `POST /process` 요청에서 `storage_type=drive`이고 단일 파일이 지정되지 않은 경우, 테넌트 Drive 폴더의 문서 중 아직 처리되지 않은 신규 파일만 비동기 인덱싱 잡으로 시작하고 `202` 상태와 `job_id`를 SHALL 반환한다.

#### Scenario: 신규 파일이 있는 폴더 인덱싱 시작
- **GIVEN** 테넌트가 유효한 Google Drive 자격을 보유하고 폴더에 미처리 문서가 존재한다
- **WHEN** 클라이언트가 `storage_type=drive`와 `tenant_id`로 `POST /process`를 호출한다
- **THEN** 시스템은 `202` 상태와 `{job_id, message}`를 반환한다
- **AND** 발견된 모든 파일은 인덱싱 상태 추적 대상으로 등록되고, 신규 파일은 백그라운드에서 처리된다

#### Scenario: 처리할 신규 파일이 없음
- **GIVEN** 테넌트 Drive 폴더의 모든 문서가 이미 처리되었다
- **WHEN** 클라이언트가 `storage_type=drive`로 `POST /process`를 호출한다
- **THEN** 시스템은 처리할 신규 문서가 없다는 안내 메시지를 반환한다
- **AND** 새 인덱싱 잡을 시작하지 않는다

#### Scenario: 문서가 없는 폴더
- **GIVEN** 테넌트 Drive 폴더에 지원 형식의 문서가 하나도 없다
- **WHEN** 클라이언트가 `storage_type=drive`로 `POST /process`를 호출한다
- **THEN** 시스템은 문서를 찾지 못했다는 안내 메시지를 반환한다

#### Scenario: Drive 인증 미보유
- **GIVEN** 테넌트가 유효한 Google Drive 자격을 보유하지 않았다
- **WHEN** 클라이언트가 `storage_type=drive`로 `POST /process`를 호출한다
- **THEN** 시스템은 `401` 상태와 `auth_url`이 포함된 인증 오류 응답을 반환한다

### Requirement: 인덱싱 잡 진행 상태 조회
시스템은 `GET /process/drive/status` 요청에 대해 해당 테넌트의 활성 또는 최근 완료된 인덱싱 잡의 진행률을 SHALL 반환하며, 추적 중인 잡이 없으면 유휴 상태를 반환한다.

#### Scenario: 진행 중 잡 상태 폴링
- **GIVEN** 테넌트의 인덱싱 잡이 실행 중이다
- **WHEN** 클라이언트가 `tenant_id`로 `GET /process/drive/status`를 호출한다
- **THEN** 시스템은 `job_id`, `status`, `total`, `processed`, `failed`, 파일별 `results`를 반환한다

#### Scenario: 완료된 잡 결과 조회
- **GIVEN** 테넌트의 인덱싱 잡이 완료 또는 실패로 끝났다
- **WHEN** 클라이언트가 `GET /process/drive/status`를 호출한다
- **THEN** 시스템은 `completed` 또는 `failed` 상태와 파일별 처리 결과를 반환한다

#### Scenario: 추적 중인 잡 없음
- **GIVEN** 테넌트에 대해 추적 중인 인덱싱 잡이 없거나 보존 기간이 지났다
- **WHEN** 클라이언트가 `GET /process/drive/status`를 호출한다
- **THEN** 시스템은 `status`가 `idle`인 응답을 반환한다

### Requirement: 파일별 인덱싱 상태 기록
시스템은 인덱싱 잡 진행 중 각 파일의 인덱싱 상태를 `pending`, `processing`, `indexed`, `failed` 단계로 SHALL 갱신하고, 콘텐츠를 추출하지 못한 파일은 실패로 기록한다.

#### Scenario: 파일 처리 성공
- **WHEN** 시스템이 한 Drive 파일의 콘텐츠를 추출해 검색 인덱스에 적재한다
- **THEN** 해당 파일의 인덱싱 상태는 `indexed`로 갱신된다
- **AND** 해당 파일은 이후 같은 폴더 재인덱싱 시 재처리 대상에서 제외된다

#### Scenario: 콘텐츠 추출 실패
- **WHEN** 시스템이 한 Drive 파일에서 콘텐츠를 추출하지 못한다
- **THEN** 해당 파일의 인덱싱 상태는 `failed`로 갱신되고 실패 사유가 함께 기록된다
- **AND** 잡의 `failed` 카운트가 증가하지만 나머지 파일 처리는 계속된다

### Requirement: 단일 Drive 파일 처리
시스템은 `POST /process` 요청에서 `storage_type=drive`이고 단일 파일이 지정된 경우, 그 파일만 동기적으로 처리하고 이미 처리된 파일이면 재처리하지 않음을 SHALL 보장한다.

#### Scenario: 지정 파일 처리 성공
- **GIVEN** 클라이언트가 처리되지 않은 Drive 파일을 지정한다
- **WHEN** 클라이언트가 단일 파일 식별자를 담아 `POST /process`를 호출한다
- **THEN** 시스템은 해당 파일을 추출·적재하고 성공 메시지를 반환한다

#### Scenario: 이미 처리된 파일 지정
- **GIVEN** 지정한 Drive 파일이 이미 해당 테넌트에서 처리되었다
- **WHEN** 클라이언트가 그 파일로 `POST /process`를 호출한다
- **THEN** 시스템은 재처리 없이 이미 처리되었다는 안내 메시지를 반환한다

#### Scenario: 존재하지 않는 파일 지정
- **GIVEN** 지정한 식별자에 해당하는 Drive 파일이 없다
- **WHEN** 클라이언트가 그 파일로 `POST /process`를 호출한다
- **THEN** 시스템은 파일을 찾을 수 없다는 오류를 반환한다
