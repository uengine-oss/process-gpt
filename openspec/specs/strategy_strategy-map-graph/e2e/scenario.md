# strategy_strategy-map-graph E2E 시나리오

## 목적

전략 레이어(전략맵/BSC)의 그래프 관리 계약을 검증한다: 전략목표→KPI(proc_def_id)→
이니셔티브 CRUD 왕복과 `GET /api/map` 중첩 응답, 전략 간 계층(`HAS_SUB_STRATEGY`)
왕복, 부모 삭제 시 자식 `parents` 정리 + KPI·이니셔티브 연쇄 삭제, 관계형→그래프 이관
(`POST /api/migrate-graph`)과 멱등성, 레거시 BSCard 이관(`POST /api/import-bscard`, 한국어
관점 정규화).

## 사전조건 / 인프라

- **인프라(Docker)**: process-gpt-age-postgres (127.0.0.1:55433, postgres/postgres/postgres).
- **애플리케이션(소스 실행)**: 상시 uvicorn 서버(포트 8114, 그래프 `corp_ontology_e2e`).
- CRUD/관계/삭제는 API 로 그래프에 직접 쓴다. 이관·BSCard 시나리오만 관계형 원천
  (`strategy_objectives/kpis/initiatives`, `configuration`, `proc_def`)에 seed 가 필요하며
  러너가 `sqlalchemy` 로 직접 INSERT 한다(`seed.sql` 참조).
- 재실행 무해를 위해 테넌트 id 는 `e2e-map-*-<ts>` 형태로 고유하게 발급한다.

## 실행 명령 · 포트 · 환경 변수

서버 기동(포트 8114):

```bash
cd services/strategy && \
DB_HOST=127.0.0.1 DB_PORT=55433 DB_USER=postgres DB_PASSWORD=postgres DB_NAME=postgres \
GRAPH_STORE=age GRAPH_NAME=corp_ontology_e2e MEASURE_AUTO_START=false \
.venv/bin/python -m uvicorn app.main:app --host 127.0.0.1 --port 8114
```

러너 실행:

```bash
services/strategy/.venv/bin/python \
  openspec/specs/strategy_strategy-map-graph/e2e/run_e2e.py
```

## 시나리오 단계 ↔ spec Scenario 매핑

| 러너 단계 | spec Scenario |
| --- | --- |
| CRUD 목표/KPI/이니셔티브 생성 + map 중첩 | 전략맵 CRUD 왕복 |
| CRUD KPI proc_def_id → IMPACTS_KPI/Process 미러 | 전략-KPI-프로세스 연결 경로 |
| CRUD 이니셔티브 proc_def_id → EXECUTED_BY | 이니셔티브-프로세스 연결 |
| 수정 결과 반영(name/perspective) | 수정 결과 반영 |
| 존재하지 않는 KPI 수정 404 | 존재하지 않는 리소스 수정 |
| 전략간 계층 생성 + map parents | 전략 간 계층 관계 저장 |
| 부모 삭제 후 자식 parents 잔존 참조 없음 | 부모 목표 삭제 시 자식의 참조 정리 |
| 목표 삭제 시 KPI·이니셔티브 연쇄 삭제 | 목표 삭제 시 KPI·이니셔티브 연쇄 삭제 |
| migrate-graph 이관(parents/proc_def 변환) | 관계형 데이터 자동 이관 |
| migrate-graph 재실행 counts 불변 | 이관 멱등성 |
| import-bscard 한국어 관점 정규화 + parents | BSCard 이관 |
