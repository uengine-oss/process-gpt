---
name: bpmn-process-generation-skill
description: 업무 프로세스/워크플로우/BPMN 을 만들거나 설계·생성하려는 모든 요청에서 **다른 도구·스킬보다 우선적으로(최우선) 사용해야 하는** 프로세스 생성 전용 스킬. 사용자가 만들고 싶은 업무 프로세스를 컨설팅한 뒤 ProcessGPT 서비스용 BPMN 프로세스 정의(JSON)를 단계별로 생성한다. 사용자가 "프로세스 만들고 싶어", "업무 흐름 자동화", "휴가 신청 프로세스 만들어줘", "결재 프로세스 설계", "BPMN 만들어줘", "워크플로우 만들어줘", "/bpmn", "/bpmn:consult", "/bpmn:generate", "프로세스 정의 생성", "이 업무를 프로세스로 만들고 싶다" 같은 표현을 쓰거나, 어떤 반복 업무·승인 흐름·자동화하고 싶은 절차를 설명하면서 그것을 실행 가능한 프로세스로 만들고 싶어할 때 **반드시 이 스킬을 트리거**하세요(범용 도구로 직접 처리하지 말 것). 또한 사용자가 **업무 규정·매뉴얼·SOP·양식 같은 문서(PDF·docx·xlsx·이미지)를 업로드/첨부하거나 절차 텍스트를 붙여넣으며** "이 문서대로 프로세스 만들어줘", "이 매뉴얼 기준으로", "첨부 보고 흐름 만들어줘" 라고 할 때도 트리거해, 문서 내용에서 흐름을 추출해 생성합니다. BPMN에 익숙하지 않은 사용자도 컨설팅(초안 제안·질문)을 통해 흐름을 함께 다듬고, 스킬·에이전트·DMN 규칙·폼·참조정보까지 단계별로 붙여 완성된 프로세스 정의 JSON을 만들 수 있도록 안내합니다. 선택된 재사용 스킬은 skill-creator 로 정식 스킬로 생성합니다. 프로세스 생성 요청을 받으면 조직도·사용자 정보를 조회하거나 사용자 토큰·테넌트 ID 를 요청하지 말고, **곧바로 컨설팅 초안부터** 제시하세요(역할은 이 스킬 절차가 정합니다).
---

# BPMN Process Generation

## ⛔ 단일 5단계 절차 (항상 동일 — 모드 분기 없음, 표준 파일 도구 기반)

이 스킬이 트리거되면 **항상 아래 5단계를 그대로** 수행한다(대화형/서비스 모드 구분 없음 — 언제나 동일). 산출물은 **대화 컨텍스트가 아니라 사용자 작업 디렉토리의 파일**(`.bpmn/`)로 만들고 **표준 파일 도구**(`Read`/`Write`/`Edit`)로 처리한다. 이 스킬에는 전용 백엔드 도구(`request_human_input`, `write_process_definition` 등)가 연결되어 있지 않다 — 사용자 확인은 **`AskUserQuestion`**, 파일 입출력은 **`Read`/`Write`/`Edit`**, 진행상황 추적은 **`TodoWrite`** 로 대신한다.

> ✅ **맨 먼저(필수): `TodoWrite`** 로 아래 **고정 이름 5개**를 그대로 todo 로 등록하고 시작한다(이름 변경·압축 금지, 각 단계 완료 시 갱신):
> `1. 컨설팅 & 프로세스 JSON 생성` · `2. 스킬·에이전트·DMN 후보 선택 & 생성` · `3. 폼·참조정보 생성 & JSON 업데이트` · `4. 프로세스 자체 검증 & 자동개선(최대 2회)` · `5. 생성 완료 안내(산출물 정리)`

