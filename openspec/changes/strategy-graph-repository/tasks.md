# 작업: strategy 서비스의 기업 운영 온톨로지 그래프 전환

## 1. 인프라 준비 (AGE 포함 Postgres)

- [x] 1.1 로컬/E2E용 Apache AGE 포함 Postgres를 Docker 인프라로 구성하고(compose의 postgres 서비스 교체 또는 별도 서비스), AGE 확장 로드·Cypher 실행이 되는지 psql로 확인한다 — `strategy_graph-store` "기동 시 그래프 환경 자동 준비" 전제 검증
- [x] 1.2 `services/strategy/README.md`에 AGE 확장 요구사항, `GRAPH_STORE`/`GRAPH_NAME`/`ONTOLOGY_SYNC_INTERVAL_SECONDS` 환경 변수, 관리형 Supabase 미지원 제약을 문서화한다

## 2. 저장소 추상화 계층 (Strategy 패턴)

- [x] 2.1 그래프 저장소 인터페이스를 도메인 연산 단위(노드/관계 CRUD, 전략맵 조회, 서브그래프 조회, 이웃 탐색, 다단 경로 탐색, 동기화용 멱등 병합)로 정의하고 `GRAPH_STORE` 설정 기반 팩토리를 구현한다 — Requirement "설정으로 그래프 저장소 구현체를 선택할 수 있다"
- [x] 2.2 지원하지 않는 `GRAPH_STORE` 값으로 기동 시 지원 목록을 포함한 오류로 기동이 실패하는지 테스트한다 — Scenario "지원하지 않는 저장소 지정"
- [x] 2.3 구현체 무관 공통 계약 테스트 스위트를 작성한다(노드/관계 CRUD, 서브그래프·이웃·경로 탐색, 멱등 병합, 테넌트 격리) — Requirement "저장소 구현체는 공통 행위 계약을 만족한다"

## 3. Apache AGE 어댑터

- [x] 3.1 AGE 어댑터의 접속·초기화(확장 로드, `GRAPH_NAME` 그래프 생성, 인덱스)를 구현하고 멱등성을 테스트한다(빈 DB 최초 기동 / 재기동 / AGE 미설치 DB 기동 실패) — Scenario "최초 기동 시 그래프 초기화", "재기동 멱등성", "AGE 확장이 없는 Postgres"
- [x] 3.2 design.md D3 온톨로지 스키마(8종 노드 라벨, 12종 관계)의 Cypher 연산과 agtype 결과 파싱을 구현한다 — Requirement "전략맵 엔티티가 온톨로지 표준 그래프 스키마로 저장된다"
- [x] 3.3 AGE 어댑터를 대상으로 2.3의 공통 계약 테스트를 통과시킨다 (다단 경로 탐색의 AGE Cypher 방언 동작 확인 포함) — Scenario "계약 테스트 통과"
- [x] 3.4 테넌트 격리(조회/변경)를 AGE 어댑터에서 검증한다 — Requirement "그래프 저장소는 테넌트 단위로 데이터를 격리한다"

## 4. 전략 레이어 API 전환

- [x] 4.1 전략목표 API(`POST/PUT/DELETE /api/objectives`)를 그래프 저장소로 전환한다: `parents` ↔ `HAS_SUB_STRATEGY` 상호 변환, 삭제 시 관계 정리와 KPI·이니셔티브 연쇄 삭제 검증 — Requirement "전략목표 삭제 시 관계가 그래프 수준에서 함께 정리된다"
- [x] 4.2 KPI API(`POST/PUT/DELETE /api/kpis`)를 그래프 저장소로 전환한다: `proc_def_id` 지정 시 `Process` 노드 MERGE + `IMPACTS_KPI` 엣지 검증 — Scenario "전략-KPI-프로세스 연결 경로"
- [x] 4.3 이니셔티브 API(`POST/PUT/DELETE /api/initiatives`)를 그래프 저장소로 전환하고 `HAS_INITIATIVE`/`EXECUTED_BY` 엣지를 검증한다 — Scenario "이니셔티브-프로세스 연결"
- [x] 4.4 `GET /api/map`을 그래프 조회 기반으로 전환하되 기존 중첩 응답 구조(`objectives[].kpis/initiatives/achievement`, `parents`, `perspective`)를 그대로 유지하는지 응답 스냅샷으로 검증한다 — Requirement "기존 전략맵 API 계약이 그래프 저장소 위에서 유지된다"
- [x] 4.5 존재하지 않는 리소스 수정/삭제 시 404 동작을 검증한다 — Scenario "존재하지 않는 리소스 수정"

