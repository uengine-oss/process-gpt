// 워크아이템 화면에서 질문 카드에 답한다 (HITL-07).
//
// usage: node ui_answer.mjs <todoId> <answer> [expectedQuestionSubstring]
// env  : VUE3_DIR(Playwright 를 빌려 쓸 저장소), APP_URL, E2E_USER_EMAIL, E2E_USER_PASSWORD, SHOT_DIR
// stdout 마지막 줄: {"questionShown": bool, "question": str, "clicked": bool}
import { createRequire } from 'node:module';
import { mkdirSync } from 'node:fs';

const [todoId, answer, expected = ''] = process.argv.slice(2);
const require = createRequire(`${process.env.VUE3_DIR}/package.json`);
const { chromium } = require('playwright');
const appUrl = process.env.APP_URL || 'http://localhost:8088';
const shotDir = process.env.SHOT_DIR;
if (shotDir) mkdirSync(shotDir, { recursive: true });

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1200, height: 800 } });
const result = { questionShown: false, question: '', clicked: false };

try {
    const target = `${appUrl}/todolist/${todoId}`;
    await page.goto(target);
    await page.waitForLoadState('networkidle').catch(() => {});

    if (page.url().includes('/auth/login')) {
        await page.locator('input:not([type="password"]):not([type="checkbox"])').first().fill(process.env.E2E_USER_EMAIL);
        await page.locator('input[type="password"]').fill(process.env.E2E_USER_PASSWORD);
        await page.keyboard.press('Enter');
        await page.waitForURL((u) => !u.pathname.startsWith('/auth/'), { timeout: 30000 });
        await page.goto(target);
    }

    const box = page.getByPlaceholder('답변을 입력하세요');
    await box.waitFor({ timeout: 30000 });
    await box.scrollIntoViewIfNeeded();

    // 질문 문구는 입력칸 바로 위 문단이다.
    const card = box.locator('xpath=ancestor::div[contains(@class,"human-query-input")][1]');
    result.question = ((await card.innerText().catch(() => '')) || '').trim();
    result.questionShown = expected ? result.question.includes(expected) : result.question.length > 0;
    if (shotDir) await page.screenshot({ path: `${shotDir}/01-question-card.png` });

    await box.fill(answer);
    await page.getByRole('button', { name: '확인' }).click();
    result.clicked = true;
    await page.waitForTimeout(1500);
    if (shotDir) await page.screenshot({ path: `${shotDir}/02-answered.png` });
} catch (e) {
    console.error(String(e?.stack || e));
    if (shotDir) await page.screenshot({ path: `${shotDir}/error.png` }).catch(() => {});
} finally {
    await browser.close();
}
console.log(JSON.stringify(result));
