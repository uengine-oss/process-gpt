// E2E suite for /process-data-query and /process-var-sql
// (completion_process-data-query).
//
// Scope (post Real-Frontend remediation, 2026-05-27):
//   - Scenario 03 drives the real BPMN designer UI in the repository
//     frontend: login → /definitions/<id> → "프로세스 변수" 다이얼로그 →
//     데이터 소스 SQL → "generate" 버튼 → assert CREATE TABLE SQL.
//     This is the only spec scenario with a real user-facing surface.
//   - Scenarios 01/02/04 are classified as backend-contract-only with
//     explicit user-action exemption (see scenarios/*.md). They call the
//     completion backend directly via Playwright `request` with
//     X-Forwarded-Host to drive the tenant context.
//
// The previous suite served a synthetic tester HTML (scripts/pdq-tester.html)
// via page.route(), which violated the Real-Frontend Rule. That file and the
// associated synthetic screenshots have been deleted.
import { test, expect, request as pwRequest } from '@playwright/test';
import { fileURLToPath } from 'url';
import path from 'path';
import fs from 'fs';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const SHOT_DIR = path.resolve(__dirname, '../results/screenshots');
fs.mkdirSync(SHOT_DIR, { recursive: true });
const FE_COV_DIR = path.resolve(__dirname, '../results/frontend-coverage/raw');
fs.mkdirSync(FE_COV_DIR, { recursive: true });

const PROJECT_PREFIX = 'process-gpt-completion_process-data-query';
const shot = (name) => path.join(SHOT_DIR, `${PROJECT_PREFIX}-${name}.png`);

const EMAIL = process.env.E2E_USER || 'e2e@uengine.org';
const PASSWORD = process.env.E2E_PASS || 'e2epassword';
// Main app gateway (shared frontend entry point) - used for the designer UI.
const APP_BASE = process.env.APP_BASE_URL || 'http://localhost:8088';
// Direct completion backend - protocol-only scenarios bypass the gateway so
// X-Forwarded-Host can be set deterministically per tenant.
const COMPLETION_DIRECT =
    process.env.COMPLETION_DIRECT_URL || 'http://127.0.0.1:8000';
// mock-llm-pdq is reachable same-origin through gateway-pdq's /__mock-llm/
// proxy on :8089 (see openspec/specs/.../e2e/docker/nginx.e2e.conf).
const MOCK_LLM_URL =
    process.env.MOCK_LLM_URL || 'http://localhost:8089/__mock-llm';

// --------------------------------------------------------------------------
// V8 frontend coverage collection (browser-only scenario 03).
// Source-mapped coverage is unavailable when the frontend is served from
// the prebuilt minified image; this raw V8 coverage is reported as
// supporting bundle-level evidence in coverage-summary.json.
// --------------------------------------------------------------------------
test.beforeEach(async ({ page }) => {
    try {
        await page.coverage.startJSCoverage({ resetOnNavigation: false });
    } catch {
        // non-chromium browser
    }
});

test.afterEach(async ({ page }, testInfo) => {
    try {
        const cov = await page.coverage.stopJSCoverage();
        const slug = testInfo.title.replace(/[^a-zA-Z0-9_-]+/g, '_').slice(0, 80);
        fs.writeFileSync(
            path.join(FE_COV_DIR, `${testInfo.titlePath.length}-${slug}.json`),
            JSON.stringify(cov)
        );
    } catch {
        // ignore - no page context (request-only tests)
    }
});

