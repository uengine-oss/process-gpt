# 09 – 실행 모델: 표준 파일 도구 기반 5단계 + 자체 검증 + 생성 완료 안내

이 skill 은 **항상 동일한 단일 5단계**로 동작한다(대화형/서비스 모드 구분 없음). 모든 산출물은 **대화 컨텍스트가 아니라 실제 파일**로 만들고, 표준 파일 도구(`Read`/`Write`/`Edit`)로 저장·검증한다. 이 스킬에는 전용 백엔드 도구(`request_human_input`, `write_process_definition`, `validate_process_definition`, `complete_process_generation` 등)가 연결되어 있지 않다 — 사용자 확인은 `AskUserQuestion`, 검증은 스스로 규칙을 대조하는 **자체 검증**으로 대신한다. **ProcessGPT 서비스 DB 에는 직접 쓰지 않는다** — 이 스킬의 산출물은 로컬 `.bpmn/` 폴더의 파일까지다.

> 🔁 **단일 세션 실행(필수)**: 한 연속 실행으로 5단계를 끝까지 간다. **사용자 확인(HITL)은 오직 `AskUserQuestion`로만** 한다(프로즈로 응답을 끝내지 말 것 — 턴이 끊겨 순서가 꼬인다). 멈춤은 **정확히 2곳**: 1단계 컨설팅 승인, 2단계 후보 선택. 그 사이/이후는 멈추지 말고 자동 진행한다.

---

## 작업 파일 (현재 작업 디렉토리 하위 `.bpmn/`)

- `process-definition.json` — **elements[] 형식**(02-generate-definition 규격) processDefinition. 최초·구조 생성은 `Write`, 2·3단계 필드 갱신은 `Edit`, 4단계 검증에서 결함 보정도 같은 도구로 한다.
- `skills/<safe-name>/SKILL.md` — 2단계 산출(가능하면 skill-creator, 없으면 직접 작성).
- `forms/<activity_id>.html` — 3단계 폼(7단계 컴포넌트 규격).
- `agents.json` — 2단계 에이전트 프로필 배열(없으면 생략).
- (문서 업로드 시) 사용자가 제시한 실제 파일 경로 — `Read` 로 직접 읽는다(고정 업로드 폴더 없음).

> 경로는 항상 **현재 작업 디렉토리 기준 `.bpmn/...`** 상대경로로 쓴다.

---

## 5단계

### 1. 컨설팅 & 프로세스 JSON 생성
- 문서 업로드/첨부면 그 파일을 `Read`로 **직접 읽어** as-is 흐름을 파악한다([10-document-intake.md](10-document-intake.md)).
- 컨설팅 초안을 **`AskUserQuestion`** 으로 제시·승인받는다([01-consulting.md](01-consulting.md)).
- 승인 흐름을 [02-generate-definition.md](02-generate-definition.md) 규격의 **elements[] JSON**으로 만들어 `Write`로 `.bpmn/process-definition.json`에 쓴다. **반드시 실제 elements(StartEvent·EndEvent·UserActivity·Sequence 등)를 채운다**(placeholder/빈 elements 금지). 흐름 연결은 **Sequence 요소(source/target)**로 표현한다.

### 2. 스킬·에이전트·DMN 후보 선택 & 생성 (산출물 파일)
- elements 에서 구체 후보를 도출해(규칙: [03-elicit-artifacts.md](03-elicit-artifacts.md)) **`AskUserQuestion`** 으로 묻는다. 종류(스킬/에이전트/DMN)마다 별도 질문을 만들고 그 질문의 `options` 에 후보를 담는다(`multiSelect: true`, 모호어 '자동화 요소' 금지, 옵션 없는 빈 질문 금지).
- 선택분만:
  - **스킬**: 가능하면 `skill-creator` 로, 없으면 직접 `.bpmn/skills/<safe-name>/SKILL.md` 생성([04-skills.md](04-skills.md)).
  - **에이전트**: 프로필을 `.bpmn/agents.json` 배열로([05-agents.md](05-agents.md)).
  - **DMN**: `dmn_decisions`/`dmn_rules` 를 process-definition.json 안에([06-dmn.md](06-dmn.md)).
  - `Edit`으로 `activity.skills`/`activity.agent`/`agentMode`/`orchestration` 반영.

