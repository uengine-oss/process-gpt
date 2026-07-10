# 설계: strategy 서비스의 기업 운영 온톨로지 그래프 전환

## Context

strategy 서비스(`services/strategy`)는 FastAPI 기반 마이크로서비스로, BSC 전략맵(전략목표·KPI·이니셔티브)을 Supabase 내 Postgres의 관계형 테이블에 직접 SQL로 저장한다. 전략목표 간 상하위 관계는 `parents` jsonb 배열로, 전략목표-KPI/이니셔티브 관계는 FK로, KPI/이니셔티브-프로세스 정의 관계는 `proc_def_id` 문자열 컬럼으로 표현된다. 이 구조는 관계 탐색을 애플리케이션 코드에서 조립해야 하고, 목표 삭제 시 다른 목표의 `parents` 배열을 수동으로 정리하는 등 그래프 무결성 관리가 취약하며, 전략과 실행 레이어(프로세스·리소스·스킬)를 가로지르는 질의가 불가능하다.

**전사 온톨로지 비전**: 이번 변경은 strategy 서비스를 "전략 관리"에서 "기업 운영 온톨로지 기반 전체 조망·분석" 서비스로 격상한다. 온톨로지는 4개 레이어로 구성된다 — ① 전략 레이어(Strategy, KPI: BSC 전략맵, 전략 간 인과관계, 정량·정성 KPI), ② 프로세스 레이어(Process, Task: 전략을 실행 단위로 분해, 프로세스 실행 결과가 KPI에 영향), ③ 리소스 레이어(User/Agent: 사람과 AI 에이전트를 동등한 수행 주체로 정의), ④ 지식/스킬 레이어(Skill: 상속/포크·참조 구조의 객체지향적 스킬 자산). 모든 레이어가 하나의 그래프로 연결되면 "분기 매출 급감 → 병목 프로세스 → 성능 저하 리소스/오류 스킬"처럼 결과에서 원인으로 거슬러 올라가는 레이어 간 영향도 분석(Impact Analysis)이 가능해진다.

온톨로지 데이터는 볼륨보다 관계의 정교함이 중요하므로, 별도 그래프 DB 서버를 추가하지 않고 Apache AGE(Postgres 확장)를 Supabase 내 Postgres에 설치해 기존 접속 정보를 그대로 재사용한다. DB 인스턴스가 하나로 유지되어 인프라가 단순해지고, 플랫폼 관계형 데이터와의 사일로가 생기지 않는다.

제약:
- 기존 공개 API 계약(`/api/map`, `/api/objectives`, `/api/kpis`, `/api/initiatives`, `/api/surveys` 등)은 유지해야 한다 — 기존 프론트엔드 무변경.
- 하위 레이어의 원천 데이터는 플랫폼 소유 관계형 테이블이다: 프로세스 정의/활동/역할자 배정은 `proc_def`(BPMN 정의에 활동별 사용자/에이전트 역할자 정보 포함), 수행 이력은 `todolist`/`bpm_proc_inst`, 사용자/에이전트는 `users`(is_agent 구분), 스킬은 `skills`/`agent_skills`, 조직도는 `configuration`(key='organization')의 chart 값. 이 테이블들의 소유권은 이관하지 않고 읽기 전용 원천으로 삼아 strategy 서비스가 온톨로지로 ETL 한다.
- 원천 데이터(스킬, 프로세스 정의 등)가 저장·수정될 때마다 변경분이 온톨로지에 인제스천되어야 한다. 스킬 간 상속/참조 관계는 원천에 구조화되어 있지 않아 스킬 본문을 LLM으로 분석해야 추출할 수 있다.
- KPI 자동 측정·설문 발행 로직은 플랫폼 관계형 테이블을 계속 조회/기록하므로 관계형 접속은 유지된다.
- 향후 Neo4j, Memgraph 등 Cypher 호환 그래프 DB로 교체 가능해야 한다 (Strategy 패턴).

## Goals / Non-Goals

