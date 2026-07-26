# 05 – Agents: 에이전트(역할 담당자) 생성 + JSON 반영

**목적**: 3단계에서 사용자가 고른 에이전트 후보(역할 × 스킬)에 대해 **에이전트 프로필**을 만들고, 그 에이전트를 담당 Activity 와 `roles` 에 연결한다. 에이전트는 특정 역할이 반복 수행하는 작업을 자동으로 처리하는 담당자다.

> 이 규칙은 pdf2bpmn 의 `_llm_generate_agent_profile`(OrganizationAgentGenerator 스타일) + `_apply_approved_agents` 를 옮긴 것입니다.

산출물:
- `process-definition.json` 업데이트 (`activity.agent` 채움 + `roles[].endpoint`/`origin` 갱신, 자동화 필드)
- (선택) 에이전트 프로필을 사람이 보게 하려면 `.bpmn/skills/` 옆에 `agents/<candidate_id>.md` 로 메모할 수 있다. 필수는 아님.

---

## 에이전트 프로필 만들기

선택된 각 후보(역할 + 그 역할이 담당하는 활동 묶음)에 대해 아래 JSON 형식으로 프로필을 생성한다:

```json
{
  "name": "에이전트의 이름 (한국어)",
  "role": "에이전트의 역할 (한 문장, 핵심만)",
  "goal": "에이전트의 목표 (SMART — 구체적·측정 가능하게)",
  "persona": "에이전트의 성격·말투·전문성 (상세히)",
  "tools": "필요한 도구들 (쉼표 구분, 없으면 빈 문자열)"
}
```

**설계 지침** (중요):
- 너무 세분화된 "단일 태스크 전용" 에이전트로 만들지 말 것. 상세도 1~10 중 **6 정도** — 관련 업무를 묶어 포괄하는 형태.
  - 예: "수강 신청 도우미"·"수강 관리 도우미"·"강의 개설 도우미" 로 쪼개지 말고 "교육/수강 운영 도우미" 로 묶기.
  - 단, "만능 도우미" 처럼 과도하게 광범위한 것도 금지.
- `name` 은 직관적·명확하게, `role` 은 한 문장, `goal` 은 구체적·측정 가능하게, `persona` 는 성격·전문성 상세히.
- 도구 목록이 따로 주어지지 않으면 `tools` 는 비워둔다(임의의 외부 도구를 지어내지 말 것).

> **기존 에이전트 재사용**: 3단계 후보에 "기존 에이전트 재사용" 표시가 있었으면 새 프로필을 만들지 않고 그 에이전트 id 를 그대로 연결만 한다.

---

## 프로세스 정의 JSON 반영

`Edit`으로 아래 필드를 요소 ID 기준 갱신한다:

1. **담당 Activity 의 `agent`** 에 에이전트 식별자를 넣는다. (신규면 새 id, 재사용이면 기존 id.)
   ```json
   "agent": "<agent_id>"
   ```
   - 후보의 `activity_ids` 에 든 모든 Activity 에 반영.
2. **자동화 정책 필드** 를 Activity 상태에 맞춰 설정한다:
   - 스킬이 배정된 Activity (`skills` 비어있지 않음): `"agentMode": "complete"`, `"orchestration": "deepagents"`
   - 에이전트만 배정(스킬 없음): `"agentMode": "draft"`, `"orchestration": "crewai-action"`
   - 둘 다 없음: `"agentMode": "none"`, `"orchestration": null`
3. **`roles[].endpoint` 갱신**: 그 역할에 에이전트가 배치되면 해당 role 의 `endpoint` 를 그 agent id 로, `origin` 을 `"used"` 로 바꾼다.

> `external_customer` 엔드포인트를 가진 외부 고객 역할에는 에이전트를 배정하지 않는다(사람/외부 참여자이므로).

---

## 사용자에게 보여주기

- 만든/연결한 에이전트마다 한 줄: "**팀장 결재 도우미**(신규) — 검토·승인 활동 1개 담당." 또는 "기존 에이전트 재사용: ~"
- 자연어 요약 위주, raw JSON 지양.

## 다음 단계 연결

3단계에서 DMN 도 골랐으면 [06-dmn.md](06-dmn.md), 아니면:

> "담당 에이전트를 연결했어요. 다음은 [DMN 규칙 / 폼 생성] 입니다."

→ [06-dmn.md](06-dmn.md) 또는 [07-forms.md](07-forms.md) 로 이어집니다.
