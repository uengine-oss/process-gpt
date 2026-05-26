// E2E suite: completion_process-definition-search
// Exercises the real browser -> nginx gateway -> completion -> documents
// vector search path for natural-language process-definition search.
// All user-facing scenarios are driven through the Vue SPA header search.
// The mock-llm embedding stub is the only stubbed external boundary.
import { test, expect } from '@playwright/test';
import { fileURLToPath } from 'url';
import path from 'path';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const SHOT_DIR = path.resolve(__dirname, '../results/screenshots');
const shot = (name) =>
    path.join(SHOT_DIR, `process-gpt-completion_process-definition-search-${name}.png`);

const EMAIL = process.env.E2E_USER || 'e2e@uengine.org';
const PASSWORD = process.env.E2E_PASS || 'e2epassword';
// mock-llm control endpoint (host-mapped port from docker-compose.e2e.yml).
const MOCK_LLM_URL = process.env.MOCK_LLM_URL || 'http://localhost:8899';

// --------------------------------------------------------------------------
// Helpers - all user-facing actions go through browser UI interactions.
// --------------------------------------------------------------------------
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

// Lands on an authenticated app page (full layout) where the global header
// search bar is shown. `/` is the public marketing landing page and has no
// header search, so a real in-app route is used.
async function openHome(page) {
    await page.goto('/todolist', { waitUntil: 'domcontentloaded' });
    await expect(searchInput(page)).toBeVisible({ timeout: 60_000 });
}

// The header global search input (Searchbar.vue, `.header-search`). The full
// layout mounts the Searchbar twice (desktop/mobile); pick the visible one.
function searchInput(page) {
    return page.locator('.header-search input').filter({ visible: true }).first();
}

// The search result dropdown panel (Searchbar.vue, `.main-search-box`).
function resultPanel(page) {
    return page.locator('.main-search-box').first();
}

// The "유사한 프로세스 정의" (similar process definitions) result category.
// The panel lists several categories; this scopes assertions to the
// vector-search category produced by POST /process-search.
function similarCategory(page) {
    return resultPanel(page)
        .locator('[role=listbox] > div')
        .filter({ hasText: '유사한 프로세스 정의' });
}

// Types a query into the header search box and submits with Enter.
// Returns the parsed /completion/process-search response body.
async function runSearch(page, keyword) {
    await searchInput(page).click();
    await searchInput(page).fill(keyword);
    const respPromise = page.waitForResponse(
        (r) =>
            r.url().includes('/completion/process-search') &&
            r.request().method() === 'POST',
        { timeout: 120_000 }
    );
    await searchInput(page).press('Enter');
    const resp = await respPromise;
    return resp;
}

// Flips the mock-llm embedding failure toggle (non-user-facing setup call).
async function setEmbedFail(request, enabled) {
    const resp = await request.post(`${MOCK_LLM_URL}/control/embed-fail`, {
        data: { enabled },
    });
    expect(resp.ok(), 'mock-llm 실패 토글 응답').toBeTruthy();
}

// Parses process definition ids out of a /process-search response, the same
// way the frontend (searchVector) does.
function idsOf(docs) {
    return (docs || []).map((d) => {
        try {
            return JSON.parse(String(d.page_content).split(': ')[1]).processDefinitionId;
        } catch {
            return null;
        }
    });
}

// ==========================================================================
// 시나리오 01: 자연어 질의로 유사한 프로세스 정의를 검색한다
// ==========================================================================
test('자연어 질의로 유사한 프로세스 정의를 검색한다', async ({ page }) => {
    await login(page);
    await openHome(page);
    await page.screenshot({ path: shot('01-search-initial'), fullPage: true });

    // 사용자가 검색창에 자연어 질의를 입력한다
    await searchInput(page).click();
    await searchInput(page).fill('휴가');
    await page.screenshot({ path: shot('01-search-input'), fullPage: true });

    // 사용자가 Enter 로 검색을 실행한다
    const respPromise = page.waitForResponse(
        (r) =>
            r.url().includes('/completion/process-search') &&
            r.request().method() === 'POST',
        { timeout: 120_000 }
    );
    await searchInput(page).press('Enter');
    const resp = await respPromise;

    // API 계약: 200 + 최대 3건의 후보 배열
    expect(resp.status(), '검색 응답 상태').toBe(200);
    const body = await resp.json();
    expect(Array.isArray(body), '응답 본문은 배열').toBeTruthy();
    expect(body.length, '후보가 1건 이상').toBeGreaterThan(0);
    expect(body.length, '후보는 최대 3건').toBeLessThanOrEqual(3);

    // "유사한 프로세스 정의" 카테고리에 시드 정의 3건이 표시된다
    const category = similarCategory(page);
    await expect(category).toBeVisible({ timeout: 60_000 });
    await expect(category.getByRole('link'), '후보는 최대 3건').toHaveCount(3);
    for (const name of [
        '휴가 신청 및 승인 프로세스',
        '출장 경비 정산 프로세스',
        '구매 요청 승인 프로세스',
    ]) {
        await expect(
            category.getByRole('heading', { name, exact: true })
        ).toBeVisible();
    }
    await page.screenshot({ path: shot('01-search-result'), fullPage: true });
});

