## 1. 전략 서비스 — 통합 전략 컨텍스트 조회

- [ ] 1.1 `services/strategy`에 `GET /api/ontology/process/{proc_def_id}/strategic-context?tenant_id=`를 신설하고, 온톨로지 그래프 순회로 기여 전략목표·KPI(`contributions`), 협업 대상(`collaborators`), 관계 프로세스(`related_processes`), 스킬(`skills`)을 한 응답으로 반환한다 (`strategy_process-strategic-context` Requirement: 통합 전략 컨텍스트 조회).
- [ ] 1.2 기여 전략을 `importance` 내림차순으로 정렬하고, KPI 소속 전략목표의 상위 전략목표까지 포함하며, 중요도 미설정 노드는 기본값 취급 + 표시 처리한다 (`strategy_process-strategic-context` Requirement: 전략적 중요도 순 정렬).
- [ ] 1.3 KPI 항목에 프로세스와의 연결 근거(측정 집계 등 엣지 속성)를 포함시킨다.
- [ ] 1.4 플랫폼에 없는 프로세스 정의는 404, 플랫폼에는 있으나 그래프 미반영이면 `sync_pending=true` + 빈 목록, 그래프에 있으나 연결 없음이면 `sync_pending=false` + 빈 목록으로 구분 응답한다 (`strategy_process-strategic-context` Requirement: 동기화 대기 구분).

## 2. deepagents — 전략 브리핑 자동 주입 (push)

- [ ] 2.1 실행 엔진이 프로세스 인스턴스 맥락에서 프로세스 정의 id를 확보하는 경로를 확인·구현한다 (워크아이템 행의 proc_def_id 우선, 없으면 인스턴스 조회 폴백).
- [ ] 2.2 에이전트 구성 시점에 통합 전략 컨텍스트를 짧은 타임아웃(초기값 3초)으로 조회하고, 결과를 압축 브리핑(범주별 상위 N=5개, 이름·중요도 중심)으로 시스템 프롬프트에 추가한다 (`deepagents_strategy-context` Requirement: 전략 브리핑 자동 주입).
- [ ] 2.3 조회 실패·타임아웃·빈 결과 시 브리핑 섹션 없이 실행을 계속하는 fail-open 처리를 구현한다 (`deepagents_strategy-context` Requirement: 브리핑 조회 실패가 실행을 지연·중단시키지 않는다).
- [ ] 2.4 브리핑이 항목 상한으로 잘린 경우 "심층 탐색 도구로 더 조회 가능"을 브리핑에 명시한다.
- [ ] 2.5 서브에이전트가 구성된 실행의 기존 "서브에이전트 위임 규칙" 안내 블록에, 브리핑의 관계 프로세스·에이전트·스킬을 위임 계획에 반영하라는 지침을 추가한다 (`deepagents_strategy-context` Requirement: 애드혹 메인 에이전트의 위임 계획에 브리핑 반영).

## 3. deepagents — 온톨로지 탐색 도구 (pull)

- [ ] 3.1 기존 전략 도구 모듈의 HTTP 호출·오류 처리 패턴(예외 없이 `{"error": ...}` 반환)을 재사용해, 통합 전략 컨텍스트 조회를 감싸는 도구를 구현한다 — 프로세스 정의 id 선택 인자, 생략 시 실행 맥락 자동 사용, 맥락도 인자도 없으면 지정 안내 반환 (`deepagents_strategy-context` Requirement: 심층 탐색 도구).
- [ ] 3.2 `GET /api/ontology/nodes/{node_id}/neighbors`를 감싸는 이웃 탐색 도구를 구현한다 (`deepagents_strategy-context` Requirement: 온톨로지 이웃 탐색 도구).
- [ ] 3.3 두 도구를 에이전트 기본 도구 목록에 추가해 테넌트 설정 없이 모든 실행에 포함시키고, 도구 docstring에 브리핑과의 관계(브리핑 범위를 넘는 탐색용)를 명시한다 (`deepagents_strategy-context` Requirement: 모든 테넌트·에이전트 기본 적용).

## 4. 검증

- [ ] 4.1 `openspec/specs/strategy_process-strategic-context/e2e/`에 시나리오 문서와 seed 데이터를 작성해, 네 범주 연결 프로세스·일부 연결 프로세스·미존재 프로세스·미동기화 프로세스·상위 전략 포함·중요도 정렬 각각의 응답을 검증한다.
- [ ] 4.2 `openspec/specs/deepagents_strategy-context/e2e/`에 시나리오 문서를 작성해, 워크아이템 실행 시 브리핑이 프롬프트에 포함되는지(도구 호출 전 시점), 전략 서비스 미응답 시 fail-open으로 실행이 진행되는지 검증한다.
- [ ] 4.3 탐색 도구를 실행 중 인자 없이 호출한 경우, 실행 맥락 없이 프로세스를 지정한 경우, 맥락도 인자도 없는 경우, 서비스 미응답인 경우 각각의 도구 결과를 검증한다.
- [ ] 4.4 서브에이전트가 여러 개 구성된 애드혹 실행에서 복합 문제 해결 요청을 던져, 위임 계획에 브리핑의 관계 프로세스·스킬 참고 지시가 반영되는지 관찰로 확인한다. 반영 품질이 낮으면 design.md의 후속 조정(위임 형식 구조화) 판단으로 넘긴다.
