# WMS 프로세스 오케스트레이션 명세

## ADDED Requirements

### Requirement: 업무 의도 기반 MCP 계약 (WMS-ORC-001)
WMS MCP 서버는 테이블 CRUD가 아닌 재고 조회, 제안, RFQ, 승인 요청, PO 확정, 입고, 검사, 처분과 적치 등 업무 의도 단위의 도구를 SHALL 제공한다.

#### Scenario: 재고 가용량 조회
- **GIVEN** ProcessGPT 서비스 계정이 대상 테넌트·창고의 재고 읽기 scope를 가진다
- **WHEN** `wms.inventory.get_availability`를 상품·창고와 기준 시각으로 호출한다
- **THEN** 도구는 on-hand, available, blocked, confirmed inbound/outbound, forecasted와 계산 시각을 구조화해 반환한다

#### Scenario: 허용되지 않은 테이블 조작
- **GIVEN** MCP client가 임의 SQL 또는 원장 row 수정을 요청한다
- **WHEN** WMS MCP에 등록되지 않은 저수준 명령을 호출한다
- **THEN** 서버는 실행하지 않고 지원되는 업무 도구만 노출한다

### Requirement: 쓰기 도구의 안전 계약 (WMS-ORC-002)
모든 WMS MCP 쓰기 도구는 tenant, actor/service identity, idempotency key, correlation, expected version과 선택적 dry-run을 SHALL 처리한다.

#### Scenario: Dry-run PO 확정
- **GIVEN** 승인된 구매 문서가 있다
- **WHEN** ProcessGPT가 `wms.procurement.confirm_po`를 `dry_run=true`로 호출한다
- **THEN** 도구는 생성될 PO, 입하 예정과 외부 통지 요약을 반환한다
- **AND** 실제 문서·outbox·원장을 변경하지 않는다

#### Scenario: 중복 쓰기 호출
- **GIVEN** PO 확정 도구가 특정 idempotency key로 성공했다
- **WHEN** ProcessGPT가 동일 key와 payload로 재호출한다
- **THEN** 도구는 동일 PO 식별자와 최초 결과를 반환한다

### Requirement: 프로세스와 업무 문서 연결 (WMS-ORC-003)
시스템은 WMS 문서에 ProcessGPT의 process instance, activity, workitem, correlation과 deep link를 SHALL 연결한다.

#### Scenario: RFQ 작업에서 생성된 문서
- **GIVEN** ProcessGPT 자동 활동이 RFQ 생성 도구를 호출한다
- **WHEN** RFQ가 성공적으로 생성된다
- **THEN** 시스템은 RFQ와 해당 프로세스 인스턴스·활동을 연결한다
- **AND** ProcessGPT에는 문서 ID, 번호, 상태, 버전과 WMS deep link를 반환한다

### Requirement: 트랜잭션 Outbox 이벤트 (WMS-ORC-004)
시스템은 업무 상태 변경과 같은 트랜잭션 안에서 ProcessGPT용 이벤트를 outbox에 SHALL 기록한다.

#### Scenario: 품질 불합격
- **GIVEN** 검사가 진행 중이다
- **WHEN** 인가된 검사자가 불합격을 확정한다
- **THEN** 시스템은 판정과 함께 `quality.inspection.failed` 이벤트를 outbox에 기록한다
- **AND** 전달 worker는 correlation을 사용해 올바른 프로세스 인스턴스에 신호를 보낸다

### Requirement: 보상 명령 (WMS-ORC-005)
시스템은 이미 실행된 명령을 삭제·롤백하지 않고 업무적으로 허용되는 반대 문서 또는 취소 상태로 SHALL 보상한다.

#### Scenario: 확정 전 RFQ 취소 보상
- **GIVEN** 프로세스가 만든 RFQ가 아직 PO로 확정되지 않았다
- **WHEN** ProcessGPT가 승인 거절에 따라 보상을 요청한다
- **THEN** 시스템은 RFQ를 취소하고 연결된 열린 제안을 해제한다
- **AND** 최초 문서와 보상 문서의 상관관계를 기록한다

#### Scenario: 이미 입고된 PO 취소 시도
- **GIVEN** PO에 입고·원장 이력이 있다
- **WHEN** 일반 취소 보상을 요청한다
- **THEN** 시스템은 과거 이력을 삭제하지 않고 반품·잔량 취소 등 허용 가능한 보상 선택지를 반환한다

### Requirement: 대상 BPMN 전체 실행 (WMS-ORC-006)
시스템은 재고 부족 감지부터 구매 승인, PO, 입고, 검사와 폐기 또는 적치까지 Odoo 없이 SHALL 실행한다.

#### Scenario: 합격 경로
- **GIVEN** 재고가 Min 아래이고 구매 승인자가 제안을 승인한다
- **WHEN** 공급사 입고가 검사에 합격하고 적치 작업이 완료된다
- **THEN** 프로세스는 PO·receipt·inspection·putaway 문서를 연결한 채 종료된다
- **AND** 적치 수량만 AVAILABLE 원장에 반영된다

#### Scenario: 불합격 폐기 경로
- **GIVEN** 입고 수량이 품질 검사에서 불합격된다
- **WHEN** 폐기 처분이 승인되고 폐기 작업이 완료된다
- **THEN** 프로세스는 폐기 종료 경로로 진행한다
- **AND** 불합격 수량은 AVAILABLE에 반영되지 않고 scrap 계보가 남는다
