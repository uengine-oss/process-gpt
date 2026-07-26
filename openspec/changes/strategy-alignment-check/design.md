## Context

- `bsc-strategy-interview` 스킬은 deepagents 실행 환경에서 `save_strategy_objective`/`save_strategy_kpi`/`save_canvas_block` 도구로 전략맵/BMC 캔버스를 `services/strategy`(FastAPI, Apache AGE 그래프 + 관계형 측정 이력)에 저장한다. 이 도구들은 MCP가 아니라 일반 LangChain `@tool`(`services/deepagents/core/strategy/tools.py`)이며 전략 서비스 HTTP API를 직접 호출한다. 저장소에 등록된 MCP 서버는 없다.
- 관련 변경 `deepagents-strategy-ontology-tools`가 다음을 도입한다(이 변경의 전제):
  - `strategy_process-contribution-lookup`: `GET /api/impact/process/{proc_def_id}` — 기존 프로세스 정의가 연결된 KPI·전략목표를 중요도 순으로 순방향 조회. 동기화 대기/연결 없음 상태 구분 포함.
  - `deepagents_strategy-ontology-tools`: 실행 중 에이전트용 협업 대상·전략 기여도 조회 도구. 실행 맥락 자동 활용, 오류 시 실행 비중단, 애드혹 메인 에이전트에 "서브태스크 분해 확정 전 필수 선행 조회" 의무 부여.
- 그러나 위 조회들은 모두 **프로세스 정의 id가 이미 존재**하고 온톨로지 그래프에 반영된 대상을 전제한다. 이 변경이 다루는 게이트의 대상은 다르다:
  - 프로세스 생성: 확정 전의 초안 — 아직 id도 그래프 노드도 없다.
  - 스킬 개선 제안(`SKILL` target): 스킬 변경 내용 텍스트 — KPI와의 연결 관계가 그래프에 없을 수 있다.
  - 프로세스 개선 제안(`PROCESS_DEFINITION` target): 대상 프로세스는 존재하지만, 제안된 **변경 내용**이 전략과 정합하는지는 기존 연결만으로 판단할 수 없다.
- 따라서 텍스트 설명 기반의 후보 탐색이 별도로 필요하다. `services/strategy`에는 이미 유사한 선례가 있다: `POST /api/ai/suggest`(app/ai.py)는 KPI 정보 → 적합한 프로세스 정의 후보를 LLM(미설정 시 키워드 휴리스틱)으로 추천한다. 이번에 필요한 것은 그 역방향(프로세스/스킬 설명 → 전략 목표·KPI 후보)이다.
- 프로세스/스킬 개선의 실행 주체는 `services/agent-feedback`이다: 피드백 배치 → LLM 분류(`SKILL`/`DMN_RULE`/`PROCESS_DEFINITION`) → target별 제안(`PROPOSED`) 생성 → 사용자가 target별 승인/거절.

## Goals / Non-Goals

**Goals:**
- 아직 그래프에 존재하지 않는 대상(프로세스 초안, 개선 제안 내용)에 대해 자유 텍스트로 관련 전략 목표·KPI 후보를 탐색할 수 있게 한다(`strategy_alignment-lookup`).
- 프로세스 생성 확정 전(`deepagents_process-generation-alignment-gate`)과 개선 제안 승인 전(`agent-feedback_improvement-alignment-gate`)에 정합성 확인을 필수 단계로 강제하고, 결과를 근거로 기록한다.
- `deepagents-strategy-ontology-tools`가 만든 조회 기능·도구 관례·강제 패턴을 재사용하고, 겹치는 기능을 중복 구현하지 않는다.
- 새로운 원격 프로토콜(MCP 서버)을 도입하지 않는다.

**Non-Goals:**
- 정합성이 없다고 프로세스/스킬 변경을 강제 차단하지 않는다(확인은 강제, 진행 여부는 사용자/승인자 판단).
- `DMN_RULE` target의 정합성 확인은 다루지 않는다.
- 이미 존재하는 프로세스의 실행 시점 전략 조회(그건 `deepagents-strategy-ontology-tools` 소관)와 전략맵 수립/수정 흐름은 변경하지 않는다.
- Claude Code CLI 단독 실행(에이전트 도구 미연결) 환경의 자동화는 다루지 않는다 — `bsc-strategy-interview`와 동일하게 "도구 없으면 생략" 제약을 따른다.

## Decisions

