## Why

`bsc-strategy-interview` 스킬로 수립된 BSC 전략맵·BMC 캔버스는 `services/strategy`에 저장되지만, 프로세스를 새로 만들거나(`bpmn-process-generation-skill`) 기존 프로세스/스킬을 개선하는 흐름(`services/agent-feedback`의 피드백 기반 제안·승인)에서는 전혀 참조되지 않는다. 그 결과 조직이 합의한 전략 목표·KPI와 무관하거나 상충하는 프로세스/스킬 변경이 그대로 만들어지거나 승인될 수 있다.

관련 변경인 `deepagents-strategy-ontology-tools`가 "이미 존재하는 프로세스"에 대한 전략 기여도 순방향 조회(`strategy_process-contribution-lookup`)와 실행 중 에이전트의 온톨로지 조회 도구를 도입한다. 그러나 그 조회는 프로세스 정의 id를 전제로 하므로, **아직 그래프에 존재하지 않는 대상** — 확정 전의 프로세스 초안, 스킬/프로세스 개선 제안 내용 — 에는 적용할 수 없다. 이 변경은 그 빈틈을 메운다: 확정·승인 이전 단계에서 자유 텍스트 설명만으로 관련 전략 요소를 탐색하고, 그 확인을 생성/개선 흐름의 필수 단계로 강제한다.

## What Changes

- `services/strategy`에 자유 텍스트(프로세스 초안/개선 제안 설명)를 입력받아 관련 전략 목표·KPI 후보와 근거를 반환하는 조회 전용 기능을 신설한다. 기존 프로세스 정의 id가 함께 주어지면 이미 연결된 전략 요소(온톨로지 그래프상 기존 연결)를 후보와 구분해 함께 반환한다 — 기존 연결 조회는 `deepagents-strategy-ontology-tools`의 `strategy_process-contribution-lookup`을 재사용하고 중복 구현하지 않는다.
- 프로세스 생성(`bpmn-process-generation-skill`, deepagents 실행 환경 기준) 흐름에 프로세스 초안을 확정하기 전 전략 정합성을 확인하는 필수 단계를 추가한다. 관련 KPI가 식별되면 기존 `link_kpi_to_process` 도구로 연결하고, 관련 전략 요소를 찾지 못하면 사용자에게 알리고 계속 진행할지 확인받는다. 이 강제 방식은 `deepagents-strategy-ontology-tools`가 애드혹 메인 에이전트에 부여하는 "확정 전 필수 선행 조회" 의무와 동일한 패턴을 따른다.
- `services/agent-feedback`의 피드백 기반 개선 제안(`SKILL`, `PROCESS_DEFINITION` target) 흐름에 승인 전 정합성 확인 단계를 추가한다. `PROCESS_DEFINITION` target은 대상 프로세스가 이미 존재하므로 기존 전략 연결(순방향 기여도 조회)과 제안 내용 기반 후보 탐색을 함께 근거로 기록하고, `SKILL` target은 제안 내용 기반 후보 탐색만 기록한다. `DMN_RULE` target은 범위에서 제외한다(조건-결과 규칙 패치는 전략 목표 단위와 대응시키기 어려움).
- 새로운 원격 프로토콜(MCP 서버 등)은 도입하지 않는다. 기존 관례(LangChain `@tool`이 `services/strategy`의 HTTP API를 직접 호출)를 그대로 확장한다.

## Capabilities

### New Capabilities
- `strategy_alignment-lookup`: 자유 텍스트 설명과 tenant_id(선택적으로 기존 프로세스 정의 id)를 입력받아, 관련 전략 목표·KPI 후보(근거 포함)와 기존 연결 항목을 구분해 반환하는 조회 전용 기능.
- `deepagents_process-generation-alignment-gate`: 프로세스 생성 스킬 실행 중 프로세스 초안을 확정하기 전에 전략 정합성을 확인하고, 확인 결과(연결된 KPI 또는 "관련 항목 없음" 확인)를 생성된 프로세스 정의에 남기는 동작.
- `agent-feedback_improvement-alignment-gate`: `SKILL`/`PROCESS_DEFINITION` 개선 제안이 승인 가능 상태가 되기 전에 전략 정합성 확인을 수행하고, 그 근거(기존 연결 + 신규 후보)를 제안 데이터에 기록해 승인자에게 노출하는 동작.

### Modified Capabilities
(없음 — 기존 스펙의 요구사항 변경 없음. `strategy_process-contribution-lookup`은 `deepagents-strategy-ontology-tools` 변경의 신규 캡퍼빌리티이며 이 변경은 그것을 소비만 한다.)

## Impact

- `services/strategy`: 텍스트 기반 정합성 후보 조회 기능 추가(읽기 전용, 기존 데이터 모델·기존 API 계약 변경 없음). 기존 KPI→프로세스 추천(`POST /api/ai/suggest`)의 역방향에 해당하며 같은 LLM+휴리스틱 폴백 패턴을 재사용한다.
- `services/deepagents`: 정합성 조회 도구 추가(`deepagents-strategy-ontology-tools`의 온톨로지 도구와 같은 위치·같은 오류 처리 관례), `bpmn-process-generation-skill` 지침에 확정 전 필수 확인 단계 편입.
- `services/agent-feedback`: 제안 생성 파이프라인에 정합성 확인 단계와 근거 필드 추가, 제안 조회 응답(`GET /feedback-proposals`)에 근거 노출.
- 선행 변경 의존: `deepagents-strategy-ontology-tools`의 `strategy_process-contribution-lookup`(기존 연결 조회 재사용). 단, 해당 기능이 미배포인 환경에서도 텍스트 기반 후보 탐색만으로 동작하도록 우아하게 축소된다.
- 신규 원격 프로토콜(MCP 서버) 도입 없음.
