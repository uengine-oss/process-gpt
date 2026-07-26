# WMS 주기 실사 명세

## ADDED Requirements

### Requirement: 실사 계획 생성 (WMS-CC-001)
시스템은 ABC 등급, 마지막 실사일, 위치·상품·차이 위험과 임계 이벤트로 주기·spot 실사 작업을 SHALL 생성한다.

#### Scenario: 계획 주기 도래
- **GIVEN** A등급 상품 위치가 설정된 실사 주기를 초과했다
- **WHEN** 일일 실사 계획 job이 실행된다
- **THEN** 시스템은 대상 위치·상품과 만기 시각이 있는 실사 작업을 생성한다

#### Scenario: Short pick 후 spot count
- **GIVEN** 피킹 작업에서 시스템 수량보다 현물 수량이 적다는 예외가 제출되었다
- **WHEN** 예외가 확정된다
- **THEN** 시스템은 해당 위치·상품의 우선 spot count 작업을 생성한다

### Requirement: Blind count 수행 (WMS-CC-002)
시스템은 현장 작업자에게 장부 수량을 숨기고 위치, 상품, lot/serial과 실사 수량을 스캔·입력하게 SHALL 한다.

#### Scenario: 현장 blind count
- **GIVEN** 작업자가 실사 작업을 claim했다
- **WHEN** 위치와 재고 식별자를 스캔하고 수량을 제출한다
- **THEN** 시스템은 제출 전 장부 수량을 노출하지 않는다
- **AND** 제출자, 시각, 장치와 원시 입력을 보존한다

### Requirement: 재검과 차이 승인 (WMS-CC-003)
시스템은 허용 오차를 넘는 차이에 독립 재검 또는 권한 있는 승인자의 검토를 SHALL 요구한다.

#### Scenario: 허용 범위 초과
- **GIVEN** 실사 차이가 수량 또는 평가금액 임계값을 넘는다
- **WHEN** 첫 실사 결과가 제출된다
- **THEN** 시스템은 원장을 즉시 바꾸지 않고 RECOUNT 또는 APPROVAL_REQUIRED 상태로 전환한다

#### Scenario: 자기 승인 방지
- **GIVEN** 정책이 작업자와 승인자 분리를 요구한다
- **WHEN** 실사 수행자가 자신의 차이를 승인하려 한다
- **THEN** 시스템은 승인을 거부하고 다른 승인자를 요구한다

### Requirement: 실사 조정 원장 (WMS-CC-004)
시스템은 승인된 차이를 명시적 조정 문서와 원장 movement로 SHALL 반영한다.

#### Scenario: 차이 승인 완료
- **GIVEN** 최종 실사 수량과 차이 사유가 승인되었다
- **WHEN** 조정이 확정된다
- **THEN** 시스템은 기존 원장을 변경하지 않고 차이만큼 adjustment entry를 생성한다
- **AND** 계획, 작업, 각 실사 결과와 승인 이력을 연결한다

### Requirement: 실사 중 운영 정책 (WMS-CC-005)
시스템은 실사 범위에 대해 freeze 또는 이동 추적 허용 정책을 SHALL 적용한다.

#### Scenario: Freeze 위치 이동
- **GIVEN** 위치가 진행 중 실사로 freeze되어 있다
- **WHEN** 일반 입출고 작업이 해당 위치의 재고를 이동하려 한다
- **THEN** 시스템은 정책에 따라 이동을 차단하거나 실사를 무효화하고 재실사를 생성한다