### 1. `deepagents-strategy-ontology-tools` 위에 계층화하고 중복을 만들지 않는다
- **결정**: 기존 프로세스의 전략 연결 조회는 `strategy_process-contribution-lookup`(`GET /api/impact/process/{proc_def_id}`)을 소비만 한다. 이 변경이 새로 만드는 것은 "id가 없는 대상에 대한 텍스트 기반 후보 탐색"과 "두 흐름에의 게이트 편입" 뿐이다.
- **근거**: 두 변경을 독립적으로 두면 전략 서비스에 순방향 조회가 두 벌 생기고, deepagents 도구 계층에도 유사 도구가 중복된다. 역할을 "존재하는 대상 = ontology-tools / 아직 없는 대상 = alignment-check"로 나누면 각 API·도구의 계약이 단순해진다.
- **의존성 처리**: `strategy_process-contribution-lookup`이 미배포인 환경에서는 기존 연결 조회를 생략하고 텍스트 후보 탐색만으로 근거를 구성한다(게이트 자체는 항상 동작). 배포 순서를 강제하지 않는다.

### 2. 텍스트 기반 후보 탐색은 `services/strategy`의 기존 AI 추천 패턴을 역방향으로 재사용한다
- **결정**: 정합성 후보 조회는 `POST /api/ai/suggest`(KPI→프로세스 후보, LLM + 키워드 휴리스틱 폴백)와 같은 구조로 구현한다 — 입력은 설명 텍스트 + tenant_id(+ 선택적 proc_def_id), 후보 풀은 그래프 저장소의 해당 테넌트 Strategy/KPI 노드(`list_nodes`), 출력은 관련도 순 후보 목록(각 항목에 근거 한 문장)이다. `OPENAI_API_KEY` 미설정 시 토큰 겹침 휴리스틱으로 폴백한다.
- **근거**: 매칭 로직을 전략 서비스 한 곳에 두면 deepagents/agent-feedback 양쪽이 같은 판단 기준을 공유한다. 기존 ai.py 패턴(LLM 후보 id 검증, 휴리스틱 폴백, `generated_by` 표기)을 그대로 뒤집으면 되므로 새 아키텍처가 필요 없다.
- **대안 및 기각**: 각 소비 서비스에서 LLM으로 직접 판단 → 판단 기준 분산·그래프 접근 권한 분산으로 기각. 임베딩 인덱스 신설 → 전략맵 노드 수(테넌트당 수십 개 수준)에 과함, LLM/휴리스틱으로 충분하므로 기각(향후 필요 시 내부 구현만 교체 가능).
- **proc_def_id가 함께 주어진 경우**: 응답에 `strategy_process-contribution-lookup` 결과(기존 연결)를 별도 섹션으로 포함해, 소비자가 "이미 연결된 것"과 "새로 제안되는 후보"를 구분할 수 있게 한다.

### 3. MCP 서버를 만들지 않는다
- **결정**: 정합성 조회는 `services/deepagents`·`services/agent-feedback` 각각의 LangChain `@tool`(또는 파이프라인 내 직접 HTTP 호출)이 전략 서비스 API를 호출한다.
- **근거**: 소비 주체가 모두 저장소 내부 Python 프로세스이고, `bsc-strategy-interview`·`deepagents-strategy-ontology-tools`가 이미 같은 직접 HTTP 관례를 쓴다. MCP는 저장소 밖 클라이언트(Claude Desktop 등)나 이종 런타임이 표준 인터페이스로 접근해야 할 때만 정당화되는데 지금은 해당 없다.

### 4. 강제 방식: 확인은 필수, 차단은 하지 않는다
- **결정**: 관련 전략 요소를 못 찾아도 흐름을 막지 않는다. 대신 (a) 확인 수행 여부와 결과를 항상 기록하고, (b) "관련 항목 없음"일 때 사용자/승인자에게 명시적으로 알리고 진행 확인을 받는다.
- **근거**: 전략맵이 모든 업무 영역을 커버하지 못할 수 있고, 운영성·긴급성 변경처럼 전략 목표와 직접 연결되지 않는 정당한 변경이 존재한다. 이번 변경이 막는 것은 "확인 없이 지나가는 것"이지 "전략 무관 변경 자체"가 아니다.
- **프롬프트 강제의 한계**: `deepagents-strategy-ontology-tools`의 리스크 분석과 동일하게, 프롬프트 지침만으로는 준수 보장이 약하다(이 저장소에서 프롬프트 문구만으로 새 기능 사용을 유도했을 때 신뢰도가 낮았던 선례가 있다). 프로세스 생성 게이트는 스킬 지침 + 도구 설명 양쪽에 명시하고 E2E로 준수를 관찰한다. agent-feedback 쪽은 프롬프트가 아니라 **제안 생성 파이프라인 코드에 확인 단계를 삽입**하므로 코드 수준으로 보장된다.

