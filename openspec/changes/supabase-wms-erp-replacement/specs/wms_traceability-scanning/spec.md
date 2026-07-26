# WMS 추적성·스캔 명세

## ADDED Requirements

### Requirement: 표준 식별자 해석 (WMS-TRC-001)
시스템은 GTIN, lot, serial, 유통기한, SSCC/LPN과 내부 위치 바코드를 해석하여 정규화된 식별 결과를 SHALL 반환한다.

#### Scenario: GS1 바코드 스캔
- **GIVEN** 상품 GTIN, lot, 수량과 유통기한을 담은 지원 형식의 바코드가 있다
- **WHEN** 작업자가 바코드를 스캔한다
- **THEN** 시스템은 각 application identifier를 필드로 분리하고 상품 정책과 대조한다
- **AND** 원문 스캔값과 정규화 결과를 작업 증빙으로 보존한다

#### Scenario: 모호한 바코드
- **GIVEN** 바코드가 여러 활성 상품과 충돌한다
- **WHEN** 작업자가 스캔한다
- **THEN** 시스템은 임의 상품을 선택하지 않고 기준정보 오류를 반환한다

### Requirement: Serial 고유성 (WMS-TRC-002)
시스템은 추적 범위 내 활성 serial의 중복 보유를 SHALL 방지한다.

#### Scenario: 이미 출고된 serial 재입고
- **GIVEN** serial이 과거 출고 이력에 있으나 현재 창고에는 없다
- **WHEN** 승인된 반품으로 같은 serial이 입고된다
- **THEN** 시스템은 반품 문서 연결을 요구한 뒤 새 lifecycle event를 기록한다

### Requirement: Handling unit 계층 (WMS-TRC-003)
시스템은 개별 상품·lot/serial을 LPN에, LPN을 상위 팔레트 SSCC에 중첩하여 SHALL 관리한다.

#### Scenario: 팔레트 이동
- **GIVEN** 하나의 SSCC 아래 여러 LPN과 상품이 들어 있다
- **WHEN** 작업자가 상위 SSCC를 목적 위치로 이동한다
- **THEN** 시스템은 유효성 검사를 통과한 모든 하위 재고를 같은 movement group으로 이동한다
- **AND** 하위 구성의 계보를 유지한다

### Requirement: 라벨 생성과 재발행 (WMS-TRC-004)
시스템은 상품, lot/serial, LPN/SSCC와 배송 라벨을 템플릿·프린터별로 SHALL 생성하고 재발행 이력을 보존한다.

#### Scenario: SSCC 라벨 재발행
- **GIVEN** 이미 발행된 SSCC가 있다
- **WHEN** 사용자가 손상 사유로 라벨을 재발행한다
- **THEN** 시스템은 같은 SSCC를 유지하고 재발행자·시각·사유를 기록한다

### Requirement: 정방향·역방향 계보 조회 (WMS-TRC-005)
시스템은 상품·lot·serial·SSCC·PO·receipt·shipment 중 하나로 입고 전후와 출고 대상을 SHALL 조회한다.

#### Scenario: lot 회수 범위 조회
- **GIVEN** 특정 lot에 회수 필요 표시가 있다
- **WHEN** 품질 담당자가 회수 범위를 조회한다
- **THEN** 시스템은 현재 위치·수량, 내부 이동, 포함 handling unit, 출고 고객·shipment를 반환한다
- **AND** 격리되지 않은 현재고를 hold할 수 있는 후속 명령을 제공한다
