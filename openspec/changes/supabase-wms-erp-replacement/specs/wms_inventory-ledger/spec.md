# WMS 재고 원장 명세

## ADDED Requirements

### Requirement: 불변 재고 수불 원장 (WMS-INV-001)
시스템은 모든 재고 증감과 상태·위치 이동을 원인 문서가 연결된 불변 원장 entry로 SHALL 기록한다.

#### Scenario: 위치 간 재고 이동
- **GIVEN** 출발 위치에 이동 가능한 상품 수량이 있다
- **WHEN** 인가된 작업이 출발 위치에서 목적 위치로 이동을 확정한다
- **THEN** 시스템은 하나의 트랜잭션에서 출발 차감과 목적 증가 entry를 같은 movement에 기록한다
- **AND** 두 entry 수량의 합은 기본 단위 기준 0이다

#### Scenario: 과거 원장 수정 시도
- **GIVEN** 확정된 원장 entry가 있다
- **WHEN** 사용자 또는 통합이 해당 entry의 수량을 수정하거나 삭제한다
- **THEN** 시스템은 요청을 거부한다
- **AND** 정정은 반대 entry와 새 정정 movement로만 허용한다

### Requirement: 재고 잔량과 가용량 투영 (WMS-INV-002)
시스템은 상품·창고·위치·재고상태·lot·serial·handling unit별 on-hand, reserved, blocked, available, inbound, outbound와 forecasted 수량을 SHALL 제공한다.

#### Scenario: 가용재고 계산
- **GIVEN** on-hand 100, reserved 30, blocked 10인 상품이 있다
- **WHEN** 사용자가 가용재고를 조회한다
- **THEN** 시스템은 available을 60으로 반환한다
- **AND** 확정 입고·출고를 포함한 forecasted 수량을 별도로 반환한다

#### Scenario: 품질 재고 제외
- **GIVEN** 입고 수량이 QC 또는 HOLD 상태에 있다
- **WHEN** 판매 가능 가용재고를 조회하거나 예약한다
- **THEN** 시스템은 해당 수량을 available에서 제외한다

### Requirement: 원자적 재고 예약 (WMS-INV-003)
시스템은 출고 또는 작업 수요에 대해 가용재고를 원자적으로 예약하고 과예약을 SHALL 방지한다.

#### Scenario: 동시 예약 경쟁
- **GIVEN** 가용재고가 10이고 서로 다른 두 요청이 각각 8을 예약하려 한다
- **WHEN** 두 요청이 동시에 처리된다
- **THEN** 시스템은 최대 한 요청만 전량 성공시킨다
- **AND** 다른 요청에는 확정된 부족 수량과 재시도 가능한 상태를 반환한다

#### Scenario: 예약 원인 취소
- **GIVEN** 출고 주문에 연결된 유효한 예약이 있다
- **WHEN** 출고 주문이 취소된다
- **THEN** 시스템은 예약을 해제하고 가용 수량을 복원한다
- **AND** 해제 원인을 감사 이력에 남긴다

### Requirement: 멱등 재고 명령 (WMS-INV-004)
시스템은 모든 재고 변경 명령에 `idempotency_key`를 요구하고 동일 키의 중복 실행을 SHALL 방지한다.

#### Scenario: 네트워크 재시도
- **GIVEN** 재고 이동 명령이 성공했으나 클라이언트가 응답을 받지 못했다
- **WHEN** 클라이언트가 동일 키와 동일 payload로 다시 요청한다
- **THEN** 시스템은 새 원장을 만들지 않고 최초 결과를 반환한다

#### Scenario: 동일 키의 다른 payload
- **GIVEN** 특정 키로 처리된 명령이 있다
- **WHEN** 같은 키에 다른 수량 또는 문서를 담아 요청한다
- **THEN** 시스템은 idempotency 충돌로 거부한다

### Requirement: 버전 기반 동시성 제어 (WMS-INV-005)
시스템은 변경 명령의 `expected_version`을 검증하여 stale 상태의 덮어쓰기를 SHALL 방지한다.

#### Scenario: 오래된 화면에서 재고 조정
- **GIVEN** 사용자가 본 조정 문서 이후 서버 버전이 변경되었다
- **WHEN** 사용자가 이전 버전으로 확정을 요청한다
- **THEN** 시스템은 변경을 적용하지 않고 현재 버전과 갱신된 차이를 반환한다

### Requirement: 승인된 재고 조정 (WMS-INV-006)
시스템은 직접 잔량 수정 대신 사유, 근거 문서, 권한과 승인 상태가 있는 조정 movement를 SHALL 사용한다.

#### Scenario: 큰 재고 조정
- **GIVEN** 조정 수량 또는 평가금액이 승인 임계값을 초과한다
- **WHEN** 재고 담당자가 조정을 제출한다
- **THEN** 시스템은 PENDING_APPROVAL 상태로 저장하고 원장 반영을 보류한다
- **AND** 승인 후에만 조정 entry를 생성한다
