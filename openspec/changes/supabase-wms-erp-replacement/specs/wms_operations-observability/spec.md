# WMS 운영 관찰성 명세

## ADDED Requirements

### Requirement: 운영 대시보드 (WMS-OBS-001)
시스템은 창고별 재고 부족, 예정·지연 입고, 품질 격리, 작업 backlog, 출고 SLA, 재고 정확도와 처리량 KPI를 SHALL 제공한다.

#### Scenario: 실시간 작업 KPI 갱신
- **GIVEN** 관리자가 창고 overview를 보고 있다
- **WHEN** 다른 작업자가 입고 또는 피킹 작업을 완료한다
- **THEN** private Broadcast는 변경 식별자와 버전을 통지한다
- **AND** 화면은 RLS 조회로 해당 KPI를 갱신한다

### Requirement: 감사 이벤트 (WMS-OBS-002)
시스템은 승인, 상태 변경, 권한 변경, 원장 명령, 예외 해결과 외부 호출에 actor, 시각, 전후 값, 사유와 correlation을 SHALL 기록한다.

#### Scenario: PO 승인 감사
- **GIVEN** 승인 대기 PO가 있다
- **WHEN** 승인자가 결정을 제출한다
- **THEN** 시스템은 승인자, 정책, 문서 버전, 결정, 사유와 ProcessGPT workitem을 감사 이벤트로 보존한다

### Requirement: 업무 알림 (WMS-OBS-003)
시스템은 품절 위험, 입고 지연, 품질 불합격, 작업 SLA, 실사 차이와 통합 실패를 역할·창고별로 SHALL 알린다.

#### Scenario: 동일 상태 중복 알림
- **GIVEN** 같은 PO 지연 상태로 이미 열린 알림이 있다
- **WHEN** monitor가 다시 실행된다
- **THEN** 시스템은 새 알림을 무한 생성하지 않고 기존 알림의 마지막 확인 시각과 심각도를 갱신한다

### Requirement: Outbox 재시도와 Dead Letter (WMS-OBS-004)
시스템은 외부 이벤트 전달의 시도 횟수, 다음 시각, 마지막 오류와 최종 실패를 SHALL 관리한다.

#### Scenario: 일시적 외부 장애
- **GIVEN** 공급사 webhook이 일시적으로 실패한다
- **WHEN** worker가 outbox를 처리한다
- **THEN** 시스템은 지수 backoff와 최대 시도 정책에 따라 재시도한다
- **AND** 같은 event id로 중복 업무 이벤트를 만들지 않는다

#### Scenario: 최대 재시도 초과
- **GIVEN** outbox 메시지가 최대 시도 횟수를 넘었다
- **WHEN** 마지막 전달도 실패한다
- **THEN** 시스템은 메시지를 DEAD_LETTER 상태로 전환하고 운영자에게 알린다
- **AND** 운영자는 원인 수정 후 같은 업무 event id로 재전송할 수 있다

### Requirement: 성능·신뢰성 지표 (WMS-OBS-005)
시스템은 RPC latency/error rate, task 처리시간, Realtime 연결, outbox lag, 원장 projection lag와 job 성공률을 SHALL 측정한다.

#### Scenario: 원장 projection 지연
- **GIVEN** balance projection lag가 운영 임계값을 넘는다
- **WHEN** health monitor가 지연을 감지한다
- **THEN** 시스템은 대시보드에 최신 계산 시각과 degraded 상태를 표시한다
- **AND** 잔량이 오래된 경우 위험 명령에 경고 또는 차단 정책을 적용한다

### Requirement: 운영 데이터 내보내기 (WMS-OBS-006)
시스템은 인가된 사용자가 필터와 기준 시각이 기록된 재고, 원장, 주문, 작업과 감사 데이터를 SHALL 내보내게 한다.

#### Scenario: 대용량 원장 내보내기
- **GIVEN** 감사자가 기간·창고·상품 범위를 선택했다
- **WHEN** 비동기 내보내기를 요청한다
- **THEN** 시스템은 생성 작업과 완료 알림을 제공한다
- **AND** 결과 파일을 만료되는 권한 URL로 제공하고 다운로드를 감사 기록한다
