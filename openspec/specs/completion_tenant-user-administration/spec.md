# 테넌트·사용자 관리 명세

## Purpose
운영자가 사용자 계정을 생성·초대하고, 초기 정보를 설정하며, 사용자 및 테넌트 관리 정보를 갱신하는 능력을 보장한다.

## Requirements

### Requirement: 사용자 생성
시스템은 `POST /create-user`로 신규 사용자 정보를 받으면 사용자 계정을 SHALL 생성한다.

#### Scenario: 사용자 생성 성공
- **GIVEN** 클라이언트가 `{input:{...신규 사용자 정보}}`를 제공한다
- **WHEN** 클라이언트가 `POST /create-user`를 호출한다
- **THEN** 시스템은 사용자 계정을 생성하고 생성 결과를 반환한다

### Requirement: 사용자 초대
시스템은 `POST /invite-user`로 초대 대상 정보를 받으면 사용자를 초대하고 초대 안내를 SHALL 발송한다.

#### Scenario: 사용자 초대 성공
- **GIVEN** 클라이언트가 `{input:{...초대 대상 정보}}`를 제공한다
- **WHEN** 클라이언트가 `POST /invite-user`를 호출한다
- **THEN** 시스템은 초대를 처리하고, 초대 대상에게 초기 설정 화면 링크가 포함된 안내 이메일을 발송한다

### Requirement: 초기 정보 설정
시스템은 `POST /set-initial-info`로 초기 정보를 받으면 사용자 또는 테넌트의 초기 정보를 SHALL 설정한다.

#### Scenario: 초기 정보 설정 성공
- **GIVEN** 클라이언트가 `{input:{...초기 정보}}`를 제공한다
- **WHEN** 클라이언트가 `POST /set-initial-info`를 호출한다
- **THEN** 시스템은 초기 정보를 저장하고 처리 결과를 반환한다

### Requirement: 사용자·테넌트 관리 정보 갱신
시스템은 `POST /update-user` 또는 `POST /set-tenant`로 관리 정보를 받으면 해당 사용자·테넌트 관리 정보를 SHALL 갱신한다.

#### Scenario: 관리 정보 갱신 성공
- **GIVEN** 클라이언트가 `{input:{...관리 정보}}`를 제공한다
- **WHEN** 클라이언트가 `POST /update-user` 또는 `POST /set-tenant`를 호출한다
- **THEN** 시스템은 사용자·테넌트 관리 정보를 갱신하고 처리 결과를 반환한다
