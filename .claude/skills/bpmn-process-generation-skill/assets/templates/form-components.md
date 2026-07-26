# 폼 컴포넌트 규격 (전체)

[07-forms.md](../../references/07-forms.md) 의 폼 생성 시 사용하는 컴포넌트 전체 목록입니다. **여기에 정의된 태그만** 사용하세요. `alias`/`label` 값은 한국어, `name` 속성은 **영문만**.

## 레이아웃

```html
<section>
  <div class='row' name='<unique_layout_name>' alias='<레이아웃 표시명>' is_multidata_mode='<true|false>'>
    <div class='col-sm-<숫자>'>
      <!-- 컴포넌트 -->
    </div>
  </div>
</section>
```

- `section` → `div.row` 정확히 1개 → `div.col-sm-{숫자}` 들.
- 한 row 의 col-sm 숫자 합 = **12**.
- 허용 조합: `{12}`, `{6,6}`, `{4,8}`, `{8,4}`, `{4,4,4}`, `{3,6,3}`, `{3,3,3,3}`.
- 모든 `name` 은 폼 전체에서 유일.
- 컴포넌트는 반드시 col-sm div 안에. 레이아웃 중첩은 col-sm div 안에 새 section 으로.
- 폼은 비어 있으면 안 됨 — 정보 부족 시 "자유 입력" textarea 하나라도.

## 컴포넌트 목록

### boolean-field
```html
<boolean-field name='<id>' alias='<표시명>' disabled='<true|false>' readonly='<true|false>'></boolean-field>
```
- 용도: true/false 선택.

### user-select-field
```html
<user-select-field name='<id>' alias='<표시명>' disabled='<true|false>' readonly='<true|false>'></user-select-field>
```
- 용도: 시스템 사용자 선택.

### select-field
```html
<select-field name='<id>' alias='<표시명>' is_dynamic_load='<fixed|urlBinding>' items='<옵션목록>' dynamic_load_url='<URL>' dynamic_load_key_json_path='<JSONPath>' dynamic_load_value_json_path='<JSONPath>' disabled='<true|false>' readonly='<true|false>'></select-field>
```
- 용도: 여러 선택지 중 하나.
- `is_dynamic_load='fixed'` 면 `items` 필수: `'[{"key1":"label1"},{"key2":"label2"}]'`.
- `is_dynamic_load='urlBinding'` 면 dynamic_load_url/key_json_path/value_json_path 모두 필수.

### checkbox-field
```html
<checkbox-field name='<id>' alias='<표시명>' is_dynamic_load='<fixed|urlBinding>' items='<옵션목록>' dynamic_load_url='<URL>' dynamic_load_key_json_path='<JSONPath>' dynamic_load_value_json_path='<JSONPath>' disabled='<true|false>' readonly='<true|false>'></checkbox-field>
```
- 용도: 여러 선택지 중 여러 개. items 규칙은 select-field 와 동일.

### radio-field
```html
<radio-field name='<id>' alias='<표시명>' is_dynamic_load='<fixed|urlBinding>' items='<옵션목록>' dynamic_load_url='<URL>' dynamic_load_key_json_path='<JSONPath>' dynamic_load_value_json_path='<JSONPath>' disabled='<true|false>' readonly='<true|false>'></radio-field>
```
- 용도: 여러 선택지 중 하나(라디오 버튼). items 규칙 동일.

### file-field
```html
<file-field name='<id>' alias='<표시명>' disabled='<true|false>' readonly='<true|false>'></file-field>
```
- 용도: 파일 업로드.

### label-field
```html
<label-field label='<설명 텍스트>'></label-field>
```
- 용도: 설명 텍스트. name/alias 가 있는 컴포넌트엔 불필요(자동 라벨 생성).

### report-field
```html
<report-field name='<id>' alias='<표시명>'></report-field>
```
- 용도: 마크다운 입력. 본문만 작성, 구분은 `---`.

### slide-field
```html
<slide-field name='<id>' alias='<표시명>'></slide-field>
```
- 용도: 슬라이드 입력. 본문만 작성, 구분은 `---`.

### bpmn-uengine-field
```html
<bpmn-uengine-field name='<id>' alias='<표시명>'></bpmn-uengine-field>
```
- 용도: BPMN 프로세스 정의(XML) 입력. 사용자가 명시적으로 BPMN 편집기를 요청할 때만.

### text-field
```html
<text-field name='<id>' alias='<표시명>' type='<text|number|email|url|date|datetime-local|month|week|time|password|tel|color>' disabled='<true|false>' readonly='<true|false>'></text-field>
```
- 용도: 한 줄 텍스트(타입 다양). 연도처럼 선택지가 매우 많으면 select 대신 text-field.

### textarea-field
```html
<textarea-field name='<id>' alias='<표시명>' rows='<행수>' disabled='<true|false>' readonly='<true|false>'></textarea-field>
```
- 용도: 여러 줄 텍스트.

## 출력 형식

폼 생성 결과는 HTML 문자열입니다(`.bpmn/forms/<activity_id>.html` 로 저장). 문자열 속성에는 한글·숫자·영문·공백·`_`·`-`·`.` 만 사용하세요.
