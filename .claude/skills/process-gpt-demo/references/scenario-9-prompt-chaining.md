# 시나리오 9 — Prompt Chaining 에이전틱 패턴 데모: 시장조사 인사이트 체인

"Prompt Chaining"(순차적 프롬프트 연쇄) 에이전틱 패턴 —복잡한 과제를 여러
단계로 나눠 이전 단계의 출력을 다음 단계의 입력으로 전달하는 방식 —을
ProcessGPT의 BPMN 프로세스 하나로 실제로 시연한다. ProcessGPT에는 "체이닝"이라는
별도 구성요소가 없다 — **BPMN 시퀀스 자체가 체이닝의 표현**이다: 각 단계가
`orchestration: "deepagents"`(딥에이전트 타입)로 무인 실행되고, 뒤 단계의
`inputData`가 앞 단계 폼 필드를 참조한다.

시연 대상 프로세스 "시장조사 인사이트 체인"(3단계, 전부 스킬 배정 →
`agentMode: "complete"` + `orchestration: "deepagents"`):

1. **시장조사 보고서 요약** — 사람이 시장조사 보고서 원문(텍스트)을 제출하는
   유일한 사람 개입 지점. 스킬: 요약. 출력 필드(예) `report_summary`.
2. **핵심 트렌드 식별** — deepagents 무인 실행. `inputData: ["<1단계
   form_id>.report_summary"]`. 스킬: 트렌드 식별(상위 3개 트렌드 + 근거 데이터
   포인트). 출력 필드(예) `trend_analysis`.
3. **마케팅팀 이메일 초안 작성** — deepagents 무인 실행. `inputData:
   ["<2단계 form_id>.trend_analysis"]`. 스킬: 이메일 초안 작성. 출력 필드(예)
   `email_draft`.

에이전트는 역할 하나("마케팅 인사이트 도우미")가 3개 스킬을 갖고 3개 활동을
전담한다(`skills/bpmn-process-generation-skill/references/05-agents.md`의
역할×스킬 매핑 그대로 — 시나리오 2와 동일한 메커니즘, 도메인만 다름).

전제: [demo-account.md](demo-account.md)의 고정 계정으로 로그인돼 있어야
한다.

## 1. 생성 — 체이닝 구조를 명시적으로 요청

⚠️ 시나리오 1에서 배운 교훈과 동일: 그냥 "요약→트렌드→이메일 프로세스
만들어줘"라고만 하면 자동화·체이닝 의도가 암묵적으로 빠질 수 있다. 아래처럼
**무인 순차 처리와 이전 단계 참조**를 명시적으로 요청한다.

`/definition-map`에서:
```
시장조사 보고서를 분석해 마케팅팀에 인사이트 이메일을 보내는 프로세스를
만들어줘. 1단계는 담당자가 시장조사 보고서 원문을 입력하고, 2단계(핵심 트렌드
식별)와 3단계(마케팅팀 이메일 초안 작성)는 사람 개입 없이 딥에이전트가 순서대로
자동 처리해야 해. 각 단계는 이전 단계의 출력 결과를 반드시 참조해서 체이닝
방식으로 작업해야 하고, 3단계는 요약이 아니라 2단계에서 식별한 구체적인
트렌드를 근거로 이메일을 써야 해.
```

이후 절차는 시나리오 2와 동일한 패턴(초안 확인 → 확정 칩 + "응답 제출" →
`skills_batch`/`agents_batch` 질문에서 3개 스킬(요약/트렌드 식별/이메일 초안
작성)과 에이전트 1개 선택 → 저장):

```sql
select status, draft_status from todolist where id='<workitem_id>';
select definition::text from proc_def where id='<proc_def_id>';
```

**정합성 확인 항목** (저장 후 반드시 확인):
- 3개 활동 모두 `activities[].orchestration = "deepagents"`,
  `agentMode = "complete"`.
- 2단계 활동의 `inputData`에 1단계 폼의 요약 필드가, 3단계 활동의 `inputData`에
  2단계 폼의 트렌드 필드가 들어 있는지(`08-reference-info.md` 규칙대로 —
  선행 단계 폼 필드만 참조 가능).
- `skills` 배열에 스킬 3개, 에이전트 1개가 각 활동에 정확히 연결됐는지.

## 2. 실행 — 첫 활동만 사람이 제출, 2·3단계는 무인 체이닝

시나리오 1/2와 동일하게 `/completion/complete` API를 JWT와 함께 직접 호출한다
(demo-account.md의 Playwright 로그인 + JWT 추출 스니펫 재사용). 첫 활동(보고서
요약)에 시장조사 보고서 원문 텍스트를 제출:

