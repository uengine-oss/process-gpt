# strategy_impact-analysis E2E 시나리오

## 목적

레이어 간 영향도 분석(역추적)과 스킬 개선점 도출을 검증한다:
`GET /api/impact/kpi/{id}` 의 KPI→프로세스→태스크→리소스→스킬 역추적과 실행 지표 기반
원인 후보 랭킹(병목 태스크 최상위), 하위 연결 없는 KPI, 404, 결정성(동일 데이터 동일 결과);
`GET /api/impact/strategy/{id}` 의 목표 미달 KPI·병목·스킬 개선점(전략까지의 연결 경로 포함).

## 사전조건 / 인프라

- **인프라(Docker)**: process-gpt-age-postgres (127.0.0.1:55433, postgres/postgres/postgres).
- **애플리케이션(소스 실행)**: 상시 uvicorn 서버(포트 8114, `MEASURE_AUTO_START=false`,
  `OPENAI_API_KEY` 미설정 → `diagnosis`는 null, 결정적 결과만).
- 분석이 의미를 갖도록 **실행 지표**를 seed 한다: 전략(비용 감소) + 목표 미달 KPI(개발 소요
  시간, decrease 10→2, current 8 → 달성률 25%), proc_def(개발 a1 / 리뷰 a2), 서로 다른
  처리시간의 todolist 완료 이력(agent a1 6h×3 → avg 6h 병목, user a2 1h×2 → avg 1h),
  agent USES_SKILL(고급 개발 스킬). 러너가 원천 seed + `POST /api/ontology/sync`.
- 고유 테넌트 `e2e-impact-<ts>` 사용, 종료 시 정리.

## 실행 명령 · 포트 · 환경 변수

서버 기동은 8114(위 스위트와 동일 환경). 러너:

```bash
services/strategy/.venv/bin/python \
  openspec/specs/strategy_impact-analysis/e2e/run_e2e.py
```

## 시나리오 단계 ↔ spec Scenario 매핑

| 러너 단계 | spec Scenario |
| --- | --- |
| KPI 역추적: 병목 태스크(개발,6h) 최상위, path+metrics, paths_summary | KPI 하락 원인 역추적 |
| 하위 연결 없는 KPI: candidates=[], no_downstream=true | 하위 연결이 없는 KPI |
| 존재하지 않는 KPI 404 | (404 요구) |
| 결정성: 동일 KPI 두 호출 결과 동일 | 동일 데이터의 재현성 |
| LLM 미설정 → diagnosis null(경로·랭킹·지표 완전) | LLM 미설정 환경의 분석 |
| 전략 하향: 목표 미달 KPI + 스킬 개선점(전략까지 경로) + 병목 | 전략 하향 분석으로 스킬 개선점 도출 |
| 존재하지 않는 전략 404 | (404 요구) |
