# 결정론적 Undo(실행 취소) 명세

## Purpose
에이전트(LLM)가 MCP 도구 호출로 수행한 활동이 남긴 부수효과(DB 변경 등)를, 기록된
도구 실행 이력(이벤트 로그)으로부터 생성된 역연산(undo) 코드로 안전하게 되돌릴 수
있는 능력을 보장한다. 재작업(rework) 시 시스템은 undo 코드를 먼저 실행해 이전
실행의 부수효과를 제거한 뒤 활동을 다시 수행함으로써, "시도 → 검증 → 확정/취소"
사이클을 프로그래밍 없이 지원한다. undo 코드 생성 시점의 계약은
`completion_process-activity-rework` 명세의 "보상 코드 생성" 요구사항이 다루며,
이 명세는 생성된 undo 코드의 형태와 CrewAI Action·DeepAgents가 공유하는 실행 계약을 다룬다.

## Requirements

### Requirement: 이벤트 로그 기반 역연산 코드
undo 코드는 도구 실행 이력(이벤트 로그)만을 입력으로 받아 기록된 부수효과를 역연산으로 SHALL 되돌린다. 역연산 대상 값은 이벤트 로그에서 동적으로 파싱하며 특정 값을 하드코딩하거나 LLM을 호출해서는 안 된다.

#### Scenario: 기록된 쓰기 작업의 역연산
- **GIVEN** 이전 실행의 이벤트 로그에 `UPDATE`(재고 변경)와 `INSERT`(감사 로그) 호출이 기록되어 있다
- **WHEN** undo 코드가 이벤트 로그를 입력으로 실행된다
- **THEN** `UPDATE`는 이전 값으로 원복되고 `INSERT`된 행은 삭제되어, 대상 데이터가 실행 이전 상태로 되돌아간다

#### Scenario: 읽기 전용 호출은 되돌리지 않음
- **GIVEN** 이벤트 로그에 SELECT 등 읽기 전용 호출이 포함되어 있다
- **WHEN** undo 코드가 실행된다
- **THEN** 읽기 전용 호출에 대한 역연산은 수행되지 않는다

#### Scenario: 다른 실행의 결과는 보존
- **GIVEN** 동일 테이블에 다른 활동 실행이 반영한 데이터가 존재한다
- **WHEN** 특정 활동의 undo 코드가 실행된다
- **THEN** 해당 활동의 이벤트 로그에 기록된 부수효과만 되돌려지고, 다른 실행의 결과는 변경되지 않는다

### Requirement: 재작업 시 undo 우선 실행
시스템은 재작업(`rework_count > 0`)으로 활동이 다시 실행될 때 보존된 undo 코드를 먼저 실행한 뒤 고착화된 순방향 코드를 SHALL 실행하고, 두 실행의 결과 목록을 합쳐 반환한다.

#### Scenario: undo 후 새 입력으로 재실행
- **GIVEN** 활동에 undo 코드와 순방향 코드가 모두 보존되어 있고, 수정된 입력의 재작업 워크아이템이 주어진다
- **WHEN** 시스템이 재작업 활동을 실행한다
- **THEN** undo 코드가 먼저 이전 부수효과를 되돌린 후, 순방향 코드가 새 입력 값으로 실행되어 데이터가 수정된 값으로 반영된다

#### Scenario: DeepAgents 재작업에서 이전 실행 이력 선택
- **GIVEN** DeepAgents 재작업의 `rework_count > 0`이고 동일 루트 프로세스·활동의 이전 실행이 존재한다
- **WHEN** 시스템이 undo 입력을 구성한다
- **THEN** 가장 최근의 더 낮은 `rework_count` 작업에서 쓰기 `tool_usage_finished` 이벤트만 수집하고 SELECT 및 `mem0`, `memento`, `human_asked`, `dmn_rule` 이벤트는 제외한다

#### Scenario: DeepAgents undo 후 순방향 코드 실행
- **GIVEN** DeepAgents 활동에 `compensation`과 순방향 `code`가 모두 존재한다
- **WHEN** 재작업 워크아이템을 실행한다
- **THEN** `{"event_logs": [...]}` 입력으로 compensation을 먼저 실행하고, 새 작업 입력에서 추출한 파라미터로 순방향 코드를 실행하여 `undo_results`와 `results`를 함께 반환한다

### Requirement: Undo 실행 방식 표시
시스템은 undo 실행을 운영자가 워크아이템 화면(에이전트 모니터)에서 확인할 수 있도록 실행 이벤트로 SHALL 기록하며, undo 실행은 에이전트 도구 추론 이벤트를 남겨서는 안 된다.

#### Scenario: undo 실행 카드 표시
- **GIVEN** 재작업 활동이 undo 코드 실행을 포함해 수행되었다
- **WHEN** 운영자가 워크아이템의 에이전트 모니터를 연다
- **THEN** Undo 실행 카드가 표시되고, 결과에 실행 방식(고착화된 undo 코드, LLM 추론 없음)과 되돌린/재실행한 스텝 목록이 포함된다

#### Scenario: DeepAgents Undo 실행 카드 표시
- **GIVEN** DeepAgents 재작업이 undo 코드와 순방향 코드를 실행했다
- **WHEN** 운영자가 실제 워크아이템의 에이전트 모니터를 연다
- **THEN** `DeepAgents Undo 후 재실행 결과` 카드가 `crew_type: result`, `execution_mode: deterministic-undo`로 표시되고 결과에 `llm_calls: 0`, `undo_results`, `results`가 포함된다

## Notes
- undo 코드 생성 주체는 completion 서비스(재작업 처리 중 `mcp_python_code.compensation`에 보존)다.
- 실행 주체는 CrewAI Action 또는 DeepAgents의 결정론적 실행 경로이며, 두 런타임 모두 동일한 `mcp_python_code.compensation`과 이벤트 로그 계약을 사용한다.
- DeepAgents 구현·실제 UI 검증은 `deepagents_deterministic-replay-undo` 명세와 그 E2E 결과를 참조한다.
- 순방향 고착화·재실행 계약은 `crewai-action_deterministic-replay` 명세를 참조한다.
