# strategy_graph-store — Cypher 그래프 저장소 추상화와 Apache AGE 어댑터

## ADDED Requirements

### Requirement: 설정으로 그래프 저장소 구현체를 선택할 수 있다
strategy 서비스는 온톨로지 그래프 데이터의 저장소 구현체를 환경 변수 `GRAPH_STORE`로 선택할 수 있어야 한다(SHALL). 기본값은 `age`(Apache AGE)이며, 지원하지 않는 값이 설정되면 서비스는 기동 시 명확한 오류 메시지와 함께 기동을 중단해야 한다(MUST). 저장소 구현체 교체는 API 계약(요청/응답 형식)에 어떤 변화도 일으키지 않아야 한다(MUST).

#### Scenario: 기본 저장소로 기동
- **WHEN** `GRAPH_STORE`를 설정하지 않고 서비스를 기동하면
- **THEN** Apache AGE 어댑터가 선택되어 서비스가 정상 기동하고 `/health`가 `{"status": "ok"}`를 반환한다

#### Scenario: 지원하지 않는 저장소 지정
- **WHEN** `GRAPH_STORE=unknown-db`로 서비스를 기동하면
- **THEN** 서비스는 지원 가능한 구현체 목록을 포함한 오류를 남기고 기동에 실패한다

### Requirement: Apache AGE 어댑터는 기동 시 그래프 환경을 자동 준비한다
Apache AGE 어댑터는 설정된 Postgres 접속 정보(`DB_HOST/PORT/NAME/USER/PASSWORD`)로 Supabase 내 Postgres에 접속하고, 기동 시 AGE 확장 로드, 온톨로지 그래프 생성(그래프 이름은 `GRAPH_NAME`으로 변경 가능), 노드 라벨과 tenant 조회용 인덱스 준비를 자동으로 수행해야 한다(SHALL). 이 초기화는 멱등이어야 하며(MUST), 이미 준비된 환경에서 재기동해도 오류나 중복 생성이 발생하지 않아야 한다(MUST).

#### Scenario: 최초 기동 시 그래프 초기화
- **WHEN** AGE 확장만 설치된 빈 Postgres를 대상으로 서비스를 처음 기동하면
- **THEN** 전략맵 그래프가 생성되고, 이후 전략목표 생성 API 호출이 정상 동작한다

#### Scenario: 재기동 멱등성
- **WHEN** 그래프와 데이터가 이미 존재하는 상태에서 서비스를 재기동하면
- **THEN** 기존 노드와 관계가 보존되고 서비스가 정상 기동한다

#### Scenario: AGE 확장이 없는 Postgres
- **WHEN** AGE 확장을 설치할 수 없는 Postgres에 접속해 기동하면
- **THEN** 서비스는 AGE 확장 필요성을 알리는 오류를 로그에 남기고 기동에 실패한다

### Requirement: 그래프 저장소는 테넌트 단위로 데이터를 격리한다
그래프 저장소의 모든 조회와 변경은 요청의 `tenant_id`로 격리되어야 한다(MUST). 한 테넌트의 질의 결과에 다른 테넌트의 노드나 관계가 포함되어서는 안 된다(MUST NOT).

#### Scenario: 테넌트 간 조회 격리
- **WHEN** 테넌트 A와 테넌트 B가 각각 전략목표를 생성한 뒤 테넌트 A로 `GET /api/map?tenant_id=A`를 호출하면
- **THEN** 응답에는 테넌트 A의 전략목표만 포함된다

#### Scenario: 테넌트 간 변경 격리
- **WHEN** 테넌트 B의 `tenant_id`로 테넌트 A 소유 전략목표의 수정/삭제를 요청하면
- **THEN** 대상이 없다는 오류(404)가 반환되고 테넌트 A의 데이터는 변경되지 않는다

### Requirement: 저장소 구현체는 공통 행위 계약을 만족한다
모든 그래프 저장소 구현체는 동일한 행위 계약(노드 생성·수정·삭제·조회, 관계 연결·해제, 전략맵 조회, 서브그래프 조회, 이웃 탐색, 다단 경로 탐색, 동기화용 멱등 병합)을 만족해야 하며(SHALL), 이 계약은 구현체와 무관하게 동일한 테스트 스위트로 검증 가능해야 한다(SHALL). 향후 Cypher를 지원하는 다른 그래프 DB 어댑터를 추가할 때 API 계층 코드 변경 없이 저장소 구현체 추가와 설정 변경만으로 교체 가능해야 한다(MUST).

#### Scenario: 계약 테스트 통과
- **WHEN** Apache AGE 어댑터를 대상으로 저장소 공통 계약 테스트 스위트를 실행하면
- **THEN** 노드/관계 CRUD, 전략맵 조회, 서브그래프 조회, 이웃 탐색, 경로 탐색, 멱등 병합 계약 케이스가 모두 통과한다
