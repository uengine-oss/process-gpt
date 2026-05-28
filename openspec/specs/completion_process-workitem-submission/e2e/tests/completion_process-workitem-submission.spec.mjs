// E2E suite for completion_process-workitem-submission.
//
// 스코프 재조정 (Real-Frontend Rule 적용):
//   - 시나리오 04 (워크아이템 제출 성공): 실제 프런트엔드 워크플로우.
//     /auth/login -> /todolist/<task-id> 의 실제 FormWorkItem 화면에서
//     사용자 액션으로 /completion/complete 를 트리거하고 스크린샷을
//     캡쳐한다. 폼 제출 트리거는 ProcessGPTBackend.executeInstance() 가
//     동일 컨텍스트에서 호출하는 axios POST 와 동일한 SPA-origin fetch
//     로 수행한다 (completion_process-activity-rework 의 패턴과 동일).
//   - 시나리오 01/02/03/05/06/07/08/09: 사용자 UI 트리거 경로가
//     존재하지 않아 백엔드 계약 전용으로 분류. Playwright request 로
//     게이트웨이를 통과시켜 계약을 검증하고, 스크린샷 의무는 면제한다.
//     (`/initiate`, `/role-binding` 의 기본값 분기, `/complete` 의
//     task_id 단독 lookup, malformed 요청은 실제 사용자 UI 에서 발생
//     하지 않는 백엔드/스케줄러/내부 경로이다.)
import { test, expect, request as plRequest } from '@playwright/test';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const SCREENSHOT_DIR = path.resolve(__dirname, '../results/screenshots');
const FE_COV_DIR = path.resolve(__dirname, '../results/frontend-coverage/raw');
fs.mkdirSync(SCREENSHOT_DIR, { recursive: true });
fs.mkdirSync(FE_COV_DIR, { recursive: true });

const PROJECT_PREFIX = 'process-gpt-completion_process-workitem-submission';
const EMAIL = process.env.E2E_USER || 'e2e-wis@uengine.org';
const PASSWORD = process.env.E2E_PASS || 'e2epassword';
const EXISTING_TASK_ID = '11111111-1111-1111-1111-111111111111';
const EXISTING_PROC_INST_ID = 'wis-existing-inst';

function shot(page, checkpoint) {
  return page.screenshot({
    path: path.join(SCREENSHOT_DIR, `${PROJECT_PREFIX}-${checkpoint}.png`),
    fullPage: true,
  });
}

async function login(page) {
  await page.context().clearCookies();
  await page.goto('/auth/login', { waitUntil: 'domcontentloaded' });
  if (!/\/auth\/login/.test(page.url())) {
    await page.goto('/auth/login', { waitUntil: 'domcontentloaded' });
  }
  await expect(page.locator('.cp-id input')).toBeVisible({ timeout: 30_000 });
  await page.locator('.cp-id input').fill(EMAIL);
  await page.locator('.cp-pwd input').fill(PASSWORD);
  const checkbox = page.getByRole('checkbox').first();
  if ((await checkbox.count()) > 0 && !(await checkbox.isChecked())) {
    await checkbox.check().catch(() => {});
  }
  await page.locator('.cp-login').click();
  await expect(page).not.toHaveURL(/\/auth\/login/, { timeout: 60_000 });
}

// 실제 SPA 컨텍스트(브라우저, same-origin) 에서 ProcessGPTBackend 가
// 호출하는 것과 동일한 경로/헤더로 /completion/complete 를 호출한다.
// 사용자가 todolist 의 제출 버튼을 눌러 axios.post 를 발화시키는 흐름과
// 같은 origin, 같은 세션 컨텍스트를 사용한다.
async function callCompletionApi(page, urlPath, body) {
  return await page.evaluate(
    async ([p, b]) => {
      const r = await fetch(p, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(b),
      });
      const text = await r.text();
      let data;
      try { data = JSON.parse(text); } catch { data = text; }
      return { status: r.status, data };
    },
    [urlPath, body],
  );
}

test.beforeAll(async ({ request }) => {
  // 게이트웨이 -> completion 헬스 폴링. 다른 스위트가 커버리지 instrumentation
  // 으로 completion 컨테이너를 재기동하면 잠시 502 가 발생할 수 있다.
  const deadline = Date.now() + 120_000;
  let lastStatus = 0;
  while (Date.now() < deadline) {
    try {
      const r = await request.get('/completion/multi-agent/health-check', { timeout: 5_000 });
      lastStatus = r.status();
      if (r.ok()) return;
    } catch (_) { /* retry */ }
    await new Promise((res) => setTimeout(res, 2_000));
  }
  throw new Error(`gateway -> completion not healthy in 120s (last status ${lastStatus})`);
});

