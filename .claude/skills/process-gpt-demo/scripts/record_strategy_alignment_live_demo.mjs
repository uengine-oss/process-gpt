#!/usr/bin/env node
import { chromium } from '../../../../services/frontend/node_modules/playwright/index.mjs';
import fs from 'node:fs/promises';
import path from 'node:path';

const root = path.resolve(process.argv[2] || 'demo-recordings/strategy-alignment-check-live');
const rawDir = path.join(root, 'raw');
await fs.mkdir(rawDir, { recursive: true });
const browser = await chromium.launch({ headless: true });
const context = await browser.newContext({
  viewport: { width: 1920, height: 1080 },
  recordVideo: { dir: rawDir, size: { width: 1920, height: 1080 } },
});
const page = await context.newPage();
const started = Date.now();
const timings = [];
const mark = scene => timings.push({ scene, start_sec: Number(((Date.now() - started) / 1000).toFixed(2)) });
const shot = async scene => page.screenshot({ path: path.join(root, `scene-${String(scene).padStart(2, '0')}.png`) });

async function slide(title, body, flow = '') {
  await page.setContent(`<!doctype html><html lang="ko"><head><meta charset="utf-8"><style>
  *{box-sizing:border-box}body{margin:0;background:#07111f;color:#eef5ff;font-family:-apple-system,BlinkMacSystemFont,"Pretendard",sans-serif}.shell{height:1080px;padding:76px 90px;background:radial-gradient(circle at 88% 3%,#1b497a 0,transparent 35%),linear-gradient(135deg,#07111f,#0d1c31)}.brand{color:#8fbfff;font-weight:800;letter-spacing:.08em;font-size:23px}.brand:before{content:'●';color:#4f9cff;margin-right:16px;text-shadow:0 0 20px #4f9cff}h1{font-size:64px;line-height:1.14;margin:58px 0 28px;letter-spacing:-.05em;white-space:pre-line}.body{font-size:27px;line-height:1.62;color:#aebfd2;white-space:pre-line}.flow{display:flex;gap:16px;align-items:center;margin-top:48px}.node{padding:18px 25px;border:1px solid #3d6791;background:#142c49;border-radius:17px;font-size:21px;font-weight:750}.accent{background:#143d67;border-color:#59a3f5}.green{background:#123a30;border-color:#5dcf9b}.arrow{font-size:31px;color:#66aaf7}.foot{position:absolute;left:90px;right:90px;bottom:48px;display:flex;justify-content:space-between;color:#71879c;font-size:17px}</style></head><body><main class="shell"><div class="brand">PROCESS GPT · STRATEGY ALIGNMENT</div><h1>${title}</h1><div class="body">${body}</div><div class="flow">${flow}</div><div class="foot"><span>strategy-alignment-check · live demo</span><span>Process GPT + Playwright</span></div></main></body></html>`);
}

// Scene 1: short explanation only.
mark(1);
await slide('설명보다 중요한 것은\n실제 시스템의 동작입니다', '전략 보드에서 원본 데이터를 확인하고,\n실제 API 화면에서 요청을 입력·실행해 결과를 검증합니다.', '<div class="node">전략 보드</div><div class="arrow">→</div><div class="node accent">정합성 API 실행</div><div class="arrow">→</div><div class="node green">실제 응답 확인</div>');
await page.waitForTimeout(900); await shot(1); await page.waitForTimeout(9500);

// Scene 2: actual Process GPT login and Strategy Board.
mark(2);
await page.goto('http://127.0.0.1:5173/auth/login', { waitUntil: 'load' });
await page.waitForSelector('input[type="text"]');
await page.locator('input[type="text"]').first().fill('demo@localhost');
await page.locator('input[type="password"]').first().fill('Demo1234!');
await page.waitForTimeout(1000);
await page.getByRole('button', { name: /로그인/ }).click();
await page.waitForTimeout(2500);
await page.goto('http://127.0.0.1:5173/strategy-board', { waitUntil: 'load' });
const strategyCard = page.getByText('교육·컨설팅 기반 리드 전환 프로세스 강화', { exact: true });
await strategyCard.waitFor();
await strategyCard.scrollIntoViewIfNeeded();
await strategyCard.evaluate(el => { const card = el.closest('.v-card') || el.parentElement; card.style.outline='5px solid #4f9cff'; card.style.boxShadow='0 0 35px #4f9cff99'; });
await page.waitForTimeout(1200); await shot(2); await page.waitForTimeout(11500);

// Scene 3: operate the integrated Strategy Board alignment dialog.
mark(3);
await page.getByTestId('open-alignment-check').click();
await page.getByTestId('alignment-dialog').waitFor();
await page.getByTestId('alignment-process-select').click();
await page.locator('.v-overlay .v-list-item').filter({ hasText: 'uengine.org 전략 수립 프로세스' }).first().click();
await page.getByTestId('alignment-description').locator('textarea').fill(
  '교육 웨비나 고객 문의를 자동 분류하고 후속 상담 담당자에게 배정해 응답 리드타임을 줄이는 프로세스'
);
await page.waitForTimeout(1400);
await page.getByTestId('run-alignment-check').click();
await page.getByTestId('alignment-status').waitFor();
await page.waitForTimeout(1400);
await page.getByTestId('alignment-candidate-0').locator('input[type="checkbox"]').check({ force: true });
await page.getByTestId('link-alignment-kpis').waitFor();
await page.waitForFunction(() => !document.querySelector('[data-testid="link-alignment-kpis"]')?.disabled);
await shot(3);
await page.waitForTimeout(10500);
await page.getByTestId('link-alignment-kpis').click();
await page.waitForTimeout(3500);

// Scene 4: execute again in the same product UI with an unrelated description.
mark(4);
await page.getByTestId('open-alignment-check').click();
await page.getByTestId('alignment-dialog').waitFor();
await page.getByTestId('alignment-description').locator('textarea').fill('사내 주차장 조명 교체 일정 관리');
await page.waitForTimeout(1000);
await page.getByTestId('run-alignment-check').click();
await page.getByTestId('alignment-empty').waitFor();
await page.waitForTimeout(1200);
await shot(4); await page.waitForTimeout(12500);

// Scene 5: final principle slide.
mark(5);
await slide('확인은 필수,\n결정은 사람에게', '후보가 있어도 자동 연결하지 않습니다.\n선택한 KPI만 연결하고, 없음·미연결·확인 불가 결과까지 기록합니다.', '<div class="node">후보 제시</div><div class="arrow">→</div><div class="node accent">사용자 선택</div><div class="arrow">→</div><div class="node green">strategyAlignment 기록</div>');
await page.waitForTimeout(900); await shot(5); await page.waitForTimeout(14500);

const video = page.video();
await context.close(); await browser.close();
const recorded = await video.path();
await fs.rm(path.join(rawDir, 'demo-raw.webm'), { force: true });
await fs.rename(recorded, path.join(rawDir, 'demo-raw.webm'));
await fs.writeFile(path.join(root, 'scenes-timing.json'), JSON.stringify(timings, null, 2));
console.log(JSON.stringify({ output: path.join(rawDir, 'demo-raw.webm'), timings }, null, 2));