**Goals:**
- 전략 레이어 엔티티(전략목표, KPI, 이니셔티브)와 관계를 온톨로지 표준 라벨·관계명의 그래프 노드·엣지로 저장한다 (그래프가 원본).
- Cypher 질의를 실행하는 저장소 인터페이스를 정의하고, 구현체를 설정으로 선택하는 Strategy 패턴을 적용한다. 1차 구현체는 Apache AGE 어댑터.
- 플랫폼 원천 데이터를 프로세스·리소스(조직도 포함)·지식 레이어의 미러 노드·관계로 ETL 하고, 원천 변경분을 증분 감지해 온톨로지에 인제스천한다.
- 변경된 스킬의 본문을 LLM으로 분석해 스킬 간 상속(`INHERITS`)·참조(`REFERENCES`) 관계를 추출한다.
- 전략층부터 스킬층까지 전체 온톨로지를 조망·탐색하는 브라우징 API를 제공한다.
- KPI 측정을 정량(완료 건수, 평균 처리시간, 폼 입력값 합산)·정성(설문)으로 다각화하고 측정 결과를 그래프에 반영한다.
- KPI 이상 원인 역추적과 전략 목표 대비 스킬 개선점 도출을 제공하는 영향도 분석 API를 제공한다.
- 기존 관계형 전략맵 데이터와 레거시 BSCard의 그래프 이관 경로를 제공한다.
- E2E 실행 환경에서 AGE 확장이 포함된 Postgres를 Docker 인프라로 제공한다.

**Non-Goals:**
- KPI 측정 이력, 설문 요청/응답, 동기화 커서 등 시계열·트랜잭션 데이터의 그래프 전환 — 관계형 테이블로 유지한다.
- 플랫폼 테이블(`proc_def`, `users`, `skills` 등)의 소유권·쓰기 경로 변경 — 그래프에는 읽기 전용 미러만 둔다.
- 온톨로지 브라우징 프론트엔드 화면 구현 — 이번 변경은 백엔드 API 계약까지이며, 화면은 후속 변경에서 신규 API를 소비한다.
- Neo4j/Memgraph 어댑터의 실제 구현 — 인터페이스만 교체 가능하게 준비한다.
- 스킬 자체의 생성/편집 기능 — 스킬 원천은 플랫폼 데이터이며, 이번 변경은 변경분 인제스천(LLM 관계 추출 포함)과 조망·분석까지만 다룬다.

## Decisions

### D1. 그래프 저장소 위치: Apache AGE (Postgres 확장) — 별도 그래프 DB 서버 대신

- **선택**: Supabase 내 Postgres에 AGE 확장을 설치하고, 기존 DB 접속(SQLAlchemy/psycopg)을 통해 `cypher('<graph>', $$ ... $$)` 함수로 Cypher를 실행한다.
- **근거**: 온톨로지는 빅데이터 볼륨이 아니라 정교한 관계가 중요한 적정 규모(right-sized) 문제다. DB 인스턴스가 하나로 유지되어 운영이 단순하고(사용자 요구), 측정·설문·동기화의 관계형 질의와 그래프 질의가 같은 커넥션 풀을 공유하며, 플랫폼 데이터와의 사일로가 생기지 않는다.
- **대안**: Neo4j 별도 기동 — 관계 질의는 강력하나 인프라가 늘고 플랫폼 관계형 데이터와의 하이브리드 질의(측정 집계 등)가 불가능해져 기각.

### D2. 저장소 추상화: 도메인 연산 수준의 Strategy 패턴

- **선택**: 저장소 인터페이스는 도메인 연산 단위(노드 생성/수정/삭제, 관계 연결/해제, 전략맵 조회, 서브그래프 조회, 경로 탐색, 동기화용 MERGE 등)로 정의하고, 각 구현체가 자기 방언으로 Cypher를 생성·실행한다. 구현체 선택은 환경 변수(`GRAPH_STORE=age`, 기본값 `age`)로 결정한다.
- **근거**: AGE의 Cypher는 openCypher 부분집합이며 호출 방식(SQL 함수 래핑, agtype 결과 파싱)이 Neo4j(Bolt 프로토콜)와 다르다. "Cypher 문자열만 갈아끼우는" 추상화는 방언·드라이버 차이로 누수가 생기므로, 인터페이스는 도메인 연산 수준으로 두고 Cypher 생성과 결과 파싱을 구현체 내부에 캡슐화한다.
- **대안**: 순수 Cypher 실행기(`run(cypher, params)`)만 추상화 — 파라미터 바인딩과 결과 타입이 DB마다 달라 호출부가 방언에 오염되므로 기각.

### D3. 온톨로지 그래프 스키마 (4레이어)

그래프 이름: `corp_ontology` (환경 변수 `GRAPH_NAME`으로 변경 가능). 모든 노드에 `tenant_id` 속성을 두어 멀티테넌시를 유지한다. 라벨·관계명은 기업 운영 온톨로지 표준을 따라 향후 다른 서비스가 같은 그래프에 레이어를 추가할 수 있게 한다.

