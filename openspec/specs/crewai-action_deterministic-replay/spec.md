# 결정론적 실행 경로 고착화(Deterministic Replay) 명세

## Purpose
에이전트(LLM)가 MCP 도구 호출로 한 번 성공적으로 수행한 활동의 실행 경로를 파라미터화된 Python 코드로 고착화(solidify)하여 보존하고, 동일 프로세스 정의의 동일 활동이 이후 다시 수행될 때 LLM 추론 없이 저장된 코드를 결정론적으로 재실행할 수 있는 능력을 보장한다. 고착화된 코드는 특정 에이전트 런타임에 종속되지 않는 공유 실행 자산이며, CrewAI Action과 DeepAgents가 동일한 `(proc_def_id, activity_id, tenant_id)` 키로 조회·실행한다. 이를 통해 한 번 검증된 업무 실행 경로가 할루시네이션 없이 매번 동일하게 재현되고, LLM 호출 비용과 실행 시간이 절감된다.

## Requirements

### Requirement: 도구 실행 이력 기록
시스템은 에이전트가 활동 수행 중 MCP 도구를 호출할 때마다 도구명과 호출 인자를 담은 `tool_usage_finished` 이벤트를 SHALL 기록한다. CrewAI Action은 `crew_type: action`, DeepAgents는 `crew_type: deepagents`를 사용하되 이벤트 데이터 계약은 `{tool_name, args}`로 동일해야 한다.

#### Scenario: MCP 도구 호출 이력 적재
- **GIVEN** 에이전트가 활동을 수행하며 MCP 서버의 도구(예: `execute_sql`)를 호출한다
- **WHEN** 각 도구 호출이 완료된다
- **THEN** 시스템은 해당 작업(todo) 식별자에 연결된 `tool_usage_finished` 이벤트를 `{tool_name, args}` 형식의 데이터와 함께 보존한다

#### Scenario: DeepAgents MCP 도구 호출 이력 적재
- **GIVEN** DeepAgents가 워크아이템을 수행하며 MCP 도구를 호출한다
- **WHEN** 도구 호출이 완료된다
- **THEN** 시스템은 `crew_type: deepagents`인 `tool_usage_finished` 이벤트에 CrewAI Action과 동일한 `{tool_name, args}` 계약으로 호출 이력을 보존한다

### Requirement: 실행 경로의 코드 고착화
시스템은 활동의 도구 실행 이력으로부터 실행 가능한 Python 코드를 생성하여 `(proc_def_id, activity_id, tenant_id)` 키로 SHALL 보존한다. 생성된 코드는 기록된 도구 호출 순서를 그대로 재현하며, LLM 호출을 포함하지 SHALL NOT 않는다.

#### Scenario: 이력 기반 코드 생성 및 저장
- **GIVEN** 활동에 재현 가능한 도구 실행 이력이 존재한다
- **WHEN** 시스템이 해당 작업에 대해 코드 생성을 수행한다
- **THEN** 기록된 도구 호출들을 순서대로 재현하는 독립 실행형 Python 코드가 생성되어 프로세스 정의·활동·테넌트 키로 보존된다

#### Scenario: 재현 불가 도구 호출 제외
- **GIVEN** 실행 이력에 `mem0`, `memento`, `human_asked`, `dmn_rule` 호출 또는 SELECT 전용 `execute_sql` 호출이 포함되어 있다
- **WHEN** 시스템이 코드 생성 대상 이력을 선별한다
- **THEN** 해당 호출들은 고착화 대상에서 제외된다

#### Scenario: 재현 가능한 이력이 없을 때 생성 실패 무시
- **GIVEN** 활동에 고착화할 도구 실행 이력이 없다
- **WHEN** 시스템이 코드 생성을 시도한다
- **THEN** 코드 생성은 실패로 종료되지만 활동 실행 결과 처리에는 영향을 주지 않는다

### Requirement: 동적 값의 파라미터 추출
시스템은 코드 생성 시 도구 호출 인자에서 업무 데이터(이름, 수량, 경로 등)를 파라미터로 추출하여 `${변수}` 템플릿으로 치환하고, 파라미터 명세(이름·타입·예시)를 코드와 함께 SHALL 보존한다. 시스템 설정값(스키마, 명령어, URL)은 파라미터로 추출하지 SHALL NOT 않는다.

#### Scenario: SQL 인자의 업무 값 파라미터화
- **GIVEN** 이력에 `UPDATE product SET stock=100 WHERE name='iPhone'` 형태의 `execute_sql` 호출이 있다
- **WHEN** 시스템이 코드를 생성한다
- **THEN** `stock`·`name` 값이 파라미터로 추출되고 SQL 인자는 `${stock_quantity}`, `${product_name}` 템플릿으로 치환된다

#### Scenario: 파라미터 제안 실패 시 규칙 기반 대체
- **GIVEN** LLM 기반 파라미터 제안이 실패한다
- **WHEN** 시스템이 코드를 생성한다
- **THEN** 정규식 기반 규칙으로 파라미터를 추출하여 코드 생성을 계속한다

