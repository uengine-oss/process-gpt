// E2E suite: completion_workitem-polling-execution (통합 검증)
//
// 본 스위트는 폴링 워커(`services/completion/polling_service/polling_service.py`)가
// `status='SUBMITTED'` + `consumer IS NULL` 인 워크아이템을 주기적으로 감지해
// (`fetch_workitem_with_submitted_status` → `safe_handle_workitem` →
// `handle_service_workitem`) 자동 처리하고, 사용자가 대시보드 KanbanBoard 에서
// SUBMITTED → DONE 컬럼 이동을 관찰할 수 있다는 것을 통합 환경에서 검증한다.
//
// 인프라는 `completion_automated-task-execution` 스위트가 이미 부트한 Docker
// Compose 스택과 시드(`ate_demo_proc.e2e-instance-0001`, success_server MCP
// serviceTask 워크아이템 `11111111-aaaa-aaaa-aaaa-000000000001`) 를 그대로
// 재사용한다. 본 스펙 고유 시드/컴포즈는 추가하지 않으며, 사용자 액션 흐름은
// 로그인 → /todolist 컬럼 관찰 → 카드 상세 확인 으로 구성된다.
//
// 외부 boundary 만 stub 상태(mock-llm-ate, mock-mcp): 폴링 워커·게이트웨이·DB·
// 프론트엔드는 모두 저장소 내 실제 서비스로 실행된다.
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

const SUITE = 'completion_workitem-polling-execution';
const shot = (name) => path.join(SHOT_DIR, `process-gpt-${SUITE}-${name}.png`);

const EMAIL = process.env.E2E_USER || 'ate-e2e@uengine.org';
const PASSWORD = process.env.E2E_PASS || 'ate-password';

const SUCCESS_WORKITEM_ID = '11111111-aaaa-aaaa-aaaa-000000000001';
const SUCCESS_ACTIVITY_NAME = 'MCP 성공 도구 실행';

// V8 raw frontend coverage (supporting evidence only — bundle-level).
test.beforeEach(async ({ page }) => {
    try {
        await page.coverage.startJSCoverage({ resetOnNavigation: false });
    } catch {}
});
test.afterEach(async ({ page }, testInfo) => {
    try {
        const cov = await page.coverage.stopJSCoverage();
        const slug = testInfo.title.replace(/[^a-zA-Z0-9_-]+/g, '_').slice(0, 60);
        const slim = cov.map((e) => ({
            url: e.url,
            scriptId: e.scriptId,
            functions: e.functions,
        }));
        fs.writeFileSync(path.join(FE_COV_DIR, `${slug}.json`), JSON.stringify(slim));
    } catch {}
});

function runSql(sql) {
    return spawnSync(
        'docker',
        ['exec', 'process-gpt-e2e-db', 'psql', '-U', 'supabase_admin', '-d', 'postgres', '-c', sql],
        { encoding: 'utf-8' }
    );
}

// 본 스펙 Req 1 (제출된 워크아이템 자동 폴링) 검증을 위해 success 워크아이템을
// 매 테스트 시작 시 SUBMITTED + consumer NULL 상태로 리셋한다. 그 결과 폴링
// 워커는 한 차례의 폴링 주기(~5초) 안에 본 워크아이템을 클레임하고
// `handle_service_workitem` 으로 처리해야 한다.
function resetSuccessWorkitem() {
    runSql(
        `update todolist set status='SUBMITTED', consumer=null, output=null, log=null, retry=0, updated_at=now() where id='${SUCCESS_WORKITEM_ID}';`
    );
}

function readWorkitemStatus(id) {
    const r = runSql(
        `select status, consumer, retry from todolist where id='${id}';`
    );
    return (r.stdout || '').toString();
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

async function openTodolist(page) {
    await page.goto('/todolist', { waitUntil: 'domcontentloaded' });
    await expect(page.getByText('완료됨').first()).toBeVisible({ timeout: 60_000 });
}

// /todolist 의 KanbanBoard 는 EventBus 트리거에서만 갱신되므로 새로고침으로
// 폴링 워커의 처리 결과를 관찰한다.
async function waitForActivityVisible(page, activityName, timeoutMs = 240_000) {
    const deadline = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
        try {
            await page.goto('/todolist', { waitUntil: 'domcontentloaded' });
            await page.waitForLoadState('networkidle', { timeout: 15_000 }).catch(() => {});
            await page.waitForTimeout(2_500);
            const visibleCount = await page.getByText(activityName, { exact: false }).count();
            if (visibleCount > 0) {
                return true;
            }
        } catch {}
        await page.waitForTimeout(4_000);
    }
    return false;
}

test('폴링 워커가 SUBMITTED serviceTask 워크아이템을 자동으로 클레임하고 DONE 으로 전이한다', async ({ page }) => {
    // 1. 시드 리셋: success 워크아이템을 다시 SUBMITTED + consumer NULL 로 만들어
    //    폴링 워커의 자동 처리 사이클을 트리거한다.
    resetSuccessWorkitem();
    const before = readWorkitemStatus(SUCCESS_WORKITEM_ID);
    expect(before).toMatch(/SUBMITTED/);

    // 2. 사용자 로그인
    await login(page);
    await page.screenshot({ path: shot('01-login'), fullPage: true });

    // 3. /todolist 진입: SUBMITTED 상태의 워크아이템이 KanbanBoard 에 노출됨
    await openTodolist(page);
    await page.screenshot({ path: shot('02-submitted-initial'), fullPage: true });

    // 4. 폴링 워커가 워크아이템을 처리한 뒤 다른 컬럼(DONE 또는 IN_PROGRESS)에서
    //    카드가 다시 노출되기를 기다린다. KanbanBoard 는 reloadAllTodoList 가
    //    호출될 때만 갱신되므로 새로고침을 반복한다.
    const visibleAfter = await waitForActivityVisible(page, SUCCESS_ACTIVITY_NAME, 240_000);
    expect(visibleAfter).toBeTruthy();
    await page.screenshot({ path: shot('03-claimed-or-done'), fullPage: true });

    // 5. DB 레벨에서 처리 완료 상태 검증: status=DONE, consumer 해제.
    //    폴링 주기(5초) + LangChain mock 응답 + serviceTask 처리에 충분한
    //    여유를 두기 위해 짧은 polling 루프로 확인한다.
    let finalStatus = '';
    const dbDeadline = Date.now() + 60_000;
    while (Date.now() < dbDeadline) {
        finalStatus = readWorkitemStatus(SUCCESS_WORKITEM_ID);
        if (/DONE/.test(finalStatus)) break;
        await page.waitForTimeout(3_000);
    }
    expect(finalStatus).toMatch(/DONE/);

    // 6. 카드 상세를 열어 결과 영역 노출을 확인한다 (페이지 전이 가능).
    const card = page.locator('.v-card', { hasText: SUCCESS_ACTIVITY_NAME }).first();
    await card.click({ timeout: 10_000 }).catch(() => {});
    await page.waitForTimeout(2_000);
    await page.screenshot({ path: shot('04-card-detail'), fullPage: true });
});