```bash
curl -X POST "http://localhost:8088/completion/complete" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"input": {
    "process_definition_id": "<proc_def_id>",
    "process_instance_id": "<proc_def_id>.<uuid>",
    "activity_id": "<1단계 activity_id>",
    "email": "demo@localhost",
    "user_id": "<auth_uid>",
    "username": "demo",
    "form_values": { "<1단계 form_id>": { "market_report": "<시장조사 보고서 원문>" } }
  }}'
```

제출 직후 폴링으로 2·3단계가 사람 개입 없이 자동 전이되는지 확인:
```sql
select activity_id, status, agent_mode, agent_orch, start_date, end_date
from todolist where proc_inst_id='<inst_id>' order by start_date;
```
- 2단계 `핵심 트렌드 식별`, 3단계 `마케팅팀 이메일 초안 작성` 모두
  `agent_mode='COMPLETE'`, `agent_orch='deepagents'`로 뜨고, 1단계 제출 후 수
  초~수십 초 안에 순서대로 `DONE`이 되는 것을 `/todolist` 화면 캡처 2~3회로
  보여준다(카드가 저절로 순차 이동).

## 3. 시연 포인트 — 슬라이드의 4가지 특징을 실측으로 짚기

1. **순차적 의존성**: 3단계 최종 출력(이메일 초안)이 2단계가 식별한 **구체적인
   트렌드 명칭/근거**를 실제로 인용하는지 확인한다(일반론이 아니라 2단계 출력에만
   있는 구체값이 등장해야 체이닝 증거). `todolist`의 각 활동 `output` 필드값을
   직접 대조.
2. **작업 분해**: 하나의 거대한 "보고서 분석" 프롬프트 대신 요약/트렌드
   식별/이메일 작성 3개의 좁은 스킬로 나뉘어 있음을 각 스킬 SKILL.md로 보여준다.
3. **단계별 최적화**: 각 활동이 서로 다른 전용 스킬(스킬 파일 3개, 서로 다른
   `procedure`)을 갖고 있어 단계마다 결과 품질이 그 단계 목적에 맞게 최적화됨을
   스킬 파일 비교로 보여준다.
4. **명확한 관찰 가능성**: `/todolist`와 워크아이템 상세의 "에이전트에 맡기기"
   탭(AgentMonitor)에서 각 단계의 실행 카드·타임스탬프·`agent_orch=deepagents`가
   그대로 노출되어, 중간 결과를 실시간으로 모니터링/디버깅할 수 있음을 화면으로
   보여준다.

## 4. 알려진 함정

- 채팅 프롬프트에 "무인 자동 처리"·"이전 단계 참조"를 명시하지 않으면
  일부 활동이 `agentMode: draft` 또는 사람 배정으로 생성될 수 있다(시나리오 1의
  분기 누락과 같은 종류의 문제) — 저장 직후 반드시 1번의 정합성 확인 항목을
  체크한다.
- 시나리오 2와 동일하게, 담당 역할("마케팅 인사이트 도우미")이 실제 에이전트
  uuid로 `roles[].endpoint`에 연결돼 있어야 2·3단계가 사람 배정 없이 바로
  에이전트에게 넘어간다 — 첫 활동만 데모 계정으로 오버라이드하면 된다(시나리오
  2의 3번 섹션과 동일한 이유).
- 스킬이 실제로 쓰였는지 의심되면 시나리오 2의 "스킬이 실제로 쓰였는지 확인하는
  3가지 방법"(출력 내용 대조 / `docker logs deepagents` / 샌드박스 내부 스킬
  파일 확인)을 그대로 적용한다.

## 5. 검증된 전체 경로 (재현 시 실측값으로 갱신)

```
시장조사 보고서 요약(DONE, 사람 제출)
→ 핵심 트렌드 식별(DONE, deepagents+스킬, 무인, 1단계 출력 참조)
→ 마케팅팀 이메일 초안 작성(DONE, deepagents+스킬, 무인, 2단계 출력 참조)
→ bpm_proc_inst.status = COMPLETED
```

## 데모 후 보고

- 생성된 proc_def id, 스킬 3개 slug, 에이전트 이름/uuid
- 시작된 proc_inst id
- 2·3단계의 SUBMITTED→DONE 타임스탬프(무인 체이닝 증거)
- 3단계 출력이 2단계 출력을 실제로 참조했다는 근거(텍스트 대조 결과)
- 최종 `bpm_proc_inst.status`
- 최종 녹화 영상 경로/길이, 내레이션 유무·voice(recording-and-narration.md
  6번 항목과 동일)
