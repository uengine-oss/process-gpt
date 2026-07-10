# 제안: strategy 서비스의 기업 운영 온톨로지 그래프 전환 (Apache AGE / Cypher)

## Why

strategy 서비스는 전략목표 간 상하위 관계, 전략목표-KPI, KPI-프로세스 연결처럼 본질적으로 그래프인 데이터를 관계형 테이블과 jsonb 컬럼(`parents`)으로 저장하고 있어, 관계 탐색과 무결성 관리가 취약하고 전략과 실행(프로세스·리소스·스킬) 사이의 연결을 조망할 수 없다. 많은 조직이 겪는 "전략과 실행의 단절"을 해소하려면, 전략(Strategy)-프로세스(Process)-리소스(User/Agent)-지식/스킬(Skill) 4개 레이어를 하나의 기업 운영 온톨로지 그래프로 연결해 북극성(전략·KPI)부터 전술(스킬)까지 하향식/상향식으로 조망하고, KPI 이상 발생 시 원인을 역추적하는 영향도 분석이 가능해야 한다.

온톨로지 데이터는 볼륨보다 정교한 관계가 중요하므로, 별도 그래프 DB 서버 대신 Apache AGE(Postgres 확장)를 Supabase 내 Postgres에 연결해 사용한다. 이렇게 하면 DB 인스턴스가 하나로 유지되어 인프라가 단순해지고, 플랫폼 관계형 데이터(프로세스 인스턴스·워크아이템·사용자·스킬)와의 데이터 사일로가 생기지 않는다.

## What Changes

- **저장 계층 전환**: strategy 서비스의 전략맵 데이터(전략목표, KPI, 이니셔티브)를 관계형 테이블 대신 Cypher 질의 기반 그래프 저장소(노드·엣지)로 저장한다. 기존 관계형 데이터의 그래프 이관 경로를 제공한다.
- **저장소 Strategy 패턴**: Cypher를 지원하는 다른 그래프 DB(Neo4j, Memgraph 등)로 교체 가능한 저장소 추상화 인터페이스를 도입하고, 1차 구현체로 Apache AGE 어댑터를 제공한다. AGE 어댑터는 Supabase 내 Postgres에 접속해 기동 시 확장·그래프·인덱스를 자동 초기화한다.
- **온톨로지 스키마**: 그래프 스키마는 기업 운영 온톨로지 4레이어 표준 라벨·관계명을 따른다 — 전략 레이어(`Strategy`, `KPI`; `HAS_SUB_STRATEGY`, `HAS_KPI`), 프로세스 레이어(`Process`, `Task`; `CONTAINS_TASK`, `IMPACTS_KPI`), 리소스 레이어(`User`/`Agent`/`Team` 조직도; `PERFORMS`, `HAS_SUB_TEAM`, `MEMBER_OF`), 지식/스킬 레이어(`Skill`; `USES_SKILL`, `INHERITS`, `REFERENCES`).
- **온톨로지 인제스천(ETL)**: 플랫폼이 소유한 하위 레이어 원천 데이터(프로세스 정의와 활동·역할자 배정, 사용자/에이전트, 조직도, 스킬, 수행 이력)가 저장·수정될 때마다 변경분을 감지(증분 폴링, 향후 Realtime 전환 가능)해 온톨로지 그래프에 반영하는 인제스천 기능을 신설한다. 변경된 스킬은 본문을 LLM으로 분석해 스킬 간 상속(`INHERITS`)·참조(`REFERENCES`) 관계를 추출한다.
- **온톨로지 조망 API**: 전략층부터 스킬층까지 전체 온톨로지를 한눈에 조망·탐색(레이어 필터, 노드 이웃 확장)할 수 있는 브라우징 API를 신설한다. 전략맵/BSC 시각화는 기존 `GET /api/map` 계약을 유지한 채 그래프 위에서 동작한다.
- **다각적 KPI 측정 확장**: 기존 정량 측정(완료 건수, 평균 처리시간)과 정성 측정(설문 점수)에 더해, 프로세스 폼 입력값 합산(예: 계약 금액 총합) 정량 측정을 추가하고, 측정 결과가 그래프의 KPI 노드와 `IMPACTS_KPI` 관계에 유기적으로 반영되게 한다.
- **영향도 분석(역추적)**: KPI 이상 시 `KPI ← Process ← Task ← 수행 리소스(User/Agent) → Skill` 경로를 역추적해 원인 후보(병목 프로세스, 성능 저하 리소스, 관련 스킬)를 랭킹으로 제시하고, 전략 목표 달성을 위한 스킬 개선점 도출을 지원하는 분석 API를 신설한다.
- **기존 API 계약 유지**: `/api/map`, `/api/objectives`, `/api/kpis`, `/api/initiatives`, `/api/surveys` 등 기존 공개 API의 요청/응답 계약은 유지한다.
- KPI 측정 이력·설문 요청 같은 시계열/트랜잭션 데이터는 동일 Postgres의 관계형 테이블로 유지한다.

