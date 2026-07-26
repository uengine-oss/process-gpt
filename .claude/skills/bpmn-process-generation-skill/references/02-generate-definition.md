# 02 – Generate Definition: 프로세스 정의 JSON 생성 (엄격 규칙)

**목적**: 1단계에서 합의한 흐름 초안을 **우리 서비스 규격의 프로세스 정의 JSON** 으로 생성한다. 이 단계의 출력 구조는 ProcessGPT 백엔드가 그대로 소비하므로 **아래 규칙을 그대로** 지켜야 한다. 흐름은 유연했지만 여기서부터는 구조가 엄격하다.

> 이 규칙은 ProcessGPT 의 `process_definition_prompt.py` / `process_generation_messages.py` 의 생성 전용(Create-Only) 규칙을 옮긴 것입니다. 임의로 바꾸지 마세요.

산출물: `.bpmn/process-definition.json` (이후 4·5·6단계에서 같은 파일을 계속 업데이트)

전체 스키마 예시는 [assets/templates/process-definition.schema.json](../assets/templates/process-definition.schema.json) 에 있습니다. 이 reference 와 함께 보세요.

---

## 작업 정의 (생성 전용)

- 너의 작업은 단 하나: **합의된 흐름 초안(`.bpmn/01-consulting.md`)에 기반해 프로세스 정의 JSON 한 개를 생성**하는 것.
- 질의(askProcessDef) 응답이나 수정(modifications) 형식은 이 단계에서 쓰지 않는다. (수정 형식은 4~6단계 업데이트 시 사용 — 아래 "프로세스 변경" 참조)
- `{"processDefinition":{...}}` 처럼 중첩 래퍼로 감싸지 말 것. **최상위에 `processDefinitionId`, `processDefinitionName`, `elements`** 가 있어야 한다.
- 창작이 아니라, 합의된 흐름을 **안정적이고 일관된 BPMN 구조로 정리**하는 것이 목표. 명시적 근거 없는 새 단계/새 역할/새 게이트웨이를 만들지 말 것.

---

## ⛔ 절대 금지 — 일반 BPMN/Camunda 스키마로 만들지 말 것

이 단계에서 가장 흔한 실패는 모델이 **자기 머릿속의 일반 BPMN(Camunda/Zeebe) JSON** 으로 생성하는 것이다. 그러면 4단계 자체 검증에서 **반드시 결함으로 걸린다**. 아래를 절대 쓰지 마라:

| ❌ 쓰면 안 되는 것(일반 BPMN) | ✅ 반드시 이렇게(ProcessGPT) |
|---|---|
| `"type": "UserTask"` / `"ServiceTask"` / `"Task"` | `"elementType": "Activity"`, `"type": "UserActivity"` |
| `"assignee"`, `"candidateGroups"`, `"candidateUsers"` | `"role": "역할명(한글)"` |
| `"formKey": "..."` | (폼은 3단계에서) `"tool": "formHandler:<form_id>"` |
| `elementType` 없이 `type` 만 | **모든 요소에 `elementType`** (Event/Activity/Gateway/Sequence) |
| `"id": "submitApplication"`(camelCase) | `"id": "submit_application"`(영문 **소문자+언더스코어**) |
| `sequenceFlows`/`flows` 별도 배열 | 흐름도 `elements` 안에 `elementType:"Sequence"` 로 |
| `activities`/`events` 분리 배열 | **모두 `elements[]` 한 배열** 에 |

핵심: **`elements[]` 안에 `elementType` 으로 구분**, Activity 는 `type:"UserActivity"` + `role` + `outputData`(1개 이상), 모든 비-Sequence 요소 뒤에 잇는 `Sequence`(source/target). 이 규격을 어기면 검증에서 critical 결함으로 막힌다.

---

## 최상위 구조

```json
{
  "megaProcessId": "메가 프로세스 ID(한글, 선택)",
  "majorProcessId": "메이저 프로세스 ID(한글, 선택)",
  "processDefinitionName": "프로세스 명(한글)",
  "processDefinitionId": "프로세스 ID(UUID). 저장 시 서버에서 UUID로 강제되므로 비워두거나 임의값 무방",
  "description": "프로세스 설명(한글)",
  "isHorizontal": true,
  "data": [ ... ],
  "roles": [ ... ],
  "elements": [ ... ],
  "subProcesses": [ ... ]
}
```

