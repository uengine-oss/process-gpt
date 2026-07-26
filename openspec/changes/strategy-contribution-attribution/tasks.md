## 1. 전략·KPI 중요도 속성 (strategy_strategy-map-graph)

- [x] 1.1 `Strategy`, `KPI` 그래프 노드에 `importance`(1~5 정수) 속성을 추가하고, 기존 노드 backfill 시 기본값(3)을 채우는 이관 스크립트를 작성한다 — "전략맵 엔티티가 온톨로지 표준 그래프 스키마로 저장된다" 요구사항의 중요도 관련 시나리오 검증
- [x] 1.2 `POST/PUT /api/objectives[/{id}]`, `POST/PUT /api/kpis[/{id}]` 요청 본문에 선택적 `importance` 필드를 받아 저장하도록 확장한다 — "기존 전략맵 API 계약이 유지된다" 요구사항의 중요도 필드 시나리오 검증
- [x] 1.3 `GET /api/map` 등 전략맵 조회 응답의 전략 목표·KPI 항목에 `importance` 필드를 포함하도록 확장한다
- [x] 1.4 `importance` 필드를 생략한 기존 요청/조회가 이전과 동일하게 동작하는지 회귀 검증한다 — "중요도 필드 생략 시 기존 동작 유지" 시나리오 검증

## 2. 중요도 가중 기여도 조회 API (strategy_contribution-attribution)

- [x] 2.1 `strategy_impact-analysis`의 전략 하위 BFS(`_descendant_strategies`)를 재사용해 전략 범위 조회 계층을 만들었다. 단, 실행 지표 기여 랭킹 자체는 재사용하지 않고 2.1b 의 인스턴스 스코프 계산으로 대체했다(이유: PERFORMS 엣지의 전체 기간 누적 통계는 "이 KPI 실적에 실제로 반영된 기여자"를 정확히 가려낼 수 없어 신규 요구사항을 만족하지 못함 — design.md 결정 2-1 참고)
- [x] 2.1a KPI 측정 인스턴스 집합 식별 방법을 확정했다 — `measurement.compute_kpi_value`가 이미 `proc_def_id`+`status='COMPLETED'`+`is_deleted=false`+`period_start`/`period_end` 필터로 결정론적으로 산출하므로, 별도 저장 없이 조회 시점에 동일 필터를 재사용해 도출한다(`contribution.py:_kpi_instance_ids`). 부수적으로 `measurement._period_filter`의 `period_end` 캐스팅 버그를 발견해 수정했다(`test_instance_count_respects_period_end_boundary`로 회귀 검증)
- [x] 2.1b 식별된 인스턴스 집합을 `public.todolist`(태스크 수행 이력)·`public.bpm_proc_inst`(폼 값)와 조인해 성과자별 기여 비중을 `measure_type`별로 계산했다(건수/처리시간 비중, `form_value_sum`은 인스턴스별 폼 값 비중 배분, `manual`은 추적 불가) — `test_contribution.py`의 측정범위 제외/폼값 배분/추적불가 시나리오로 검증
- [x] 2.2 `GET /api/contribution/kpi/{id}`를 구현해 단일 KPI 기준 성과자별 기여도를 기여도 내림차순으로 반환한다 — 성공/빈 목록/404 시나리오 검증
- [x] 2.3 `GET /api/contribution/strategy/{id}`를 구현해 전략 목표 및 하위 전략·KPI 전체 범위의 성과자별 합산 기여도를 반환한다
- [x] 2.4 `GET /api/contribution/performer/{id}`를 구현해 특정 성과자(사람/에이전트) 기준 전략별 기여도 통계 요약을 반환한다 — 성공/기여 이력 없음/404 시나리오 검증
- [x] 2.5 응답 스키마에 `performer_type`(`HUMAN`|`AGENT`) 필드를 포함해 사람과 에이전트가 동일한 순위표에서 함께 정렬되도록 구현한다
- [x] 2.6 KPI 기여도(0~1 정규화 share)를 전략 범위로 합산할 때 각 전략의 `importance` 값으로 가중하고, 미설정 전략은 중간값(3)으로 처리하는 가중합 로직을 구현한다 — 가중 합산 및 미설정 처리 시나리오 검증

## 3. 스킬별 사람 기여 이력 추적 (agent-feedback_skill-contribution-tracking)

