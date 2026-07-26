# ProcessGPT WMS 자동 작업 연동 명세

## ADDED Requirements

### Requirement: WMS MCP 자동 작업 실행 (WMS-COMP-AUTO-001)
시스템은 WMS 연동 serviceTask에서 허용된 WMS MCP 도구를 호출하고 구조화된 업무 결과를 워크아이템 output에 SHALL 보존한다.

#### Scenario: WMS 명령 실행 성공
- **GIVEN** serviceTask에 WMS 도구명, 입력 매핑과 테넌트 service identity가 설정되어 있다
- **WHEN** 자동 작업 worker가 활동을 실행한다
- **THEN** 시스템은 process instance와 activity에서 생성한 correlation 및 idempotency key로 도구를 호출한다
- **AND** 문서 ID, 번호, 상태, 버전, deep link와 업무 결과를 output에 기록한 뒤 다음 활동을 진행한다

### Requirement: WMS 자동 작업 재시도 분류 (WMS-COMP-AUTO-002)
시스템은 WMS MCP 오류를 일시적, 업무 검증, 권한, 버전 충돌과 사람 승인 필요로 SHALL 분류한다.

#### Scenario: 일시적 장애
- **GIVEN** WMS MCP가 timeout 또는 일시적 가용성 오류를 반환한다
- **WHEN** 자동 작업이 실패한다
- **THEN** 시스템은 같은 idempotency key로 제한된 backoff 재시도를 수행한다
- **AND** 중복 PO 또는 재고 movement가 생기지 않는다

#### Scenario: 사람 승인 필요
- **GIVEN** WMS 도구가 `requires_human_approval`과 승인 대상 문서를 반환한다
- **WHEN** 자동 작업이 결과를 처리한다
- **THEN** 시스템은 활동을 성공으로 오인하지 않고 WMS 문서 버전이 연결된 HITL workitem을 생성한다

#### Scenario: 업무 검증 실패
- **GIVEN** WMS가 재고 부족, 허용 오차 초과 또는 상태 불일치 오류를 반환한다
- **WHEN** 자동 작업이 결과를 처리한다
- **THEN** 시스템은 같은 명령을 무한 재시도하지 않고 BPMN 예외 경로에 구조화된 오류를 전달한다