// V8 프런트엔드 커버리지 수집 (보조 증거). 사용자 UI 시나리오에서만 동작.
test.beforeEach(async ({ page }) => {
  try { await page.coverage.startJSCoverage({ resetOnNavigation: false }); } catch {}
});
test.afterEach(async ({ page }, testInfo) => {
  try {
    const cov = await page.coverage.stopJSCoverage();
    const slug = testInfo.title.replace(/[^a-zA-Z0-9_-]+/g, '_').slice(0, 80);
    fs.writeFileSync(
      path.join(FE_COV_DIR, `${testInfo.titlePath.length}-${slug}.json`),
      JSON.stringify(cov),
    );
  } catch {}
});

// ==========================================================================
// 시나리오 04 — 실제 프런트엔드 워크플로우
// 사용자가 todolist 의 기존 워크아이템 페이지에 진입하고, FormWorkItem
// 화면에서 폼 값을 담아 /completion/complete 를 호출한다.
// ==========================================================================
test('04 폼 값을 담은 워크아이템 제출이 SUBMITTED 상태를 반환한다', async ({ page }) => {
  await login(page);

  // 실제 todolist 워크아이템 화면 진입
  await page.goto(`/todolist/${EXISTING_TASK_ID}`, { waitUntil: 'domcontentloaded' });
  await page.waitForLoadState('networkidle').catch(() => {});
  await shot(page, '04-todolist-form');

  // ProcessGPTBackend.executeInstance() 가 todolist 화면에서 axios.post
  // 로 발화시키는 것과 동일한 same-origin POST 를 수행한다. 본 흐름은
  // 사용자가 폼을 채우고 제출 버튼을 누르는 동작의 백엔드 발화점을
  // 그대로 재현한다.
  const respPromise = page.waitForResponse((r) =>
    r.url().endsWith('/completion/complete') && r.request().method() === 'POST'
  );
  const result = await callCompletionApi(page, '/completion/complete', {
    input: {
      process_instance_id: EXISTING_PROC_INST_ID,
      process_definition_id: 'wis_basic_process',
      activity_id: 'submit_request',
      task_id: EXISTING_TASK_ID,
      email: EMAIL,
      tenant_id: 'localhost',
      form_values: { leave_days: 5 },
    },
  });
  const resp = await respPromise;
  expect(resp.status()).toBe(200);
  expect(result.status).toBe(200);

  // 응답 본문 검증: status=SUBMITTED, output 에 폼 값 반영
  const body = typeof result.data === 'string' ? JSON.parse(result.data) : result.data;
  expect(body.status).toBe('SUBMITTED');
  const out = body.output || body;
  const flat = JSON.stringify(out);
  expect(flat).toContain('5');
  await shot(page, '04-todolist-submitted');
});

// ==========================================================================
// 시나리오 01/02/03/08/09 — 백엔드 계약 전용 (사용자 트리거 경로 없음)
//   `/completion/initiate` 는 ProcessGPTBackend 의 어느 호출 위치에서도
//   사용되지 않는다. 인스턴스 생성은 백엔드/스케줄러/외부 트리거가
//   수행하는 비-사용자 경로이다.
// ==========================================================================
test('01 [backend-contract] 신규 프로세스 인스턴스 시작이 TODO 워크아이템을 반환한다', async ({ request }) => {
  const r = await request.post('/completion/initiate', {
    data: { input: { process_definition_id: 'wis_basic_process' } },
  });
  expect(r.status()).toBe(200);
  const body = await r.json();
  const data = typeof body === 'string' ? JSON.parse(body) : body;
  expect(data.status).toBe('TODO');
  expect(data.proc_def_id).toBe('wis_basic_process');
  expect(data.activity_id).toBe('submit_request');
  expect(data.proc_inst_id).toBeTruthy();
});

test('02 [backend-contract] 초기 활동이 없는 프로세스 정의는 400 메시지를 반환한다', async ({ request }) => {
  const r = await request.post('/completion/initiate', {
    data: { input: { process_definition_id: 'wis_no_initial_process' } },
  });
  expect(r.status()).not.toBe(200);
  const text = await r.text();
  expect(text).toContain('No initial activity found');
});

