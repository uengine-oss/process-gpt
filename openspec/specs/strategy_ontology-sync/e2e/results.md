# strategy_ontology-sync E2E 실행 결과

- 실행 일시: 2026-07-09 (KST)
- 인프라: process-gpt-age-postgres (127.0.0.1:55433) / uvicorn 8114 (그래프 corp_ontology_e2e, OPENAI_API_KEY 미설정)
- 결과: **24/24 PASS**

## Pass/Fail 표

| # | 시나리오 | 결과 |
| --- | --- | --- |
| 1 | 인제스천 결과에 last_synced_at 포함 | PASS |
| 2 | 인제스천 요약: users/processes merged | PASS |
| 3 | 스킬 관계 추출 보류(pending, LLM 미설정) | PASS |
| 4-9 | 노드 라벨 Process/Task/User/Agent/Team/Skill 존재 | PASS |
| 10 | proc_def 3활동 → Task 노드 3개 | PASS |
| 11-15 | 관계 CONTAINS_TASK/PERFORMS/HAS_SUB_TEAM/MEMBER_OF/USES_SKILL 존재 | PASS |
| 16 | CONTAINS_TASK: Process→Task(a1) | PASS |
| 17 | PERFORMS(정의): User(담당자)→Task a1 | PASS |
| 18 | PERFORMS(정의): Agent→Task a2 | PASS |
| 19 | HAS_SUB_TEAM: 본부→1팀 | PASS |
| 20 | MEMBER_OF: 팀원→1팀 | PASS |
| 21 | USES_SKILL: Agent→Skill(slug=pptx-생성) | PASS |
| 22 | PERFORMS 실행 지표 count=2, avg=1.5h | PASS |
| 23 | 수정분 반영: Process 이름 갱신 + 중복 없음 | PASS |
| 24 | 삭제분 반영: Process/Task 제거 | PASS |

## 주요 응답 발췌

`POST /api/ontology/sync?tenant_id=e2e-sync-*` 요약:

```json
{
  "users": {"merged": 3, "deleted": 0},
  "processes": {"merged": 1, "tasks": 3, "performs": 2, "deleted": 0},
  "org": {"teams": 2, "sub_team_edges": 1, "member_edges": 1, "deleted": 0},
  "skills": {"merged": 2, "edges": 2, "extracted": 0,
             "pending_extraction": ["PPTX 생성", "리포트 작성"]},
  "performs": {"items": 2, "edges": 1},
  "last_synced_at": "2026-07-09T..."
}
```

- LLM 미설정 → `skills.pending_extraction` 에 변경 스킬 2건이 보류로 기록(노드는 생성됨).
- PERFORMS(Agent→Task a2) 엣지 속성: `count=2, avg_duration_hours=1.5`.

## 실행 콘솔

```
=== SUMMARY: 24/24 PASSED ===
```