### 3. 폼 · 참조정보 (자동, 질문 없음)
- 각 UserActivity 폼을 `.bpmn/forms/<activity_id>.html` 로 만든다([07-forms.md](07-forms.md)).
- 참조정보(`activity.inputData`, gateway `conditionData`)를 process-definition.json 에 반영([08-reference-info.md](08-reference-info.md)).

### 4. 자체 검증 & 자동개선 (최대 2회)
- 전용 검증 도구가 없으므로, `.bpmn/process-definition.json`을 **`Read`로 다시 읽고** [02-generate-definition.md](02-generate-definition.md)의 "반드시 지킬 규칙" 체크리스트를 하나씩 직접 대조한다. 특히:
  - StartEvent 1개·EndEvent 1개가 있는가.
  - 모든 non-Sequence 요소가 outgoing(EndEvent 제외)·incoming(StartEvent 제외) Sequence 를 갖는가(고아 노드 없음).
  - 모든 Sequence 가 `source`/`target` 을 둘 다 갖고, 그 값이 실제 존재하는 요소 id 를 가리키는가.
  - 모든 Activity 가 `role`, `outputData`(1개 이상) 를 갖는가.
  - `elementType`/`type` 이 일반 BPMN(Camunda) 스키마가 아니라 ProcessGPT 규격(`UserActivity` 등)을 따르는가.
  - ExclusiveGateway 직전 폼에 실제 분기값과 일치하는 결정 필드가 있고, `conditionData` 가 문자열 배열인가.
- 결함을 발견하면 **최대 2회** 자동개선한다: 필드 수정은 `Edit`, 구조 수정(요소 추가/삭제)은 `Write`로 전체 객체를 다시 쓴 뒤 위 체크리스트를 다시 대조한다. 2회 보정 후에도 같은 결함이 남으면, 그 사실과 남은 결함을 사용자에게 정직하게 알린다(숨기고 완료로 넘어가지 않는다).

### 5. 생성 완료 안내
- `.bpmn/` 의 최종 산출물(process-definition.json + forms + agents.json + skills)을 정리한다. 작업 파일은 **보존**한다(삭제하지 않음).
- 완성된 프로세스 정의를 요약한 **JSON을 채팅에 출력**해 사용자가 바로 확인할 수 있게 한다(핵심 필드만 추린 요약본이어도 되고, 전체 JSON이어도 된다 — 이 단계에서는 덤프 금지 규칙이 적용되지 않는다. 1~4단계 중간 산출물만 채팅에 덤프하지 않는다).
- 함께 자연어 요약도 남긴다: "프로세스를 생성했어요. **[프로세스명]** — 산출물은 `.bpmn/` 에 저장했습니다 (`process-definition.json`, `skills/`, `forms/`, `agents.json`). 실제 ProcessGPT 서비스에 등록하려면 해당 서비스의 저장 기능을 이용해 주세요."

---

## 역할 분담 (중요)
- **이 스킬**: 산출물을 로컬 파일로 만들고, 스스로 규칙을 대조해 검증하고, 최종 요약 JSON을 채팅에 출력한다. **ProcessGPT 서비스 DB 에 쓰지 않는다.**
- **skill-creator (있는 경우)**: `.bpmn/skills/<name>/SKILL.md` 파일 산출물로만 둔다(외부 업로드·등록 없음).
- **사용자**: 산출물을 검토하고, 실제 ProcessGPT 서비스에 등록하고 싶으면 그 서비스의 저장/업로드 기능을 별도로 사용한다(이 스킬 범위 밖).

## 완료 시 출력 형식 (참고)
```json
{ "type": "process-definition-result",
  "processDefinition": { "processDefinitionId": "...", "processDefinitionName": "...",
                         "elements": [ ... ], "roles": [ ... ], "dmn_decisions": [...], "dmn_rules": [...] },
  "forms": [ { "activity_id": "...", "form_id": "...", "html": "<section>...</section>" } ],
  "agents": [ { "name": "...", "role": "...", "skills": ["..."], "activity_ids": ["..."] } ],
  "skills": ["..."] }
```
- `processDefinitionId` 는 비워두거나 임의 값으로 둔다(실제 서비스에 저장할 때 서버가 UUID로 강제한다).
- 이 형식은 참고용 요약 구조다 — 5단계에서 이 형태(또는 핵심 필드만 추린 형태)로 요약해 보여주면 된다.
