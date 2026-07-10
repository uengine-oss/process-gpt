# strategy_ontology-sync E2E 시나리오

## 목적

플랫폼 원천 데이터(proc_def/users/조직도/skills/todolist)를 온톨로지 그래프로
인제스천하는 ETL 을 검증한다: 프로세스 정의의 태스크 분해와 역할자 `PERFORMS`,
사람/에이전트 구분, 조직도(`Team`/`HAS_SUB_TEAM`/`MEMBER_OF`), 스킬 노드와 `USES_SKILL`,
완료 워크아이템의 실행 지표 집계, 수정분/삭제분 반영, LLM 미설정 시 스킬 관계 추출 보류.

## 사전조건 / 인프라

- **인프라(Docker)**: process-gpt-age-postgres (127.0.0.1:55433, postgres/postgres/postgres).
- **애플리케이션(소스 실행)**: 상시 uvicorn 서버(포트 8114, 그래프 `corp_ontology_e2e`,
  `MEASURE_AUTO_START=false`). 인제스천 루프는 꺼 두고 `POST /api/ontology/sync` 로 명시 실행.
- **LLM 미설정**: 서버 프로세스에 `OPENAI_API_KEY` 가 없어 스킬 관계 추출은 보류(pending) 경로.
- 러너가 원천 테이블(proc_def/users/configuration/todolist/agent_skills/skills)을 CREATE +
  INSERT 한다(`seed.sql` = 컬럼 DDL). 고유 테넌트 `e2e-sync-<ts>` 사용, 종료 시 정리.

## 실행 명령 · 포트 · 환경 변수

서버 기동은 strategy_strategy-map-graph 스위트와 동일(포트 8114, 위 환경). 러너:

```bash
services/strategy/.venv/bin/python \
  openspec/specs/strategy_ontology-sync/e2e/run_e2e.py
```

## 시나리오 단계 ↔ spec Scenario 매핑

| 러너 단계 | spec Scenario |
| --- | --- |
| proc_def 3활동 → Task 3 + CONTAINS_TASK | 프로세스 정의의 태스크 분해 |
| 역할(담당자)→User PERFORMS, agent→Agent PERFORMS | 정의상 역할자의 수행 관계 생성 |
| User 1 / Agent 1 구분 | 사람과 에이전트의 구분 반영 |
| 본부→1팀 HAS_SUB_TEAM, 팀원→1팀 MEMBER_OF | 조직도 반영 |
| Skill 노드 + Agent USES_SKILL | (스킬 노드 동기화) |
| LLM 미설정 → pending_extraction 보고 | LLM 미설정 환경 |
| todolist 2건(1h,2h) → PERFORMS count=2, avg=1.5h | 실행 지표 집계 |
| proc_def 이름 수정 → 재sync 갱신·무중복 | 수정분의 반영 |
| proc_def isdeleted → 재sync Process/Task 제거 | 삭제분의 반영 |

> 스킬 관계 추출(INHERITS/REFERENCES)의 실제 LLM 경로는 단위 테스트
> `tests/test_ontology_sync.py::test_skill_relation_extraction`(LLM stub 주입)로 검증된다.