// --------------------------------------------------------------------------
// Login helper - mirrors completion_process-definition-search.
// --------------------------------------------------------------------------
async function login(page) {
    // Clear cookies AND localStorage so cached Supabase session does not
    // redirect /auth/login to the home dashboard before the form mounts.
    await page.context().clearCookies();
    await page.goto(`${APP_BASE}/`, { waitUntil: 'domcontentloaded' }).catch(() => {});
    await page.evaluate(() => {
        try { window.localStorage.clear(); } catch {}
        try { window.sessionStorage.clear(); } catch {}
    }).catch(() => {});
    await page.goto(`${APP_BASE}/auth/login`, { waitUntil: 'domcontentloaded' });
    if (!/\/auth\/login/.test(page.url())) {
        await page.goto(`${APP_BASE}/auth/login`, { waitUntil: 'domcontentloaded' });
    }
    await expect(page.locator('.cp-id input')).toBeVisible({ timeout: 60_000 });
    await page.locator('.cp-id input').fill(EMAIL);
    await page.locator('.cp-pwd input').fill(PASSWORD);
    const checkbox = page.getByRole('checkbox').first();
    if ((await checkbox.count()) > 0 && !(await checkbox.isChecked())) {
        await checkbox.check().catch(() => {});
    }
    const loginBtn = page.locator('.cp-login');
    await expect(loginBtn).toBeVisible({ timeout: 30_000 });
    await loginBtn.click();
    await page.waitForTimeout(1500);
    if (/\/auth\/login/.test(page.url())) {
        await loginBtn.click().catch(() => {});
    }
    await expect(page).not.toHaveURL(/\/auth\/login/, { timeout: 180_000 });
}

// --------------------------------------------------------------------------
// 01: 자연어 프로세스 데이터 조회 - protocol-only (user-action exempt).
// --------------------------------------------------------------------------
test('01 자연어 프로세스 데이터 조회가 HTML table 문자열을 반환한다 (protocol-only)', async () => {
    const ctx = await pwRequest.newContext({ baseURL: COMPLETION_DIRECT });
    const resp = await ctx.post('/process-data-query', {
        headers: {
            'Content-Type': 'application/json',
            'X-Forwarded-Host': 'localhost:8088',
        },
        data: {
            input: {
                query: '내 휴가 신청 목록',
                user_id: EMAIL,
                chat_room_id: 'e2e-room-01',
            },
        },
        timeout: 120_000,
    });
    expect(resp.status()).toBe(200);
    const body = await resp.text();
    // body is a JSON-quoted HTML string (langserve wrapping varies);
    // assert the <table marker survives both raw and quoted forms.
    expect(body).toContain('<table');
    await ctx.dispose();
});

// --------------------------------------------------------------------------
// 02: 빈 결과 - protocol-only (user-action exempt).
// --------------------------------------------------------------------------
test('02 표로 만들 결과가 없으면 빈 본문이 반환된다 (protocol-only)', async () => {
    const ctx = await pwRequest.newContext({ baseURL: COMPLETION_DIRECT });
    const resp = await ctx.post('/process-data-query', {
        headers: {
            'Content-Type': 'application/json',
            'X-Forwarded-Host': 'localhost:8088',
        },
        data: {
            input: {
                query: '_EMPTY_ 표를 만들 수 없는 질의',
                user_id: EMAIL,
                chat_room_id: 'e2e-room-02',
            },
        },
        timeout: 120_000,
    });
    expect(resp.status()).toBe(200);
    const body = await resp.text();
    // 후처리 후 본문에 <table 마커가 없어야 한다.
    expect(body).not.toContain('<table');
    await ctx.dispose();
});

