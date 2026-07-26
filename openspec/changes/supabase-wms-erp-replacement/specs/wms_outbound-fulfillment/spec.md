# WMS 출고 이행 명세

## ADDED Requirements

### Requirement: 출고 주문 접수 (WMS-OUT-001)
시스템은 외부 주문 또는 수동 입력으로 수취인, 납기, 운송 조건, 상품·수량과 lot/serial 제약이 있는 출고 주문을 SHALL 생성한다.

#### Scenario: 중복 외부 주문
- **GIVEN** 같은 `source_system`과 `source_ref`의 출고 주문이 있다
- **WHEN** 외부 시스템이 주문을 다시 전송한다
- **THEN** 시스템은 중복 주문을 생성하지 않고 기존 주문과 처리 결과를 반환한다

### Requirement: 재고 할당과 예약 (WMS-OUT-002)
시스템은 FIFO, FEFO, lot/serial, 고객, 상태와 위치 규칙에 따라 가용재고를 할당하고 SHALL 예약한다.

#### Scenario: FEFO 할당
- **GIVEN** 유통기한이 다른 두 lot이 있고 둘 다 출고 가능하다
- **WHEN** FEFO 상품을 할당한다
- **THEN** 시스템은 고객 잔여 유통기한 조건을 만족하는 lot 중 가장 먼저 만료되는 수량부터 예약한다

#### Scenario: 재고 부족
- **GIVEN** 주문 수량보다 가용재고가 적다
- **WHEN** 할당을 실행한다
- **THEN** 시스템은 정책에 따라 부분 할당 또는 미할당을 기록한다
- **AND** 부족 수량을 재보충 또는 예외 대상으로 발행한다

### Requirement: Wave와 피킹 작업 (WMS-OUT-003)
시스템은 납기, 구역, 운송편, 우선순위와 작업 용량으로 주문을 wave에 묶고 release 시 피킹 작업을 SHALL 생성한다.

#### Scenario: 피킹 위치 보충 필요
- **GIVEN** 전체 재고는 충분하지만 피킹 위치 수량이 부족하다
- **WHEN** wave를 release한다
- **THEN** 시스템은 피킹보다 선행하는 보충 작업을 생성한다
- **AND** 보충 완료 전 종속 피킹 step을 시작하지 않게 한다

### Requirement: 스캔 기반 피킹 (WMS-OUT-004)
시스템은 출발 위치, 상품, lot/serial, 수량과 목적 tote/LPN을 스캔 검증하여 피킹을 SHALL 기록한다.

#### Scenario: 잘못된 lot 피킹
- **GIVEN** 특정 lot이 할당되어 있다
- **WHEN** 작업자가 다른 lot을 스캔한다
- **THEN** 시스템은 피킹 확정을 거부하고 허용 lot을 안내한다

#### Scenario: Short pick
- **GIVEN** 시스템 수량보다 실제 수량이 적다
- **WHEN** 작업자가 short pick 사유를 제출한다
- **THEN** 시스템은 피킹 차이와 spot count 작업을 생성한다
- **AND** 잔여 주문의 재할당 또는 backorder를 실행한다

### Requirement: 포장과 출하 확정 (WMS-OUT-005)
시스템은 피킹된 품목을 package에 담고 중량·라벨·운송 참조를 기록한 뒤 출하 시 원장을 SHALL 차감한다.

#### Scenario: 출하 확정
- **GIVEN** 필수 품목이 포장되고 운송 라벨이 생성되었다
- **WHEN** 출하 담당자가 도크에서 shipment를 확정한다
- **THEN** 시스템은 PACKED 재고를 창고 밖 IN_TRANSIT/SHIPPED 상태로 이동한다
- **AND** 주문, package, SSCC와 lot/serial 계보를 보존한다

### Requirement: 출고 취소 복원 (WMS-OUT-006)
시스템은 처리 단계에 따라 예약 해제, 피킹 재고 복귀 또는 반품 절차로 취소를 SHALL 처리한다.

#### Scenario: 피킹 전 주문 취소
- **GIVEN** 출고 주문이 예약되었지만 피킹되지 않았다
- **WHEN** 주문이 취소된다
- **THEN** 시스템은 예약을 해제하고 수량을 available로 복원한다
