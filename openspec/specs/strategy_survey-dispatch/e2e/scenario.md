# strategy_survey-dispatch E2E 시나리오

## 목적

설문 자동 발행→담당자 워크아이템→응답→KPI 재집계 전체 경로를 순수 HTTP(+직접 SQL
확인)로 검증한다. 기존 `strategy_kpi-measurement` 스위트는 `ANSWERED` 설문 요청을
직접 seed 해 측정 수식만 격리 검증하고, 단위 테스트(`tests/test_measurement.py::
test_survey_watch_dispatch_and_recompute`)는 `survey.submit_response()`를 파이썬
함수로 직접 호출한다 — 두 경우 모두 "완료 인스턴스 → `watch_completions()` 발행 →
`todolist` 워크아이템 생성 → `POST /api/surveys/{id}/respond` REST 응답" 경로를
네트워크 너머로 검증하지 않는다. 이 스위트는 그 빈틈을 메운다.

## 사전조건 / 인프라

- **인프라(Docker)**: process-gpt-age-postgres (127.0.0.1:55433, postgres/postgres/postgres).
- **애플리케이션(소스 실행)**: 상시 uvicorn 서버(포트 8114, `MEASURE_AUTO_START=false` —
  설문 발행은 `POST /api/measure/run` 이 내부적으로 `survey.watch_completions()` 도
  함께 호출하므로 이를 통해 명시 실행한다, `app/main.py`의 `run_measurement`).
- 러너가 `survey_score` KPI가 연결된 완료 인스턴스(`bpm_proc_inst`)와 참여자
  (`users`)를 seed 한다(`seed.sql`). `watch_completions()`의 완료 인스턴스 커서
  (`strategy_sync_state.completed_instance_cursor`)는 테넌트 스코프가 아닌 전역
  값이지만, 항상 과거 시점이므로 방금 seed 한 인스턴스(`updated_at=now()`)는 항상
  그보다 새로워 안정적으로 스캔 대상에 포함된다.
- 고유 테넌트 `e2e-survey-<ts>` 사용, 종료 시 정리(`bpm_proc_inst`/`proc_def`/`users`/
  `todolist`/`strategy_survey_requests`/`strategy_kpi_measurements`).

## 실행 명령 · 포트 · 환경 변수

서버 기동은 8114(다른 strategy e2e 스위트와 동일 환경):

```bash
cd services/strategy && \
DB_HOST=127.0.0.1 DB_PORT=55433 DB_USER=postgres DB_PASSWORD=postgres DB_NAME=postgres \
GRAPH_STORE=age GRAPH_NAME=corp_ontology_e2e MEASURE_AUTO_START=false \
.venv/bin/python -m uvicorn app.main:app --host 127.0.0.1 --port 8114
```

러너:

```bash
services/strategy/.venv/bin/python \
  openspec/specs/strategy_survey-dispatch/e2e/run_e2e.py
```

## 시나리오 단계 ↔ spec Scenario 매핑

| 러너 단계 | spec Scenario |
| --- | --- |
| `POST /api/measure/run` → `surveys_dispatched>=1` | 완료 인스턴스 감지 → 설문 발행 |
| `GET /api/surveys?kpi_id=` 요청 1건 생성, 상태 대기중 | 설문 요청 레코드 생성 |
| `todolist` 워크아이템 생성(`activity_id='kpi_survey'`, `status='IN_PROGRESS'`) | 설문의 BPM 워크아이템화(알림 트리거 재사용) |
| 워크아이템이 완료 인스턴스(`proc_inst_id`)에 연결 | 설문-인스턴스 연결 |
| `POST /api/surveys/{id}/respond` 200 | 설문 응답 제출(REST) |
| 응답 후 `status=ANSWERED`, `score=4.0` | 응답 집계(평점 평균) |
| `todolist` 워크아이템 `status=DONE` 전이 | 응답 시 워크아이템 완료 처리 |
| `GET /api/map` KPI `current_value=4.0` (재측정 호출 없이) | 응답 즉시 KPI 재집계 반영 |
