# strategy_kpi-measurement E2E 실행 결과

- 실행 일시: 2026-07-19 (KST, `external_source` 시나리오 추가 재실행)
- 인프라: process-gpt-age-postgres (127.0.0.1:55433) / uvicorn 8114 (그래프 corp_ontology_e2e)
- 결과: **13/13 PASS**

## Pass/Fail 표

| # | 시나리오 | 결과 |
| --- | --- | --- |
| 1 | measure/run 측정 수행(kpis_measured>=5) | PASS |
| 2 | 수동 입력 200 | PASS |
| 3 | instance_count current_value=3, achievement=30.0 | PASS |
| 4 | avg_duration_hours current_value=2.0 | PASS |
| 5 | form_value_sum current_value=300 (평탄+중첩) | PASS |
| 6 | survey_score current_value=4.5 | PASS |
| 7 | manual current_value=50, achievement=50.0 | PASS |
| 8 | external_source current_value=82.5 (외부 HTTP GET) | PASS |
| 9 | instance_count 이력 최신값=3, source=auto | PASS |
| 10 | external_source 이력 source=auto | PASS |
| 11 | survey_score 이력 source=survey | PASS |
| 12 | manual 이력 source=manual | PASS |
| 13 | 전략맵 current_value 와 이력 최신값 일치(instance_count) | PASS |

## 주요 응답 발췌

- `POST /api/measure/run` → `kpis_measured >= 5`.
- `GET /api/map` KPI `current_value` / `achievement`:
  - instance_count: 3 / 30.0
  - avg_duration_hours: 2.0
  - form_value_sum(계약금액 평탄100 + 중첩200): 300.0
  - survey_score(ANSWERED 4,5): 4.5
  - external_source(모의 SoR `{"data":{"nps_score":82.5}}`, `source_field="data.nps_score"`): 82.5
  - manual(POST value 50, 0→100): 50 / 50.0
- `GET /api/kpis/{id}/measurements` 최신 기록 source: `auto`(정량/외부연동) / `survey`(설문) / `manual`(수동).

## 실행 콘솔

```
=== SUMMARY: 13/13 PASSED ===
```