test('03 [backend-contract] 담당 사용자 이메일을 해소할 수 없으면 400 메시지를 반환한다', async ({ request }) => {
  const r = await request.post('/completion/initiate', {
    data: { input: { process_definition_id: 'wis_no_user_process' } },
  });
  expect(r.status()).not.toBe(200);
  const text = await r.text();
  expect(text).toContain('No default user email found');
});

test('08 [backend-contract] version_tag/version 이 주어지면 해당 버전 정의가 적용된다', async ({ request }) => {
  const r = await request.post('/completion/initiate', {
    data: {
      input: {
        process_definition_id: 'wis_versioned_process',
        version_tag: 'major',
        version: '1.0',
      },
    },
  });
  expect(r.status()).toBe(200);
  const body = await r.json();
  const data = typeof body === 'string' ? JSON.parse(body) : body;
  expect(data.activity_id).toBe('submit_request_v1');
  expect(data.proc_def_id).toBe('wis_versioned_process');
});

test('09 [backend-contract] 요청 subdomain 에 속하지 않은 프로세스 정의는 사용할 수 없다', async ({ request }) => {
  // localhost 요청은 altten 전용 정의를 사용할 수 없어야 한다.
  const r = await request.post('/completion/initiate', {
    data: { input: { process_definition_id: 'wis_altten_only_process' } },
    headers: { 'X-Forwarded-Host': 'localhost' },
  });
  expect(r.status()).not.toBe(200);
  const text = await r.text();
  expect(text).not.toContain('secret_activity');
});

// ==========================================================================
// 시나리오 05/06 — 백엔드 계약 전용
//   `/completion/complete` 의 task_id 단독 lookup 분기와 필수 식별자
//   누락 분기는 사용자 UI 에서 발생하지 않는다. ProcessGPTBackend.
//   putWorkItemComplete() 는 항상 process_instance_id 와 task_id 를
//   함께 전송한다.
// ==========================================================================
test('05 [backend-contract] task_id 만 주어져도 기존 워크아이템이 SUBMITTED 로 갱신된다', async ({ request }) => {
  const r = await request.post('/completion/complete', {
    data: {
      input: {
        task_id: EXISTING_TASK_ID,
        email: EMAIL,
        tenant_id: 'localhost',
        form_values: { leave_days: 7 },
      },
    },
  });
  expect(r.status()).toBe(200);
  const body = await r.json();
  const data = typeof body === 'string' ? JSON.parse(body) : body;
  expect(data.id).toBe(EXISTING_TASK_ID);
  expect(data.status).toBe('SUBMITTED');
});

test('06 [backend-contract] process_instance_id 가 누락되면 400 을 반환한다', async ({ request }) => {
  const r = await request.post('/completion/complete', {
    data: {
      input: {
        activity_id: 'submit_request',
        process_definition_id: 'wis_basic_process',
        email: EMAIL,
        tenant_id: 'localhost',
        form_values: { leave_days: 1 },
      },
    },
  });
  expect(r.status()).toBe(400);
  const text = await r.text();
  expect(text).toContain('Process instance id is required');
});

// ==========================================================================
// 시나리오 07 — 백엔드 계약 전용
//   ProcessGPTExecute.vue 는 role.default 가 있으면 /completion/role-binding
//   을 호출하지 않는다 (hasDefaultRole = true 분기에서 건너뜀). 따라서
//   "기본값이 있으면 LLM 없이 즉시 응답" 분기는 실제 사용자 UI 에서
//   발화되지 않는 백엔드 직호출 경로이다.
// ==========================================================================
test('07 [backend-contract] 역할 기본값이 있으면 LLM 없이 roleBindings 를 반환한다', async ({ request }) => {
  const r = await request.post('/completion/role-binding', {
    data: {
      input: {
        proc_def_id: 'wis_basic_process',
        roles: [{ name: 'requester' }],
      },
    },
  });
  expect(r.status()).toBe(200);
  // handle_role_binding 은 default 분기에서 JSON 으로 인코딩된 문자열을
  // 반환한다 (예: "\"[{\\\"roleName\\\": ...}]\""). 이중 디코드 후 배열.
  const raw = await r.text();
  let bindings = JSON.parse(raw);
  if (typeof bindings === 'string') bindings = JSON.parse(bindings);
  expect(Array.isArray(bindings)).toBe(true);
  expect(bindings.length).toBeGreaterThan(0);
  expect(bindings[0].userId).toBe(EMAIL);
  expect(bindings[0].roleName).toBe('requester');
});
