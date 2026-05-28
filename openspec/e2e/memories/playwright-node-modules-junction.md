---
name: playwright-node-modules-junction
description: 스위트 로컬 Playwright 테스트가 @playwright/test를 못 찾는 경우, services/frontend/node_modules로 junction을 만들거나 --prefix 로컬 설치하는 패턴. Windows는 junction 사용.
applies-to:
  - spec-local-playwright
  - windows
  - node-modules-resolution
last-verified: 2026-05-27
metadata:
  type: workaround
---

# Spec-local Playwright tests need @playwright/test resolution

`openspec/specs/<spec-name>/e2e/tests/` 아래에 둔 Playwright config/spec이
`@playwright/test`를 import할 때, 해당 디렉터리 위 어디에도 `node_modules`가
없으면 모듈 해석에 실패함. 반대로 매 스위트마다 별도 `node_modules`를 두면
중복과 용량 부담이 큼.

## What works

**옵션 1 — junction (Windows에서 권장)**

`services/frontend/node_modules`에 이미 `@playwright/test`가 있으면 junction:

```powershell
# 스위트 tests 디렉터리에서
New-Item -ItemType Junction `
  -Path .\node_modules `
  -Target ..\..\..\..\..\services\frontend\node_modules
```

Linux/Mac이면 심볼릭 링크로 동일하게 처리:

```bash
ln -s ../../../../../services/frontend/node_modules node_modules
```

**옵션 2 — 가벼운 로컬 설치 (포터블한 대안)**

```bash
npm install --prefix openspec/specs/<spec-name>/e2e/tests \
  --no-save @playwright/test
npx playwright install chromium
```

이 방법은 약 200MB의 중복 설치가 생기지만 환경 의존성이 없어 CI에서 더 안정적.

**옵션 3 — 상위에 공유 node_modules 두기**

`openspec/e2e/tests-shared/node_modules`를 만들고 모든 스위트의 playwright
config가 `NODE_PATH`로 그 위치를 참조하도록 하는 방법도 가능. 아직 두 번
이상 필요한 경우가 없어 도입은 보류.

## Why

- Node의 module resolution은 자기 디렉터리부터 위로 올라가며 `node_modules`를
  찾는데, `openspec/` 트리에는 전통적으로 node_modules가 없음.
- monorepo가 아니라 다국적 언어가 한 repo에 섞여 있는 구조라
  `package.json`을 루트에 두기도 어색함.

## How to apply

- Triggered when:
  - 새 E2E 스위트의 첫 `npx playwright test` 실행에서 "Cannot find module
    @playwright/test" 또는 비슷한 ERR_MODULE_NOT_FOUND가 발생
- Skip if:
  - 이미 다른 방식(예: `package.json`을 e2e 폴더에 둠)으로 해결되어 있음
  - CI 컨테이너에서 모듈 경로가 정적으로 다른 곳에 매핑되어 있음

선택 기준:
- 로컬 개발 + Windows: 옵션 1 (junction) — 가장 빠르고 디스크 절약
- CI/CD 또는 클린 체크아웃: 옵션 2 (`--prefix` 설치) — 가장 견고
- 옵션 3은 두 번째 이상 같은 패턴이 필요할 때 도입 검토
