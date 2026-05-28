// E2E suite: completion_process-definition-search
//
// Exercises the real browser -> nginx gateway -> source-run completion ->
// pgvector path for the process definition search feature through the Vue
// SPA header Searchbar, plus protocol-level checks for the empty-result and
// tenant-isolation contracts.
//
// External boundary stubs: only mock-llm /v1/embeddings.
import { test, expect } from '@playwright/test';
import { fileURLToPath } from 'url';
import path from 'path';
import fs from 'fs';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const SHOT_DIR = path.resolve(__dirname, '../results/screenshots');
fs.mkdirSync(SHOT_DIR, { recursive: true });
const FE_COV_DIR = path.resolve(__dirname, '../results/frontend-coverage/raw');
fs.mkdirSync(FE_COV_DIR, { recursive: true });

const shot = (name) =>
    path.join(SHOT_DIR, `process-gpt-completion_process-definition-search-${name}.png`);

const EMAIL = process.env.E2E_USER || 'e2e@uengine.org';
const PASSWORD = process.env.E2E_PASS || 'e2epassword';
const COMPLETION_DIRECT = process.env.E2E_COMPLETION_DIRECT || 'http://127.0.0.1:8000';

// V8 frontend coverage capture (source-mapped via Vite dev server).
test.beforeEach(async ({ page }) => {
    try {
        await page.coverage.startJSCoverage({ resetOnNavigation: false });
    } catch {}
});
test.afterEach(async ({ page }, testInfo) => {
    try {
        const cov = await page.coverage.stopJSCoverage();
        const slug = testInfo.title.replace(/[^a-zA-Z0-9_-]+/g, '_').slice(0, 80);
        fs.writeFileSync(path.join(FE_COV_DIR, `${slug}.json`), JSON.stringify(cov));
    } catch {}
});

async function login(page) {
    await page.context().clearCookies();
    // Vite dev server lazy-compiles SideLogin + LoginForm on first hit; use
    // networkidle and a long visibility timeout so the test survives a cold
    // compile (warm runs settle to ~5s).
    await page.goto('/auth/login', { waitUntil: 'networkidle', timeout: 120_000 });
    if (!/\/auth\/login/.test(page.url())) {
        await page.goto('/auth/login', { waitUntil: 'networkidle', timeout: 120_000 });
    }
    await expect(page.locator('.cp-id input')).toBeVisible({ timeout: 120_000 });
    await page.locator('.cp-id input').fill(EMAIL);
    await page.locator('.cp-pwd input').fill(PASSWORD);
    const checkbox = page.getByRole('checkbox').first();
    if ((await checkbox.count()) > 0 && !(await checkbox.isChecked())) {
        await checkbox.check().catch(() => {});
    }
    await page.locator('.cp-login').click();
    await expect(page).not.toHaveURL(/\/auth\/login/, { timeout: 60_000 });
}

// ==========================================================================
// 시나리오 01: 헤더 검색바에서 자연어 키워드를 입력하면 유사한 프로세스 정의가 표시된다
// ==========================================================================
test('헤더 검색바에서 자연어 키워드를 입력하면 유사한 프로세스 정의가 표시된다', async ({ page }) => {
    await login(page);

    // 헤더 검색바 입력창 (placeholder는 i18n: 'headerMenu.search')
    const searchInput = page.locator('.header-search input').first();
    await expect(searchInput).toBeVisible({ timeout: 30_000 });
    await page.screenshot({ path: shot('01-search-initial'), fullPage: true });

    await searchInput.click();
    await searchInput.fill('휴가');
    await page.screenshot({ path: shot('01-search-input'), fullPage: true });

    const respPromise = page.waitForResponse(
        (r) =>
            r.url().includes('/completion/process-search') &&
            r.request().method() === 'POST',
        { timeout: 60_000 }
    );
    await searchInput.press('Enter');
    const resp = await respPromise;
    expect(resp.status(), 'process-search 응답 상태').toBe(200);
    const body = await resp.json();
    expect(Array.isArray(body), '응답이 배열이어야 함').toBeTruthy();
    expect(body.length, '최대 3건 반환').toBeGreaterThan(0);
    expect(body.length).toBeLessThanOrEqual(3);

    // 결과 패널의 "유사한 프로세스 정의" 헤더가 나타날 때까지 대기
    await expect(page.getByText('유사한 프로세스 정의').first()).toBeVisible({ timeout: 30_000 });
    // 시드된 프로세스 정의명에 "휴가"가 포함된 항목이 결과 카테고리 안에서 보여야 한다.
    // init.sql/시드 데이터에 따라 "휴가신청" 또는 "휴가 신청 프로세스" 둘 중 한 형식으로 나타난다.
    await expect(
        page.locator('text=/휴가\\s*신청|휴가신청/').first()
    ).toBeVisible({ timeout: 30_000 });
    await page.screenshot({ path: shot('01-search-result'), fullPage: true });
});

// ==========================================================================
// 시나리오 02: 유사한 프로세스 정의가 없을 때 200 과 빈 목록을 반환한다
// ==========================================================================
test('유사한 프로세스 정의가 없을 때 200 과 빈 목록을 반환한다', async ({ request }) => {
    const resp = await request.post(`${COMPLETION_DIRECT}/process-search`, {
        headers: { 'X-Forwarded-Host': 'empty-tenant.example.com' },
        data: { query: '휴가' },
    });
    expect(resp.status(), 'empty-tenant 응답 상태').toBe(200);
    const body = await resp.json();
    expect(Array.isArray(body), '응답이 배열이어야 함').toBeTruthy();
    expect(body.length, 'empty-tenant 결과는 0건').toBe(0);
});

// ==========================================================================
// 시나리오 03: 테넌트 subdomain 에 따라 검색 결과가 분리된다
// ==========================================================================
test('테넌트 subdomain 에 따라 검색 결과가 분리된다', async ({ request }) => {
    const localhostResp = await request.post(`${COMPLETION_DIRECT}/process-search`, {
        headers: { 'X-Forwarded-Host': 'localhost' },
        data: { query: '휴가' },
    });
    expect(localhostResp.status()).toBe(200);
    const localhostBody = await localhostResp.json();
    const localhostIds = localhostBody.map((d) =>
        (d?.metadata && d.metadata.processDefinitionId) || ''
    );
    expect(localhostIds, 'localhost 테넌트는 vacation_request_process 포함').toContain(
        'vacation_request_process'
    );
    expect(localhostIds, 'localhost 테넌트는 tenant-b 항목 미포함').not.toContain(
        'meeting_room_process'
    );

    const tenantBResp = await request.post(`${COMPLETION_DIRECT}/process-search`, {
        headers: { 'X-Forwarded-Host': 'tenant-b.example.com' },
        data: { query: '회의실' },
    });
    expect(tenantBResp.status()).toBe(200);
    const tenantBBody = await tenantBResp.json();
    const tenantBIds = tenantBBody.map((d) =>
        (d?.metadata && d.metadata.processDefinitionId) || ''
    );
    expect(tenantBIds, 'tenant-b 테넌트는 meeting_room_process 포함').toContain(
        'meeting_room_process'
    );
    expect(tenantBIds, 'tenant-b 테넌트는 localhost 항목 미포함').not.toContain(
        'vacation_request_process'
    );
});