- `isHorizontal`: 기본 `true`. 사용자가 "세로로 만들어줘" 라고 하면 반드시 `false`.
- `data`: 프로세스에서 쓰는 변수 목록. 각 항목: `{ "name": "변수명(한글)", "description": "설명(한글)", "type": "Text"|"Number"|"Date"|"Attachment"|"Form" }`

---

## roles (역할)

```json
{
  "name": "역할명(한글)",
  "endpoint": "역할 엔드포인트(영문 id)",
  "resolutionRule": "역할 매핑 방법",
  "origin": "used" | "created"
}
```

> ⚠️ **조직도를 조회하거나 요청하지 않는다.** 조직도는 **이미 대화 컨텍스트에 주어진 경우에만** 참고한다. 조직도 조회 도구를 호출하거나, 조직도를 얻으려고 사용자 토큰·테넌트 ID·현재 사용자 정보를 요청하지 말 것. 컨텍스트에 조직도가 없으면(이 skill 의 일반적 상황) 아래 3번대로 **흐름에 필요한 역할을 그냥 만든다.**

**역할 배정 규칙:**
1. (조직도가 **이미 컨텍스트에 주어진 경우에만**) 적절한 팀을 먼저 찾고, 그 팀의 `type=agent` 팀원을 역할로 **우선** 사용한다. 적절한 agent 가 없으면 그 팀 자체를 역할로 쓴다. **agent 가 아닌 사람(팀원)은 역할로 쓸 수 없다.** 적절한 팀·agent 가 모두 없을 때만 새 역할을 만든다.
2. 조직도에서 가져온 역할이면 `origin: "used"`, 새로 만든 역할이면 `origin: "created"`.
3. 조직도 정보가 없으면(이 skill 의 일반적 상황) 흐름에 필요한 역할을 만들고 `origin: "created"`, `endpoint` 는 영문 소문자 id 로 임의 생성.
4. 역할에 **외부 고객/참여자**가 있으면 그 역할의 `endpoint` 는 고정값 `external_customer`.

---

## elements (흐름 요소)

`elements` 배열에는 **Event / Activity / Gateway / Sequence** 네 종류만 넣는다. 시작·종료 이벤트와 시퀀스는 **항상 필수**.

> 중요: 흐름은 반드시 `elements` 안의 `Sequence` 로 표현한다. `sequenceFlows` 같은 별도 배열로 분리하지 말 것.

### Event
```json
{
  "elementType": "Event",
  "id": "event_id(영문)",
  "name": "이벤트명(한글)",
  "role": "역할명",
  "source": "이전_컴포넌트_id",
  "type": "StartEvent" | "EndEvent" | "IntermediateCatchEvent",
  "eventType": "Timer" | "Signal" | "Message" | "Conditional",
  "expression": "타이머 설정(cron). eventType이 Timer 일 때만",
  "description": "이벤트 설명(한글)",
  "trigger": "트리거 조건"
}
```
- StartEvent 1개, EndEvent 1개는 반드시 포함.

### Activity
```json
{
  "elementType": "Activity",
  "id": "activity_id(영문, lowercase)",
  "name": "액티비티명(한글)",
  "type": "UserActivity",
  "source": "이전_컴포넌트_id",
  "description": "액티비티 설명(한글)",
  "instruction": "사용자 지침(한글)",
  "role": "역할명",
  "skills": ["재사용 가능한 스킬 ID(선택)"],
  "inputData": ["입력 데이터명"],
  "outputData": ["출력 데이터명"],
  "checkpoints": ["체크포인트1", "체크포인트2"],
  "duration": "5"
}
```
- **현재 모드에서는 `type` 은 `UserActivity` 만 사용 가능.** EmailActivity / ManualActivity 는 지원하지 않는다.
- `instruction` 은 합의된 흐름의 원문 지침을 최우선으로 사용. 요약·재작성하지 말고 원문을 최대한 유지. 지침이 없으면 빈 문자열로 둔다(임의 생성 금지).
- **모든 Activity 는 `outputData` 를 최소 1개 이상** 가져야 한다. 빈 배열이거나 누락되면 안 됨.
- `skills` 는 2단계에서는 보통 비워두고, 4단계에서 사용자가 선택한 스킬을 채운다.

