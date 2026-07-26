# 06 – DMN: 분기 판단을 의사결정 규칙으로 + JSON 반영

**목적**: 3단계에서 사용자가 고른 ExclusiveGateway 들을, 분기 조건을 표로 정리한 **DMN 의사결정(decision) + 규칙(rule)** 으로 만들어 프로세스 정의 JSON 에 추가한다. 게이트웨이 1개 = 의사결정 1개, 그 게이트웨이의 각 분기 = 규칙 1개.

> 이 규칙은 pdf2bpmn 의 `_augment_runtime_with_gateway_dmn`(게이트웨이 → dmn_decisions/dmn_rules) 을 옮긴 것입니다.

산출물: `process-definition.json` 에 `dmn_decisions[]`, `dmn_rules[]` 추가 + 분기 Sequence 의 `properties.examples` 보강.

---

## 자격 (3단계에서 이미 거른 후보)

- ExclusiveGateway 만. (Parallel/Inclusive 제외 — 조건 평가 의미가 다름)
- outgoing Sequence 2개 이상.
- 선택된 게이트웨이만 변환한다. 안 고른 게이트웨이는 **BPMN 분기 조건(Sequence.condition)만** 그대로 쓴다.

이 자격 자체가 "DMN 으로 만들 가치가 있는 후보"만 걸러진 결과다 — [03-elicit-artifacts.md](03-elicit-artifacts.md)의 DMN 승격조건(①같은 판단 로직의 반복/재사용 가능성, ②조건 3개 이상 또는 복합 조건, ③운영자가 자주 바꾸는 정책·기준값)을 하나 이상 만족한 게이트웨이만 3단계에서 사용자에게 후보로 제시됐고, 사용자가 그중 고른 것만 여기로 넘어온다. 단순 1회성 "승인/반려" 2지 분기처럼 위 조건에 해당하지 않는 분기는 애초에 후보에 없었어야 하며, 혹시 넘어왔다면 다시 3단계 기준으로 판단해 필요 없으면 건너뛴다.

---

## 의사결정(decision) 만들기

게이트웨이 1개당 1개:

```json
{
  "decision_id": "dmn_decision_<gateway_id를 snake_case로>",
  "name": "<게이트웨이명(한글)>",
  "description": "<게이트웨이 설명 또는 'OO에 대한 분기 판단'>",
  "related_gateway_id": "<gateway_id>"
}
```

## 규칙(rule) 만들기

그 게이트웨이의 **조건이 있는 outgoing Sequence 마다** 1개:

```json
{
  "rule_id": "dmn_rule_<gateway_id를 snake_case로>_<순번>",
  "decision_id": "<위 decision_id>",
  "decision_name": "<게이트웨이명>",
  "when": "<Sequence.condition (한글 조건)>",
  "then": "<도착 노드명> 경로 선택",
  "condition": "<Sequence.condition>",
  "target": "<도착 노드 id>"
}
```

조건이 없는 Sequence(예: 기본 분기)는 규칙을 만들지 않는다.

---

## 분기 예시 보강 (properties.examples)

각 분기 Sequence 의 `properties` 에 good/bad 예시를 기록한다. ExclusiveGateway 에서 한 분기의 "좋은 예시"(=이 분기 조건)와 "나쁜 예시"(=다른 분기 조건)는 서로 반대 케이스이므로 자동 도출된다:

```json
"properties": "{\"examples\": {\"good_examples\": [{\"given\": \"<게이트웨이명>\", \"when\": \"<이 분기 조건>\", \"then\": \"<대상>으로 진행\"}], \"bad_examples\": [{\"given\": \"<게이트웨이명>\", \"when\": \"<다른 분기 조건>\", \"then\": \"이 경로로 진행하지 않음\"}]}}"
```

(`properties` 는 JSON 문자열로 직렬화해 넣는다.)

---

## 프로세스 정의 JSON 반영

`Edit`으로 gateway 필드와 top-level DMN 배열을 갱신:

1. 최상위에 `dmn_decisions` 배열(없으면 생성)에 decision 추가.
2. 최상위에 `dmn_rules` 배열(없으면 생성)에 rule 들 추가.
3. 해당 분기 Sequence 의 `properties` 를 위 예시로 보강.
4. **게이트웨이의 BPMN 분기 조건(`Sequence.condition`)은 그대로 둔다.** DMN 은 그 위에 얹는 것이지 대체가 아니다.

> decision_id/rule_id 가 이미 있으면 중복 추가하지 않는다.

---

## 사용자에게 보여주기

- "**연차 사용 가능 여부 판단** 의사결정을 만들었어요 — 규칙 3개: '잔여일수·근속연수·직급 한도를 모두 충족 → 승인', '일부 미달 → 추가 서류 요청', '기준 미달 → 반려'. 인사 규정이 바뀌면 이 표만 수정하면 됩니다."
- 자연어 요약 위주.

## 다음 단계 연결

> "분기 판단 규칙을 정리했어요. 이제 각 단계에서 **사람이 입력할 양식(폼)** 을 만들 차례입니다."

→ [07-forms.md](07-forms.md) 로 5단계(폼)에 진입합니다.
