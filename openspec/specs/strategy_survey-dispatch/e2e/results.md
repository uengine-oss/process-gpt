# strategy_survey-dispatch E2E 실행 결과

- 실행 일시: 2026-07-19 (KST)
- 인프라: process-gpt-age-postgres (127.0.0.1:55433) / uvicorn 8114 (그래프 corp_ontology_e2e)
- 결과: **11/11 PASS**

## Pass/Fail 표

| # | 시나리오 | 결과 |
| --- | --- | --- |
| 1 | measure/run 이 설문 발송을 트리거함(surveys_dispatched>=1) | PASS |
| 2 | 설문 요청이 발행됨(strategy_survey_requests) | PASS |
| 3 | 발행된 설문 상태가 대기중 | PASS |
| 4 | 설문 워크아이템(todolist) 생성됨: activity_id=kpi_survey | PASS |
| 5 | 설문 워크아이템 상태 IN_PROGRESS | PASS |
| 6 | 설문 워크아이템이 완료 인스턴스에 연결됨 | PASS |
| 7 | 설문 응답 제출 200 | PASS |
| 8 | 응답 후 상태 ANSWERED | PASS |
| 9 | 응답 점수 = 4.0 | PASS |
| 10 | 설문 워크아이템 상태 DONE 전이 | PASS |
| 11 | KPI current_value 가 설문 점수(4.0)를 반영 | PASS |

## 주요 응답 발췌

- `POST /api/measure/run` → `surveys_dispatched >= 1` (완료 인스턴스 감지 후 `watch_completions()`가 즉시 설문을 발행).
- `GET /api/surveys?kpi_id=` → 발행된 요청 1건, 최초 상태는 미응답(`ANSWERED` 아님).
- `public.todolist` 직접 조회 → `activity_id='kpi_survey'`, `status='IN_PROGRESS'`, `proc_inst_id`가 seed 한 완료 인스턴스와 일치.
- `POST /api/surveys/{id}/respond` (평점 4) → 200, 이후 `GET /api/surveys/{id}`: `status='ANSWERED'`, `score=4.0`.
- 응답 후 `public.todolist` 재조회 → `status='DONE'`.
- `respond_survey`가 응답 즉시 `measurement.measure_all()`을 재실행하므로, 별도 측정 호출 없이 `GET /api/map`의 KPI `current_value`가 곧바로 `4.0`으로 반영됨.

## 실행 콘솔

```
=== SUMMARY: 11/11 PASSED ===
```

## 결론

이미 구현되어 있던 설문 자동 발행 파이프라인(`app/survey.py`)이 완료 인스턴스 감지 →
`todolist` 워크아이템 생성(알림 트리거 재사용) → REST 응답 제출 → KPI 재집계까지
네트워크 경계를 넘어 실제로 동작함을 확인했다. 코드 변경은 없었다(검증 전용 스위트).
