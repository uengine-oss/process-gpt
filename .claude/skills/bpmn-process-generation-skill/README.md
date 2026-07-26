# BPMN Process Generation — Claude Code Skill

> 만들고 싶은 업무를 **컨설팅 → 프로세스 정의(JSON) 생성 → 스킬/에이전트/DMN 선택 생성 → 폼 → 참조정보** 순서로 Claude Code와 함께 만들어가는 skill.
> 사내 **ProcessGPT / pdf2bpmn** 프로젝트의 컨설팅·생성 규칙을 따르고, 진행 방식은 GitHub Spec Kit 의 단계형 사용법을 참고했습니다.

---

## 이 skill은 무엇인가

BPMN을 몰라도, "휴가 신청 프로세스 만들어줘" 같은 한마디만으로 **실행 가능한 프로세스 정의(JSON)** 를 만들 수 있게 안내합니다. Claude가 먼저 흐름 초안을 제안하고, 최소한의 질문으로 함께 다듬은 뒤, ProcessGPT 서비스 규격의 JSON을 생성합니다. 이어서 자동화 요소(재사용 스킬·에이전트·DMN 규칙)를 *고른 것만* 붙이고, 입력 폼과 참조정보까지 연결해 완성합니다.

각 단계의 산출물은 사용자 작업 디렉토리의 `.bpmn/` 폴더에 저장되어 다음 단계의 입력이 됩니다.

**핵심 특징**:
- BPMN 초심자도 따라갈 수 있도록 용어를 풀어 설명 (액티비티=사람이 하는 일 한 단계, 게이트웨이=갈림길 등)
- 흐름은 유연하게(컨설팅), 출력 구조는 엄격하게(서비스 규격 JSON 그대로)
- 스킬/에이전트/DMN은 **사용자가 고른 것만** 생성 (HITL)
- **문서 업로드 기반 생성**: 업무 규정·매뉴얼·SOP·양식(PDF·docx·xlsx·이미지)을 올리면 그 내용에서 흐름을 추출해 프로세스로 만듦
- **여러 프로세스 한 번에**: 한 문서에 별개 프로세스가 여러 개거나 여러 문서/여러 요청이면 **고정 일괄 절차**로 진행 — 만들 프로세스 선택 → 모든 프로세스 컨설팅 일괄 → 일괄 응답 → JSON 일괄 생성 → 프로세스별 아티팩트 패널 → 이후 일괄 실행 (프로세스별 `.bpmn/<NN>-<slug>/` 네임스페이스, 아티팩트 선택은 프로세스마다 별도 패널로 HITL 유지)
- **선택된 재사용 스킬은 skill-creator 로 정식 스킬로 생성** (단순 텍스트 카드가 아니라 SKILL.md 구조의 실제 스킬)

> 검증(validation) 단계는 이 skill 범위에서 제외합니다. 검증·실행이 필요하면 ProcessGPT 본 서비스로 진행하세요.

---

## 설치

Claude Code는 `~/.claude/skills/<skill-name>/SKILL.md` 위치의 skill을 자동 인식합니다.

### 방법 1: git clone (권장)

```bash
git clone https://github.com/<owner>/bpmn-process-generation.git ~/.claude/skills/bpmn-process-generation
```

> Windows: `%USERPROFILE%\.claude\skills\bpmn-process-generation` 로 클론하세요.

### 방법 2: zip 다운로드 후 복사

1. 이 repo의 zip을 다운로드 → 압축 해제
2. 폴더 이름이 `bpmn-process-generation` 이 되도록 정리 후 `~/.claude/skills/` 안에 이동

### 설치 확인

설치 후 Claude Code를 재시작(또는 새 세션)한 다음 자연어로 호출:

```
휴가 신청 프로세스 만들고 싶어
```

흐름 초안 제안 또는 짧은 질문이 시작되면 성공입니다.

### 디렉토리 구조

```
~/.claude/skills/bpmn-process-generation/
├── README.md                        # 이 문서
├── SKILL.md                         # skill manifest (Claude Code가 읽음)
├── references/                      # 단계별 디테일 가이드
│   ├── 00-orientation.md
│   ├── 01-consulting.md
│   ├── 02-generate-definition.md
│   ├── 03-elicit-artifacts.md
│   ├── 04-skills.md
│   ├── 05-agents.md
│   ├── 06-dmn.md
│   ├── 07-forms.md
│   ├── 08-reference-info.md
│   ├── 09-service-execution.md      # 서비스(deepagent) 실행 모드 출력 계약
│   ├── 10-document-intake.md        # 문서 업로드 → 흐름 추출
│   └── 11-multi-process.md          # 여러 프로세스 고정 일괄 절차·네임스페이스
└── assets/
    └── templates/
        ├── process-definition.schema.json
        ├── skill-card.md
        └── form-components.md
```

**중요**: `SKILL.md`, `references/`, `assets/` 가 모두 `~/.claude/skills/bpmn-process-generation/` 안에 있어야 합니다.

---

## 빠른 시작

Claude Code 세션에서 자연어로 트리거 (자동 인식):

