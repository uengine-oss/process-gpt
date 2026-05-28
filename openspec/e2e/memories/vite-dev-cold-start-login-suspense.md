---
name: vite-dev-cold-start-login-suspense
description: Source-run Vite dev 서버가 cold-start 시 LoginForm 의존 모듈 트리를 즉시 컴파일하지 못해 Playwright login 헬퍼가 .cp-id input 을 못 찾고 타임아웃하는 함정
applies-to:
  - vite-dev
  - source-run-frontend
  - playwright
  - vuetify
  - login-form
last-verified: 2026-05-28
metadata:
  type: pitfall
---

# Vite dev 서버 cold-start 가 로그인 페이지를 Loading 스켈레톤 상태로 묶는다

호스트에서 `npx vite --host 127.0.0.1 --port 8081` 로 source-run 프론트엔드를
띄운 직후 Playwright 가 곧바로 `/auth/login` 으로 이동하면 페이지가
`Loading...` 스켈레톤(Vuetify 의 Suspense/skeleton 상태)에 멈추고
`SideLogin.vue → LoginForm.vue` 가 끝까지 렌더되지 않는다. 그 결과
`expect(page.locator('.cp-id input')).toBeVisible(...)` 가 120s 까지 기다려도
실패한다. 동일 사용자 시나리오는 prebuilt SPA 이미지(예:
`ghcr.io/uengine-oss/process-gpt:<tag>`) 환경에서는 5~10s 안에 통과한다.

이슈는 Vue 컴포넌트 그래프가 매우 크고 (`monaco`, `vuetify`, `vee-validate`,
`@fullcalendar` 등) Vite dev 의 on-demand transform 이 첫 hit 의 import 트리를
순차적으로 처리하는 데 1분 이상이 걸리는 데서 온다. `--prebundle` 옵션이나
`optimizeDeps.entries` 를 늘려도 충분치 않다.

## What works

- (선호) 호스트에서 미리 `cd services/frontend && NODE_OPTIONS="--max-old-space-size=8192" npx vite build --minify=false` 로 source-mapped 정적 산출물을 만든 뒤 `npx vite preview --port 8081 --strictPort` 로 서빙. preview 모드는 정적 파일을 그대로 내려주므로 cold-start 페널티가 사라진다.
- 또는 Playwright `globalSetup` 에서 `fetch('http://localhost:8088/auth/login')` 를 2~3회 보내 dev 서버 transform 캐시를 warm 시킨 뒤 본 테스트를 실행한다 (`page.goto(..., waitUntil:'networkidle')` 와 병행). 단일 cold-fetch 만으로는 부족하다.
- 그래도 안 되면 prebuilt SPA 이미지로 fallback 하고 frontend coverage 를 V8 번들 보조 지표로 표기한다. 본 spec 의 시나리오 01 처럼 사용자 동선 스크린샷이 필요한 경우 prebuilt 가 가장 안정적이다.

## Why

Vite dev 의 dependency graph transform 은 첫 요청에서 모든 import 를 lazy 로
컴파일한다. 큰 frontend (uengine-oss/process-gpt 의 `services/frontend` 처럼)
에서는 LoginForm + Logo + 다국어 + Vuetify Suspense boundary 가 모두 첫 hit
에 동시에 트리거되어 브라우저는 의미 있는 UI 가 마운트되기 전에
Suspense fallback("Loading...") 만 보게 된다.

## How to apply

- Triggered when: 호스트 source-run Vite dev (`npx vite` 또는 `vite dev`) 를 Playwright `page.goto('/auth/login')` 가 즉시 호출하고, 화면 yaml snapshot 이 `Loading...` alert 만 노출하며 `.cp-id input` 가 30s+ 안에 안 보일 때.
- Skip if: Vite preview/build 산출물 또는 prebuilt SPA 이미지를 서빙 중일 때 (이 함정은 dev 서버 한정).

Related: [[frontend-source-build-oom]], [[playwright-node-modules-junction]], [[rtk-suppresses-playwright-reporters]]
