# 07 – Forms: 액티비티 입력 폼(HTML) 생성 + JSON 반영

> 📁 **경로 주의**: 아래 `.bpmn/forms/...` 는 **현재 작업 디렉토리(cwd) 하위의 `.bpmn/forms/`** 를 뜻한다(여러 프로세스면 `.bpmn/<NN>-<slug>/forms/`).

**목적**: 각 UserActivity 에서 사람이 입력할 **폼(HTML)** 을 만든다. 폼은 정해진 컴포넌트 태그와 그리드 규칙을 그대로 따라야 한다(프론트가 이 규격으로 렌더). 만든 폼을 Activity 의 `tool` 에 `formHandler:<form_id>` 로 연결한다.

> 이 규칙은 pdf2bpmn 의 폼 생성기(FormDesignGenerator 스타일) 컴포넌트 규격을 옮긴 것입니다. 전체 컴포넌트 목록은 [assets/templates/form-components.md](../assets/templates/form-components.md) 참조.

산출물:
- `.bpmn/forms/<activity_id>.html` (Activity 마다 1개)
- `process-definition.json` 업데이트 (`activity.tool = "formHandler:<form_id>"`)

---

## 폼을 만들 대상

- 메인 흐름의 모든 **UserActivity** 에 폼 1개. (서브프로세스 children.activities 도 동일.)
- Event/Gateway/Sequence 에는 폼이 없다.
- 폼은 **반드시 존재**해야 한다 — 태스크 정보가 부족하면 "자유 입력(Free Input)" textarea 하나라도 만든다(빈 폼 금지).

---

## 레이아웃 규칙 (그리드)

```html
<section>
  <div class='row' name='<unique_layout_name>' alias='<레이아웃 표시명>' is_multidata_mode='false'>
    <div class='col-sm-6'>
      <!-- 컴포넌트 -->
    </div>
    <div class='col-sm-6'>
      <!-- 컴포넌트 -->
    </div>
  </div>
</section>
```

- `section` 안에는 `class='row'` 인 div 가 **정확히 하나**.
- `row` 안에는 `class='col-sm-{숫자}'` div 들. 한 row 의 숫자 합은 **반드시 12**.
- 허용된 열 조합만 사용: **{12}, {6,6}, {4,8}, {8,4}, {4,4,4}, {3,6,3}, {3,3,3,3}**.
- 모든 컴포넌트는 `col-sm` div **안에** 둔다.
- 레이아웃 중첩 가능(col-sm div 안에 새 section).
- 모든 `name` 속성(div.row 포함)은 **폼 전체에서 유일**해야 한다.
- 문자열 속성에는 한글·숫자·영문·공백·`_`·`-`·`.` 만 사용.

---

## 컴포넌트 (요약 — 전체는 form-components.md)

| 태그 | 용도 |
|------|------|
| `text-field` | 한 줄 텍스트 (type: text/number/email/url/date/datetime-local/time/password/tel/color 등) |
| `textarea-field` | 여러 줄 텍스트 (`rows`) |
| `boolean-field` | true/false |
| `select-field` | 다수 중 하나 선택 |
| `checkbox-field` | 다수 중 여러 개 선택 |
| `radio-field` | 다수 중 하나 선택(라디오) |
| `user-select-field` | 시스템 사용자 선택 |
| `file-field` | 파일 업로드 |
| `report-field` | 마크다운 입력 |
| `slide-field` | 슬라이드 입력 |
| `label-field` | 설명 텍스트 |
| `bpmn-uengine-field` | BPMN 프로세스 정의(XML) 입력 |

- select/checkbox/radio 의 `items` 는 `'[{"key1":"label1"},{"key2":"label2"}]'` 형식(`is_dynamic_load='fixed'` 일 때 필수).
- **`alias`/`label` 값은 한국어**, **`name` 속성은 영문만**.

## 필드 추론 (유연하게)

태스크의 이름·설명·지침에서 최소 필요한 입력을 추론한다:
- 사람의 결정(승인/반려/보류)이 있으면 → 결정 필드 + 사유 필드.
- 금액/입금/지불이면 → 일자·금액·지급자·증빙 필드.
- 검토/확인이면 → 결과·코멘트 필드.
- 계약/서명이면 → 계약 id·일자·서명 방식 필드.
- 문서에 없는 내용을 지어내지 말 것. 애매하면 자유 입력(Free Input)으로.

---

## form_id 규칙

`form_id` 는 영문 소문자·언더스코어. 권장 형식: `<프로세스id>_<activity_id>_form` (하이픈은 `_` 로). 예: `leave_request_apply_leave_form`.

폴백(정보 부족) 최소 폼:
```html
<section>
  <div class='row' name='free_input_layout' alias='자유 입력' is_multidata_mode='false'>
    <div class='col-sm-12'>
      <textarea-field name='free_input' alias='자유 입력' rows='5' disabled='false' readonly='false'></textarea-field>
    </div>
  </div>
</section>
```

---

## 프로세스 정의 JSON 반영

- 각 Activity 에 `"tool": "formHandler:<form_id>"` 를 설정한다.
- 폼 HTML 은 `.bpmn/forms/<activity_id>.html` 로 저장.
- (참조정보 단계를 위해) 각 폼의 `form_id` 와 필드 `name` 목록을 기억해 둔다 — 6단계 inputData/conditionData 가 `<form_id>.<field_name>` 형식을 쓴다.

---

> **이 단계는 자동 실행이다.** 3단계 답변 직후 별도 확인 없이 모든 UserActivity 폼을 생성한다. 폼 생성 결과를 여기서 따로 길게 보고하지 말고(중간 멈춤 금지), 곧바로 6단계(참조정보)로 이어간 뒤 **마지막에 한 번** 통합 요약한다.

## 다음 단계 연결 (자동)

폼을 모두 만들고 `activity.tool` 을 연결했으면, **확인 질문 없이 곧바로** [08-reference-info.md](08-reference-info.md) 를 로드해 6단계(참조정보 연결)로 진입한다. 폼만 따로 요약·확인하지 않는다 — 최종 요약은 8단계 "완료 안내" 에서 폼·참조정보를 함께 보고한다.

> 사용자가 나중에 특정 폼을 고치고 싶다고 하면 해당 파일만 다시 만든다(최종 요약에서 "수정 가능" 안내).
