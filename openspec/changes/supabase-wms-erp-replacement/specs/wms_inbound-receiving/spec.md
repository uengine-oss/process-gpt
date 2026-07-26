# WMS 입하·입고 명세

## ADDED Requirements

### Requirement: PO·ASN 기반 입하 예정 (WMS-INB-001)
시스템은 확정 PO와 공급사 ASN으로 예정 도착일, 차량·운송 참조, 도크, 상품, 수량과 handling unit을 SHALL 관리한다.

#### Scenario: 공급사 ASN 접수
- **GIVEN** 유효한 확정 PO가 있다
- **WHEN** 공급사가 PO line, 예정 시각과 SSCC 목록이 있는 ASN을 제출한다
- **THEN** 시스템은 PO 잔량을 검증하고 입하 예정을 갱신한다
- **AND** 알 수 없는 상품·PO 또는 허용치를 넘는 수량은 예외로 분리한다

### Requirement: 도착과 도크 접수 (WMS-INB-002)
시스템은 입하 도착 시각, 도크 배정, 봉인·차량 정보와 하역 작업을 SHALL 기록한다.

#### Scenario: 도착 등록
- **GIVEN** 오늘 도착할 입하 예정이 있다
- **WHEN** 입고 담당자가 차량 도착을 등록한다
- **THEN** 시스템은 ARRIVED 상태로 전환하고 도크·하역 작업을 생성한다
- **AND** ProcessGPT에 공급사 출하/도착 이벤트를 연결한다

### Requirement: 스캔 기반 입고 (WMS-INB-003)
시스템은 PO 또는 ASN 선택 후 LPN/SSCC, GTIN, lot/serial, 수량을 스캔하여 receipt line을 SHALL 확정한다.

#### Scenario: 정상 부분 입고
- **GIVEN** PO에 특정 상품 100 EA가 예정되어 있다
- **WHEN** 현장 작업자가 올바른 상품과 lot 60 EA를 스캔한다
- **THEN** 시스템은 60 EA를 RECEIVING 또는 QC 위치에 기록한다
- **AND** 나머지 40 EA를 미입고 수량으로 유지한다

#### Scenario: serial 중복 스캔
- **GIVEN** serial 번호가 이미 재고에 있거나 현재 receipt에서 처리되었다
- **WHEN** 작업자가 같은 serial을 다시 스캔한다
- **THEN** 시스템은 수량을 증가시키지 않고 중복 식별자 오류를 반환한다

### Requirement: 초과·미달·파손 예외 (WMS-INB-004)
시스템은 PO 허용 오차를 기준으로 초과·미달·오품·파손을 SHALL 분류하고 승인 또는 처분을 요구한다.

#### Scenario: 허용 범위 초과 입고
- **GIVEN** PO 잔량과 허용 초과 범위를 합쳐 105 EA까지 받을 수 있다
- **WHEN** 작업자가 110 EA를 확정한다
- **THEN** 시스템은 105 EA를 넘는 수량의 자동 확정을 차단한다
- **AND** 초과 수령 승인 또는 공급사 반환 예외를 생성한다

#### Scenario: 파손품 분리
- **GIVEN** 하역 중 파손 수량이 발견되었다
- **WHEN** 작업자가 파손 사유와 사진을 등록한다
- **THEN** 시스템은 파손 수량을 DAMAGED/HOLD 위치로 분리한다
- **AND** 정상 수량과 동일한 가용재고로 합산하지 않는다

### Requirement: 입고 수량 확정과 품질 대기 (WMS-INB-005)
시스템은 입고 확정 시 실제 수령 수량을 PO에 반영하고 품질 대상 수량을 QC 상태로 SHALL 보낸다.

#### Scenario: 검사 대상 상품 입고 완료
- **GIVEN** 상품에 유효한 품질 규칙이 있다
- **WHEN** receipt line이 확정된다
- **THEN** 시스템은 품질 검사와 검사 작업을 생성한다
- **AND** 합격·적치 전까지 해당 수량을 available에 포함하지 않는다

### Requirement: 입고 완료 조건 (WMS-INB-006)
시스템은 모든 처리 수량이 정상, 품질 대기 또는 승인된 예외로 분류된 경우에만 receipt를 SHALL 완료한다.

#### Scenario: 미해결 스캔 차이
- **GIVEN** receipt에 오품 또는 설명되지 않은 수량 차이가 있다
- **WHEN** 작업자가 입고 완료를 요청한다
- **THEN** 시스템은 완료를 거부하고 해결해야 할 예외를 표시한다
