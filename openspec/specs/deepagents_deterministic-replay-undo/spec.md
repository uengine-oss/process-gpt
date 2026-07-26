# DeepAgents 결정론적 Replay/Undo 명세

## Purpose
DeepAgents가 수행하는 프로세스 활동도 CrewAI Action과 동일한
`mcp_python_code` 자산을 사용해, 검증된 MCP 실행 경로를 LLM 없이 재실행하고
재작업 시 이전 부수효과를 undo한 뒤 새 입력으로 다시 실행할 수 있어야 한다.

## Requirements

### Requirement: DeepAgents 실행 전 저장 코드 조회
시스템은 채팅이 아닌 DeepAgents 워크아이템을 실행하기 전에 `(proc_def_id, activity_id, tenant_id)` 키의 순방향 코드를 SHALL 조회한다.

#### Scenario: 저장 코드가 있는 활동
- **GIVEN** 동일 프로세스·활동·테넌트에 고착화된 코드가 존재한다
- **WHEN** DeepAgents 워크아이템 실행이 시작된다
- **THEN** DeepAgents 그래프와 LLM을 생성하지 않고 저장 코드를 실행한다

#### Scenario: 저장 코드가 없는 활동
- **GIVEN** 고착화된 코드가 존재하지 않는다
- **WHEN** DeepAgents 워크아이템 실행이 시작된다
- **THEN** 기존 DeepAgents 그래프 실행 경로로 폴백한다

#### Scenario: 저장 코드 테이블이 없는 기존 설치
- **GIVEN** 설치 환경에 `mcp_python_code` 테이블이 아직 없다
- **WHEN** DeepAgents가 저장 코드를 조회한다
- **THEN** 조회 오류를 기록하고 기존 DeepAgents 그래프 실행 경로로 폴백한다

#### Scenario: 채팅 요청은 결정론적 분기에서 제외
- **GIVEN** 요청에 채팅 스트리머가 연결되어 있다
- **WHEN** DeepAgents가 요청을 실행한다
- **THEN** 워크아이템용 결정론적 분기를 적용하지 않고 기존 대화형 DeepAgents 경로를 사용한다

### Requirement: 테넌트 MCP와 새 입력 파라미터 사용
시스템은 활성화된 테넌트 MCP 설정을 `MCP_CONFIG`로 전달하고 새 워크아이템 지시에서 파라미터 명세의 업무 값을 추출해 순방향 코드에 SHALL 전달하며, 파라미터 추출과 코드 실행 중 LLM을 호출해서는 안 된다.

#### Scenario: 다른 업무 값으로 재실행
- **GIVEN** 최초 실행의 상품·수량이 파라미터화된 코드가 있다
- **WHEN** 다른 상품·수량의 DeepAgents 워크아이템이 도착한다
- **THEN** 새 값만 바인딩되고 기록된 MCP 호출 순서는 그대로 재현된다

#### Scenario: 비활성 MCP 서버 제외
- **GIVEN** 테넌트 MCP 설정에 활성·비활성 서버가 함께 존재한다
- **WHEN** DeepAgents가 `MCP_CONFIG`를 구성한다
- **THEN** `enabled: false` 서버와 런타임 전용 `enabled` 속성을 제거하고 활성 서버만 서브프로세스에 전달한다

#### Scenario: 결정론적 코드 실행 실패
- **GIVEN** 저장 코드는 존재하지만 필수 파라미터를 추출할 수 없거나 서브프로세스가 실패한다
- **WHEN** DeepAgents가 결정론적 실행을 시도한다
- **THEN** 검증되지 않은 LLM 실행으로 조용히 폴백하지 않고 워크아이템 실행을 실패로 기록한다

### Requirement: DeepAgents 재작업 시 undo 우선 실행
시스템은 `rework_count > 0`이고 compensation 코드가 존재할 때 이전 동일 활동의 쓰기 이벤트를 수집하여 undo 코드를 먼저 실행하고 순방향 코드를 SHALL 실행하며, SELECT와 제외 도구 이벤트는 undo 입력에서 SHALL 제외한다.

#### Scenario: undo 후 새 입력 적용
- **GIVEN** 이전 실행의 쓰기 이벤트와 undo·순방향 코드가 존재한다
- **WHEN** 재작업 DeepAgents 워크아이템을 실행한다
- **THEN** 이전 부수효과를 되돌린 후 새 입력으로 순방향 실행한다

#### Scenario: undo 입력 계약
- **GIVEN** 이전 실행에서 수집한 쓰기 이벤트가 존재한다
- **WHEN** compensation 코드를 실행한다
- **THEN** 시스템은 `{"event_logs": [...]}` 형식으로 이벤트를 전달하고 순방향 파라미터와 혼합하지 않는다

#### Scenario: undo 대상 이력이 없는 재작업
- **GIVEN** `rework_count > 0`이지만 이전 쓰기 이벤트가 없다
- **WHEN** DeepAgents가 재작업을 실행한다
- **THEN** compensation은 실행하지 않고 새 입력의 순방향 코드만 실행하며 실행 모드는 `deterministic`이다

### Requirement: 실행 방식 표시
결정론적 DeepAgents 실행은 `crew_type: result` 카드로 SHALL 표시하고,
`execution_mode`는 `deterministic` 또는 `deterministic-undo`여야 한다.
이 경로는 `tool_usage_started`/`tool_usage_finished` 추론 이벤트를 만들지
SHALL NOT 한다.

#### Scenario: 운영자 모니터 표시
- **GIVEN** DeepAgents가 저장 코드를 실행했다
- **WHEN** 운영자가 에이전트 모니터를 연다
- **THEN** 결정론적 실행 또는 Undo 후 재실행 카드와 `llm_calls: 0` 결과가 표시된다

#### Scenario: 결정론적 결과 이벤트와 아티팩트
- **GIVEN** DeepAgents 저장 코드 실행이 성공했다
- **WHEN** 실행 결과를 완료 처리한다
- **THEN** 시스템은 같은 job 식별자의 `task_started`/`task_completed` 결과 이벤트와 `assistant_response` 텍스트 아티팩트를 기록한다

## Verification

- 자동 테스트: `services/deepagents/tests/test_deterministic_replay.py`
- 실측 실행: `e2e/run_live_demo.py`
- 실제 UI Playwright 녹화: `e2e/record_live_ui.py`
- 실제 UI 영상: `demo-recordings/deepagents-deterministic-live-demo.mp4`
- 검증된 실측값:
  - Replay: Galaxy 재고 `35 → 250`
  - Undo 후 재실행: iPhone 최종 재고 `60`
  - 결정론적 경로: `llm_calls: 0`
