# WMS 반품 물류 명세

## ADDED Requirements

### Requirement: 반품 승인과 원출고 연결 (WMS-RTN-001)
시스템은 고객 반품에 RMA 번호, 원출고·주문·package, 상품·수량, 사유와 예상 도착일을 SHALL 연결한다.

#### Scenario: 출고 이력 기반 RMA
- **GIVEN** 추적 가능한 원출고 line이 있다
- **WHEN** 반품 담당자가 허용 수량 내에서 RMA를 생성한다
- **THEN** 시스템은 원출고의 상품, lot/serial, 고객과 가격 참조를 복사한다
- **AND** 이미 반품된 수량을 제외한 잔여 허용 수량을 검증한다

#### Scenario: 원출고 없는 반품
- **GIVEN** 사용자가 원출고를 식별할 수 없는 상품을 반품 등록한다
- **WHEN** 예외 반품을 제출한다
- **THEN** 시스템은 관리자 승인 전 자동 환불·가용재고 전환을 차단한다

### Requirement: 반품 입고와 검사 (WMS-RTN-002)
시스템은 도착한 반품의 상품, lot/serial, 수량, 상태와 사진을 스캔하고 검사 대기 재고로 SHALL 수령한다.

#### Scenario: 다른 serial 도착
- **GIVEN** RMA에 특정 serial이 승인되어 있다
- **WHEN** 작업자가 다른 serial을 스캔한다
- **THEN** 시스템은 정상 반품 확정을 차단하고 불일치 예외를 생성한다

### Requirement: 반품 처분 (WMS-RTN-003)
시스템은 검사 결과에 따라 재판매 적치, 수리·재작업, 폐기, 공급사 반품 또는 고객 반환 처분을 SHALL 지원한다.

#### Scenario: 재판매 가능 반품
- **GIVEN** 반품품이 품질 기준을 통과했다
- **WHEN** 검사자가 재판매 처분을 승인한다
- **THEN** 시스템은 putaway 작업을 만들고 적치 완료 후에만 AVAILABLE로 전환한다

#### Scenario: 폐기 처분
- **GIVEN** 반품품이 재판매·수리 불가 판정을 받았다
- **WHEN** 인가된 사용자가 사유와 함께 폐기를 승인한다
- **THEN** 시스템은 scrap movement와 감사 이력을 기록한다

### Requirement: 재무 연계 이벤트 (WMS-RTN-004)
시스템은 환불·credit note 자체를 회계 처리하지 않고 확정된 반품 수량과 처분을 외부 회계 시스템용 이벤트로 SHALL 발행한다.

#### Scenario: 환불 가능 반품 확정
- **GIVEN** RMA 정책상 환불 가능한 수량의 입고와 검사가 완료되었다
- **WHEN** 반품 처분이 확정된다
- **THEN** 시스템은 중복 방지 키가 있는 `return.disposition.confirmed` 이벤트를 outbox에 기록한다

### Requirement: 반품 추적성 (WMS-RTN-005)
시스템은 원출고부터 반품 입고, 검사, 처분과 후속 재고 movement까지 SHALL 추적한다.

#### Scenario: 반품 serial 조회
- **GIVEN** 반품 처리된 serial이 있다
- **WHEN** 사용자가 serial 계보를 조회한다
- **THEN** 시스템은 원출고 고객, RMA, 검사 결과와 현재 처분 상태를 시간순으로 반환한다