```
비품 구매 결재 프로세스 만들어줘
```
```
신규 입사자 온보딩 흐름을 자동화하고 싶어
```
```
BPMN 프로세스 만들어줘
```

호출하면:
1. **컨설팅** — Claude가 흐름 초안을 제안하고, 핵심만 한두 가지 질문 (시스템·도구·소요시간은 묻지 않습니다)
2. 동의하면 **프로세스 정의 JSON** 생성 (`.bpmn/process-definition.json`)
3. **스킬/에이전트/DMN 후보**를 보여주고 무엇을 만들지 선택 (안 골라도 됨)
4. **폼**과 **참조정보** 연결 → 완성

---

## 전체 흐름 개요

| # | 단계 | 무엇을 하나 | 산출물 |
|---|------|------------|--------|
| 0 | Orientation | 진입 패턴 판별, 초심자/숙련자 모드 결정 | (없음) |
| 1 | Consulting | 흐름 초안 제안 + 핵심 질문으로 다듬기 | `.bpmn/01-consulting.md` |
| 2 | Generate Definition | 승인된 초안을 프로세스 정의 JSON 으로 생성 | `.bpmn/process-definition.json` |
| 3 | Elicit Artifacts | 스킬/에이전트/DMN 후보 제시 → 선택 (HITL) | (사용자 선택) |
| 4 | Build Artifacts | 선택된 스킬/에이전트/DMN 생성 + JSON 반영 | `.bpmn/skills/*.md` + JSON |
| 5 | Forms | 각 액티비티 입력 폼 생성 + JSON 반영 | `.bpmn/forms/*.html` + JSON |
| 6 | Reference Info | inputData/conditionData 참조 연결 | JSON 최종 업데이트 |

> 한 단계가 끝나면 자동으로 요약 + 다음 단계 제안. 사용자 동의 후 진행.

---

## 산출물 구조

전체 산출물은 사용자 작업 디렉토리의 `.bpmn/` 폴더에 저장됩니다:

```
.bpmn/
├── 01-consulting.md            # 컨설팅 요약 + 합의된 흐름 초안
├── process-definition.json     # 메인 산출물. 2단계 생성, 4~6단계에서 계속 업데이트
├── skills/                     # 4단계에서 생성된 스킬 카드
│   └── <safe-name>.md
└── forms/                      # 5단계에서 생성된 폼 HTML
    └── <activity_id>.html
```

`process-definition.json` 은 **하나의 파일을 단계마다 업데이트**합니다.

**여러 프로세스일 때**는 충돌을 막기 위해 프로세스별 하위 폴더로 나뉩니다(1개면 위 플랫 구조 그대로):

```
.bpmn/
├── index.md                     # 프로세스 인벤토리 + 진행상태 표
├── 01-<slug>/                   # 프로세스 1
│   ├── 01-consulting.md
│   ├── process-definition.json
│   ├── skills/
│   └── forms/
└── 02-<slug>/                   # 프로세스 2 …
```

---

## 초심자 vs 숙련자 모드

기본은 **초심자 모드**. "BPMN 익숙해, 용어 설명 빼" 라고 명시하면 숙련자 모드로 전환됩니다.

| 항목 | 초심자 모드 | 숙련자 모드 |
|------|------------|------------|
| 용어 설명 | 처음 등장 시 30자 정의 병기 | 생략 |
| 흐름 표시 | 항상 "1. ~ / 2. ~" 자연어 | 필요시 JSON 직접 |
| 결과 | 자연어 요약 위주 | raw JSON 노출 가능 |

---

## 팁과 주의사항

### 잘 사용하는 방법
- 한 단계씩 검토하며 진행하세요. 컨설팅 초안에 동의한 뒤 생성으로 넘어갑니다.
- "그냥 바로 만들어줘" 라고 하면 컨설팅을 짧게 마치고 생성합니다. 단 정보가 너무 부족하면 핵심 질문 1~2개는 받습니다.
- 산출물을 직접 편집해도 OK. 다음 세션에서 "이어서 하자" 하면 `.bpmn/` 상태부터 재개합니다.

### 피해야 할 패턴
- 컨설팅 없이 바로 JSON부터 만들지 않기.
- 스킬/에이전트/DMN을 사용자에게 묻지 않고 다 만들지 않기 (HITL 필수).
- 모든 단계를 한꺼번에 몰아서 진행하지 않기.
- placeholder만 남기지 않기 — 실제 내용으로 채우기.

---

## 출처

이 skill의 컨설팅·프로세스 정의·스킬/DMN/폼/참조정보 생성 규칙은 사내 **ProcessGPT / pdf2bpmn** 프로젝트의 정의를 기반으로 합니다. 흐름·진행 방식은 [ddd-crew/ddd-starter-modelling-process](https://github.com/ddd-crew/ddd-starter-modelling-process) 스타일과 GitHub Spec Kit 의 단계형 사용법을 참고했습니다.

각 단계의 디테일은 [references/](references/) 에, 산출물 템플릿은 [assets/templates/](assets/templates/) 에 있습니다.