- [x] 3.1 스킬 기여 이력을 적재할 관계형 이력 테이블(기여자, 기여 시각, 기여 유형)을 설계하고 마이그레이션을 작성한다 — `skill_contributions.sql`(`skill_contributions` 테이블), `core/database.py`에 `record_skill_contribution`/`fetch_skill_contributors` 추가
- [x] 3.2 스킬 생성/수정 처리 흐름에 기여 이력 기록을 연결한다 — `skill_committer.commit_to_skill`에 `contributor_user_ids`/`contribution_source` 전파, CREATE→CREATED/UPDATE→MODIFIED 기록. "스킬 생성·수정 시 기여자가 자동으로 기록된다" 요구사항의 생성/수정 시나리오 검증(mock 기반 단위 테스트)
- [x] 3.3 `feedback_proposals` 승인/거부 흐름에 기여 이력 기록을 연결해, 승인 시에만 제안자·승인자가 기록되도록 구현한다 — `apply_approved_proposal`이 배치의 원 피드백 작성자(`_union_user_ids`) + 승인자(`approver_id`)를 합쳐 `contribution_source="proposal_approval"`로 전달, 거부 경로는 그대로 두어 기록되지 않음을 확인. 승인/거부 시나리오 검증
- [x] 3.4 온톨로지 그래프에 `User -CONTRIBUTED_TO-> Skill` 관계를 반영하는 파생 동기화 로직을 구현한다 — services/strategy(같은 플랫폼 Supabase를 공유)의 `ontology_sync.sync_skill_contributions`가 agent-feedback이 적재한 `public.skill_contributions`를 증분 동기화해 그래프 엣지로 반영, `sync_all`에 편입
- [x] 3.5 `GET /api/skills/{id}/contributors`를 구현해 기여자 목록과 상대적 기여 비중을 반환한다 — `core/skill_contributor_routes.py`. 다수 기여자/이력 없음/404 시나리오 검증
- [x] 3.6 기존 `feedback_proposals`의 과거 승인 이력을 신규 기여 이력 테이블과 그래프 엣지로 이관하는 1회성 backfill 스크립트를 작성하고 실행한다 — `scripts/backfill_skill_contributions.py`(멱등, 단위 테스트로 로직 검증). **실행은 보류**: 대상 프로덕션 Supabase 인스턴스에 대한 실행 권한/자격 증명이 이 세션에 없어 실제 백필 실행은 운영자가 별도로 수행해야 한다(그래프 반영은 3.4의 `sync_skill_contributions`가 이후 자동으로 따라잡는다)

## 4. 성과·성장 기여도 대시보드 (analytic-service_dashboard-analytics)

- [x] 4.1 `GET /api/dashboard/contribution`을 구현해 전략 목표를 `importance` 내림차순으로 정렬하고, 각 목표 아래 성과자 기여도(2절 API)와 스킬 기여 이력(3절 API)을 결합해 반환한다 — `services/analytic/backend/app/contribution_dashboard.py`, 부분 실패 완화(graceful degrade) 포함, mock 테스트 9건
- [x] 4.2 `strategy_id` 파라미터로 특정 전략 목표 범위로 좁혀 조회하는 기능을 구현한다
- [x] 4.3 기여도·기여 이력 데이터가 없는 경우 오류 없이 빈 목록을 반환하도록 처리한다
- [x] 4.4 ~~별도 대시보드 화면~~ → **사용자 확인을 거쳐 전략맵 노드 상세 통합으로 재설계** (`storyboard.html` 승인, 2026-07-23): 보드 카드 중요도 배지, 상세 패널 "기여도" 탭(analytic 결합 API 소비 — 사람·에이전트 통합 가중 순위 + 스킬 성장 기여), KPI 행 확장 기여도 블록, 성과자 역방향 요약 다이얼로그, 온톨로지 탐색기 CONTRIBUTED_TO('기여') 표시. `StrategyBoard.vue`/`OntologyExplorer.vue`/`strategyStore.ts`/locales 수정, `vue-tsc --noEmit` clean, 실서비스 대상 Playwright 검증 전부 PASS(`e2e/record_ui_demo.py`), 데모 영상 `docs/demo/contribution-attribution-ui-demo.mp4`

## 5. 통합 검증

- [x] 5.1 `openspec/specs/strategy_contribution-attribution/e2e/`에 전략→KPI→성과자, 성과자→전략 양방향 조회 E2E 시나리오를 작성하고 실행한다 — `seed_demo.py`+`demo.html`+`record_demo.py`로 실서비스 3개(strategy/agent-feedback/analytic) 대상 8개 검증 항목 전부 PASS, 데모 영상 `docs/demo/contribution-attribution-demo.mp4` 및 `e2e/results.md` 참조
- [ ] 5.2 `openspec/specs/agent-feedback_skill-contribution-tracking/e2e/`에 스킬 생성·제안 승인에 따른 기여자 반영 E2E 시나리오를 작성하고 실행한다
- [ ] 5.3 `strategy-graph-repository` 변경이 먼저 archive되었는지 확인하고, 순서가 맞지 않으면 이 변경의 delta를 그 시점의 베이스라인에 맞게 재조정한다
- [ ] 5.4 기존 `GET /api/map`, `GET /api/impact/*`, `GET /api/analytics/*` 엔드포인트에 대한 회귀 테스트를 재실행해 하위 호환이 깨지지 않았음을 확인한다