### Requirement: 고착화된 코드의 결정론적 재실행
시스템은 동일 `(proc_def_id, activity_id, tenant_id)`의 활동이 다시 수행될 때 보존된 코드를 조회하고, 존재하면 새 작업의 입력에서 파라미터 값만 추출하여 저장된 코드를 서브프로세스로 SHALL 실행한다. 이때 CrewAI 크루 또는 DeepAgents 그래프 등 LLM 추론 기반 실행기는 생성되지 SHALL NOT 않는다.

#### Scenario: 저장된 코드로 LLM 없이 재실행
- **GIVEN** 활동에 고착화된 코드가 존재하고 새 작업 입력이 주어진다
- **WHEN** 시스템이 해당 활동을 실행한다
- **THEN** 저장된 코드가 테넌트의 활성 MCP 서버 구성(`MCP_CONFIG`)과 추출된 파라미터로 실행되고, 도구 호출 결과 목록이 `{ok, results}` 형식으로 반환되며 LLM 실행기는 생성되지 않는다

#### Scenario: DeepAgents 실행 전 결정론적 분기
- **GIVEN** 채팅이 아닌 DeepAgents 워크아이템에 고착화된 코드가 존재한다
- **WHEN** DeepAgents 실행기가 워크아이템 처리를 시작한다
- **THEN** 시스템은 DeepAgents 그래프를 구성하기 전에 저장 코드를 실행하고 `llm_calls: 0`인 결과를 반환한다

#### Scenario: 저장된 코드가 없으면 에이전트 실행으로 폴백
- **GIVEN** 활동에 고착화된 코드가 존재하지 않는다
- **WHEN** 시스템이 해당 활동을 실행한다
- **THEN** 시스템은 선택된 런타임의 기존 에이전트 실행 경로(CrewAI Action 또는 DeepAgents)로 활동을 수행한다

#### Scenario: 저장소 마이그레이션이 없는 DeepAgents 환경
- **GIVEN** 기존 설치 환경에 `mcp_python_code` 테이블이 아직 존재하지 않는다
- **WHEN** DeepAgents가 결정론적 코드 조회를 시도한다
- **THEN** 조회 실패를 기록하고 기존 DeepAgents 실행 경로로 폴백한다

#### Scenario: 재실행 결과의 폼 데이터 구성
- **GIVEN** 작업이 폼 제출형(`formHandler:<form_id>`) 활동이다
- **WHEN** 고착화된 코드 실행이 성공한다
- **THEN** 실행 결과로부터 폼 필드 키에 맞는 `form_result`가 구성되어 최종 결과 이벤트로 전달된다

### Requirement: 실행 방식 표시
시스템은 활동이 어떤 방식으로 실행되었는지 운영자가 워크아이템 화면(에이전트 모니터)에서 구분할 수 있도록 실행 이벤트를 SHALL 기록한다. 고착화된 코드 재실행은 `결정론적 코드 실행 결과` 또는 `DeepAgents 결정론적 코드 실행 결과` 카드(`task_started`/`task_completed`, `crew_type: result`, `execution_mode: deterministic`)로 기록되며, 에이전트 도구 추론 이벤트(`tool_usage_started`/`tool_usage_finished`)를 남기지 SHALL NOT 않는다.

#### Scenario: LLM 실행 이력 표시
- **GIVEN** 활동이 LLM 에이전트 추론으로 수행되었다
- **WHEN** 운영자가 워크아이템의 에이전트 모니터를 연다
- **THEN** 에이전트 실행 카드(`crew_type: action`)와 함께 수행된 도구 사용 이력(예: `execute_sql` 호출별 SQL)이 표시된다

#### Scenario: 결정론적 재실행 표시
- **GIVEN** 활동이 고착화된 코드로 재실행되었다
- **WHEN** 운영자가 워크아이템의 에이전트 모니터를 연다
- **THEN** `결정론적 코드 실행 결과` 카드가 표시되고, 결과에 실행 방식(고착화된 코드, LLM 추론 없음)과 재현된 스텝 목록이 포함되며, 도구 추론 이력은 표시되지 않는다

#### Scenario: DeepAgents 결정론적 재실행 표시
- **GIVEN** DeepAgents 워크아이템이 고착화된 코드로 재실행되었다
- **WHEN** 운영자가 실제 워크아이템의 에이전트 모니터를 연다
- **THEN** `DeepAgents 결정론적 코드 실행 결과` 카드와 `execution_mode: deterministic`, `llm_calls: 0` 결과가 표시되고 도구 추론 이력은 표시되지 않는다

## Notes
- CrewAI Action의 순방향 고착화·재실행 진입점은 현재 실행 흐름에서 비활성(주석 처리) 상태이며, 활성화 시 이 명세의 계약을 따라야 한다.
- DeepAgents 진입점은 `services/deepagents/executor.py`에서 그래프 구성 전에 활성화되어 있으며, 실행 구현은 `services/deepagents/core/deterministic/replay.py`에 있다.
- DeepAgents 전용 분기와 undo 통합 계약은 `deepagents_deterministic-replay-undo` 명세가 다룬다.
- 보상(undo) 방향의 코드 생성은 `completion_process-activity-rework` 명세의 "보상 코드 생성" 요구사항이, undo 코드의 형태·실행은 `crewai-action_deterministic-undo` 및 `deepagents_deterministic-replay-undo` 명세가 다룬다.