**노드 (레이어 — label — 원본 소유):**

| 레이어 | Label | 원본 | 주요 속성 |
|---|---|---|---|
| 전략 | `Strategy` | 그래프(이 서비스 소유) | id, tenant_id, name, description, perspective(BSC 4관점), sort_order, created_at, updated_at |
| 전략 | `KPI` | 그래프(이 서비스 소유) | id, tenant_id, name, unit, measure_type, form_field, direction, baseline_value, target_value, current_value, period_start/end, survey_questions, last_measured_at |
| 전략 | `Initiative` | 그래프(이 서비스 소유) | id, tenant_id, name, owner_email, status, progress, start_date, due_date |
| 프로세스 | `Process` | `proc_def` 미러 | id, tenant_id, name |
| 프로세스 | `Task` | `proc_def` BPMN 활동 미러 | id(proc_def_id:activity_id), tenant_id, name, activity_id |
| 리소스 | `User` | `users`(is_agent=false) 미러 | id, tenant_id, name, email |
| 리소스 | `Agent` | `users`(is_agent=true) 미러 | id, tenant_id, name |
| 리소스(조직) | `Team` | `configuration`(key='organization') chart 미러 | id, tenant_id, name |
| 지식/스킬 | `Skill` | `skills`/`agent_skills` 미러 | id, tenant_id, name, description |

**엣지:**

| 관계 | 방향 | 의미 | 생성 주체 |
|---|---|---|---|
| `HAS_SUB_STRATEGY` | (Strategy)→(Strategy) | 상위 전략이 하위 전략을 가짐 (기존 `parents` jsonb 대체) | 전략맵 API |
| `HAS_KPI` | (Strategy)→(KPI) | 전략의 성과지표 | 전략맵 API |
| `HAS_INITIATIVE` | (Strategy)→(Initiative) | 전략의 실행과제 | 전략맵 API |
| `IMPACTS_KPI` | (Process)→(KPI) | 프로세스 실행 결과가 KPI에 영향 (기존 KPI.proc_def_id 대체) | 전략맵 API(KPI-프로세스 매핑 시) |
| `EXECUTED_BY` | (Initiative)→(Process) | 이니셔티브가 해당 프로세스로 실행됨 | 전략맵 API |
| `CONTAINS_TASK` | (Process)→(Task) | 프로세스가 태스크(활동)로 구성됨 | 인제스천(proc_def BPMN 파싱) |
| `PERFORMS` | (User\|Agent)→(Task) | 리소스가 태스크를 수행함 — 정의상 역할 배정에서 생성, 실행 이력 집계(count, avg_duration_hours 속성)로 보강 | 인제스천(proc_def 역할자 + todolist 집계) |
| `USES_SKILL` | (Agent\|Task)→(Skill) | 에이전트/태스크가 스킬을 사용함 | 인제스천(agent_skills 등) |
| `INHERITS` | (Skill)→(Skill) | 스킬 상속/포크 | 인제스천(변경 스킬 본문 LLM 분석) |
| `REFERENCES` | (Skill)→(Skill) | 스킬 참조/호출 | 인제스천(변경 스킬 본문 LLM 분석) |
| `HAS_SUB_TEAM` | (Team)→(Team) | 조직 계층 구조 | 인제스천(조직도 chart) |
| `MEMBER_OF` | (User\|Agent)→(Team) | 리소스의 조직 소속 | 인제스천(조직도 chart) |

- **근거**: 사용자 제시 온톨로지 스키마(HAS_SUB_STRATEGY/HAS_KPI/IMPACTS_KPI/CONTAINS_TASK/PERFORMS/USES_SKILL/INHERITS/REFERENCES)를 그대로 채택해, 전략간 관계와 전략-KPI-프로세스 경로가 명시적 엣지로 드러나고 레이어 간 역추적 경로(`KPI ←IMPACTS_KPI– Process –CONTAINS_TASK→ Task ←PERFORMS– User/Agent –USES_SKILL→ Skill`)가 그래프 질의 하나로 표현된다.
- **API 호환**: 기존 API의 `parents` 필드는 해당 목표로 들어오는 `HAS_SUB_STRATEGY` 엣지의 출발 노드 id 목록으로, `proc_def_id` 필드는 `IMPACTS_KPI`/`EXECUTED_BY` 엣지로 상호 변환한다. API 표면의 "objective"는 그래프의 `Strategy` 노드에 대응한다(계약 유지 우선).
- **미러 노드**: 하위 레이어 원본은 플랫폼 관계형 테이블이므로 그래프에는 id/name 중심의 참조 노드만 MERGE 하고, 그래프 쪽 미러는 읽기 전용으로 취급한다.

