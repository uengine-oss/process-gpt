# 08 – Reference Info: 참조정보(inputData / conditionData) 연결

**목적**: 폼이 만들어진 뒤, 각 단계가 **이전 단계의 어떤 입력값을 참조**할지 연결한다. 두 가지를 채운다:
- Activity 의 `inputData`: 이 태스크를 수행할 때 참고할 **이전 태스크 폼의 필드**.
- ExclusiveGateway 의 `conditionData`: 그 분기 조건을 평가할 때 참조할 **이전 태스크 폼의 필드**.

이 단계가 끝나면 프로세스 정의가 완성된다. **이 단계는 5단계(폼) 직후 자동으로 이어 실행되며, 사용자에게 따로 묻지 않는다.** 참조 연결을 마친 뒤 아래 "완료 안내" 로 4·5·6단계 결과를 **한 번에** 요약하고 수정 가능 안내를 한다.

> 이 규칙은 pdf2bpmn 의 `_expand_process_after_forms`(inputData) + conditionData 선택 로직을 옮긴 것입니다.

산출물: `process-definition.json` 최종 업데이트 (`activity.inputData`, `gateway.conditionData`).

---

## 참조 형식

참조값은 항상 **`<form_id>.<field_name>`** 형식이다. (7단계에서 만든 폼의 form_id 와 필드 name 을 쓴다.) 예: `leave_request_apply_form.start_date`.

---

## 후보는 "선행 태스크"의 폼 필드만

핵심 제약: **반드시 그 노드보다 앞선(predecessor) Activity 의 폼 필드만** 참조할 수 있다. 미래/뒤에 오는 폼이나 존재하지 않는 필드는 참조 금지.

1. Sequence 를 따라 각 노드의 **선행 Activity 집합**을 구한다.
2. 선행 Activity 들의 폼에서 필드(`<form_id>.<field_name>`)를 후보로 모은다.
3. 그 후보 중에서만 고른다.

---

## inputData (각 Activity)

각 UserActivity 에 대해:
- 후보(선행 폼 필드) 중 **이 태스크 수행에 참고하면 좋은 것**만 고른다. 불필요한 참조는 넣지 않는다.
- 적절한 게 분명치 않으면 **선행 후보 전체**를 넣는 폴백도 허용(과하지 않게 상한 내에서).
- 첫 Activity(선행 없음)는 `inputData: []`.

```json
"inputData": ["leave_request_apply_form.start_date", "leave_request_apply_form.reason"]
```

---

## conditionData (각 ExclusiveGateway)

각 ExclusiveGateway 에 대해:
- **필수 실행 계약**: 바로 전 UserActivity 폼에 분기 판단 전용 `select-field`가 있어야 한다. 선택지의 실제 `value`는 각 outgoing Sequence의 `condition` 문자열과 정확히 같아야 한다(예: `승인`, `반려`). 단순한 요청 메모나 검토 의견 필드는 판단값으로 간주하지 않는다.
- `conditionData`는 위 결정 필드 하나를 우선 참조한다. 값은 반드시 문자열 배열이며 객체(`{"field": ...}`)를 넣지 않는다.
- 그 게이트웨이의 **선행 Activity 들의 폼 필드** 중, 분기 조건을 평가할 때 참조해야 하는 필드만 고른다.
- 후보가 분명치 않으면 폴백: **가장 가까운 선행 Activity 의 모든 폼 필드**를 conditionData 로.
- ParallelGateway/InclusiveGateway 는 조건 평가가 없으므로 `conditionData: []` (비워둔다).

```json
"conditionData": ["leave_approval_form.decision"]
```

폼과 시퀀스 예시:

```html
<select-field name='decision' alias='승인 여부'>
  <option value='승인'>승인</option>
  <option value='반려'>반려</option>
</select-field>
```

```json
{"elementType":"Sequence","source":"approval_gateway","target":"execute","condition":"승인"}
{"elementType":"Sequence","source":"approval_gateway","target":"rework","condition":"반려"}
```

---

## 프로세스 정의 JSON 반영

`Edit`으로 아래 참조 필드를 요소 ID 기준 갱신:
1. 각 Activity 의 `inputData` 를 선행 후보로 한정해 채운다(중복 제거, 상한 적용).
2. 각 ExclusiveGateway 의 `conditionData` 를 채운다.
3. 메인 `elements` 와 (있으면) 서브프로세스 `children` 양쪽 모두 동기화한다.

> 제약 위반 방지: 채운 모든 참조가 "선행 폼 필드" 후보 집합에 실제로 있는지 확인한다. 없으면 제거한다.

---

## 완료 안내

참조정보까지 연결하면 프로세스 정의가 완성된다. 사용자에게:

> "프로세스 정의가 완성됐어요! **[프로세스명]**
> - 흐름: ①~ ②~ ③~ (분기: ~)
> - 역할/에이전트: ~
> - 스킬: ~ / DMN 규칙: ~
> - 폼: 단계별 입력 양식 N개
> - 참조정보: 각 단계가 이전 입력을 참조하도록 연결
>
> 산출물은 `.bpmn/` 에 있습니다 (`process-definition.json`, `skills/`, `forms/`). 수정하고 싶은 부분이 있으면 말씀해 주세요."

> 참조정보 연결 뒤에는 사용자에게 다시 묻지 말고 곧바로 4단계(자체 검증)로 넘어간다. `.bpmn/process-definition.json`을 `Read`로 다시 읽어 [02-generate-definition.md](02-generate-definition.md)의 규칙 체크리스트를 직접 대조하고, 결함이 있으면 보정한 뒤에만 5단계 완료 안내로 진행한다.
