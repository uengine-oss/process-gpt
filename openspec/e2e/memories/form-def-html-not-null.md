---
name: form-def-html-not-null
description: public.form_def.html 컬럼이 NOT NULL이므로 fields_json만 채우는 시드는 실패한다
applies-to:
  - supabase
  - form_def
  - e2e-seed
last-verified: 2026-05-27
metadata:
  type: pitfall
---

# form_def 시드 시 html NOT NULL 제약

`public.form_def` 테이블은 다음과 같다:

```
uuid         uuid    not null default gen_random_uuid()
html         text    not null
proc_def_id  text    not null
activity_id  text    not null
tenant_id    text
id           text
fields_json  jsonb
```

`fields_json`만 채우고 `html`을 생략하면 다음 오류로 시드가 실패한다:

```
ERROR:  null value in column "html" of relation "form_def" violates not-null constraint
```

## What works

시드 INSERT에 `html` 컬럼을 함께 채운다. 콜봇 protocol API는 폼을 HTML로 렌더하지 않고 `fields_json`만 사용하므로 placeholder HTML 한 줄로 충분하다:

```sql
insert into public.form_def (id, proc_def_id, activity_id, tenant_id, fields_json, html)
values ('...', '...', '...', 'localhost', '[...]'::jsonb,
        '<form><input name="customer_name"/></form>');
```

## Why

form_def는 본래 웹 UI 렌더링용 HTML 산출물도 함께 저장하도록 설계되어 있어 `html`이 NOT NULL이다. 콜봇처럼 fields_json만 소비하는 클라이언트의 E2E에서도 제약은 동일하게 적용된다.

## How to apply

- Triggered when: form_def 시드를 작성하면서 fields_json만 채우거나, 콜봇/AI Function Calling 같이 HTML 렌더를 거치지 않는 클라이언트용 시나리오에서 form_def row가 필요할 때.
- Skip if: 이미 다른 시나리오/시드가 form_def row를 채워두었고 그대로 재사용 가능할 때.

Related: -
