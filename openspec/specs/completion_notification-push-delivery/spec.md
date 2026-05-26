# 알림 푸시 전달 명세

## Purpose
시스템이 미처리 알림을 주기적으로 감지하여 사용자 기기로 푸시 알림을 전달하고, 온디맨드 알림 전송과 기기 토큰 조회를 제공하는 능력을 보장한다.

## Requirements

### Requirement: 미처리 알림 자동 전달
시스템은 미처리 상태의 알림을 주기적으로 감지하여 해당 사용자 기기로 푸시 알림을 SHALL 전달한다.

#### Scenario: 미처리 알림 전달
- **GIVEN** `consumer`가 지정되지 않은 알림 행이 존재한다
- **WHEN** 알림 전달 워커의 폴링 주기가 도래한다
- **THEN** 시스템은 해당 알림을 처리 주체로 클레임하고 대상 사용자 기기로 푸시 알림을 전달한다

#### Scenario: 알림 메시지 구성
- **GIVEN** 알림에 발신자(`from_user_id`)가 포함되어 있다
- **WHEN** 시스템이 푸시 알림을 구성한다
- **THEN** 시스템은 발신자를 제목으로, 본문과 함께 알림 내용을 표시하고 `data`에 `type`, `url`, `notification_id`를 포함한다

### Requirement: 온디맨드 알림 전송
시스템은 `POST /send-notification`으로 알림 정보를 받으면 대상 사용자 기기로 즉시 푸시 알림을 SHALL 전송한다.

#### Scenario: 알림 전송 성공
- **GIVEN** 클라이언트가 `{user_id, title, body, type, url, from_user_id, data}`를 제공한다
- **WHEN** 클라이언트가 `POST /send-notification`을 호출한다
- **THEN** 시스템은 `{success, message}` 형태로 전송 결과를 반환한다

### Requirement: 기기 토큰 조회
시스템은 `GET /device-token/{user_id}`로 사용자 식별자를 받으면 해당 사용자의 등록 기기 토큰을 SHALL 반환한다.

#### Scenario: 기기 토큰 조회
- **WHEN** 클라이언트가 `GET /device-token/{user_id}`를 호출한다
- **THEN** 시스템은 `{user_id, device_token}`을 반환하며, 등록된 토큰이 없으면 토큰 값은 비어 있다

### Requirement: 서비스 상태 점검
시스템은 `GET /health` 요청에 대해 알림 서비스의 정상 동작 여부를 SHALL 반환한다.

#### Scenario: 상태 점검 응답
- **WHEN** 클라이언트가 `GET /health`를 호출한다
- **THEN** 시스템은 `{status: "healthy", service: "fcm-service"}`를 반환한다