## 5. 데이터 이관

- [x] 5.1 기동 시 자동 이관(전략 레이어 비어 있음 + 관계형 데이터 존재 시)과 `POST /api/migrate-graph`를 구현하고, jsonb `parents` → `HAS_SUB_STRATEGY`, `proc_def_id` → `IMPACTS_KPI`/`EXECUTED_BY` 변환을 검증한다 — Scenario "관계형 데이터 자동 이관"
- [x] 5.2 이관 멱등성(반복 실행 시 노드/관계 수 불변)과 결과 요약(노드·관계 수) 반환을 테스트한다 — Scenario "이관 멱등성"
- [x] 5.3 `POST /api/import-bscard`를 그래프 저장소 대상으로 재작성하고 관점 표기 정규화와 부모 관계 이관을 검증한다 — Scenario "BSCard 이관"

## 6. 온톨로지 인제스천 (ETL)

- [x] 6.1 원천 테이블별 증분 커서 기반 변경 감지와 인제스천 루프(`ONTOLOGY_SYNC_INTERVAL_SECONDS`), `POST /api/ontology/sync`(+`full=true`)를 구현한다. 인제스천 로직은 "변경 행 목록 → 그래프 반영" 함수로 분리해 향후 Realtime push 전환에 대비한다 — Requirement "원천 데이터 변경분이 온톨로지 그래프에 인제스천된다"
- [x] 6.2 `proc_def` 인제스천: `Process`/`Task` 노드 + `CONTAINS_TASK`, BPMN 정의 내 활동별 역할자(사용자/에이전트) → `PERFORMS`(정의 기반) 생성을 검증한다 — Scenario "프로세스 정의의 태스크 분해", "정의상 역할자의 수행 관계 생성"
- [x] 6.3 `users` 인제스천: is_agent 구분에 따른 `User`/`Agent` 노드 생성을 검증한다 — Scenario "사람과 에이전트의 구분 반영"
- [x] 6.4 조직도(configuration key='organization') 인제스천: 실제 chart 구조를 확인해 `Team` + `HAS_SUB_TEAM` + `MEMBER_OF` 매핑을 구현·검증한다 — Scenario "조직도 반영"
- [x] 6.5 스킬 인제스천: `Skill` 노드 + `USES_SKILL` 동기화, 변경 스킬 본문의 LLM 분석으로 `INHERITS`/`REFERENCES` 추출(근거 속성 포함, 존재하는 대상만, 미변경 스킬 분석 생략, LLM 미설정 시 보류 기록)을 검증한다 — Requirement "변경된 스킬은 LLM 분석으로 스킬 간 관계가 추출된다"
- [x] 6.6 `todolist` 완료 워크아이템 증분 집계로 `PERFORMS` 실행 지표(건수·평균 처리시간) 갱신을 검증한다 — Scenario "실행 지표 집계"
- [x] 6.7 원천 삭제분의 미러 노드·관계 제거와 수정분의 중복 없는 갱신을 검증한다 — Scenario "수정분의 반영", "삭제분의 반영"

## 7. 온톨로지 조망 API

- [x] 7.1 `GET /api/ontology/graph`(노드·관계 JSON, 마지막 인제스천 시각 포함)를 구현하고 4레이어 전체 조회와 빈 테넌트 조회를 검증한다 — Requirement "전체 온톨로지를 한눈에 조망할 수 있다"
- [x] 7.2 `layers` 파라미터 필터링(선택 레이어 노드 + 양끝이 포함된 관계만)을 구현·검증한다 — Requirement "레이어를 선택해 조망할 수 있다"
- [x] 7.3 `GET /api/ontology/nodes/{id}/neighbors`(depth 기본 1, 404 처리)를 구현·검증한다 — Requirement "노드에서 이웃으로 점진 탐색할 수 있다"

## 8. KPI 다각 측정

