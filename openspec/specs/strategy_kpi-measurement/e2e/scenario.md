# strategy_kpi-measurement E2E 시나리오

## 목적

다각적 KPI 측정과 그래프/이력 반영을 검증한다: 정량(`instance_count`,
`avg_duration_hours`, `form_value_sum` — 평탄/중첩 폼 값 합산)·정성(`survey_score`)·
수동(`manual`) 측정을 `POST /api/measure/run` / `POST /api/kpis/{id}/value` 로 실행하고,
`GET /api/map` 의 `current_value`/`achievement` 와 `GET /api/kpis/{id}/measurements` 이력을
확인한다.

## 사전조건 / 인프라

- **인프라(Docker)**: process-gpt-age-postgres (127.0.0.1:55433, postgres/postgres/postgres).
- **애플리케이션(소스 실행)**: 상시 uvicorn 서버(포트 8114, `MEASURE_AUTO_START=false` —
  측정을 API 로 명시 실행).
- 러너가 완료 인스턴스(`bpm_proc_inst` COMPLETED, 건수·처리시간·`variables_data` 평탄/중첩
  계약금액)와 ANSWERED 설문 요청(`strategy_survey_requests`)을 seed 한다(`seed.sql`).
  각 측정 유형은 별도 `proc_def` 로 격리해 상호 간섭을 막는다.
- 고유 테넌트 `e2e-measure-<ts>` 사용, 종료 시 정리.

## 실행 명령 · 포트 · 환경 변수

서버 기동은 8114(위 스위트와 동일 환경). 러너:

```bash
services/strategy/.venv/bin/python \
  openspec/specs/strategy_kpi-measurement/e2e/run_e2e.py
```

## 시나리오 단계 ↔ spec Scenario 매핑

| 러너 단계 | spec Scenario |
| --- | --- |
| instance_count: 완료 3건 → current_value 3, achievement 30 | 완료 건수 정량 측정 |
| form_value_sum: 평탄(100)+중첩(200) → 300 | 폼 입력값 합산 정량 측정 |
| avg_duration_hours: 1h+3h → 2.0 | (정량 측정) |
| survey_score: ANSWERED 4,5 → 4.5 (source=survey) | 설문 기반 정성 측정 |
| manual: POST value 50 → 50, achievement 50 (source=manual) | 수동 실적 입력과 달성률 계산 |
| map current_value == 이력 최신값 | 측정 후 전략맵·이력 동시 반영 |
| 이력 최신순 + source 기록 | (측정 이력 요구) |
