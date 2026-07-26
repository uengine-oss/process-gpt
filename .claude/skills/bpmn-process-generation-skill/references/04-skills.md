# 04 – Skills: skill-creator 로 재사용 스킬 생성 + JSON 반영

> 📁 **경로 주의**: 아래의 모든 `.bpmn/...` 는 **현재 작업 디렉토리(cwd) 하위의 `.bpmn/`** 를 뜻한다(여러 프로세스면 `.bpmn/<NN>-<slug>/`). skill-creator 를 호출할 때도 **출력 위치를 그 디렉터리 하위(`skills/<safe-name>/SKILL.md`)로 지정**한다.

**목적**: 3단계에서 사용자가 고른 스킬 후보를, **`skill-creator` 스킬을 사용해 정식 Claude 스킬(SKILL.md 구조)로 생성**하고, 프로세스 정의 JSON 의 해당 Activity 와 `skills` 목록에 연결한다.

  **업그레이드 노트 (중요).** pdf2bpmn 원본에서는 이 단계가 단순 LLM 호출(템플릿 채우기) 한 번으로 스킬 카드 텍스트만 뽑았습니다. 이 skill 에서는 그 부분을 **`skill-creator` 사용으로 대체**합니다. 즉, 프로세스의 활동(activity)에서 "이 스킬이 무엇을·언제·어떻게 하는지"를 자동으로 정리한 뒤, 그 의도를 skill-creator 에 넘겨 **실제로 재사용 가능한 스킬 디렉토리**(SKILL.md + 필요한 references)를 만들게 합니다. 이렇게 하면 결과 스킬이 progressive disclosure·트리거용 description·번들 리소스 같은 스킬 작성 모범사례를 갖추게 됩니다.

산출물:
- `.bpmn/skills/<safe-name /SKILL.md` (skill-creator 가 생성한 정식 스킬, 선택된 스킬마다 1개 디렉토리)
- `process-definition.json` 업데이트 (`skills[]` 추가 + 관련 `activity.skills` 채움)

  **항상 동일(단일 모드).** 스킬은 **가능하면 skill-creator 로 `.bpmn/skills/<safe-name>/SKILL.md` 파일을 생성**(단계 B)한다 — 이 파일이 곧 산출물이며 **외부 업로드·DB 저장은 하지 않는다.** 그런 다음 단계 C에서 `skills[]`·`activity.skills`를 `Edit`으로 반영한다.

---

## 단계 A. 스킬 의도(intent) 정리 — 프로세스에서 자동 추출

skill-creator 는 보통 사용자 인터뷰로 "무엇을 하는 스킬인지"를 캡처한다. 하지만 **여기서는 그 의도를 이미 프로세스가 담고 있다.** 사용자에게 다시 묻지 말고, 근거가 된 Activity 들(`source_activity_ids`)의 `name`/`description`/`instruction` 을 종합해 아래 **스킬 브리프**를 채운다. 이 브리프가 곧 skill-creator 의 "Capture Intent" 입력이 된다.

| 필드 | 규칙 |
|------|------|
| `safe_name` | 영문 소문자 + 하이픈(kebab-case), 3~6 단어. 한글/공백/특수문자 금지. 예: `leave-balance-check`. **이 값이 스킬 디렉토리 이름이자 슬래시 호출명**이 된다. |
| `name` | 도메인 의미가 분명한 **한국어 명사구**. "공통지침", "기타", "스킬", "절차" 같은 일반·형식적 단어 금지. 예: "휴가 잔여일수 검증" |
| `description` | frontmatter 용. **무엇을 + 언제 트리거하는지** 구체적으로. (트리거 정확도를 위해 다소 "적극적"으로 쓴다 — skill-creator 의 description 작성 지침을 따른다.) |
| `summary` | 3~5 문장 개요. 무엇을, 왜, 어떤 산출물로 만드는지. |
| `when_to_use` | 사용 시점/트리거를 질문·조건 형태로 4~6개. |
| `inputs` | 필요한 입력/사전 조건(서류·레코드·결과코드 등 명사구) 3~5개. |
| `outputs` | 결과물/산출물 2~4개. |
| `procedure` | 단계별 절차 4~7단계. 각 단계 `{ title(한국어 짧은 제목), detail(2~4문장 구체 설명) }`. |
| `examples` | 구체 시나리오 1~2개. 각 `{ scenario, input, output }` 모두 한국어. |
| `notes` | 운영 시 주의/제약/정책 3~5개. |

