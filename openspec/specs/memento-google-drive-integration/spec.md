# Google Drive 연동 명세

## Purpose
테넌트가 Google OAuth로 Drive 접근을 인가하고, 인가된 자격으로 파일을 Drive에 업로드하는 능력을 보장한다.

## Requirements

### Requirement: Google OAuth 인가 URL 발급
시스템은 `GET /auth/google/url` 요청을 받으면 테넌트의 OAuth 설정을 기반으로 Google 인가 URL을 생성해 SHALL 반환한다.

#### Scenario: 인가 URL 발급
- **GIVEN** 테넌트에 OAuth 설정(client id, redirect uri)이 등록되어 있다
- **WHEN** 클라이언트가 `tenant_id`로 `GET /auth/google/url`을 호출한다
- **THEN** 시스템은 `auth_url`과 `state`(테넌트 식별자)를 반환한다

#### Scenario: OAuth 설정 미등록
- **GIVEN** 테넌트에 OAuth 설정이 없다
- **WHEN** 클라이언트가 `GET /auth/google/url`을 호출한다
- **THEN** 시스템은 `404` 상태로 OAuth 설정을 찾을 수 없다는 오류를 반환한다

### Requirement: OAuth 콜백 토큰 교환
시스템은 `POST /auth/google/callback` 요청을 받으면 인가 코드를 Google 토큰으로 교환하고, 그 토큰을 테넌트 자격으로 SHALL 저장한다. `POST /auth/google/save-token`으로 토큰을 직접 저장할 수도 있다.

#### Scenario: 인가 코드 교환 성공
- **GIVEN** 클라이언트가 유효한 인가 코드와 `state`를 제공한다
- **WHEN** 클라이언트가 `POST /auth/google/callback`을 호출한다
- **THEN** 시스템은 코드를 토큰으로 교환해 테넌트 자격으로 저장하고 완료 응답을 반환한다

#### Scenario: 인가 코드 교환 실패
- **GIVEN** 인가 코드가 유효하지 않아 토큰 교환이 실패한다
- **WHEN** 클라이언트가 `POST /auth/google/callback`을 호출한다
- **THEN** 시스템은 `400` 상태로 토큰 교환 실패 오류를 반환한다

### Requirement: 인증 상태 조회
시스템은 `GET /auth/google/status` 요청을 받으면 테넌트가 유효한(만료되지 않은) Google 자격을 보유했는지 SHALL 반환한다.

#### Scenario: 유효한 자격 보유
- **GIVEN** 테넌트에 만료되지 않은 Google 자격이 저장되어 있다
- **WHEN** 클라이언트가 `GET /auth/google/status`를 호출한다
- **THEN** 시스템은 `authenticated=true`와 만료 시각·갱신 시각을 반환한다

#### Scenario: 자격 없음 또는 만료
- **GIVEN** 테넌트에 Google 자격이 없거나 토큰이 만료되었다
- **WHEN** 클라이언트가 `GET /auth/google/status`를 호출한다
- **THEN** 시스템은 `authenticated=false`와 사유 메시지를 반환한다

### Requirement: Drive 파일 업로드
시스템은 `POST /save-to-drive` 멀티파트 요청을 받으면 인가된 테넌트 자격으로 파일을 Google Drive에 업로드하고 업로드 메타를 SHALL 반환하며, 인덱싱은 수행하지 않는다.

#### Scenario: 파일 업로드 성공
- **GIVEN** 테넌트가 유효한 Google Drive 자격을 보유한다
- **WHEN** 클라이언트가 파일, `file_name`, `tenant_id`로 `POST /save-to-drive`를 호출한다
- **THEN** 시스템은 파일을 Drive에 업로드하고 업로드 메타를 반환한다

#### Scenario: 인증 미보유 상태 업로드
- **GIVEN** 테넌트가 유효한 Google Drive 자격을 보유하지 않는다
- **WHEN** 클라이언트가 `POST /save-to-drive`를 호출한다
- **THEN** 시스템은 `401` 상태와 `auth_url`이 포함된 인증 오류 응답을 반환한다
