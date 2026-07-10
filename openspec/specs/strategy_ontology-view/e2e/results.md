# strategy_ontology-view E2E 실행 결과

- 실행 일시: 2026-07-09 (KST)
- 인프라: process-gpt-age-postgres (127.0.0.1:55433) / uvicorn 8114 (그래프 corp_ontology_e2e)
- 결과: **16/16 PASS**

## Pass/Fail 표

| # | 시나리오 | 결과 |
| --- | --- | --- |
| 1 | 전체 조회: 8개 라벨 존재 | PASS |
| 2 | 전체 조회: 레이어 간 관계 존재 | PASS |
| 3 | 전체 조회: last_synced_at 포함(값 존재) | PASS |
| 4 | 전체 조회: layers=전체 4레이어 | PASS |
| 5 | 노드 layer 표기(strategy/process/resource/skill) | PASS |
| 6 | 빈 테넌트: 노드/관계 빈 목록 | PASS |
| 7 | layers=strategy: 전략층 라벨만 | PASS |
| 8 | layers=strategy: HAS_KPI 포함, IMPACTS_KPI 제외 | PASS |
| 9 | layers=strategy: layers 에코 | PASS |
| 10 | layers=strategy,process: 교차 IMPACTS_KPI 포함 | PASS |
| 11 | layers=strategy,process: 리소스/스킬 라벨 제외 | PASS |
| 12 | 잘못된 layers 값 거부(4xx) | PASS |
| 13 | neighbors(KPI, depth1): KPI+Strategy+Process | PASS |
| 14 | neighbors(KPI, depth1): HAS_KPI/IMPACTS_KPI 관계 | PASS |
| 15 | neighbors(Strategy, depth2): KPI+Process 도달 | PASS |
| 16 | neighbors 존재하지 않는 노드 404 | PASS |

## 주요 응답 발췌

- 전체 조회 라벨: `{Strategy, KPI, Initiative, Process, Task, User, Agent, Team, Skill}`.
- 전체 조회 관계: `{HAS_KPI, HAS_INITIATIVE, IMPACTS_KPI, CONTAINS_TASK, PERFORMS,
  MEMBER_OF, USES_SKILL, HAS_SUB_TEAM, EXECUTED_BY}`, `layers=[strategy,process,resource,skill]`.
- `layers=strategy` → 라벨 ⊆ `{Strategy, KPI, Initiative}`, `IMPACTS_KPI` 없음(프로세스 끝 제외).
- `layers=strategy,process` → `IMPACTS_KPI(Process→KPI)` 포함, Agent/Skill 제외.

## 실행 콘솔

```
=== SUMMARY: 16/16 PASSED ===
```
