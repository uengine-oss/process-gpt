# strategy_impact-analysis E2E 실행 결과

- 실행 일시: 2026-07-09 (KST)
- 인프라: process-gpt-age-postgres (127.0.0.1:55433) / uvicorn 8114 (그래프 corp_ontology_e2e, OPENAI_API_KEY 미설정)
- 결과: **21/21 PASS**

## Pass/Fail 표

| # | 시나리오 | 결과 |
| --- | --- | --- |
| 1 | KPI 역추적 200 | PASS |
| 2 | KPI 요약 + 달성률(<100 목표 미달) | PASS |
| 3 | 원인 후보 비어있지 않음 | PASS |
| 4 | 최상위 후보 = 병목 태스크(개발, score=6.0) | PASS |
| 5 | 모든 후보에 path + metrics 존재 | PASS |
| 6 | 경로가 KPI(개발 소요 시간)에서 시작 | PASS |
| 7 | paths_summary(processes=1,tasks=2,resources=2,skills=1) | PASS |
| 8 | no_downstream=false | PASS |
| 9 | LLM 미설정 → diagnosis null | PASS |
| 10 | 하위 연결 없는 KPI: candidates=[], no_downstream=true | PASS |
| 11 | 존재하지 않는 KPI 404 | PASS |
| 12 | 결정성: 동일 KPI 두 호출 결과 동일 | PASS |
| 13 | 전략 하향 분석 200 | PASS |
| 14 | 전략 요약 | PASS |
| 15 | 목표 미달 KPI(개발 소요 시간) 포함 | PASS |
| 16 | 스킬 개선 후보 비어있지 않음 | PASS |
| 17 | 개선 스킬 경로(linked_via)가 전략(비용 감소)에서 시작 | PASS |
| 18 | 고급 개발 스킬이 개선 후보에 포함 | PASS |
| 19 | 병목(태스크/리소스) 후보 존재 | PASS |
| 20 | 전략 분석 LLM 미설정 → diagnosis null | PASS |
| 21 | 존재하지 않는 전략 404 | PASS |

## 주요 응답 발췌

- `GET /api/impact/kpi/{id}`: `candidates[0] = {type:"task", name:"개발", score:6.0}`(병목),
  `paths_summary={processes:1, tasks:2, resources:2, skills:1}`, `no_downstream:false`,
  `diagnosis:null`. 두 호출 응답 JSON 완전 동일(결정성).
- `GET /api/impact/strategy/{id}`: `lagging_kpis` 에 "개발 소요 시간" 포함, `skill_improvements`
  에 "고급 개발 스킬"(linked_via 각 경로가 `Strategy:비용 감소` 에서 시작), `bottlenecks` 비어있지 않음.

## 실행 콘솔

```
=== SUMMARY: 21/21 PASSED ===
```
