// 실제 SPA 인앱 알림 표시 E2E (시나리오 05).
//
// Real-Frontend Rule 재평가: completion_notification-push-delivery 명세의
// "미처리 알림 자동 전달" 요구사항은 외부 FCM 푸시뿐 아니라 SPA 의 헤더
// 벨 + 드롭다운(`NotificationDD.vue`) 으로도 사용자에게 전달된다. 본
// 테스트는 docker-compose.e2e.yml 의 frontend + gateway(:8088) 진입점을
// 통해 로그인 → 알림 행 INSERT → realtime 수신 → 벨 배지 → 드롭다운 클릭
// → `is_checked=true` 의 사용자 워크플로우를 구동하고 스크린샷을 남긴다.
//
// 외부 FCM 도달은 본 파일의 검증 대상이 아니다 (시나리오 03/04 가 담당).
// 새 알림 행은 `consumer = 'inapp-ui-test'` 로 INSERT 해 폴링 워커가
// 클레임하지 않도록 한다.
import { test, expect } from '@playwright/test';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const SCREENSHOT_DIR = path.resolve(__dirname, '../results/screenshots');
const ARTIFACT_DIR = path.resolve(__dirname, '../results/artifacts');
fs.mkdirSync(SCREENSHOT_DIR, { recursive: true });
fs.mkdirSync(ARTIFACT_DIR, { recursive: true });

const PROJECT_PREFIX = 'process-gpt-completion_notification-push-delivery-05';
const EMAIL = process.env.E2E_FCM_UI_USER || 'e2e-fcm-ui@uengine.org';
const PASSWORD = process.env.E2E_FCM_UI_PASS || 'e2epassword';
const SUPABASE_REST = process.env.SUPABASE_REST_URL || 'http://localhost:54321/rest/v1';
const SERVICE_KEY = process.env.SERVICE_ROLE_KEY || process.env.SUPABASE_SERVICE_ROLE_KEY || '';
const NOTIFICATION_ID = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeee0005';

function shot(page, checkpoint) {
    return page.screenshot({
        path: path.join(SCREENSHOT_DIR, `${PROJECT_PREFIX}-${checkpoint}.png`),
        fullPage: true,
    });
}

function writeArtifact(name, data) {
    fs.writeFileSync(path.join(ARTIFACT_DIR, name), JSON.stringify(data, null, 2));
}

function restHeaders() {
    if (!SERVICE_KEY) {
        throw new Error('SERVICE_ROLE_KEY 가 설정되어 있지 않습니다. 인앱 UI 시나리오는 PostgREST 로 알림 행을 INSERT 하기 위해 service-role 키가 필요합니다.');
    }
    return {
        apikey: SERVICE_KEY,
        Authorization: `Bearer ${SERVICE_KEY}`,
        'Content-Type': 'application/json',
        Prefer: 'return=representation',
    };
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

test('로그인한 사용자는 새 알림이 도착하면 헤더 벨 배지와 드롭다운에서 확인하고 클릭으로 읽음 처리할 수 있다', async ({ page, request }) => {
    test.setTimeout(180_000);

    // 0) 사전 정리: 이전 실행 잔존 행 제거 (멱등성)
    await request.delete(
        `${SUPABASE_REST}/notifications?user_id=eq.${encodeURIComponent(EMAIL)}`,
        { headers: restHeaders() },
    );

    // 1) 로그인
    await login(page);

    // 2) 메인 레이아웃 + 벨 아이콘 노출 대기
    const bell = page.locator('button:has(i[class*="bell"]), button:has(svg[class*="bell"]), .position-realtive').first();
    // NotificationDD 의 벨 버튼은 `<v-btn icon>` 안에 `Icons[icon=bell-bing-line-duotone]` 컴포넌트를 렌더한다.
    // 스택에 따라 i/svg/span 으로 컴파일되므로 다중 셀렉터로 견고하게 잡는다.
    await expect(bell).toBeVisible({ timeout: 60_000 });
    await shot(page, '01-after-login-bell-idle');

    // 3) PostgREST 로 인앱 알림 행 INSERT (consumer 세팅 — 폴링 워커가 클레임하지 않도록)
    const insertPayload = {
        id: NOTIFICATION_ID,
        user_id: EMAIL,
        title: '신규 워크아이템',
        description: '담당 업무를 확인하세요',
        type: 'workitem',
        url: '/todolist',
        is_checked: false,
        from_user_id: '프로세스봇',
        tenant_id: 'localhost',
        consumer: 'inapp-ui-test',
        time_stamp: new Date().toISOString(),
    };
    const insertRes = await request.post(`${SUPABASE_REST}/notifications`, {
        headers: restHeaders(),
        data: insertPayload,
    });
    expect([200, 201]).toContain(insertRes.status());

    // 4) realtime 수신 → notiCount > 0 → 벨 옆 `.notify` 활성화 대기
    const notifyDot = page.locator('.notify');
    await expect(notifyDot).toBeVisible({ timeout: 30_000 });
    await shot(page, '02-bell-badge-active');

    // 5) 벨 클릭 → 드롭다운 오픈 → 새 알림 항목 노출 확인
    await bell.click();
    const dropdownItem = page.locator('.notification-dd-box .v-list-item', { hasText: '신규 워크아이템' }).first();
    await expect(dropdownItem).toBeVisible({ timeout: 15_000 });
    await expect(page.locator('.notification-dd-box')).toContainText('담당 업무를 확인하세요');
    await shot(page, '03-dropdown-list');

    // 6) 항목 클릭 → 라우팅 + is_checked 마킹
    await Promise.all([
        page.waitForURL(/\/todolist/, { timeout: 30_000 }),
        dropdownItem.click(),
    ]);
    await shot(page, '04-after-click-routed');

    // 7) DB 에서 is_checked 검증
    const verifyRes = await request.get(
        `${SUPABASE_REST}/notifications?id=eq.${NOTIFICATION_ID}&select=id,user_id,is_checked,url,consumer`,
        { headers: restHeaders() },
    );
    expect(verifyRes.ok()).toBe(true);
    const rows = await verifyRes.json();
    expect(rows.length).toBeGreaterThan(0);
    expect(rows[0].is_checked).toBe(true);

    writeArtifact('05-inapp-display.json', {
        insertPayload,
        verifiedRow: rows[0],
        note: '인앱 UI 가 클릭 시 backend.setNotifications 를 호출해 is_checked=true 로 마킹함을 검증',
    });
});