safe_name 이 겹치면 `-2`, `-3` 접미사를 붙여 유일하게 만든다.

  참고 템플릿: 브리프의 절차/예시/주의 항목을 정리할 때 [assets/templates/skill-card.md](../assets/templates/skill-card.md) 의 섹션 구성을 그대로 활용하면 skill-creator 에 넘길 본문이 깔끔하게 정리된다.

---

## 단계 B. skill-creator 로 스킬 생성 (반드시 호출)

  **이 단계의 단일 규칙: 스킬은 직접 손으로 쓰지 말고 `skill-creator` 스킬을 호출해 만든다.** 이게 이번 업그레이드의 핵심 이유다 — 손으로 SKILL.md 를 흉내 내면 progressive disclosure·트리거 설명·번들 구조 같은 모범사례가 누락되고, "skill-creator 를 썼다"는 약속이 깨진다. 아래 절차를 그대로 따른다.

### B-0. 먼저 사용 가능 여부를 **확인**한다 (건너뛰지 말 것)
스킬 생성을 시작하기 전에, 현재 세션의 **사용 가능한 스킬 목록**에 `anthropic-skills:skill-creator`(또는 동등한 `skill-creator`)가 있는지 확인한다.
- **있으면 → 반드시 B-1 의 Skill 도구 호출로 만든다. 손으로 SKILL.md 를 작성하지 않는다.** "내가 직접 써도 결과가 같다"는 이유로 fallback 을 택하지 않는다. 약속한 동작은 *skill-creator 호출* 이다.
- **정말로 목록에 없을 때만 → B-2 fallback** 으로 간다.
- 어느 쪽을 택했든 단계 C 이후 사용자 보고에서 **어떤 경로로 만들었는지 한 줄로 밝힌다**(아래 "사용자에게 보여주기"). 추정하지 말고 실제로 한 행동을 그대로 말한다.

### B-1. skill-creator 호출 (기본 경로)
선택된 각 스킬마다 **`anthropic-skills:skill-creator` 를 Skill 도구로 호출**해 `.bpmn/skills/<safe-name /` 에 정식 스킬을 만든다. skill-creator 의 **"Creating a skill" 절차**를 따르되, 호출 시 다음을 명확히 지시한다:

- **Capture Intent / Interview 는 생략.** 의도는 단계 A 의 스킬 브리프로 이미 확보됐다. 사용자에게 다시 인터뷰 질문을 하지 않는다. (프로세스 생성 흐름 중간이므로 사용자를 다시 붙잡지 않는 게 중요하다.) → 단계 A 브리프 전체를 skill-creator 에 입력으로 넘긴다.
- **출력 위치**: `.bpmn/skills/<safe-name /SKILL.md` (필요하면 `references/` 도 그 아래에).
- **frontmatter**: `name` 은 한국어 스킬명, `description` 은 단계 A 에서 정한 트리거 지향 설명.
- **본문**: 단계 A 브리프의 `summary`/`when_to_use`/`inputs`/`outputs`/`procedure`/`examples`/`notes` 를 skill-creator 의 작성 패턴(명령형 지시, 예시 패턴, progressive disclosure)으로 풀어 쓰게 한다.
- **평가 루프(evals)·벤치마크는 생략(기본)**. 프로세스 생성 흐름을 끊지 않기 위해 기본적으로 만들지 않는다. **단, 사용자가 "이 스킬 제대로 테스트해줘"처럼 명시적으로 요청하면** 그때 skill-creator 의 eval 루프를 돌린다.

생성된 스킬의 마지막에 **출처(Source Activities)** 정보를 남긴다(추적용): `coverage`(근거 활동 수), `activities`(activity id 목록), `canonical`(대표 원문 문장).

  스킬이 여러 개면 각각에 대해 skill-creator 를 호출한다. (한 번의 호출로 여러 스킬을 묶어 만들 수 있으면 그렇게 해도 되지만, 각 스킬이 자기 디렉토리 `.bpmn/skills/<safe-name /SKILL.md` 로 떨어져야 한다.)

