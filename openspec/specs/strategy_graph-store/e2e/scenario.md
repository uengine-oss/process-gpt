# strategy_graph-store E2E 시나리오

## 목적

Cypher 그래프 저장소 추상화와 Apache AGE 어댑터를 **실제 기동/재기동/기동 실패** 관점에서
검증한다: AGE 기본 저장소 기동과 `/health`, 그래프 자동 초기화의 멱등성(재기동 후 데이터
생존), 지원하지 않는 `GRAPH_STORE` 값의 기동 실패, AGE 미설치 Postgres 기동 실패, 그리고
테넌트 격리(조회/변경).

## 사전조건 / 인프라

- **인프라(Docker)**: Apache AGE 포함 Postgres 컨테이너 `process-gpt-age-postgres`
  (127.0.0.1:55433, postgres/postgres/postgres). `services/strategy/docker-compose.age.yml`.
- **애플리케이션(소스 실행)**: 이 스위트는 러너가 uvicorn 서브프로세스를 **직접 기동/종료**한다
  (전용 포트 8115, 그래프 `corp_ontology_e2e_store`). 재기동 멱등성·기동 실패를 관측하기 위함.
- AGE 미설치 시나리오는 litellm-db(127.0.0.1:5432, AGE 없음)를 대상으로 하며, 접근 불가 시 스킵.
- 전략목표는 그래프에 저장되므로 관계형 원천 seed 가 필요 없다(`seed.sql` 참조).

## 실행 명령 · 포트 · 환경 변수

```bash
services/strategy/.venv/bin/python \
  openspec/specs/strategy_graph-store/e2e/run_e2e.py
```

러너가 아래 환경으로 uvicorn 을 기동한다(포트 8115):

| 변수 | 값 |
| --- | --- |
| DB_HOST/DB_PORT | 127.0.0.1 / 55433 |
| DB_USER/DB_PASSWORD/DB_NAME | postgres / postgres / postgres |
| GRAPH_STORE | age (기본) / unknown-db (실패 시나리오) |
| GRAPH_NAME | corp_ontology_e2e_store |
| MEASURE_AUTO_START | false |

## 시나리오 단계 ↔ spec Scenario 매핑

| 러너 단계 | spec Scenario |
| --- | --- |
| S1 기동/health, 그래프 자동 초기화 로그 | 기본 저장소로 기동 / 최초 기동 시 그래프 초기화 |
| S2 재기동 후 health + 기존 노드·관계 보존 | 재기동 멱등성 |
| S3 `GRAPH_STORE=unknown-db` 기동 실패 + 지원 목록 오류 | 지원하지 않는 저장소 지정 |
| S5 AGE 미설치 Postgres 기동 실패 + AGE 오류 로그 | AGE 확장이 없는 Postgres |
| S4 테넌트 A/B 격리 조회, 교차 테넌트 수정 404 | 테넌트 간 조회 격리 / 테넌트 간 변경 격리 |

> 참고: "계약 테스트 통과"(공통 행위 계약) Requirement 는 단위 계약 스위트
> `services/strategy/tests/graph_contract.py`(AGE 어댑터 대상, 85 passed)로 검증된다.