- [x] 8.1 measurement 모듈이 KPI 목록·프로세스 연결을 그래프에서 조회하도록 전환하고, 측정 결과를 KPI 노드 속성 + 관계형 측정 이력 + `IMPACTS_KPI` 엣지 실행 집계에 반영한다 — Requirement "측정 결과가 온톨로지 그래프와 측정 이력에 함께 반영된다"
- [x] 8.2 `form_value_sum` 측정 유형과 KPI `form_field` 지정을 구현한다 (폼 데이터 위치·필드 경로는 실제 완료 인스턴스 데이터로 확정) — Scenario "폼 입력값 합산 정량 측정"
- [x] 8.3 기존 정량(`instance_count`, `avg_duration_hours`)·정성(`survey_score`) 측정과 수동 입력·달성률 계산이 그래프 전환 후에도 동일하게 동작하는지 검증한다 — Scenario "완료 건수 정량 측정", "설문 기반 정성 측정", "수동 실적 입력과 달성률 계산"
- [x] 8.4 survey 모듈의 KPI 참조를 그래프 조회로 전환하고 설문 발행→응답→재집계 흐름과 KPI 삭제 시 측정 이력·설문 정리를 검증한다 — Requirement "KPI 측정·설문 데이터는 관계형 테이블과 정합성을 유지한다"

## 9. 영향도 분석 (역추적)

- [x] 9.1 `GET /api/impact/kpi/{id}`: KPI→Process→Task→리소스→Skill 역추적 경로 수집과 실행 지표 기반 원인 후보 랭킹을 구현·검증한다 (하위 연결 없는 KPI, 404 포함) — Requirement "KPI 이상의 원인을 하위 레이어로 역추적할 수 있다"
- [x] 9.2 `GET /api/impact/strategy/{id}`: 전략 하향 경로 수집과 목표 미달 KPI 연계 병목·개선 대상 스킬 도출(연결 경로·근거 지표 포함)을 구현·검증한다 — Requirement "전략 목표 달성을 위한 스킬 개선점을 도출할 수 있다"
- [x] 9.3 분석의 결정성(동일 데이터 동일 결과)과 LLM 미설정 환경의 완전한 응답, LLM 설정 시 서술형 진단의 "진단 후보" 표기를 검증한다 — Requirement "분석 결과는 재현 가능하고 LLM 서술은 보조로만 제공된다"

## 10. E2E 검증

- [x] 10.1 openspec/specs/strategy_graph-store/e2e/ 에 Docker AGE-Postgres 인프라 + 소스 실행(uvicorn) 구성으로 기동/초기화/저장소 선택 E2E를 작성·실행한다 (실행 명령, 포트, 환경 변수 기록 포함) — 15/15 PASS
- [x] 10.2 openspec/specs/strategy_strategy-map-graph/e2e/ 에 전략맵 CRUD 왕복, 전략간 관계, 삭제 정리, 이관 E2E를 작성·실행한다 — 20/20 PASS
- [x] 10.3 openspec/specs/strategy_ontology-sync/e2e/ 에 원천 데이터 seed(proc_def·users·조직도·skills·todolist) → 인제스천 → 그래프 검증 E2E를 작성·실행한다 (LLM 스킬 관계 추출은 stub/실 LLM 겸용) — 24/24 PASS
- [x] 10.4 openspec/specs/strategy_ontology-view/e2e/ 와 openspec/specs/strategy_impact-analysis/e2e/ 에 4레이어 조망·이웃 탐색·KPI 역추적·전략 스킬 개선점 E2E를 작성·실행한다 — ontology-view 16/16, impact-analysis 21/21 PASS
- [x] 10.5 openspec/specs/strategy_kpi-measurement/e2e/ 에 정량(건수/시간/폼값 합산)·정성(설문) 측정 E2E를 작성·실행한다 — 11/11 PASS
- [x] 10.6 프론트엔드(전략맵 화면)로 그래프 전환 후에도 기존 화면이 동작하는지 확인한다 (API 계약 무변경 evidence) — openspec/specs/strategy_strategy-map-graph/e2e/frontend-contract-evidence.md (레거시 8014 vs 신규 8114 /api/map 키 대조: 구조 동일, kpis 에 form_field 만 additive → 기존 화면 무변경)

## 11. 마무리

- [x] 11.1 `services/strategy/PLAN.md`·README를 온톨로지 기반 조망·분석 서비스 관점으로 갱신하고, 기존 관계형 전략맵 테이블의 읽기 중단(보존) 상태와 향후 제거 계획을 기록한다
- [x] 11.2 openspec 델타 스펙을 main spec으로 sync 준비 상태로 검증한다 (`openspec status`로 전체 done 확인)