## Capabilities

### New Capabilities

- `strategy_graph-store`: Cypher 질의 기반 그래프 저장소 추상화 계층. 저장소 전략(Strategy 패턴) 선택, Apache AGE 어댑터의 접속/초기화/질의 실행, 설정에 의한 구현체 전환, 테넌트 격리를 다룬다.
- `strategy_strategy-map-graph`: 전략 레이어(전략맵/BSC) 그래프 관리. 전략목표·KPI·이니셔티브 노드와 온톨로지 표준 관계의 생성/수정/삭제/조회, 기존 전략맵 API 계약 유지, 관계형·레거시 BSCard 데이터의 그래프 이관을 다룬다.
- `strategy_ontology-sync`: 플랫폼 원천 데이터(프로세스 정의/활동/역할자, 사용자/에이전트, 조직도, 스킬, 수행 이력)의 변경분을 감지해 온톨로지 그래프의 프로세스·리소스·지식 레이어 노드와 관계로 인제스천하는 ETL 기능. 변경 스킬의 LLM 관계 추출 포함.
- `strategy_ontology-view`: 전략-프로세스-리소스-스킬 전체 온톨로지를 조망·탐색하는 브라우징 API (레이어별 서브그래프 조회, 노드 이웃 확장).
- `strategy_kpi-measurement`: 정량(완료 건수, 평균 처리시간, 폼 입력값 합산)·정성(설문 점수) KPI 측정과 측정 결과의 그래프 반영, 측정 이력 관리.
- `strategy_impact-analysis`: KPI 이상 원인 역추적(레이어 간 영향도 분석)과 전략 목표 달성을 위한 스킬 개선점 도출.

### Modified Capabilities

(없음 — strategy 서비스의 기존 main spec이 존재하지 않는다.)

## Impact

- **서비스**: `services/strategy` 백엔드의 저장 계층 전면 교체 + 온톨로지 동기화/조망/영향도 분석 기능 신설 (기존 공개 API 계약은 유지, 신규 API 추가).
- **DB**: Supabase 내 Postgres에 Apache AGE 확장 설치 필요. 전략맵 엔티티 테이블은 그래프로 대체되고, 측정 이력·설문·동기화 상태 테이블은 유지. 플랫폼 테이블(`proc_def`, `todolist`, `bpm_proc_inst`, `users`, `skills`, `agent_skills`, `configuration`(조직도))은 읽기 전용 원천으로 사용.
- **인프라**: 로컬/E2E/배포 환경의 Postgres 이미지가 AGE 확장을 포함해야 함 (self-hosted 기준, 관리형 Supabase 클라우드는 미지원).
- **프론트엔드**: 기존 전략맵 화면 무변경. 온톨로지 브라우징 뷰는 신규 API를 사용하는 후속 화면 작업 필요 (이번 변경은 백엔드 계약까지).
- **의존성**: AGE는 기존 SQLAlchemy/psycopg 접속 재사용. 스킬 개선점 서술 생성은 기존 LLM 설정(`OPENAI_API_KEY` 등)을 선택적으로 활용.