// ==========================================================================
// 시나리오 02: 검색 처리에 실패해도 오류 없이 빈 결과가 표시된다
//   임베딩 외부 경계에 결정적 실패를 주입(mock-llm 토글)한 뒤, 검색이
//   500 오류가 아니라 200 + 빈 목록으로 graceful 하게 마무리되는지 검증한다.
// ==========================================================================
test('검색 처리에 실패해도 오류 없이 빈 결과가 표시된다', async ({ page, request }) => {
    // setup(비 UI): 임베딩 실패 주입
    await setEmbedFail(request, true);
    try {
        await login(page);
        await openHome(page);

        // 사용자가 검색창에 자연어 질의를 입력한다
        await searchInput(page).click();
        await searchInput(page).fill('보고서 작성');
        await page.screenshot({ path: shot('02-search-input'), fullPage: true });

        // 사용자가 Enter 로 검색을 실행한다
        const respPromise = page.waitForResponse(
            (r) =>
                r.url().includes('/completion/process-search') &&
                r.request().method() === 'POST',
            { timeout: 120_000 }
        );
        await searchInput(page).press('Enter');
        const resp = await respPromise;

        // graceful 계약: 검색 실패는 500 이 아니라 200 + 빈 목록
        expect(resp.status(), '검색 실패 시에도 200 상태').toBe(200);
        expect(await resp.json(), '빈 목록 반환').toEqual([]);

        // 화면에는 오류가 아니라 "검색 결과가 없습니다" 빈 상태가 표시된다
        const panel = resultPanel(page);
        await expect(panel.getByText('검색 결과가 없습니다')).toBeVisible({ timeout: 60_000 });
        await expect(panel.getByText('유사한 프로세스 정의')).toHaveCount(0);
        await page.screenshot({ path: shot('02-search-empty'), fullPage: true });
    } finally {
        // teardown(비 UI): 임베딩 동작 복원
        await setEmbedFail(request, false);
    }
});

// ==========================================================================
// 시나리오 03: 검색 결과가 현재 테넌트의 프로세스 정의로 한정된다
//   메인 흐름은 브라우저 검색으로 검증하고, 동일 엔드포인트가 요청 테넌트로
//   결과를 한정하는지는 보조 프로토콜 비교로 확인한다.
// ==========================================================================
test('검색 결과가 현재 테넌트의 프로세스 정의로 한정된다', async ({ page, request }) => {
    await login(page);
    await openHome(page);

    // localhost 테넌트 사용자가 검색한다
    await runSearch(page, '프로세스');

    const panel = resultPanel(page);
    const category = similarCategory(page);
    await expect(category).toBeVisible({ timeout: 60_000 });
    await expect(
        category.getByRole('heading', { name: '휴가 신청 및 승인 프로세스', exact: true })
    ).toBeVisible();
    // 다른 테넌트(tenant-b) 전용 정의는 결과에 포함되지 않는다
    await expect(panel.getByText('외부 테넌트 전용 프로세스')).toHaveCount(0);
    await page.screenshot({ path: shot('03-search-result'), fullPage: true });

    // 보조 프로토콜 검증: 동일 POST /process-search 가 요청 테넌트로 한정된다
    const localhostResp = await request.post('/completion/process-search', {
        data: { query: 'process' },
    });
    expect(localhostResp.status(), 'localhost 검색 상태').toBe(200);
    const localhostIds = idsOf(await localhostResp.json());
    expect(localhostIds, 'localhost 결과에 자사 정의 포함').toContain('e2e_pds_leave');
    expect(localhostIds, 'localhost 결과에 타 테넌트 정의 미포함').not.toContain(
        'e2e_pds_competitor'
    );

    const tenantBResp = await request.post('/completion/process-search', {
        headers: { 'X-Forwarded-Host': 'tenant-b.example.com' },
        data: { query: 'process' },
    });
    expect(tenantBResp.status(), 'tenant-b 검색 상태').toBe(200);
    const tenantBIds = idsOf(await tenantBResp.json());
    expect(tenantBIds, 'tenant-b 결과에 해당 테넌트 정의 포함').toContain(
        'e2e_pds_competitor'
    );
    expect(tenantBIds, 'tenant-b 결과에 localhost 정의 미포함').not.toContain(
        'e2e_pds_leave'
    );
});