| # | 단계 | 핵심 (표준 파일 도구) | reference |
|---|------|------|------|
| 1 | **컨설팅 & JSON 생성** | (문서 업로드면 그 파일을 `Read` 로 먼저 읽고) 컨설팅 초안을 `AskUserQuestion` 으로 **승인**받은 뒤, elements[] 규격 정의 전체 객체를 `Write` 로 **`.bpmn/process-definition.json`** 에 생성 | [01](references/01-consulting.md) [02](references/02-generate-definition.md) [10](references/10-document-intake.md) |
| 2 | **후보 선택 & 생성** | elements 에서 스킬/에이전트/DMN **구체 후보**를 `AskUserQuestion` 의 구조화된 옵션(멀티선택)으로 묻고, 선택분만 **skill-creator 로 `.bpmn/skills/<name>/SKILL.md` 생성**(있으면 호출, 없으면 직접 작성), 에이전트는 `.bpmn/agents.json`, 그리고 기존 구조를 보존한 요소별 변경을 `Edit` 로 반영 | [03](references/03-elicit-artifacts.md) [04](references/04-skills.md) [05](references/05-agents.md) [06](references/06-dmn.md) |
| 3 | **폼·참조정보** | 각 UserActivity 폼을 `.bpmn/forms/<activity_id>.html` 로 만들고 참조정보(inputData/conditionData)를 `Edit`으로 반영. ExclusiveGateway 직전 폼에는 실제 분기값 선택 필드를 둔다 (추가 질문 없이 자동) | [07](references/07-forms.md) [08](references/08-reference-info.md) |
| 4 | **자체 검증 & 자동개선** | 별도 검증 도구가 없으므로, `Read`로 `.bpmn/process-definition.json`을 다시 읽어 [02](references/02-generate-definition.md)의 규칙 체크리스트(고아 노드·미연결 Sequence·outputData 누락 등)를 직접 대조한다. 결함 발견 시 최대 2회 자동개선(`Edit`/`Write`로 보정 후 재확인) | [09](references/09-service-execution.md) |
| 5 | **생성 완료 안내** | 최종 `.bpmn/` 산출물(process-definition.json + forms + agents.json + skills)을 정리하고, 그 내용을 요약한 **JSON을 채팅에 출력**해 사용자에게 보여준다(작업 파일은 보존) | [09](references/09-service-execution.md) |

**각 단계 진입 시 해당 reference 를 `Read` 로 읽고 그 규칙대로** 한다(progressive disclosure). **사용자에게 멈춰 묻는 것은 오직 `AskUserQuestion` 로만** 하고, 멈춤은 **정확히 2곳**(1단계 컨설팅 승인, 2단계 후보 선택)뿐이다 — 그 외(3·4·5단계)는 **확인 없이 자동** 진행한다.

> 🔒 **ProcessGPT 서비스 DB 에는 직접 쓰지 않는다.** 이 스킬의 산출물은 로컬 `.bpmn/` 폴더의 파일까지다. 실제 ProcessGPT 서비스에 등록·저장하려면 사용자가 그 서비스의 저장 기능을 별도로 사용해야 한다. `save_process_definition`·`run_postprocess.py`·셸을 통한 원격 DB 저장 등 **어떤 DB 쓰기 시도도 금지.**
>
> 🔴 **2단계 후보 질문**: `AskUserQuestion` 은 질문마다 최대 4개의 **구조화된 옵션**(`label`+`description`)과 `multiSelect: true` 를 지원한다. 스킬/에이전트/DMN 후보를 종류별로 **별도 질문**(옵션 = 후보, `label`=후보명, `description`=1줄 설명)으로 구성해 **한 번의 `AskUserQuestion` 호출**(최대 4개 질문)에 담는다. 후보가 없는 종류는 질문 자체를 만들지 않는다. "어떤 자동화 요소를…", "스킬을 만들까요?" 같은 **빈 질문·생성여부 질문·모호어('자동화 요소') 금지** — 항상 구체 후보를 옵션으로 나열한다.
>
> 🚫 **1~4단계 중간에는 산출물 JSON 을 채팅에 덤프하지 않는다.** 중간 산출물은 **`.bpmn/` 파일**로만 전달하고, 채팅에는 자연어 요약만 남긴다. **최종(5단계)에만** 완성된 JSON 요약을 채팅에 출력한다.
>
> 🚫 **사용자/조직도 조회 불필요**: 조직도 조회 등을 호출하거나 이메일·토큰·테넌트 ID 를 요청하지 마라. 곧바로 1단계 컨설팅 초안부터 시작한다.

