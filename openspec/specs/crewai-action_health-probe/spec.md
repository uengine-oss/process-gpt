# CrewAI 액션 서버 헬스 점검 명세

## Purpose
운영자와 컨테이너 오케스트레이터가 CrewAI 액션 서버의 생존 및 준비 상태를 HTTP로 점검할 수 있도록 보장한다. 헬스 엔드포인트는 작업 처리와 독립적으로 응답하여 readiness/liveness 프로브 대상으로 사용된다.

## Requirements

### Requirement: 헬스 상태 조회
시스템은 `GET /health` 요청을 받으면 상태 코드 `200`과 본문 `{"status":"ok"}`를 SHALL 반환한다. 응답은 `Content-Type: application/json; charset=utf-8` 헤더와 본문 길이 헤더를 포함해야 한다.

#### Scenario: 정상 헬스 응답
- **GIVEN** CrewAI 액션 서버가 기동되어 있다
- **WHEN** 클라이언트가 `GET /health`를 호출한다
- **THEN** 시스템은 상태 코드 `200`을 반환한다
- **AND** 응답 본문은 `{"status":"ok"}`이다
- **AND** 응답 `Content-Type`은 `application/json; charset=utf-8`이다

#### Scenario: 작업 처리 중에도 헬스 응답 유지
- **GIVEN** 서버가 작업을 폴링하거나 실행하고 있다
- **WHEN** 클라이언트가 `GET /health`를 호출한다
- **THEN** 시스템은 작업 처리 진행 여부와 무관하게 상태 코드 `200`과 `{"status":"ok"}`를 반환한다

### Requirement: HEAD 메서드 헬스 점검 지원
시스템은 `HEAD /health` 요청을 받으면 본문 없이 상태 코드 `200`과 헬스 응답용 헤더를 SHALL 반환한다.

#### Scenario: HEAD 요청 헬스 점검
- **GIVEN** CrewAI 액션 서버가 기동되어 있다
- **WHEN** 클라이언트가 `HEAD /health`를 호출한다
- **THEN** 시스템은 상태 코드 `200`을 반환한다
- **AND** 응답 본문은 전송되지 않는다

### Requirement: 정의되지 않은 경로 거부
시스템은 `/health` 외의 경로에 대한 `GET` 또는 `HEAD` 요청을 받으면 상태 코드 `404`와 본문 `{"status":"not_found"}`를 SHALL 반환한다.

#### Scenario: 알 수 없는 경로 요청
- **GIVEN** CrewAI 액션 서버가 기동되어 있다
- **WHEN** 클라이언트가 `/health`가 아닌 경로로 `GET` 요청을 보낸다
- **THEN** 시스템은 상태 코드 `404`를 반환한다
- **AND** 응답 본문은 `{"status":"not_found"}`이다
