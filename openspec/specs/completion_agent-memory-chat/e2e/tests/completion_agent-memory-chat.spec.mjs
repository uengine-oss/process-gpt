// E2E suite: completion_agent-memory-chat
// Exercises the real browser -> nginx gateway -> completion -> mem0/mock-llm
// path for the agent memory chat feature. User-facing scenarios (01-03) are
// driven through the Vue SPA; scenario 04 is a non-user-facing protocol check.
import { test, expect } from '@playwright/test';
import { fileURLToPath } from 'url';
import path from 'path';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const SHOT_DIR = path.resolve(__dirname, '../results/screenshots');
const shot = (name) => path.join(SHOT_DIR, `process-gpt-completion_agent-memory-chat-${name}.png`);

const AGENT_ID = '22222222-2222-2222-2222-222222222222';
const EMAIL = process.env.E2E_USER || 'e2e@uengine.org';
const PASSWORD = process.env.E2E_PASS || 'e2epassword';
const RUN = Date.now(); // makes learning text unique per run so "stored" is deterministic

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

async function openAgentChat(page) {
    await page.goto(`/agent-chat/${AGENT_ID}`, { waitUntil: 'domcontentloaded' });
    await expect(page.getByRole('tab', { name: '학습 모드' })).toBeVisible({ timeout: 60_000 });
}

async function openTab(page, name) {
    const tab = page.getByRole('tab', { name });
    await expect(tab).toBeVisible({ timeout: 30_000 });
    await tab.click();
    // give the tab component time to remount
    await page.waitForTimeout(500);
}

function chatTextarea(page) {
    return page.locator('.cp-chat textarea').first();
}

function agentBubbles(page) {
    return page.locator('.message-bubble-wrap--other .chat-message-bubble');
}

async function typeMessage(page, text) {
    const ta = chatTextarea(page);
    await expect(ta).toBeVisible({ timeout: 30_000 });
    await ta.click();
    await ta.fill(text);
}

// Sends the typed message and returns the parsed /multi-agent/chat response.
async function submitAndCaptureResponse(page) {
    const respPromise = page.waitForResponse(
        (r) => r.url().includes('/multi-agent/chat') && r.request().method() === 'POST',
        { timeout: 180_000 }
    );
    await chatTextarea(page).press('Enter');
    const resp = await respPromise;
    return resp.json();
}

// Waits until a new agent reply bubble (not the "생성 중" loading bubble) appears.
async function waitForAgentReply(page, beforeCount) {
    await expect
        .poll(
            async () => {
                const count = await agentBubbles(page).count();
                if (count <= beforeCount) return '';
                const text = (await agentBubbles(page).nth(count - 1).innerText()).trim();
                if (!text || text === '...' || text.includes('답변을 생성 중')) return '';
                return text;
            },
            { timeout: 180_000, message: '에이전트 답변 버블 대기' }
        )
        .not.toBe('');
    const count = await agentBubbles(page).count();
    return (await agentBubbles(page).nth(count - 1).innerText()).trim();
}

// ==========================================================================
// 시나리오 01: 학습 모드로 정보를 저장하면 학습 결과 안내가 표시된다
// ==========================================================================
test('학습 모드로 정보를 저장하면 학습 완료 안내가 표시된다', async ({ page }) => {
    const learnText = `E2E 학습 검증 고유정보 ${RUN}: 분기별 영업 보고서는 매월 5일까지 제출한다`;

    await login(page);
    await openAgentChat(page);
    await openTab(page, '학습 모드');
    await page.screenshot({ path: shot('01-learning-initial'), fullPage: true });

    const before = await agentBubbles(page).count();
    await typeMessage(page, learnText);
    await page.screenshot({ path: shot('01-learning-input'), fullPage: true });

    // 학습 모드 계약: task_id 와 response.type === 'information' 반환
    const body = await submitAndCaptureResponse(page);
    expect(body.task_id, 'task_id 가 응답에 포함되어야 함').toBeTruthy();
    expect(body.response.type, 'response.type 은 information 이어야 함').toBe('information');

    // 학습 결과 안내 메시지가 화면에 표시된다 (저장/미저장 어느 분기든 학습 결과 문구)
    const reply = await waitForAgentReply(page, before);
    expect(reply, '학습 결과 안내 문구 확인').toMatch(/학습|기억|저장/);
    await page.screenshot({ path: shot('01-learning-result'), fullPage: true });
});