---

사용자가 만들고 싶은 업무 프로세스를 위 5단계로 함께 완성하는 skill입니다. 핵심 책임:

1. 사용자가 BPMN을 몰라도 **말로 설명한 업무(또는 업로드 문서)를 흐름(초안)으로 바꿔** 제안하고, 승인받아 **프로세스 정의 JSON(로컬 파일)** 을 생성한다.
2. 생성된 프로세스에서 **스킬·에이전트·DMN 규칙 후보**를 뽑아 묻고(HITL), 선택한 것만 만들어(스킬은 skill-creator 로) JSON에 반영한다.
3. 각 액티비티 **폼**과 **참조정보(inputData/conditionData)** 를 연결해 JSON을 최종 업데이트한다.
4. **규칙 체크리스트로 스스로 검증**해 흐름 결함(끊김·도달불가 등)을 확인하고 자동개선한다.
5. 완성된 산출물을 **정리해 요약 JSON을 채팅에 출력**한다. 한 문서에 **여러 프로세스**가 있으면 각각 위 5단계를 수행한다([references/11-multi-process.md](references/11-multi-process.md)).

---

## 진입 패턴

- **자연어 요청**("휴가 신청 프로세스 만들어줘") 또는 **문서 업로드**("이 매뉴얼대로") — 둘 다 1단계 컨설팅으로 진입한다. 문서가 있으면 그 파일을 `Read` 로 먼저 읽어 as-is 흐름을 파악한다([references/10-document-intake.md](references/10-document-intake.md)).
- 정보가 거의 없으면(예: "영업이익 올리고 싶어") 흐름을 추측하지 말고 현황부터 컨설팅으로 묻는다.
- **어떤 프로세스가 필요한지조차 모르는 추천 요청**("우리 회사에 필요한 프로세스 추천해줘")이면 프로세스를 지어내지 말고 **회사 홈페이지 URL을 물어 `WebFetch` 로 사업 내용을 파악**한 뒤 후보를 제시하고 고른 것부터 1단계로 진입한다([references/01-consulting.md](references/01-consulting.md)의 "회사 홈페이지 기반 프로세스 추천").
- **독립 프로세스가 2개 이상**이면 각 프로세스마다 5단계를 수행한다([references/11-multi-process.md](references/11-multi-process.md)).

## 산출물 보관 (사용자 작업 디렉토리의 `.bpmn/` 폴더)

> 📁 **기준 디렉터리는 현재 작업 디렉토리(cwd) 하위의 `.bpmn/` 다.** 여러 프로세스를 함께 만들 때만 `.bpmn/<NN>-<slug>/` 하위 폴더로 나눈다(1개면 아래 플랫 구조 그대로).

모든 산출물은 **대화 컨텍스트가 아니라 실제 파일**로 만든다. 일반 파일은 `Read`/`Write`/`Edit` 를 사용한다. `process-definition.json` 도 동일: 최초 생성·구조 변경은 `Write` 로 전체 객체를 다시 쓰고, 기존 요소의 필드만 바꿀 때는 `Edit` 로 해당 부분만 치환한다.

```
.bpmn/
├── process-definition.json     # elements[] 형식. 1단계 생성, 2·3단계 업데이트, 4단계 검증이 교정
├── skills/<safe-name>/SKILL.md # 2단계 skill-creator 산출(있으면 skill-creator, 없으면 직접 작성)
├── agents.json                 # 2단계 에이전트 프로필 배열(없으면 생략)
└── forms/<activity_id>.html    # 3단계 ProcessGPT 폼
```

