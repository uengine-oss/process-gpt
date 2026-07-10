# strategy_strategy-map-graph — 전략 레이어(전략맵/BSC) 그래프 관리

## ADDED Requirements

### Requirement: 전략맵 엔티티가 온톨로지 표준 그래프 스키마로 저장된다
전략목표, KPI, 이니셔티브는 기업 운영 온톨로지 표준 라벨의 그래프 노드(`Strategy`, `KPI`, `Initiative`)로 저장되어야 하며(SHALL), 이들 간의 연결은 표준 관계명의 명시적 엣지로 표현되어야 한다(SHALL): 전략 간 계층은 `HAS_SUB_STRATEGY`(상위→하위), 전략-KPI는 `HAS_KPI`, 전략-이니셔티브는 `HAS_INITIATIVE`, 프로세스-KPI 영향은 `IMPACTS_KPI`(프로세스→KPI), 이니셔티브-프로세스는 `EXECUTED_BY`. 이 라벨·관계명은 다른 서비스가 같은 온톨로지 그래프에 하위 레이어를 결합할 때 그대로 질의 가능해야 한다(MUST).

#### Scenario: 전략 간 계층 관계 저장
- **WHEN** 상위 전략목표를 부모로 지정하여(`parents` 필드) 하위 전략목표를 생성한 뒤 온톨로지 그래프를 조회하면
- **THEN** 상위 `Strategy` 노드에서 하위 `Strategy` 노드로 향하는 `HAS_SUB_STRATEGY` 관계가 존재하고, 전략맵 조회 시 하위 목표의 `parents`에 상위 목표 id가 포함된다

#### Scenario: 전략-KPI-프로세스 연결 경로
- **WHEN** 전략목표에 KPI를 생성하고 그 KPI에 프로세스 정의(`proc_def_id`)를 연결하면
- **THEN** `Strategy -HAS_KPI-> KPI <-IMPACTS_KPI- Process`로 이어지는 관계 경로가 그래프에 존재하고, 전략맵 조회 응답에서 해당 KPI의 `proc_def_id`로 확인할 수 있다

#### Scenario: 이니셔티브-프로세스 연결
- **WHEN** 전략목표에 프로세스 정의가 연결된 이니셔티브를 생성하면
- **THEN** `Strategy -HAS_INITIATIVE-> Initiative -EXECUTED_BY-> Process` 관계 경로가 그래프에 존재한다

### Requirement: 기존 전략맵 API 계약이 그래프 저장소 위에서 유지된다
저장소가 그래프로 전환되어도 기존 공개 API의 경로, HTTP method, 요청/응답 필드는 변경 없이 동일하게 동작해야 한다(MUST): `GET /api/map`, `POST/PUT/DELETE /api/objectives[/{id}]`, `POST/PUT/DELETE /api/kpis[/{id}]`, `POST /api/kpis/{id}/value`, `GET /api/kpis/{id}/measurements`, `POST/PUT/DELETE /api/initiatives[/{id}]`. `GET /api/map`은 전략목표별로 KPI·이니셔티브·달성률(`achievement`)이 중첩된 기존 응답 구조(BSC 4관점 `perspective` 포함)를 유지해야 한다(MUST) — 전략 맵/BSC 시각화 화면이 무변경으로 동작해야 한다.

#### Scenario: 전략맵 CRUD 왕복
- **WHEN** 전략목표를 생성하고, 그 목표에 KPI와 이니셔티브를 생성한 뒤 `GET /api/map?tenant_id=`을 호출하면
- **THEN** 응답의 `objectives` 배열에 생성한 목표가 있고 그 아래 `kpis`, `initiatives` 배열에 생성한 항목이 중첩되어 반환된다

#### Scenario: 수정 결과 반영
- **WHEN** `PUT /api/objectives/{id}`로 전략목표의 이름과 관점(`perspective`)을 수정하면
- **THEN** 응답과 이후 전략맵 조회에 수정된 값이 반영된다