### B-2. Fallback — skill-creator 가 **사용 불가일 때만**
B-0 확인에서 skill-creator 가 목록에 **정말 없을 때만** 사용한다. (있는데 fallback 을 쓰는 것은 규칙 위반이다.) 이 경우 skill-creator 의 작성 원칙을 직접 적용해 `.bpmn/skills/<safe-name /SKILL.md` 를 만든다. 구조는 [assets/templates/skill-card.md](../assets/templates/skill-card.md) 의 섹션을 따르되, 파일은 **디렉토리 안 SKILL.md** 로 저장한다(슬래시 호출·자동 트리거가 되도록). 그리고 사용자 보고에 **"skill-creator 가 환경에 없어 fallback 으로 직접 작성했다"**고 밝힌다.

```markdown
---
name: "휴가 잔여일수 검증"
description: "신청 전 신청자의 잔여 연차를 확인해 신청 가능 여부를 판단한다. '휴가 신청', '연차 확인', '잔여일수' 같은 맥락에서 사용하라."
---

# 휴가 잔여일수 검증

## 개요
(summary 3~5문장)

## 사용 시점
- (when_to_use 항목들)

## 입력 / 사전 조건
- (inputs 항목들)

## 산출물
- (outputs 항목들)

## 절차
### 1. (title)
(detail)
### 2. (title)
(detail)
...

## 실전 예시
### 예시 1: (scenario)
- 입력: (input)
- 산출: (output)

## 주의사항
- (notes 항목들)

## 출처 (Source Activities)
- coverage: (근거 활동 수)
- activities: (activity id 목록)
- canonical: (대표 원문 문장)
```

---

## 단계 C. 프로세스 정의 JSON 반영

`Edit`으로 아래 필드를 요소 ID 기준 갱신한다 ([02-generate-definition.md](02-generate-definition.md)의 변경 규칙 준수):

1. **최상위 `skills` 배열에 추가** (없으면 만든다). 각 항목:
   ```json
   { "id": "<safe_name ", "name": "<한국어 스킬명 ", "description": "<요약 " }
   ```
   - `id` 는 단계 A 의 `safe_name` 과 **정확히 일치**(= 스킬 디렉토리 이름). 이 값으로 `.bpmn/skills/<safe_name /` 를 역추적할 수 있어야 한다.
2. **근거 Activity 의 `skills` 에 그 스킬 id 추가**:
   ```json
   "skills": ["leave-balance-check"]
   ```
   - `source_activity_ids` 에 든 모든 Activity 에 해당 스킬 id 를 넣는다.
3. 스킬이 배정된 Activity 는 자동화 정책상 다음을 함께 설정한다(있으면 유지, 없으면 추가):
   ```json
   "agentMode": "complete",
   "orchestration": "deepagents"
   ```

  메인 `elements` 의 Activity 와, (서브프로세스가 있다면) 서브프로세스 `children.activities` 양쪽 모두에서 id 가 일치하는 항목에 반영한다.

---

## 사용자에게 보여주기

- 만든 스킬마다 한 줄 요약 + **생성 경로 명시**: "**휴가 잔여일수 검증** — 신청 전 잔여 연차 확인 (활동 2개에 연결). *skill-creator 로 생성*: `.bpmn/skills/leave-balance-check/SKILL.md`"
- **정직하게 보고한다.** skill-creator 를 실제로 호출했으면 "skill-creator 로 생성", fallback 으로 직접 작성했으면 "skill-creator 미설치로 직접 작성(fallback)" 이라고 사실대로 적는다. 한 게 아닌 것을 했다고 말하지 않는다.
- raw JSON 을 들이밀지 말고 자연어로.

## 다음 단계 연결

3단계에서 에이전트/DMN 도 골랐으면 그 단계로, 아니면:

  "스킬을 붙였어요. 다음은 [에이전트 연결 / DMN 규칙 / 폼 생성] 입니다."

처리 순서대로 [05-agents.md](05-agents.md) → [06-dmn.md](06-dmn.md) → [07-forms.md](07-forms.md) 로 이어집니다.
