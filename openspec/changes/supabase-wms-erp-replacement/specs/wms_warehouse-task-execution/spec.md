# WMS 창고 작업 실행 명세

## ADDED Requirements

### Requirement: 통합 작업 생명주기 (WMS-TASK-001)
시스템은 입고, 검사, 적치, 이동, 보충, 피킹, 포장, 출하와 실사를 `CREATED → READY → CLAIMED → IN_PROGRESS → COMPLETED` 생명주기로 SHALL 관리한다.

#### Scenario: 선행 작업이 있는 작업
- **GIVEN** 피킹 위치 보충 후 실행해야 하는 피킹 작업이 있다
- **WHEN** 보충 작업이 아직 완료되지 않았다
- **THEN** 시스템은 피킹 작업을 BLOCKED 상태로 유지한다
- **AND** 선행 작업 완료 후 READY로 전환한다

### Requirement: 우선순위와 작업 배정 (WMS-TASK-002)
시스템은 작업 유형, 구역, 장비·자격, 납기, SLA와 우선순위에 따라 사용자 또는 팀에 작업을 SHALL 배정한다.

#### Scenario: 자격 없는 검사 작업
- **GIVEN** 품질 검사 작업에 특정 skill이 필요하다
- **WHEN** 해당 skill이 없는 사용자가 claim하려 한다
- **THEN** 시스템은 claim을 거부하고 필요한 자격을 표시한다

### Requirement: 원자적 Claim (WMS-TASK-003)
시스템은 하나의 READY 작업을 한 작업자만 원자적으로 claim하도록 SHALL 보장한다.

#### Scenario: 동시 claim
- **GIVEN** 두 작업자가 같은 READY 작업을 보고 있다
- **WHEN** 두 작업자가 동시에 claim한다
- **THEN** 시스템은 한 명에게만 작업을 할당한다
- **AND** 다른 사용자에게 최신 담당자와 대체 작업을 반환한다

### Requirement: 단계별 스캔 실행 (WMS-TASK-004)
시스템은 작업 유형별 필수 step과 예상 입력을 내려주고 각 스캔을 서버에서 SHALL 검증한다.

#### Scenario: 필수 단계 생략
- **GIVEN** 위치→상품→lot→목적 위치 스캔이 필요한 작업이 있다
- **WHEN** 작업자가 lot 확인 없이 완료를 요청한다
- **THEN** 시스템은 완료를 거부하고 남은 필수 단계를 안내한다

### Requirement: 작업 예외와 Escalation (WMS-TASK-005)
시스템은 재고 없음, 위치 폐쇄, 상품 불일치, 파손, 장비 문제와 안전 문제를 구조화된 예외로 SHALL 기록한다.

#### Scenario: 작업 중 파손 발견
- **GIVEN** 작업자가 이동 중 파손을 발견한다
- **WHEN** 수량·사유·사진을 제출한다
- **THEN** 시스템은 정상 작업 수량과 파손 수량을 분리하고 품질/격리 후속 작업을 생성한다
- **AND** 원 작업의 SLA와 관리자 알림을 갱신한다

### Requirement: 오프라인 멱등 재전송 (WMS-TASK-006)
시스템은 승인된 오프라인 작업 step을 로컬 queue에 저장하고 재연결 시 원래 순서와 idempotency key로 SHALL 재전송한다.

#### Scenario: 오프라인 완료 후 서버 버전 충돌
- **GIVEN** 작업자가 오프라인에서 작업을 완료하는 동안 다른 사용자가 서버 상태를 변경했다
- **WHEN** 단말이 재연결되어 명령을 전송한다
- **THEN** 시스템은 변경을 자동 덮어쓰지 않고 충돌 결과와 서버 상태를 반환한다
- **AND** 해결 전까지 후속 재고 movement를 생성하지 않는다

### Requirement: 작업 SLA 관찰 (WMS-TASK-007)
시스템은 작업의 예정·시작·완료·중단 시간과 SLA 위험을 SHALL 계산한다.

#### Scenario: SLA 임박 작업
- **GIVEN** READY 또는 IN_PROGRESS 작업이 경고 임계시간에 도달했다
- **WHEN** SLA monitor가 실행된다
- **THEN** 시스템은 관리자 알림과 대시보드 경고를 생성하되 동일 상태의 중복 알림을 억제한다