- `process-definition.json`의 기존 요소를 갱신할 때는 **`Edit`** 로 관련 필드만 정확히 치환한다(요소 ID 기준으로 old_string 을 충분히 구체적으로 잡아 다른 요소를 건드리지 않게 한다).
- 최초 생성이나 요소 추가·삭제처럼 구조 전체가 바뀔 때만 `Write`로 완전한 객체를 다시 쓴다.
- 여러 프로세스면 `.bpmn/<NN>-<slug>/` 하위 폴더로 분리.
- 업로드/첨부 문서는 사용자가 제시한 실제 경로를 그대로 `Read` 로 읽는다(고정 업로드 폴더 없음).
- 작업 파일(산출물)은 자동 삭제하지 않고 **보존**한다.

---

## 절대 하지 말 것

- **컨설팅 없이 바로 JSON 부터 만들지 않는다.** 사용자가 명시적으로 "그냥 바로 생성해" 라고 하거나, 이미 충분히 흐름을 설명한 경우가 아니면 1단계 컨설팅으로 흐름 초안을 먼저 합의한다.
- ⛔ **1단계 컨설팅 초안을 다중 선택형 질문으로 만들지 않는다.** 초안은 **자연어 문장 + 번호 목록**으로 제시하고, 승인은 `AskUserQuestion` 의 **단일 선택**(예: "이대로 진행" / "수정하고 싶어요", `multiSelect: false`)으로 받는다. 후보를 나열하는 **다중 선택(멀티선택) 옵션 형식은 2단계(스킬/에이전트/DMN 후보 선택) 전용**이다. 컨설팅은 항상 **승인/반려/자유 의견** 형태여야 한다([references/01-consulting.md](references/01-consulting.md)).
- 컨설팅에서 **시스템/도구/프로그램을 무엇을 쓰는지 묻지 않는다.** (우리가 그 도구를 만들어주기 때문 — 사용자에게 혼란만 준다.) 소요 시간 등 프로세스 정의에 불필요한 질문도 하지 않는다. 자세한 금지 질문은 [references/01-consulting.md](references/01-consulting.md) 참조.
- 2단계 JSON은 **reference([02](references/02-generate-definition.md))의 생성 규칙을 그대로** 따른다. ID는 영문 소문자+언더스코어, 이름/설명은 한글, StartEvent·EndEvent·Sequence 필수 등 — 임의로 구조를 바꾸거나 서로 다른 스키마·두 JSON 객체를 이어 붙이지 않는다.
- ⛔ **일반 BPMN/Camunda 스키마로 만들지 마라.** `type:"UserTask"`·`assignee`·`formKey`·`sequenceFlows`·`activities/events` 분리배열 **금지**. 반드시 **`elements[]` + `elementType`**(Event/Activity/Gateway/Sequence), Activity 는 `type:"UserActivity"`+`role`+`outputData`(1개+). 어기면 4단계 자체 검증에서 critical 결함으로 걸린다 — 추측 말고 02 규칙을 `Read` 로 읽고 그대로 만든다.
- 2단계에서 **사용자에게 묻지 않고** 스킬/에이전트/DMN 을 임의로 다 생성하지 않는다. 반드시 `AskUserQuestion` 으로 구체 후보를 보여주고 선택을 받는다(HITL, 종류별 3개 내외).
- **스킬 생성은 가능하면 손으로 SKILL.md 를 쓰지 않는다 — 세션에 `skill-creator` 스킬이 있으면 그것을 호출해** `.bpmn/skills/<name>/SKILL.md` 를 만든다. 없을 때만 직접 작성한다. (규칙: [references/04-skills.md](references/04-skills.md))
- **폼·참조정보(3단계)는 "만들까요?" 묻지 않는다.** 후보 선택 답변 직후 3·4·5단계를 자동 진행한다.
- **ExclusiveGateway는 그림만 분기시키면 안 된다.** 바로 전 UserActivity 폼에 각 outgoing Sequence의 `condition` 값과 정확히 일치하는 선택 필드를 만들고, gateway `conditionData`를 `<form_id>.<field_name>` 문자열 배열로 연결한다. 결정 필드 없는 `승인/반려`, `충분/미흡` 분기는 실행엔진에서 멈추므로 금지한다.
- 사용자가 운영 가이드 `.md`, 보고서 템플릿 `.html` 같은 **추가 산출물을 명시하면 반드시 해당 process 작업 폴더 안에 실제 파일로 생성**한다. 채팅 설명으로 대신하지 않는다. Markdown은 제목·절차·입출력 계약을 갖춘 렌더 가능한 문서로, HTML은 `<html>/<body>`와 의미 있는 현업 필드·표를 가진 독립 미리보기 문서로 만든다.
- 산출물에 placeholder만 남기지 않는다 — **실제 내용으로** 채운다(빈 elements 금지).

