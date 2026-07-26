## 1. `services/strategy` — 텍스트 기반 정합성 후보 조회 (`strategy_alignment-lookup`)

- [x] 1.1 기존 `POST /api/ai/suggest`(app/ai.py)의 LLM+휴리스틱 폴백 패턴을 역방향으로 재사용해, 설명 텍스트 + tenant_id를 입력받아 그래프 저장소의 Strategy/KPI 노드에서 관련 후보를 반환하는 조회 기능을 구현한다(관련도 순 정렬, 근거 문장, 생성 방식 표기).
- [x] 1.2 관련 후보가 없는 경우 및 전략맵 미수립 테넌트에 대해 오류가 아닌 "관련 항목 없음" 응답을 반환하도록 구현한다.
- [x] 1.3 proc_def_id가 함께 지정된 경우 `deepagents-strategy-ontology-tools`의 프로세스 기준 기여도 조회(`GET /api/impact/process/{proc_def_id}`)를 호출해 기존 연결을 신규 후보와 구분해 포함하고, 해당 기능 미배포 환경에서는 생략 사실을 표기하며 텍스트 후보만으로 응답하도록 구현한다.
- [x] 1.4 `strategy_alignment-lookup`의 세 Requirement(텍스트 후보 조회, 기존 연결 구분, 테넌트 격리)에 대응하는 자동화 테스트(있음/없음/미수립 테넌트, 기존 연결 포함/생략, 테넌트 격리)를 작성하고 통과시킨다.

## 2. `services/deepagents` — 프로세스 생성 정합성 게이트

- [x] 2.1 `core/strategy/tools.py`에 1번 조회를 호출하는 정합성 조회 도구를 추가한다 — `deepagents-strategy-ontology-tools`의 온톨로지 도구와 동일한 오류 처리 관례(예외 전파 없이 오류 결과 반환)를 따른다.
- [x] 2.2 `bpmn-process-generation-skill` 지침(SKILL.md/references)에 "프로세스 정의 확정 전 정합성 조회 필수" 단계를 추가하고, 도구 설명(스키마)에도 같은 취지를 명시한다(프롬프트 강제 이중화).
- [x] 2.3 관련 KPI 후보가 있을 때 사용자에게 후보를 제시하고, 사용자가 선택한 KPI만 기존 `link_kpi_to_process` 도구로 연결하는 흐름을 구현한다(자동 연결 금지, 미연결 선택도 기록).
- [x] 2.4 관련 전략 요소가 없거나 조회가 실패했을 때 사용자에게 알리고 계속 진행 여부를 확인받는 흐름을 구현한다.
- [x] 2.5 `proc_def.definition` 스키마를 확인해 정합성 확인 결과(연결 KPI / "관련 항목 없음" 확인 / 확인 불가 사유)의 기록 위치를 확정하고(design Open Question 해소), 조회 가능한 형태로 기록한다.
- [ ] 2.6 `deepagents_process-generation-alignment-gate`의 네 Requirement(필수 선행 확인, 사용자 선택 연결, 없음 확인 후 진행, 근거 기록)에 대응하는 E2E 시나리오를 작성하고 실행해, 프롬프트 기반 강제의 실제 준수 여부를 관찰 기록한다.

## 3. `services/agent-feedback` — 개선 제안 정합성 게이트

- [x] 3.1 제안 생성 파이프라인(core/feedback_batch_manager.py 계열)에 1번 조회를 호출하는 정합성 확인 단계를 코드 수준으로 삽입한다 — SKILL target은 제안 내용 텍스트로, PROCESS_DEFINITION target은 대상 proc_def_id를 함께 지정해 기존 연결+신규 후보를 받는다.
- [x] 3.2 정합성 조회 결과(또는 확인 불가 사실)를 제안 데이터의 근거 필드에 기록하고, 조회 실패가 제안 생성을 막지 않도록 처리한다.
- [x] 3.3 `DMN_RULE` target에는 정합성 조회를 수행하지 않도록 분기 처리한다.
- [x] 3.4 `GET /feedback-proposals` 응답에 target별 정합성 근거(관련 전략 요소 / "관련 항목 없음" / 확인 불가)를 포함한다.
- [x] 3.5 `agent-feedback_improvement-alignment-gate`의 세 Requirement(생성 시 확인·기록, 승인자 노출, DMN_RULE 제외)에 대응하는 자동화 테스트를 작성하고 통과시킨다.

## 4. 통합 검증

- [ ] 4.1 `services/strategy` + `services/deepagents`를 함께 띄운 환경에서, 전략맵이 있는 테넌트와 없는 테넌트 각각에 대해 프로세스 생성 → 정합성 확인 → KPI 연결(또는 없음 확인 후 진행) → 프로세스 정의에서 근거 조회까지 엔드투엔드로 검증한다.
- [ ] 4.2 `services/strategy` + `services/agent-feedback`를 함께 띄운 환경에서, 피드백 배치 → SKILL/PROCESS_DEFINITION 제안 생성 → `GET /feedback-proposals`에서 정합성 근거 확인 → 승인까지, 그리고 `deepagents-strategy-ontology-tools` 미배포 상황의 축소 동작(기존 연결 생략 표기)까지 엔드투엔드로 검증한다.
- [ ] 4.3 design.md의 남은 Open Question(승인 UI 노출, 스킬-전략 관련성의 온톨로지 반영)을 후속 변경 후보로 정리해 문서에 반영한다.
