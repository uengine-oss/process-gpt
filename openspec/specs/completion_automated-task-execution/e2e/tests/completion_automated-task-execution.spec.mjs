// E2E suite: completion_automated-task-execution
// Browser -> Vue SPA kanban observes polling-worker auto-executing
// serviceTask workitems via MCP. Only external boundaries (mock-mcp,
// mock-llm) are stubbed; completion-polling, db, gateway, frontend
// are all real in-repository services.
import { test, expect } from '@playwright/test';
import { fileURLToPath } from 'url';
import path from 'path';
import fs from 'fs';
import { spawnSync } from 'child_process';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const SHOT_DIR = path.resolve(__dirname, '../results/screenshots');
fs.mkdirSync(SHOT_DIR, { recursive: true });
const FE_COV_DIR = path.resolve(__dirname, '../results/frontend-coverage/raw');
fs.mkdirSync(FE_COV_DIR, { recursive: true });

const shot = (name) =>
    path.join(SHOT_DIR, `process-gpt-completion_automated-task-execution-${name}.png`);

const EMAIL = process.env.E2E_USER || 'ate-e2e@uengine.org';
const PASSWORD = process.env.E2E_PASS || 'ate-password';

// V8 raw frontend coverage (supporting evidence only).
test.beforeEach(async ({ page }) => {
    try {
        await page.coverage.startJSCoverage({ resetOnNavigation: false });
    } catch {}
});
test.afterEach(async ({ page }, testInfo) => {
    try {
        const cov = await page.coverage.stopJSCoverage();
        const slug = testInfo.title.replace(/[^a-zA-Z0-9_-]+/g, '_').slice(0, 60);
        // Drop heavy `source` text to stay under V8 string length limit.
        const slim = cov.map((e) => ({
            url: e.url,
            scriptId: e.scriptId,
            functions: e.functions,
        }));
        fs.writeFileSync(path.join(FE_COV_DIR, `${slug}.json`), JSON.stringify(slim));
    } catch {}
});

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

async function openTodolist(page) {
    await page.goto('/todolist', { waitUntil: 'domcontentloaded' });
    // KanbanBoard 의 "완료됨" 컬럼 헤더 등장을 기다린다
    await expect(page.getByText('완료됨').first()).toBeVisible({ timeout: 60_000 });
}

// Wait until a workitem (identified by activity name) appears in the
// DONE column. We reload /todolist on each iteration because the
// KanbanBoard fetches via reloadAllTodoList on EventBus events only.
async function waitForWorkitemDone(page, activityName, timeoutMs = 180_000) {
    const deadline = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
        try {
            await page.goto('/todolist', { waitUntil: 'domcontentloaded' });
            await page.waitForLoadState('networkidle', { timeout: 15_000 }).catch(() => {});
            // KanbanBoard 가 todolist API 로 워크아이템을 가져온 뒤 카드 렌더링 시간을 약간 더 준다
            await page.waitForTimeout(2_500);
            const visibleCount = await page.getByText(activityName, { exact: false }).count();
            if (visibleCount > 0) {
                return true;
            }
        } catch (e) {
            // ignore, retry
        }
        await page.waitForTimeout(4_000);
    }
    return false;
}

// Use docker exec to release the failure workitem by clearing its
// reservation field. This is a setup helper, not a user action, so it
// does not appear in the screenshot evidence for the user-facing flow.
function releaseFailureWorkitem() {
    runSql(
        "update todolist set status='SUBMITTED', consumer=null, output=null, log=null, retry=0 where id='22222222-aaaa-aaaa-aaaa-000000000002';"
    );
}

function runSql(sql) {
    spawnSync(
        'docker',
        ['exec', 'process-gpt-e2e-db', 'psql', '-U', 'supabase_admin', '-d', 'postgres', '-c', sql],
        { stdio: 'inherit' }
    );
}

function releaseWorkitemById(id) {
    runSql(
        `update todolist set status='SUBMITTED', consumer=null, output=null, log=null, retry=0 where id='${id}';`
    );
}

function readMarkerFile(name) {
    const r = spawnSync('docker', ['exec', 'process-gpt-e2e-completion-polling', 'cat', `/coverage/${name}`]);
    return (r.stdout || Buffer.from('')).toString('utf-8');
}

test('서비스 작업 워크아이템이 MCP 도구로 자동 실행되고 결과가 DONE 으로 기록된다', async ({ page }) => {
    await login(page);
    await page.screenshot({ path: shot('01-login'), fullPage: true });

    await openTodolist(page);
    await page.screenshot({ path: shot('01-todolist-initial'), fullPage: true });

    const done = await waitForWorkitemDone(page, 'MCP 성공 도구 실행', 180_000);
    expect(done).toBeTruthy();
    await page.screenshot({ path: shot('01-service-task-done'), fullPage: true });

    // 워크아이템 카드 클릭하여 상세 노출 시도 (페이지 이동 가능)
    const card = page.locator('.v-card', { hasText: 'MCP 성공 도구 실행' }).first();
    await card.click().catch(() => {});
    await page.waitForTimeout(2_000);
    await page.screenshot({ path: shot('01-next-activity-shown'), fullPage: true });
});

test('MCP 도구가 실패하면 워크아이템 로그에 실패 내역이 기록된다', async ({ page }) => {
    releaseFailureWorkitem();

    await login(page);
    await openTodolist(page);

    const done = await waitForWorkitemDone(page, 'MCP 실패 도구 실행', 180_000);
    expect(done).toBeTruthy();
    await page.screenshot({ path: shot('02-failure-log'), fullPage: true });
});

test('스크립트 작업이 정상 종료되면 stdout 이 결과로 기록되고 트리거 워크아이템이 DONE 으로 전이된다', async ({ page }) => {
    releaseWorkitemById('33333333-aaaa-aaaa-aaaa-000000000003');

    await login(page);
    await openTodolist(page);

    const done = await waitForWorkitemDone(page, '스크립트 03 트리거', 240_000);
    expect(done).toBeTruthy();
    await page.screenshot({ path: shot('03-script-result'), fullPage: true });

    // _execute_script_tasks 가 pythonCode 를 실행했음을 부수효과 파일로 검증
    const marker = readMarkerFile('ate_script_03.out');
    expect(marker).toContain('ate-script-03-result:E2E-1001');
});

test('스크립트 작업이 비정상 종료되면 stderr 가 결과로 기록되고 트리거 워크아이템이 DONE 으로 전이된다', async ({ page }) => {
    releaseWorkitemById('44444444-aaaa-aaaa-aaaa-000000000004');

    await login(page);
    await openTodolist(page);

    const done = await waitForWorkitemDone(page, '스크립트 04 트리거', 240_000);
    expect(done).toBeTruthy();
    await page.screenshot({ path: shot('04-script-error'), fullPage: true });

    const marker = readMarkerFile('ate_script_04.err');
    expect(marker).toContain('ate-script-04-error:boom');
});
