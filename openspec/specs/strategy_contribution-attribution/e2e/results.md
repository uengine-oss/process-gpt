# strategy_contribution-attribution — E2E 데모 실행 결과 (2026-07-21)

## 실행 환경 (Dockerized infrastructure + source-run application services)

| 구성 요소 | 실행 방식 | 접속 |
|---|---|---|
| 플랫폼 관계형 DB | Docker `supabase-db` (기존 기동분) | 127.0.0.1:54322 |
| 온톨로지 그래프(AGE) | Docker `docker-infra-age-postgres-1` | 127.0.0.1:55433 (graph `corp_ontology`) |
| Supabase REST | Docker `supabase-kong` | http://localhost:54321 |
| 스킬 API (deepagents) | 기존 기동분 | http://localhost:8888 |
| strategy 서비스 | 소스 실행 `uvicorn app.main:app --port 8014` (`DB_*`=54322, `GRAPH_DB_*`=55433, `MEASURE_AUTO_START=false`) | :8014 |
| agent-feedback 서비스 | 소스 실행 `python main.py` (`SUPABASE_URL=…54321`, `SKILL_API_BASE_URL=…8888`, `PORT=6789`) | :6789 |
| analytic 서비스 | 소스 실행 `uvicorn app.main:app --port 8022` (`STRATEGY_SERVICE_URL=…8014`, `AGENT_FEEDBACK_SERVICE_URL=…6789`, `ETL_AUTO_START=false`) | :8022 |

시드/재현: `seed_demo.py` (스크래치 테넌트 생성→전략맵 API→실행 이력·기여 이력 시드→측정→온톨로지 동기화)
→ `demo.html` (:9321 정적 서빙, 3개 서비스 라이브 응답 렌더링) → `record_demo.py` (Playwright headed 녹화).
데모 영상: [`docs/demo/contribution-attribution-demo.mp4`](../../../../docs/demo/contribution-attribution-demo.mp4) (~30초).
섹션별 스크린샷: `screenshots/s1.png` ~ `s8.png`. **mock 없음** — 영상의 모든 수치는 실서비스 HTTP 응답이다.

## 시나리오와 검증 결과 (8/8 PASS)

시드 데이터: 전략 "매출 성장"(중요도 5, KPI 계약 완료 건수) ← 하위 "운영 효율화"(중요도 2, KPI 검토 완료 건수),
"브랜드 강화"(중요도 3, manual KPI). 계약 프로세스 완료 3건(김지은 2·계약검토봇 1), 검토 완료 2건(봇 2).
스킬 기여 이력: 김지은 CREATED+MODIFIED, 박민수 PROPOSAL_APPROVED ("계약 검토 스킬").

| # | 검증 항목 (요구사항) | 결과 |
|---|---|---|
| ① | `GET /api/map`에 `importance` 노출, 미지정 시 기본값 3 | PASS — 5/2/3, "브랜드 강화" 미지정→3 |
| ② | KPI 기준 성과자 기여도 — 측정 반영 인스턴스 근거, 사람·에이전트 동일 순위표 | PASS — 김지은(HUMAN) 66.7% > 봇(AGENT) 33.3% |
| ③ | 전략 범위 중요도 가중 합산 | PASS — 봇 3.6665(0.333×5+1.0×2) > 김지은 3.3335(0.667×5) — **가중치로 순위 역전** |
| ④ | 성과자 기준 역방향 통계 (`/api/contribution/performer/{id}`) | PASS — 봇 총 3.6665, KPI 2건 전략별 내역 |
| ⑤ | 추적 불가 측정 유형(manual) 구분 표시 | PASS — `traceable: false`, performers `[]` |
| ⑥ | 스킬별 사람 기여자 조회 (실제 agent-feedback + 실제 Supabase + 실제 스킬 API 존재 확인) | PASS — 김지은 66.7%(2건) · 박민수 33.3%(1건) |
| ⑦ | 기여 이력의 온톨로지 반영 — `(User)-[:CONTRIBUTED_TO]->(Skill)` 증분 동기화 | PASS — sync 결과 items 3 → edges 2 |
| ⑧ | `GET /api/dashboard/contribution` — 3개 서비스 결합, 중요도 내림차순, 하위 전략 이중 집계 방지 | PASS — [5]매출 성장(성과자+스킬 기여자) → [3]브랜드 강화, `strategy_id` 범위 축소·빈 테넌트 graceful 확인 |