// --------------------------------------------------------------------------
// 03: 프로세스 변수 SQL 스키마 생성 - 실 BPMN 디자이너 UI 시나리오.
// --------------------------------------------------------------------------
test('03 BPMN 디자이너 프로세스 변수에서 SQL 생성을 누르면 CREATE TABLE SQL이 반환된다', async ({ page }) => {
    await login(page);

    await page.goto(`${APP_BASE}/definitions/vacation_request_process`, {
        waitUntil: 'domcontentloaded',
    });
    // BPMN designer needs the SPA to hydrate and the canvas to mount.
    await page.waitForLoadState('networkidle').catch(() => {});
    await page.screenshot({ path: shot('03-designer-loaded'), fullPage: true }).catch(() => {});

    // 프로세스 변수 다이얼로그 열기
    const openVarsBtn = page.locator('#processVariables').first();
    await expect(openVarsBtn).toBeVisible({ timeout: 60_000 });
    await openVarsBtn.click();
    await page.screenshot({ path: shot('03-variables-dialog'), fullPage: true }).catch(() => {});

    // 변수 입력 - ProcessVariable.vue 의 셀렉터 사용
    const nameInput = page.locator('.cp-v-name input').first();
    await expect(nameInput).toBeVisible({ timeout: 30_000 });
    await nameInput.fill('total_vacation_days_remains');

    // 타입은 Text (필수 아님; 데이터 소스가 SQL로 가야 generate 버튼이 노출됨)
    const typeAutocomplete = page.locator('.cp-v-type input').first();
    if (await typeAutocomplete.count()) {
        await typeAutocomplete.click().catch(() => {});
        // overlay menu에서 Text 옵션 선택 (없으면 Esc로 닫음)
        const textItem = page.getByRole('option', { name: 'Text' });
        if (await textItem.count()) {
            await textItem.first().click().catch(() => {});
        } else {
            await page.keyboard.press('Escape').catch(() => {});
        }
    }

    // 설명 입력 (#hem)
    const descInput = page.locator('#hem').first();
    if (await descInput.count()) {
        await descInput.fill(
            'vacation_addition 테이블의 휴가일수에서 vacation_request 사용일수를 제외'
        );
    }

    // 데이터 소스를 SQL로 변경 → SQL textarea 와 generate/test 버튼이 나타남
    // ProcessVariable.vue 의 datasources autocomplete (3번째 v-autocomplete)
    const datasourceAutocomplete = page
        .locator('.v-autocomplete')
        .nth(2)
        .locator('input')
        .first();
    await datasourceAutocomplete.click();
    const sqlItem = page.getByRole('option', { name: 'SQL' });
    await expect(sqlItem.first()).toBeVisible({ timeout: 15_000 });
    await sqlItem.first().click();
    await page.screenshot({ path: shot('03-variable-input'), fullPage: true }).catch(() => {});

    // "generate" 버튼은 텍스트로 식별 (ProcessVariable.vue 라인 103)
    const generateBtn = page.getByRole('button', { name: /^generate$/ });
    await expect(generateBtn).toBeVisible({ timeout: 15_000 });

    const respPromise = page.waitForResponse(
        (r) =>
            r.url().includes('/completion/process-var-sql/invoke') &&
            r.request().method() === 'POST',
        { timeout: 60_000 }
    );
    await generateBtn.click();
    const resp = await respPromise;
    expect(resp.status()).toBe(200);

    // 응답 후 SQL textarea가 CREATE TABLE 로 채워짐을 검증
    const sqlTextarea = page.locator('textarea').first();
    await expect(sqlTextarea).toBeVisible({ timeout: 30_000 });
    await expect(sqlTextarea).toContainText(/CREATE\s+TABLE/i, { timeout: 30_000 });
    await page.screenshot({ path: shot('03-sql-generated'), fullPage: true }).catch(() => {});
});

// --------------------------------------------------------------------------
// 04: 테넌트 격리 - protocol-only (user-action exempt).
// --------------------------------------------------------------------------
test('04 프로세스 데이터 조회는 요청 테넌트 범위로 한정된다 (protocol-only)', async () => {
    const completionCtx = await pwRequest.newContext({ baseURL: COMPLETION_DIRECT });
    // Use the absolute MOCK_LLM_URL directly; Playwright's request.get with an
    // absolute path would otherwise override the baseURL's pathname.
    const mockLlmCtx = await pwRequest.newContext();

    const resp = await completionCtx.post('/process-data-query', {
        headers: {
            'Content-Type': 'application/json',
            'X-Forwarded-Host': 'localhost:8088',
        },
        data: {
            input: {
                query: '내 진행 중인 프로세스 인스턴스 목록',
                user_id: EMAIL,
                chat_room_id: 'e2e-room-04',
            },
        },
        timeout: 120_000,
    });
    expect(resp.status()).toBe(200);

    const promptResp = await mockLlmCtx.get(`${MOCK_LLM_URL}/control/last-prompt`, {
        timeout: 30_000,
    });
    expect(promptResp.status()).toBe(200);
    const promptBody = await promptResp.text();

    expect(promptBody).toContain('vacation_request_process');
    expect(promptBody).not.toContain('altten_only_secret_process');

    await completionCtx.dispose();
    await mockLlmCtx.dispose();
});