### D4. 온톨로지 인제스천 (변경분 기반 ETL — 프로세스·리소스·조직·지식 레이어)

- **변경 감지 방식**: 증분 폴링을 기본으로 한다. 기존 설문 감시 루프와 같은 패턴의 인제스천 루프(`ONTOLOGY_SYNC_INTERVAL_SECONDS`, 기본 60초)가 원천 테이블별 커서(`strategy_sync_state`의 updated_at 커서 — 기존 증분 커서 패턴 재사용)로 저장·수정된 행만 읽어 온톨로지에 반영한다. 즉시 실행 API(`POST /api/ontology/sync`, `full=true` 시 전체 재구축)를 제공한다.
  - **대안 (향후 확장)**: Supabase Realtime 구독 또는 DB 트리거로 변경 이벤트를 push 수신 — 지연은 줄지만 구독 연결 관리·유실 복구 복잡도가 커서 1차에서는 채택하지 않는다. 인제스천 로직을 "변경된 행 목록 → 그래프 반영" 함수로 분리해 두어, 이후 Realtime 이벤트가 같은 함수를 호출하는 형태로 전환 가능하게 한다.
- **원천별 ETL 규칙**:
  - `proc_def`(변경분) → `Process` 노드 MERGE, BPMN 정의 파싱으로 활동 → `Task` 노드 + `CONTAINS_TASK`. 정의에 이미 들어 있는 활동별 역할자(사용자/에이전트) 정보 → `PERFORMS`(정의 기반) 엣지 생성.
  - `users`(변경분) → `User`(is_agent=false)/`Agent`(is_agent=true) 노드 MERGE.
  - `configuration`(key='organization') chart(변경분) → `Team` 노드 + `HAS_SUB_TEAM`(조직 계층) + `MEMBER_OF`(구성원 소속) MERGE — 조직도 레이어.
  - `skills`/`agent_skills`(변경분) → `Skill` 노드 MERGE + `USES_SKILL`(Agent→Skill). **변경된 스킬의 본문을 LLM으로 분석**해 다른 스킬에 대한 상속/포크(`INHERITS`)·참조/호출(`REFERENCES`) 관계를 추출하고 엣지로 반영한다. LLM 미설정 시 노드 동기화만 수행하고 관계 추출은 건너뛴다(추출 보류 상태 기록). 변경분만 분석하므로 LLM 호출 비용이 스킬 변경 빈도에 비례한다.
  - `todolist` 완료 워크아이템(증분) 집계 → `PERFORMS` 엣지의 실행 지표(건수·평균 처리시간) 속성 갱신.
  - 원천에서 삭제된 항목의 미러 노드는 관계와 함께 제거한다.
- **근거**: 조망·역추적 질의가 그래프 하나로 닫히려면 하위 레이어가 그래프에 존재해야 한다. 원천 소유권을 옮기지 않고 증분 ETL로 결합도를 낮추면서, 원천이 저장·수정될 때마다(폴링 주기 내에) 온톨로지에 반영되게 한다. 스킬 상속/참조는 원천에 구조화되어 있지 않으므로 LLM 분석이 유일한 추출 수단이며, 변경분 한정 분석으로 재현성·비용을 통제한다.
- **대안**: 조회 시점 관계형 실시간 조인 — 그래프 질의와 SQL 조인이 뒤섞여 저장소 추상화가 무너지고 Neo4j 교체 시 동작 불가라 기각. 매 주기 전체 재구축 — 스킬 LLM 분석을 매번 반복하게 되어 기각(전체 재구축은 명시적 `full=true`로만).

### D5. KPI 다각 측정과 그래프 반영

- 측정 유형(`measure_type`): 기존 `instance_count`(완료 건수), `avg_duration_hours`(평균 처리시간), `survey_score`(설문 정성 평가), `manual`에 **`form_value_sum`(폼 입력값 합산, 예: 계약 금액 총합)** 을 추가한다. `form_value_sum`은 KPI에 `form_field`(합산할 폼 필드명)를 지정하고, 연결된 프로세스의 완료 인스턴스 폼 데이터에서 해당 숫자 필드를 합산한다.
- 측정 결과는 관계형 측정 이력 테이블(`strategy_kpi_measurements`)에 기록하고, 그래프 KPI 노드의 `current_value`/`last_measured_at` 속성에 반영한다. 프로세스 실행 상태(완료율·실행 속도)는 `IMPACTS_KPI`/`PERFORMS` 엣지 속성으로 집계되어 KPI 노드와 유기적으로 연결된다.
- 설문 발행·응답 흐름(완료 인스턴스 감지 → 설문 워크아이템 발행 → 응답 평균)은 기존 동작을 유지하되 KPI 참조를 그래프에서 조회한다.