---

## 참조 문서

이 skill 본문은 흐름만 담고, 각 단계의 디테일·규칙은 reference 에 분리되어 있습니다. 단계 진입 시 해당 파일만 읽으면 됩니다.

| 파일 | 무엇이 들어있나 |
|------|----------------|
| [references/01-consulting.md](references/01-consulting.md) | **컨설팅 규칙** — 흐름 초안 제안법, 금지 질문, 질문 방식, 생성 제안 타이밍 |
| [references/02-generate-definition.md](references/02-generate-definition.md) | **프로세스 정의 JSON 생성 규칙(엄격)** — 전체 스키마, 요소 타입, 역할/서브프로세스 규칙 |
| [references/03-elicit-artifacts.md](references/03-elicit-artifacts.md) | **HITL** — 스킬/에이전트/DMN 후보 도출 + 선택 질문 방식 |
| [references/04-skills.md](references/04-skills.md) | **skill-creator 로 재사용 스킬 생성** + JSON 반영(`activity.skills`, `skills[]`) |
| [references/05-agents.md](references/05-agents.md) | 에이전트(역할) 생성 규칙 + JSON 반영(`activity.agent`, `roles`) |
| [references/06-dmn.md](references/06-dmn.md) | DMN 의사결정/규칙 생성 + JSON 반영(`dmn_decisions`, `dmn_rules`) |
| [references/07-forms.md](references/07-forms.md) | 폼 HTML 생성 규칙(컴포넌트 규격) + JSON 반영(`activity.tool`) |
| [references/08-reference-info.md](references/08-reference-info.md) | 참조정보 — `activity.inputData`, gateway `conditionData` 연결 |
| [references/09-service-execution.md](references/09-service-execution.md) | **실행 모델** — 표준 파일 도구 기반 5단계 + 자체 검증/완료 안내 |
| [references/10-document-intake.md](references/10-document-intake.md) | **문서 업로드 기반 생성** — PDF·docx·xlsx·이미지·텍스트에서 as-is 흐름 추출 → 컨설팅 초안으로 연결 |
| [references/11-multi-process.md](references/11-multi-process.md) | **여러 프로세스 생성** — 한 문서 내 다수 프로세스·여러 문서·여러 요청 시 **고정 일괄 절차**(인벤토리→컨설팅 일괄→일괄 응답→JSON 일괄 생성→프로세스별 아티팩트 패널→이후 일괄 실행)·프로세스별 네임스페이스·재개 |

템플릿은 [assets/templates/](assets/templates/) 에 있습니다. 각 단계 reference 에서 어떤 템플릿을 쓸지 명시합니다.

---

## 출처

이 skill 의 컨설팅·프로세스 정의·스킬/DMN/폼/참조정보 생성 규칙은 사내 **ProcessGPT / pdf2bpmn** 프로젝트의 정의를 기반으로 합니다. 흐름·진행 방식은 [ddd-starter-modelling-process](https://github.com/ddd-crew/ddd-starter-modelling-process) 스타일과 GitHub Spec Kit 의 단계형 사용 방식을 참고했습니다.