#### Scenario: 존재하지 않는 리소스 수정
- **WHEN** 존재하지 않는 id로 `PUT /api/kpis/{id}`를 호출하면
- **THEN** 404 오류가 반환된다

### Requirement: 전략목표 삭제 시 관계가 그래프 수준에서 함께 정리된다
전략목표를 삭제하면 그 목표에 연결된 모든 관계(다른 전략과의 `HAS_SUB_STRATEGY`, KPI·이니셔티브 보유 관계)가 함께 제거되어야 하며(MUST), 그 목표에 속한 KPI와 이니셔티브도 함께 삭제되어야 한다(SHALL). 삭제 후 다른 전략목표를 조회했을 때 삭제된 목표를 가리키는 잔존 참조가 남아 있어서는 안 된다(MUST NOT).

#### Scenario: 부모 목표 삭제 시 자식의 참조 정리
- **WHEN** 하위 목표가 계층 관계로 연결된 상위 전략목표를 삭제한 뒤 전략맵을 조회하면
- **THEN** 하위 목표의 `parents`에 삭제된 목표 id가 더 이상 포함되지 않는다

#### Scenario: 목표 삭제 시 KPI·이니셔티브 연쇄 삭제
- **WHEN** KPI와 이니셔티브가 속한 전략목표를 삭제하면
- **THEN** 전략맵 조회에서 해당 KPI와 이니셔티브가 더 이상 반환되지 않는다

### Requirement: 기존 관계형 전략맵 데이터를 그래프로 이관할 수 있다
기존 관계형 테이블(`strategy_objectives`, `strategy_kpis`, `strategy_initiatives`)에 저장된 전략맵 데이터를 그래프로 이관하는 수단을 제공해야 한다(SHALL). 서비스 기동 시 그래프의 전략 레이어가 비어 있고 관계형 데이터가 존재하면 자동으로 이관하며(SHALL), `POST /api/migrate-graph`로 명시적으로도 실행할 수 있어야 한다(SHALL). 이관 시 `parents` 배열은 `HAS_SUB_STRATEGY` 관계로, `proc_def_id`는 `IMPACTS_KPI`/`EXECUTED_BY` 관계로 변환되어야 한다(MUST). 이관은 멱등이어야 하며(MUST) 반복 실행해도 노드나 관계가 중복 생성되지 않아야 한다(MUST NOT). 이관 결과에는 생성된 노드·관계 수가 포함되어야 한다(SHALL).

#### Scenario: 관계형 데이터 자동 이관
- **WHEN** 기존 관계형 테이블에 전략목표(parents 포함)·KPI·이니셔티브가 있는 상태에서 그래프가 빈 채로 서비스를 기동한 뒤 전략맵을 조회하면
- **THEN** 기존 데이터가 목표 간 관계를 포함해 동일한 구조로 반환된다

#### Scenario: 이관 멱등성
- **WHEN** 이관이 완료된 상태에서 `POST /api/migrate-graph`를 다시 호출하면
- **THEN** 노드와 관계 수가 변하지 않고 중복 없이 완료 결과가 반환된다

### Requirement: 레거시 BSCard 전략맵을 그래프로 이관할 수 있다
`POST /api/import-bscard`는 레거시 BSCard 데이터(configuration key='strategy')의 전략과 관점, 전략 간 부모 관계를 `Strategy` 노드와 `HAS_SUB_STRATEGY` 관계로 이관해야 한다(SHALL). 관점 표기는 한국어/영문 표기를 모두 표준 관점 값(`financial`, `customer`, `internal_process`, `learning_growth`)으로 정규화해야 한다(MUST).

#### Scenario: BSCard 이관
- **WHEN** 레거시 BSCard 데이터가 존재하는 테넌트에서 `POST /api/import-bscard?tenant_id=`를 호출한 뒤 전략맵을 조회하면
- **THEN** 레거시 전략들이 관점별 전략목표로, 부모 관계가 계층 관계로 반환되고 응답에 `imported` 건수가 포함된다
