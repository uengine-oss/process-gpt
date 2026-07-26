# strategy_strategy-map-graph — 전략 레이어(전략맵/BSC) 그래프 관리

## MODIFIED Requirements

### Requirement: 전략맵 엔티티가 온톨로지 표준 그래프 스키마로 저장된다
전략목표, KPI, 이니셔티브는 기업 운영 온톨로지 표준 라벨의 그래프 노드(`Strategy`, `KPI`, `Initiative`)로 저장되어야 하며(SHALL), 이들 간의 연결은 표준 관계명의 명시적 엣지로 표현되어야 한다(SHALL): 전략 간 계층은 `HAS_SUB_STRATEGY`(상위→하위), 전략-KPI는 `HAS_KPI`, 전략-이니셔티브는 `HAS_INITIATIVE`, 프로세스-KPI 영향은 `IMPACTS_KPI`(프로세스→KPI), 이니셔티브-프로세스는 `EXECUTED_BY`. 이 라벨·관계명은 다른 서비스가 같은 온톨로지 그래프에 하위 레이어를 결합할 때 그대로 질의 가능해야 한다(MUST).

`Strategy` 노드와 `KPI` 노드는 전략적 중요도를 나타내는 `importance` 속성(1~5 정수, 5가 가장 높음)을 가져야 한다(SHALL). 값이 지정되지 않은 노드는 중간값(3)으로 취급되어야 한다(MUST). 이 값은 다른 서비스가 여러 전략·KPI에 걸친 기여도나 통계를 가중 합산할 때 재사용할 수 있어야 한다(MUST).

#### Scenario: 전략 간 계층 관계 저장
- **WHEN** 상위 전략목표를 부모로 지정하여(`parents` 필드) 하위 전략목표를 생성한 뒤 온톨로지 그래프를 조회하면
- **THEN** 상위 `Strategy` 노드에서 하위 `Strategy` 노드로 향하는 `HAS_SUB_STRATEGY` 관계가 존재하고, 전략맵 조회 시 하위 목표의 `parents`에 상위 목표 id가 포함된다

#### Scenario: 전략-KPI-프로세스 연결 경로
- **WHEN** 전략목표에 KPI를 생성하고 그 KPI에 프로세스 정의(`proc_def_id`)를 연결하면
- **THEN** `Strategy -HAS_KPI-> KPI <-IMPACTS_KPI- Process`로 이어지는 관계 경로가 그래프에 존재하고, 전략맵 조회 응답에서 해당 KPI의 `proc_def_id`로 확인할 수 있다

#### Scenario: 이니셔티브-프로세스 연결
- **WHEN** 전략목표에 프로세스 정의가 연결된 이니셔티브를 생성하면
- **THEN** `Strategy -HAS_INITIATIVE-> Initiative -EXECUTED_BY-> Process` 관계 경로가 그래프에 존재한다

#### Scenario: 전략 목표에 중요도 지정
- **WHEN** 전략 목표를 생성하면서 `importance` 값을 지정하면
- **THEN** 해당 `Strategy` 노드에 지정한 `importance` 값이 저장되고, 전략맵 조회 응답에서 확인할 수 있다

#### Scenario: 중요도 미지정 시 기본값 적용
- **WHEN** `importance` 값을 지정하지 않고 전략 목표를 생성한 뒤 조회하면
- **THEN** 해당 전략 목표의 `importance`는 중간값(3)으로 반환된다

### Requirement: 기존 전략맵 API 계약이 그래프 저장소 위에서 유지된다
저장소가 그래프로 전환되어도 기존 공개 API의 경로, HTTP method, 요청/응답 필드는 변경 없이 동일하게 동작해야 한다(MUST): `GET /api/map`, `POST/PUT/DELETE /api/objectives[/{id}]`, `POST/PUT/DELETE /api/kpis[/{id}]`, `POST /api/kpis/{id}/value`, `GET /api/kpis/{id}/measurements`, `POST/PUT/DELETE /api/initiatives[/{id}]`. `GET /api/map`은 전략목표별로 KPI·이니셔티브·달성률(`achievement`)이 중첩된 기존 응답 구조(BSC 4관점 `perspective` 포함)를 유지해야 한다(MUST) — 전략 맵/BSC 시각화 화면이 무변경으로 동작해야 한다.

`POST/PUT /api/objectives[/{id}]`와 `POST/PUT /api/kpis[/{id}]`는 요청 본문에 `importance` 필드를 선택적으로 받아야 하며(SHALL), `GET /api/map`을 비롯한 전략맵 조회 응답의 전략 목표·KPI 항목에는 `importance` 필드가 포함되어야 한다(MUST). `importance`를 생략한 요청은 기존과 동일하게 동작해야 한다(MUST) — 이 필드 추가로 기존 클라이언트가 영향을 받지 않아야 한다.

#### Scenario: 전략맵 CRUD 왕복
- **WHEN** 전략목표를 생성하고, 그 목표에 KPI와 이니셔티브를 생성한 뒤 `GET /api/map?tenant_id=`을 호출하면
- **THEN** 응답의 `objectives` 배열에 생성한 목표가 있고 그 아래 `kpis`, `initiatives` 배열에 생성한 항목이 중첩되어 반환된다

#### Scenario: 수정 결과 반영
- **WHEN** `PUT /api/objectives/{id}`로 전략목표의 이름과 관점(`perspective`)을 수정하면
- **THEN** 응답과 이후 전략맵 조회에 수정된 값이 반영된다

#### Scenario: 존재하지 않는 리소스 수정
- **WHEN** 존재하지 않는 id로 `PUT /api/kpis/{id}`를 호출하면
- **THEN** 404 오류가 반환된다

#### Scenario: 중요도 필드를 포함한 전략맵 조회
- **WHEN** 전략 목표와 KPI에 각각 `importance`를 지정한 뒤 `GET /api/map?tenant_id=`를 호출하면
- **THEN** 응답의 해당 전략 목표·KPI 항목에 지정한 `importance` 값이 포함된다

#### Scenario: 중요도 필드 생략 시 기존 동작 유지
- **WHEN** `importance` 필드 없이 기존 방식대로 `POST /api/objectives`를 호출하면
- **THEN** 요청이 이전과 동일하게 성공하고, 생성된 전략 목표의 `importance`는 중간값(3)으로 반환된다