### D6. 영향도 분석 (역추적)

- **선택**: 그래프 경로 탐색과 실행 데이터 집계를 결합한 규칙 기반 분석을 기본으로 하고, LLM(기존 `OPENAI_API_KEY` 설정)이 있으면 원인 후보에 대한 서술형 진단·스킬 개선 방향을 생성한다(미설정 시 규칙 기반 요약만).
  - `GET /api/impact/kpi/{id}`: KPI에서 출발해 `IMPACTS_KPI` 역방향 → Process → `CONTAINS_TASK` → Task → `PERFORMS` 역방향 → User/Agent → `USES_SKILL` → Skill 경로를 수집하고, 각 요소에 실행 지표(태스크별 평균 처리시간·건수, 리소스별 수행 성과, KPI 달성률 추이)를 붙여 원인 후보를 기여도 순으로 랭킹한다.
  - `GET /api/impact/strategy/{id}`: 전략에서 하위 전략·KPI·프로세스·스킬까지의 하향 경로를 수집해, 목표 미달 KPI와 연결된 병목 태스크·리소스·스킬을 도출하고 개선 대상 스킬을 제시한다.
- **근거**: 온톨로지의 핵심 가치(결과→원인 역추적, 스킬 개선점 도출)를 결정적(deterministic) 그래프 질의로 재현 가능하게 제공하고, LLM은 해석 계층으로만 사용해 신뢰성을 유지한다.
- **대안**: LLM에게 그래프 전체를 주고 자유 분석 — 재현성·비용 문제로 기각.

### D7. 온톨로지 조망 API

- `GET /api/ontology/graph?tenant_id=&layers=`: 노드·엣지 목록(JSON)으로 서브그래프를 반환한다. `layers`(strategy|process|resource|skill, 콤마 구분, 기본 전체)로 레이어를 필터링한다. 시각화 프론트엔드가 그대로 렌더링할 수 있는 형태(id, label, 속성, source/target)로 반환한다.
- `GET /api/ontology/nodes/{id}/neighbors?tenant_id=&depth=`: 특정 노드에서 지정 깊이(기본 1)까지 이웃을 확장 조회한다 — 브라우저의 점진 탐색용.
- 전략맵/BSC 시각화는 기존 `GET /api/map` 계약(관점별 목표 중첩 구조)을 그대로 유지한다.

### D8. 관계형으로 유지하는 데이터

`strategy_kpi_measurements`(측정 이력), `strategy_survey_requests`(설문), `strategy_sync_state`(증분 커서)는 append 중심 시계열/트랜잭션 데이터로 그래프 모델링 이득이 없어 관계형 테이블로 유지한다.

### D9. 마이그레이션: 기동 시 1회 자동 이관 + 명시적 API

- 서비스 기동 시 그래프에 전략 레이어가 비어 있고 기존 관계형 테이블에 데이터가 있으면 자동 이관한다(멱등). 명시적 재실행용 API(`POST /api/migrate-graph`)도 제공한다. jsonb `parents`는 `HAS_SUB_STRATEGY` 엣지로, `proc_def_id`는 `IMPACTS_KPI`/`EXECUTED_BY` 엣지로 변환한다.
- 이관 후에도 기존 테이블은 즉시 삭제하지 않고 읽기 중단만 한다(롤백 대비). 테이블 제거는 후속 변경으로 미룬다.
- 레거시 BSCard import(`POST /api/import-bscard`)는 그래프 저장소를 향하도록 재작성한다.

## Risks / Trade-offs