### Gateway
```json
{
  "elementType": "Gateway",
  "id": "gateway_id(영문)",
  "name": "게이트웨이명(한글)",
  "role": "역할명",
  "source": "이전_컴포넌트_id",
  "type": "ExclusiveGateway" | "ParallelGateway" | "InclusiveGateway",
  "description": "게이트웨이 설명(한글)"
}
```
- Gateway 를 만들면 outgoing Sequence 가 **2개 이상**이어야 한다. 분기가 1개뿐이면 Gateway 를 만들지 말고 직선으로 연결.
- ExclusiveGateway 면 각 outgoing Sequence 의 `condition` 을 한글로 채운다. 2분기면 true/false 의미가 드러나게: 예) "승인인 경우" / "반려인 경우".
- 이름은 의사결정 의미를 담는다. "분기1/분기2", "조건1/조건2" 같은 placeholder **금지**.
- ParallelGateway 는 condition 을 비워두고 분기/병합 구조가 자연스럽게.

### Sequence
```json
{
  "elementType": "Sequence",
  "id": "sequence_id(영문)",
  "name": "시퀀스명(한글, 선택)",
  "source": "시작_컴포넌트_id",
  "target": "도착_컴포넌트_id",
  "condition": "조건문(한글)"
}
```
- 모든 Sequence 는 `source` 와 `target` 을 둘 다 가져야 한다.
- non-sequence 요소(Event/Activity/Gateway)가 `source` 를 가지면, 그 source 에서 연결되는 Sequence 요소를 반드시 함께 정의한다. 즉 **각 요소 바로 뒤에 그 요소를 다음으로 잇는 Sequence 를 둔다.**

---

## subProcesses (서브프로세스)

하나의 단계가 단순 Task 가 아니라 **독립적/반복적 하위 흐름**이면 Activity 가 아니라 `subProcesses` 항목으로 만든다. 사용자가 "서브프로세스로 만들어줘" 라고 명시하면 그 단계는 반드시 `subProcesses` 에 넣는다 (서브프로세스 역할을 하는 일반 Activity 는 존재할 수 없음).

**메인 흐름과의 연결**: 서브프로세스는 마지막에 생성되므로, 메인 흐름을 만들 때 서브프로세스 id 를 미리 정해두고 *있다고 가정*하고 시퀀스를 잇는다. 예) 흐름이 `start → A → B → C(서브프로세스) → D → end` 면, B·D 는 C 가 있다고 가정하고 시퀀스를 만들고, 서브프로세스 생성 시 가정한 `C` id 로 정보를 채운다.

서브프로세스 구조는 [assets/templates/process-definition.schema.json](../assets/templates/process-definition.schema.json) 의 `subProcesses` 부분 참조. 핵심 골격:
```json
{
  "id": "subprocess_id(영문)",
  "name": "서브프로세스명(한글)",
  "role": "역할명",
  "type": "subProcess",
  "process": "부모_프로세스_id",
  "duration": "5",
  "properties": "{}",
  "attachedEvents": null,
  "children": { "data": [], "roles": [], "events": [...], "gateways": [...], "sequences": [...], "activities": [...], "subProcesses": [] },
  "processDefinitionId": "서브프로세스_정의_id",
  "processDefinitionName": "서브프로세스 정의명(한글)"
}
```
서브프로세스 내부 `children` 의 activities 는 `tool: "formHandler:form_name"`, `type: "userTask"` 형식을 쓴다(메인 elements 의 Activity 와 키가 다름에 주의).

---

## 반드시 지킬 규칙 (요약)

