---
name: rtk-suppresses-playwright-reporters
description: RTK 후크가 `npx playwright test` 를 가로채면 list 요약만 남고 json/html 리포터가 results.json·html-report/index.html 을 생성하지 않는다
applies-to:
  - rtk
  - playwright
  - spec-local-playwright
  - windows
last-verified: 2026-05-28
metadata:
  type: pitfall
---

# RTK 후크가 Playwright 리포터 출력을 잘라낸다

## 상황

Playwright 를 `npx playwright test --config=...` 로 실행하면 Claude Code 의 RTK
훅이 출력을 가로채 `PASS (3) FAIL (0)` 같은 한 줄 요약으로 바꾼다. 이 경로에서는
`playwright.config.mjs` 에 선언한 `json`/`html` 리포터가 결과 파일을 쓰지 못해
`results/results.json` 과 `results/html-report/index.html` 이 생성되지 않는다.
스크린샷과 `artifacts/.last-run.json` 은 정상 생성되어 “테스트는 통과한 것 같은데
리포트만 빈다” 형태로 헷갈리기 쉽다.

## What works

`rtk proxy` 로 RTK 의 필터링을 우회해 raw stdout 을 그대로 흘려보낸다:

```bash
cd openspec/specs/<spec-name>/e2e/tests
rtk proxy npx playwright test --config=playwright.config.mjs
```

이렇게 실행하면 모든 reporter 가 동작해 `results/results.json`,
`results/html-report/index.html` 이 정상 생성되고 `evaluate_spec_coverage.mjs`
가 `results.json` 을 읽어 추적성 게이트를 통과시킨다.

## Why

RTK 의 `tee` 후크는 명령 출력 buffering·요약을 위해 별도 파이프를 둔다.
이 파이프 단계에서 일부 Playwright reporter 가 stdout flush 타이밍을 잃거나
process exit hook 이 호출되지 않아 결과 파일 기록이 누락된다.
`rtk proxy <cmd>` 는 후크를 비활성화한 채 그대로 실행하므로 reporter 의 onEnd
콜백이 끝까지 동작한다.

## How to apply

- Triggered when: spec-local Playwright 를 `npx playwright test` 로 호출했는데
  results.json / html-report 가 만들어지지 않음. `.last-run.json` 만 존재.
- Skip if: 다른 도구로 Playwright 를 호출할 때 (예: pnpm exec, CI 의 직접 실행).
  CI 환경에서는 RTK 후크가 없을 가능성이 높음.

Related: [[playwright-node-modules-junction]]
