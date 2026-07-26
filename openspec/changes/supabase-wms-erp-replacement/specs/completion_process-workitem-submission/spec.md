# ProcessGPT WMS 사람 작업 제출 명세

## ADDED Requirements

### Requirement: WMS 문서 문맥 보존 (WMS-COMP-HITL-001)
시스템은 구매 승인, 품질 처분, 폐기 또는 재고 조정 HITL workitem에 WMS 문서 ID, 유형, 상태, 버전, correlation과 deep link를 SHALL 보존한다.

#### Scenario: 구매 승인 화면 열기
- **GIVEN** WMS가 승인 필요 PO를 반환했다
- **WHEN** 승인자가 ProcessGPT workitem을 연다
- **THEN** 시스템은 PO 번호, 금액, 공급사, 변경 요약과 WMS deep link를 표시한다
- **AND** 제출 payload에 보이지 않는 문서 ID와 expected version을 포함한다

### Requirement: 최신 WMS 버전 검증 제출 (WMS-COMP-HITL-002)
시스템은 사람 결정을 WMS에 적용하기 전에 연결된 문서의 현재 버전과 workitem의 expected version을 SHALL 검증한다.

#### Scenario: 승인 대기 중 PO 변경
- **GIVEN** 승인자가 workitem을 연 뒤 WMS PO 버전이 변경되었다
- **WHEN** 승인자가 이전 버전을 승인한다
- **THEN** 시스템은 결정을 적용하지 않고 stale version 응답과 변경 요약을 표시한다
- **AND** 최신 조건을 확인한 새 제출을 요구한다

### Requirement: 결정과 프로세스 전이의 일관성 (WMS-COMP-HITL-003)
시스템은 WMS 업무 결정이 성공적으로 확정된 후에만 해당 승인·거절 BPMN 분기로 SHALL 진행한다.

#### Scenario: 구매 승인 성공
- **GIVEN** workitem과 WMS PO 버전이 일치하고 승인자가 권한을 가진다
- **WHEN** 승인 결정을 제출한다
- **THEN** 시스템은 같은 correlation과 idempotency key로 WMS 승인을 먼저 확정한다
- **AND** WMS가 반환한 새 상태·버전을 output에 기록한 후 승인 분기로 진행한다

#### Scenario: WMS 결정 적용 실패
- **GIVEN** 승인 제출 중 WMS가 권한 또는 상태 오류를 반환한다
- **WHEN** ProcessGPT가 응답을 처리한다
- **THEN** 시스템은 workitem을 완료 처리하지 않고 오류를 사용자에게 표시한다
- **AND** BPMN의 승인 또는 거절 분기로 진행하지 않는다
