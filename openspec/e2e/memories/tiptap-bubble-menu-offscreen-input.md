---
name: tiptap-bubble-menu-offscreen-input
description: Tiptap BubbleMenu가 큰 tippy offset으로 viewport 바깥에 배치될 때 Playwright click/fill이 force:true 로도 실패하는 경우의 우회 패턴
applies-to:
  - vue
  - vuetify
  - tiptap
  - bubble-menu
  - playwright
last-verified: 2026-05-27
metadata:
  type: workaround
---

# Tiptap BubbleMenu가 viewport 바깥에 배치되어 Playwright click/fill이 실패

`services/frontend/src/views/markdown/MarkdownEditor.vue` 의 BubbleMenu 는
`tippy-options.popperOptions` 에 `{ name: 'offset', options: { offset: [400, -300] } }` 가 걸려
있어, 본문을 선택하면 메뉴가 에디터 본문 위/오른쪽으로 크게 떨어져 표시된다.
기본 Playwright viewport(1280×720) 에서는 메뉴 안의 `.ai-input input` 이
viewport 바깥에 위치하는 경우가 발생하고, 이때:

- `aiInput.click()` → `Element is outside of the viewport` 로 실패
- `aiInput.click({ force: true })` 도 같은 사유로 실패 (force 는 actionability
  체크는 끄지만 viewport 체크는 끄지 않음)
- `aiInput.fill(value, { force: true })` 도 동일 실패

## What works

같은 패턴을 만나면 native DOM API 와 `dispatchEvent` 로 우회한다:

```js
// 1) 값 주입 (Vuetify v-model 이 input 이벤트로 동기화됨)
await aiInput.evaluate((el, value) => {
  const setter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value').set;
  setter.call(el, value);
  el.dispatchEvent(new Event('input', { bubbles: true }));
  el.dispatchEvent(new Event('change', { bubbles: true }));
  el.focus();
}, '짧게 보강해 주세요.');

// 2) Enter 전송 (`@keydown.enter="handleAIOption(null)"` 에 매칭)
await aiInput.dispatchEvent('keydown', {
  key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true
});
```

이 두 단계로 실제 사용자가 입력하고 Enter 를 누른 것과 동일한 효과가 나며
Real-Frontend Rule 을 위반하지 않는다(여전히 진짜 프론트엔드 컴포넌트가
실행되고, 그 v-model/이벤트 핸들러가 정상 동작한다).

## Why

Playwright 의 click/fill 은 actionability 와 viewport 검사를 둘 다 수행하는데
`force: true` 는 actionability 만 끈다. tippy 의 큰 음수 offset 으로 popper 가
viewport 바깥에 놓이면 둘 중 viewport 검사에서 막히고, scrollIntoView 도
fixed-position 컨테이너에서는 효과가 없다.

`evaluate` 로 native value setter 를 호출하면 Vuetify/Vue 가 듣는 `input`
이벤트가 발생해 v-model 이 갱신되고, `dispatchEvent('keydown')` 으로
`@keydown.enter` 핸들러가 직접 호출된다. 둘 다 viewport 와 무관한 DOM 호출이다.

## How to apply

- Triggered when: BubbleMenu / 떠 있는 popper 안의 입력 필드를 Playwright 로
  조작해야 하고, 평소처럼 `click` → `fill` → `press('Enter')` 가
  "Element is outside of the viewport" 로 실패할 때.
- Skip if: 입력 필드가 실제로 viewport 안에 보이고 일반 click/fill 이 통과할
  때. 굳이 native dispatch 로 우회하면 디버깅이 어려워진다.

Related: [[frontend-source-build-oom]]