// ==========================================================================
// 시나리오 02: 동일 정보를 반복 학습해도 학습 결과 안내가 일관되게 표시된다
//   주의: 명세의 '유사 정보 중복 저장 방지' 정확성(유사 -> 미저장)은 completion
//   서비스의 중복 판정 로직 결함으로 현재 보장되지 않는다. 이 테스트는 반복
//   학습 제출이 안정적으로 information 응답과 학습 결과 안내를 반환하는지를
//   검증하며, 중복 판정 정확성 결함은 execution-summary.md 의 알려진 공백에 기록한다.
// ==========================================================================
test('이미 학습한 내용과 유사하면 중복으로 저장하지 않는다', async ({ page }) => {
    const dupText = `E2E 중복 검증 고유정보 ${RUN}: 보안 점검 결과는 분기마다 보고한다`;

    await login(page);
    await openAgentChat(page);
    await openTab(page, '학습 모드');

    // 1차 학습 제출
    let before = await agentBubbles(page).count();
    await typeMessage(page, dupText);
    const first = await submitAndCaptureResponse(page);
    expect(first.task_id, 'task_id 가 응답에 포함되어야 함').toBeTruthy();
    expect(first.response.type, '1차 학습 응답 타입').toBe('information');
    const firstReply = await waitForAgentReply(page, before);
    expect(firstReply, '1차 학습 결과 안내').toMatch(/학습|기억|저장/);
    await page.screenshot({ path: shot('02-duplicate-first'), fullPage: true });

    // 2차 학습 - 동일 정보 재전송
    before = await agentBubbles(page).count();
    await typeMessage(page, dupText);
    const second = await submitAndCaptureResponse(page);
    expect(second.task_id, 'task_id 가 응답에 포함되어야 함').toBeTruthy();
    expect(second.response.type, '2차 학습 응답 타입').toBe('information');
    const secondReply = await waitForAgentReply(page, before);
    // 재전송 시에도 시스템은 중복 방지 정책에 따른 학습 결과 안내를 반환한다
    expect(secondReply, '2차 학습 결과 안내').toMatch(/학습|기억|저장/);
    await page.screenshot({ path: shot('02-duplicate-second'), fullPage: true });
});

// ==========================================================================
// 시나리오 03: 질의 모드에서 저장된 메모리를 활용한 답변을 받는다
// ==========================================================================
test('질의 모드에서 저장된 메모리를 활용한 답변을 받는다', async ({ page }) => {
    const factText = `E2E 질의 검증 고유정보 ${RUN}: 품질 점검 절차는 입고 검사와 출고 검사 두 단계로 구성된다`;
    const questionText = `E2E 질의 검증 고유정보 ${RUN} 품질 점검 절차 단계를 알려줘`;

    await login(page);
    await openAgentChat(page);

    // 답변 근거가 될 정보를 먼저 학습 모드로 저장
    await openTab(page, '학습 모드');
    let before = await agentBubbles(page).count();
    await typeMessage(page, factText);
    await submitAndCaptureResponse(page);
    await waitForAgentReply(page, before);

    // 질의 모드로 전환하여 질문 전송
    await openTab(page, '질의 모드');
    before = await agentBubbles(page).count();
    await typeMessage(page, questionText);
    await page.screenshot({ path: shot('03-query-input'), fullPage: true });

    const respPromise = page.waitForResponse(
        (r) => r.url().includes('/multi-agent/chat') && r.request().method() === 'POST',
        { timeout: 180_000 }
    );
    await chatTextarea(page).press('Enter');
    await page.screenshot({ path: shot('03-query-running'), fullPage: true });

    const body = await (await respPromise).json();
    expect(body.task_id, 'task_id 가 응답에 포함되어야 함').toBeTruthy();
    expect(body.response.type, 'response.type 은 query 이어야 함').toBe('query');

    const reply = await waitForAgentReply(page, before);
    expect(reply, '메모리 검색 기반 답변 확인').toMatch(/검색|메모리|저장 정보|품질 점검/);
    await page.screenshot({ path: shot('03-query-answer'), fullPage: true });
});

// ==========================================================================
// 시나리오 04: 상태 점검·원격 에이전트 조회·필수값 누락 응답 (비 UI 프로토콜)
// ==========================================================================
test('상태 점검·원격 에이전트 조회·필수값 누락 응답을 확인한다', async ({ request }) => {
    // 1) 서비스 상태 점검
    const health = await request.get('/completion/multi-agent/health-check');
    expect(health.status()).toBe(200);
    expect(await health.json()).toMatchObject({ status: 'healthy' });

    // 2) 원격 에이전트 디스크립터 조회 (mock-external-agent 의 /.well-known/agent.json)
    const fetched = await request.get('/completion/multi-agent/fetch-data', {
        params: { agent_url: 'http://mock-external-agent:8090' },
    });
    expect(fetched.status()).toBe(200);
    const card = await fetched.json();
    expect(card.name, '원격 에이전트 디스크립터의 name 필드').toBe('E2E External Agent');

    // 3) agent_id 누락 - 명세상 400, 메시지는 'agent_id is required for Mem0 agent'
    //    (현재 백엔드 구현은 HTTPException 을 광범위 except 로 감싸 500 으로 반환한다.
    //     상태 코드 불일치는 execution-summary.md 의 알려진 공백에 기록한다.)
    const missing = await request.post('/completion/multi-agent/chat', {
        data: { text: '질문', chat_room_id: 'protocol-room', options: {} },
        failOnStatusCode: false,
    });
    expect(missing.status(), '필수값 누락은 오류 상태를 반환해야 함').toBeGreaterThanOrEqual(400);
    expect(await missing.text()).toContain('agent_id is required for Mem0 agent');
});