- [Supabase 관리형(클라우드)은 AGE 확장을 지원하지 않음] → 이 프로젝트의 배포 형태는 self-hosted Postgres(docker compose/K3S)이므로 AGE 포함 이미지(예: `apache/age` 또는 AGE 설치 커스텀 이미지)로 교체한다. 관리형 Supabase 시나리오는 지원 대상에서 제외하고 README에 명시한다.
- [AGE의 openCypher 부분집합 제약 (일부 함수·가변 길이 경로 구문 차이)] → 저장소 인터페이스를 도메인 연산 수준으로 두어 복잡 Cypher를 구현체 내부에 가두고, 필요 시 SQL 하이브리드 질의로 우회한다. 영향도 분석의 다단 경로 탐색은 AGE에서 실제 동작을 계약 테스트로 검증한다.
- [agtype 결과 파싱 비용과 오류 가능성] → 어댑터 내부에 단일 파싱 유틸을 두고 저장소 공통 계약 테스트로 검증한다.
- [인제스천 지연으로 그래프가 원천과 일시 불일치] → 조망·분석 용도로는 폴링 주기(기본 60초) 지연이 허용 가능하다. 즉시성이 필요한 흐름은 `POST /api/ontology/sync` 호출로 보완한다. 응답에 마지막 인제스천 시각을 포함해 소비자가 신선도를 판단할 수 있게 한다. 향후 Supabase Realtime/트리거 push 수신으로 전환 가능한 구조를 유지한다.
- [LLM 스킬 관계 추출의 부정확성 (환각·누락)] → 추출된 INHERITS/REFERENCES 엣지는 대상 스킬이 실제 존재하는 경우에만 생성하고, 추출 근거(스킬 본문 내 참조 구절)를 엣지 속성으로 남겨 검증 가능하게 한다. LLM 미설정 시 관계 추출을 건너뛰고 보류 상태를 기록한다.
- [이관 중 데이터 정합성 (jsonb parents → 엣지)] → 이관은 MERGE 기반 멱등으로 작성하고, 이관 결과 요약(노드/엣지 수)을 응답으로 반환해 검증 가능하게 한다.
- [측정/설문 테이블의 kpi_id FK가 그래프 노드를 참조 불가] → FK 제약 없는 논리 참조로 완화하고, KPI 삭제 시 어댑터가 측정 이력·설문을 함께 정리한다.
- [영향도 분석의 원인 랭킹이 상관관계일 뿐 인과 증명이 아님] → 응답에 근거 지표(처리시간, 건수, 달성률 추이)를 함께 반환해 사용자가 판단하도록 하고, LLM 서술은 "진단 후보"로 표기한다.
- [성능] → 온톨로지는 테넌트당 수백~수천 노드 규모로 작아 문제 없음. tenant_id 속성 인덱스만 준비한다.

## Migration Plan

1. AGE 포함 Postgres 이미지로 로컬/E2E 인프라 교체 (compose의 postgres 서비스).
2. 신규 저장 계층(인터페이스 + AGE 어댑터) 배포 — 기동 시 확장/그래프 초기화, 빈 그래프면 관계형 전략맵 데이터 자동 이관.
3. 전략맵 API가 그래프 저장소를 사용하도록 전환. 측정/설문 모듈은 KPI 조회만 그래프로 바꾸고 기록은 관계형 유지.
4. 온톨로지 동기화 루프 활성화 → 조망 API → 영향도 분석 API 순서로 기능 배포 (각 단계가 독립 검증 가능).
5. 롤백: 이전 버전 이미지로 되돌리면 기존 테이블 데이터로 복구된다 (이관 후 신규 기록분은 유실 가능 — 릴리스 노트에 명시).

## Open Questions

- 운영 테넌트의 기존 전략맵 데이터 규모 — 기동 시 자동 이관 시간이 문제 되는 수준인지 확인 필요 (예상: 문제 없음).
- K3S/프로덕션 환경의 Postgres 이미지에 AGE를 설치하는 방식(공식 `apache/age` 이미지 vs Supabase postgres 이미지에 확장 빌드 추가) — 인프라 담당 확인 필요.
- 스킬 본문 LLM 분석의 프롬프트·정확도 기준 — 상속(fork 출처)과 참조(호출)를 구분해 추출하는 기준을 실제 스킬 데이터 샘플로 검증해 확정한다.
- 조직도 chart 값의 정확한 구조(팀 계층·구성원 매핑 필드) — 구현 시 실제 테넌트 데이터로 확정한다.
- `form_value_sum` 측정이 읽을 폼 데이터의 위치(완료 워크아이템 output vs 인스턴스 변수) 및 필드 경로 표기법 — 구현 시 실제 데이터 형태로 확정한다.
- Supabase Realtime/트리거 기반 push 인제스천 전환 시점 — 폴링 주기 지연이 사용성에 문제 될 때 재검토한다.
