# strategy_strategy-map-graph E2E 실행 결과

- 실행 일시: 2026-07-09 (KST)
- 인프라: process-gpt-age-postgres (127.0.0.1:55433) / uvicorn 소스 실행 포트 8114 (그래프 corp_ontology_e2e)
- 결과: **20/20 PASS**

## Pass/Fail 표

| # | 시나리오 | 결과 |
| --- | --- | --- |
| 1 | CRUD 목표 생성/조회 | PASS |
| 2 | CRUD KPI 중첩(proc_def_id 포함) | PASS |
| 3 | CRUD 이니셔티브 중첩 | PASS |
| 4 | CRUD 응답 계약 키(objectives/kpis/initiatives/parents/achievement) | PASS |
| 5 | 수정 결과 반영(name/perspective) | PASS |
| 6 | 존재하지 않는 KPI 수정 404 | PASS |
| 7 | 전략간 계층 생성 응답 parents | PASS |
| 8 | 전략맵 조회 시 하위 parents 에 상위 id | PASS |
| 9 | 부모 삭제 후 부모 노드 제거 | PASS |
| 10 | 부모 삭제 후 자식 parents 잔존 참조 없음 | PASS |
| 11 | 목표 삭제 시 KPI 연쇄 삭제 | PASS |
| 12 | 목표 삭제 시 이니셔티브 연쇄 삭제 | PASS |
| 13 | 이관 요약 노드 수(objectives=2,kpis=1,initiatives=1,processes=1) | PASS |
| 14 | 이관 후 parents→HAS_SUB_STRATEGY 왕복 | PASS |
| 15 | 이관 후 proc_def_id 유지 + Process 미러 이름 | PASS |
| 16 | 이관 멱등성(counts_before == counts_after) | PASS |
| 17 | 이관 멱등성(노드 중복 없음: 목표2/KPI1/이니셔티브1) | PASS |
| 18 | BSCard 이관 imported=4, skipped=0 | PASS |
| 19 | BSCard 관점 정규화(한국어→표준) | PASS |
| 20 | BSCard 부모 관계 이관(HAS_SUB_STRATEGY) | PASS |

## 주요 응답 발췌

- CRUD `GET /api/map` objective 키: `id, tenant_id, name, description, perspective, sort_order,
  created_at, updated_at, parents, kpis, initiatives, achievement` — 관계형 시절과 동일한 중첩 계약.
- 이관 요약(`POST /api/migrate-graph`): `{objectives:2, kpis:1, initiatives:1, processes:1,
  counts_before==counts_after (재실행)}`.
- BSCard 관점 정규화: `재무→financial`, `고객→customer`, `내부 프로세스→internal_process`,
  `학습 및 성장→learning_growth`.

## 실행 콘솔

```
=== SUMMARY: 20/20 PASSED ===
```
