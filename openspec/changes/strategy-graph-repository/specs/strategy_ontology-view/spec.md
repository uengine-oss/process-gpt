# strategy_ontology-view — 기업 운영 온톨로지 조망·탐색

## ADDED Requirements

### Requirement: 전체 온톨로지를 한눈에 조망할 수 있다
`GET /api/ontology/graph?tenant_id=`는 테넌트의 온톨로지 서브그래프를 노드 목록과 관계 목록(JSON)으로 반환해야 한다(SHALL). 각 노드에는 id, 라벨(레이어 구분), 이름과 표시에 필요한 속성이, 각 관계에는 관계명과 출발/도착 노드 id가 포함되어야 한다(MUST) — 시각화 클라이언트가 추가 질의 없이 전략층부터 스킬층까지 전체를 렌더링할 수 있어야 한다. 응답에는 마지막 인제스천 시각이 포함되어야 한다(SHALL).

#### Scenario: 4레이어 전체 조회
- **WHEN** 전략·KPI·프로세스·리소스·스킬 데이터가 존재하는 테넌트에서 `GET /api/ontology/graph?tenant_id=`를 호출하면
- **THEN** 응답에 `Strategy`, `KPI`, `Process`, `Task`, `User`/`Agent`, `Team`, `Skill` 노드와 이들을 잇는 관계가 모두 포함된다

#### Scenario: 빈 테넌트 조회
- **WHEN** 데이터가 없는 테넌트로 조회하면
- **THEN** 빈 노드/관계 목록이 오류 없이 반환된다

### Requirement: 레이어를 선택해 조망할 수 있다
`GET /api/ontology/graph`는 `layers` 파라미터(`strategy`, `process`, `resource`, `skill`, 콤마 구분)로 반환 레이어를 필터링할 수 있어야 한다(SHALL). 선택된 레이어의 노드와, 양 끝이 모두 선택 범위에 포함되는 관계만 반환해야 한다(MUST). `layers` 미지정 시 전체 레이어를 반환한다(SHALL).

#### Scenario: 전략 레이어만 조회
- **WHEN** `layers=strategy`로 조회하면
- **THEN** `Strategy`, `KPI`, `Initiative` 노드와 그들 사이의 관계만 반환되고 프로세스·리소스·스킬 노드는 포함되지 않는다

#### Scenario: 인접 레이어 조합 조회
- **WHEN** `layers=strategy,process`로 조회하면
- **THEN** 전략·프로세스 레이어 노드와 함께 두 레이어를 잇는 `IMPACTS_KPI` 관계가 포함된다

### Requirement: 노드에서 이웃으로 점진 탐색할 수 있다
`GET /api/ontology/nodes/{id}/neighbors?tenant_id=&depth=`는 지정 노드에서 지정 깊이(기본 1)까지 연결된 이웃 노드와 관계를 반환해야 한다(SHALL) — 온톨로지 브라우저의 노드 확장 탐색용. 존재하지 않는 노드 id에 대해서는 404 오류를 반환해야 한다(MUST).

#### Scenario: KPI 노드의 이웃 확장
- **WHEN** 전략과 프로세스에 연결된 KPI 노드의 id로 이웃을 조회하면
- **THEN** 그 KPI를 보유한 `Strategy` 노드와 그 KPI에 영향을 주는 `Process` 노드가 관계와 함께 반환된다

#### Scenario: 깊이 2 탐색
- **WHEN** `depth=2`로 전략 노드의 이웃을 조회하면
- **THEN** 전략에 직접 연결된 노드와 그 노드들에 연결된 노드(예: KPI에 연결된 프로세스)까지 반환된다

#### Scenario: 존재하지 않는 노드
- **WHEN** 존재하지 않는 노드 id로 이웃을 조회하면
- **THEN** 404 오류가 반환된다