### 5. 정합성 근거의 기록 위치
- **결정**:
  - 프로세스 생성: 관련 KPI 연결은 기존 `link_kpi_to_process`(그래프 `IMPACTS_KPI` 관계)로 남기고, "확인 수행 + 관련 항목 없음" 확인은 프로세스 정의의 메타데이터로 남긴다(정확한 필드 위치는 tasks에서 `proc_def.definition` 스키마 확인 후 확정).
  - 개선 제안: 제안 레코드에 정합성 근거 필드를 추가하고 `GET /feedback-proposals` 응답에 포함한다.
- **근거**: KPI 연결은 이미 그래프가 원천(single source of truth)이므로 이중 기록하지 않는다. "없음 확인"은 그래프에 표현할 관계가 없으므로 각 산출물(프로세스 정의/제안)에 남긴다.

## Risks / Trade-offs

- [텍스트 매칭 부정확성 — 무관한 KPI를 관련로 오판하거나 관련 KPI를 놓침] → 후보에 근거 문장과 생성 방식(`llm`/`heuristic`)을 표기하고, 자동 확정 연결을 금지한다(최종 연결은 항상 사용자/승인자 확인).
- [정합성 단계 추가로 생성/승인 흐름 지연] → 조회는 읽기 전용 단건 호출이며, 후보 풀이 테넌트당 전략맵 노드 수준으로 작아 지연 영향이 제한적이다.
- [전략맵 미수립 테넌트에서 오류로 흐름이 막힘] → 전략맵 없음을 오류가 아닌 "관련 항목 없음"과 동형의 응답으로 처리한다.
- [`deepagents-strategy-ontology-tools` 미배포 환경에서 기존 연결 근거 누락] → 텍스트 후보만으로 축소 동작하고, 근거에 기존 연결 조회 생략 사실을 표기한다.
- [프로세스 생성 게이트가 프롬프트 지침 기반이라 준수 신뢰도가 낮을 수 있음] → 스킬 지침·도구 설명 이중 명시 + E2E 관찰. 계속 낮으면 프로세스 정의 저장 직전 코드 수준 게이팅(정합성 메타데이터 없으면 경고)을 후속 변경으로 검토한다.
- [`DMN_RULE` 제외로 커버리지 부분적] → 범위 제외를 명시했고, 조회 기능은 target 종류에 결합되지 않은 범용(텍스트 입력) 설계라 후속 확장이 열려 있다.

## Migration Plan

1. `services/strategy`에 텍스트 기반 정합성 후보 조회를 추가 배포한다(additive, 기존 API·데이터 모델 영향 없음).
2. `services/deepagents`에 정합성 조회 도구를 추가하고 `bpmn-process-generation-skill` 지침에 필수 단계를 반영한다.
3. `services/agent-feedback` 제안 생성 파이프라인에 확인 단계·근거 필드를 추가한다.
4. 각 단계는 독립 롤백 가능하다 — 조회는 읽기 전용, 도구/지침/파이프라인 변경은 이전 버전 복귀로 즉시 원상복구된다. `deepagents-strategy-ontology-tools`와의 배포 순서는 무관하다(미배포 시 축소 동작).

## Resolved During Implementation

- 프로세스 정의의 정합성 근거는 기존 `proc_def.definition` JSON의 최상위
  `strategyAlignment`에 저장한다. 값은 `status`, `checkedAt`, `selectedKpiIds`,
  `candidates`, `confirmation`을 포함해 별도 DB 컬럼 없이 기존 정의 조회로 확인한다.

## Open Questions

- 개선 제안의 근거 필드가 승인 UI(프론트엔드)에 어떻게 노출될지는 범위 밖 — 응답 계약까지만 이 변경에서 보장하고, UI 반영은 후속 변경 후보로 남긴다.
- `SKILL` target 승인으로 스킬이 변경된 뒤, 그 스킬-전략 관련성이 온톨로지 그래프(`Skill` 노드)에 반영되어야 하는지는 `strategy_ontology-sync`의 스킬 인제스천 범위와 겹치므로 이번 변경에서는 다루지 않고 후속 검토로 남긴다.
