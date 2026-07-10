# strategy_ontology-view E2E 시나리오

## 목적

기업 운영 온톨로지의 조망·탐색 API 를 검증한다: `GET /api/ontology/graph` 전체 4레이어
조회와 빈 테넌트, `layers` 필터(strategy / strategy,process — 양끝 포함 관계만),
`GET /api/ontology/nodes/{id}/neighbors` 이웃 확장(depth1/2)과 404.

## 사전조건 / 인프라

- **인프라(Docker)**: process-gpt-age-postgres (127.0.0.1:55433, postgres/postgres/postgres).
- **애플리케이션(소스 실행)**: 상시 uvicorn 서버(포트 8114, 그래프 `corp_ontology_e2e`,
  `MEASURE_AUTO_START=false`).
- 4레이어 온톨로지는 전략 API(전략/KPI/이니셔티브 + Process 미러) + 원천 seed +
  `POST /api/ontology/sync`(프로세스/태스크/리소스/스킬)로 구성한다. `proc_def_id` 공유로
  두 경로가 같은 Process 노드에서 만난다. 러너가 원천 테이블을 CREATE + INSERT(`seed.sql`).
- 고유 테넌트 `e2e-view-<ts>` 사용, 종료 시 정리.

## 실행 명령 · 포트 · 환경 변수

서버 기동은 8114(위 스위트와 동일 환경). 러너:

```bash
services/strategy/.venv/bin/python \
  openspec/specs/strategy_ontology-view/e2e/run_e2e.py
```

## 시나리오 단계 ↔ spec Scenario 매핑

| 러너 단계 | spec Scenario |
| --- | --- |
| 전체 조회: 8라벨 + 레이어 간 관계 + last_synced_at | 4레이어 전체 조회 |
| 빈 테넌트: 노드/관계 빈 목록 | 빈 테넌트 조회 |
| layers=strategy: 전략층 라벨만, IMPACTS_KPI 제외 | 전략 레이어만 조회 |
| layers=strategy,process: 교차 IMPACTS_KPI 포함, 리소스/스킬 제외 | 인접 레이어 조합 조회 |
| neighbors(KPI, depth1): Strategy + Process 반환 | KPI 노드의 이웃 확장 |
| neighbors(Strategy, depth2): KPI→Process 도달 | 깊이 2 탐색 |
| neighbors 존재하지 않는 노드 404 | 존재하지 않는 노드 |