1. 모든 **id 는 영문 소문자 + 언더스코어**.
2. 모든 **이름·설명은 한글**.
3. 프로세스는 항상 **StartEvent 로 시작, EndEvent 로 종료**.
4. 모든 요소는 Sequence 로 연결 — **끊긴 노드(고아) 금지**. EndEvent 는 incoming 1개 이상, EndEvent 제외 모든 Activity/Gateway 는 outgoing 1개 이상.
5. 각 Sequence 는 source·target 필수.
6. Gateway 사용 시 분기 조건을 명확히.
7. 모든 Activity·Gateway 에 `role` 배정.
8. (조직도 있으면) 위 "역할 배정 규칙" 적용.
9. 조건이 있는 Sequence 는 `condition` 포함.
10. **JSON 안에 주석 금지** (`//`, `/* */`).
11. 각 요소 바로 뒤에 그 요소를 다음으로 잇는 Sequence 를 둔다.
12. non-sequence 요소가 `source` 를 가지면 대응 Sequence 를 정의.
13. 외부 고객/참여자 역할의 endpoint 는 `external_customer`.
14. 모든 Activity 는 `outputData` 1개 이상.
15. 분기 판단 내용은 dmn_rules 가 아니라 **Sequence.condition 에 직접** 작성한다(2단계 기준).

### 시작 task 결정 (중요)
- 합의된 흐름의 첫 단계가 BPMN 의 첫 Activity 다. StartEvent 의 outgoing 은 그 첫 단계로 향한다.
- "통보/완료/종료/결과 발송/마감" 처럼 **종결 의미가 강한 단계를 시작점으로 만들지 말 것.** 이런 단계는 거의 항상 EndEvent 직전에 온다.

---

## 출력 형식

- 산출물 `.bpmn/process-definition.json`에 **valid JSON 객체 1개**를 `Write` 도구로 저장한다. 마크다운/설명/코드펜스/주석 없이 순수 JSON.
- 설명이 필요하면 JSON 의 `description`/`instruction`/`trigger` 같은 **필드 값(문자열)** 안에 넣는다.
- 파일에 쓴 뒤, 사용자에게는 자연어로 요약해 보여준다 (사용자에게 raw JSON 을 들이밀지 말 것):

> "프로세스 정의를 만들었어요. **[프로세스명]** — 시작은 [트리거], 단계는 ①~ ②~ ③~ 이고, [분기설명] 갈림길이 있습니다. 역할은 [역할목록] 입니다. (`.bpmn/process-definition.json`)"

---

## 프로세스 변경(수정) 형식 — 4~6단계에서 사용

2단계는 **새로 생성**이지만 이후 단계는 기존 JSON을 **수정**한다. 기존 요소를 바꿀 때는 전체 재생성이 아니라 `Edit` 도구로 요소 ID 기준 해당 필드만 갱신한다(old_string 을 충분히 구체적으로 잡아 다른 요소를 건드리지 않게 한다). 개념적으로는 ProcessGPT의 `modifications` 형식과 동일하다:

```json
{
  "modifications": [
    {
      "action": "replace" | "add" | "delete",
      "targetJsonPath": "$.activities[?(@.id=='leave_request')]",
      "value": { ... },
      "beforeActivity": "이전_액티비티_id"
    }
  ]
}
```
- 액티비티/게이트웨이/이벤트를 추가하면 시퀀스도 같이 연결. 삭제하면 앞뒤를 다시 시퀀스로 잇기.
- Sequence 는 replace 없음 — add 또는 delete 만.
- 기존 요소의 위치/이름을 임의로 바꾸지 않는다.

> 이 skill에서는 modifications를 `Edit` 도구로 필요한 필드만 정밀 치환합니다. 요소 추가·삭제 같은 구조 변경만 완전한 객체를 `Write`로 다시 씁니다.

---

## 다음 단계 연결

JSON 을 만들고 요약을 보여준 뒤:

> "이제 이 프로세스에 **스킬·에이전트·DMN** 을 붙일 수 있어요. 반복되는 작업을 재사용 **스킬**로, 담당을 **에이전트**로, 분기 판단을 **DMN 규칙**으로 만들 수 있는데, 어떤 걸 만들지 골라주시면 됩니다."

그리고 [03-elicit-artifacts.md](03-elicit-artifacts.md) 를 로드해 3단계(HITL)로 진입합니다.