## 단위 테스트 증거 (라이브 DB 대상, mock 아님*)

- `services/strategy`: 112 passed — 신규 `test_contribution.py` 11건(측정범위 제외/폼값 배분/추적불가/404/가중합),
  `test_skill_contribution_sync.py` 5건, `test_api_strategy_map.py` +3건(importance), `test_migration.py` +2건(backfill),
  `test_measurement.py` +1건(period_end 경계 회귀 — 구현 중 발견한 기존 버그 수정 검증).
  (기존부터 실패하던 `test_ontology_sync.py` 9건은 로컬 todolist 테이블 스키마 문제로 본 변경과 무관 — 55433 DB의 `duration` 컬럼 부재.)
- `services/agent-feedback`: 32 passed — 신규 `test_skill_contribution_tracking.py` 10건(*mock 기반),
  `test_backfill_skill_contributions.py` 3건(*mock 기반). (기존 실패 2건은 본 변경 이전부터 존재.)
- `services/analytic/backend`: 9 passed — 신규 `tests/test_contribution_dashboard.py`(*HTTP mock 기반: 정렬/결합/부분 실패 완화).

## 데모 중 확인된 사항 / 남은 작업

- 실제 플랫폼 스키마(supabase-db)는 `tenants`/`tenant_skills` FK 를 강제한다 — `seed_demo.py`가 이를 처리하도록 반영됨.
- strategy 서비스의 이중 DB 토폴로지(관계형=플랫폼 Supabase, 그래프=AGE 분리)에서 기여도 조회가 정상 동작함을 확인.
- 미완: 4.4(프론트엔드 Vue 대시보드 화면) — 본 데모의 `demo.html`은 검증용 뷰어이며 제품 화면이 아니다.
- 미완: 5.2(agent-feedback 커밋 훅 E2E — Deep Agent 실행 포함 경로), 5.4(전체 회귀 스위트 재실행).
- 데모 스크래치 테넌트는 실행 후 정리(cleanup)되었다 — 재현하려면 `seed_demo.py`부터 다시 실행.

---

# UI 통합 검증 (2026-07-23) — 스토리보드 승인 후 구현분

사용자 방향 정정("각 노드 클릭 → 상세에서 기여도 조망")에 따라 스토리보드
(`openspec/changes/strategy-contribution-attribution/storyboard.html`) 승인 후 구현.
검증은 **실제 제품 컴포넌트**(StrategyBoard.vue / OntologyExplorer.vue)를 로그인 프리
하네스로 마운트해 실서비스(strategy :8014 / agent-feedback :6789 / analytic :8899,
vite :5199) 대상 Playwright assert 로 수행 — `record_ui_demo.py`, 전부 PASS.

| 장면 | 검증 항목 | 결과 |
|---|---|---|
| 1 | 보드 카드 중요도(★) 배지 표시 | PASS (`ui-1-board-importance.png`) |
| 3 | KPI 행 확장 → KPI 단위 기여도 블록(김지은 66.7% 등) | PASS (`ui-2-kpi-contribution.png`) |
| 2 | 상세 패널 "기여도" 탭 — 가중 순위 1위가 에이전트(계약검토봇 3.6665, 역전) + 스킬 성장 기여자 표시 | PASS (`ui-3-contribution-tab.png`) |
| 2 | 성과자 행 확장 — KPI별 산출 내역(비중 × 중요도) | PASS (`ui-4-breakdown.png`) |
| 4 | 성과자 이름 클릭 → 역방향 요약 다이얼로그(전략별 가중 테이블) | PASS (`ui-5-performer-dialog.png`) |
| 5 | 온톨로지 탐색기 CONTRIBUTED_TO('기여') 라벨 | PASS (`ui-6-ontology-contributed-to.png`) |

- 데모 영상: `docs/demo/contribution-attribution-ui-demo.mp4` (~21초)
- `vue-tsc --noEmit` clean (수정 파일: StrategyBoard.vue, OntologyExplorer.vue, strategyStore.ts, locales ko/en)
- 하네스 파일(demo-contribution.html, src/demo-contribution-main.ts)은 기존 데모 컨벤션대로 녹화 후 제거 —
  재현 방법은 docs/demo/README.md "How this recording was made" 참조
- 스크래치 테넌트(demo-b6178d44)는 그래프·Supabase 양쪽에서 정리 완료
