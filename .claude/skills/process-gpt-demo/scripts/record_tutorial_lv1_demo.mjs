#!/usr/bin/env node
// 튜토리얼 영상 시리즈 1/5 — "프로세스 생성과 실행" (튜토리얼 Lv.1)
// scenario-tutorial-lv1.md 참조. 오프닝/클로징 슬라이드 + 실제 Process GPT UI
// (로그인 · 정의화면 · AI채팅 프롬프트 실타이핑 · 생성된 BPMN · 인스턴스 실행/완료) 혼합.
//
// 실행: node record_tutorial_lv1_demo.mjs [outDir] [BASE]
import { chromium } from '../../../../services/frontend/node_modules/playwright/index.mjs';
import { makeSlides } from './lib_tutorial_slides.mjs';
import fs from 'node:fs/promises';
import path from 'node:path';

const BASE = process.argv[3] || 'http://localhost:8088';
const root = path.resolve(process.argv[2] || 'demo-recordings/tutorial-lv1-process-basics');
const rawDir = path.join(root, 'raw');
await fs.mkdir(rawDir, { recursive: true });

// 이번 실행에서 실제로 만들어진 값 (scenario-tutorial-lv1.md §0).
const PROC_DEF_ID = 'b2f50721_3a7b_4f83_975e_cc046c8618c6';
const ROOM_ID     = '0867ccac-f1ac-4b9f-a912-d2d2c3d9b102';
const WORKITEM_1  = 'd7ac8ebc-f15b-44cf-a95b-46a37d736ac6'; // 요청사항 입력 (COMPLETED)
const WORKITEM_2  = '1b91eb4f-f317-4e61-88e8-55f9dea925c7'; // 제안서 작성 및 전달 (COMPLETED)
const PROMPT = '영업 제안서 작성 프로세스를 만들어줘. 고객이 요청사항을 입력하면 영업 담당자가 제안서를 작성해서 전달하는 2단계 프로세스야. 각 단계에 맞는 입력 폼도 만들어줘.';

const browser = await chromium.launch({ headless: true });
const context = await browser.newContext({
  viewport: { width: 1920, height: 1080 },
  recordVideo: { dir: rawDir, size: { width: 1920, height: 1080 } },
});
const page = await context.newPage();
const slide = makeSlides(page, { level: 1, brand: 'PROCESS GPT · TUTORIAL Lv.1', foot: 'tutorial-lv1 · 프로세스 생성과 실행 · 1/5' });

const started = Date.now();
const timings = [];
const mark = (scene) => { timings.push({ scene, start_sec: Number(((Date.now() - started) / 1000).toFixed(2)) }); console.log('scene', scene, ((Date.now()-started)/1000).toFixed(1)+'s'); };
const shot = (n) => page.screenshot({ path: path.join(root, `scene-${String(n).padStart(2,'0')}.png`) }).catch(()=>{});

async function login() {
  await page.goto(`${BASE}/auth/login`, { waitUntil: 'load', timeout: 30000 });
  await page.waitForSelector('input[type="text"]', { timeout: 15000 });
  await page.locator('input[type="text"]').first().click();
  await page.locator('input[type="text"]').first().type('demo@localhost', { delay: 45 });
  await page.locator('input[type="password"]').first().click();
  await page.locator('input[type="password"]').first().type('Demo1234!', { delay: 45 });
}

// ── Scene 1 — 오프닝 ─────────────────────────────────────────────
mark(1);
await slide({
  title: '프로세스 생성과 실행',
  body: 'ProcessGPT 튜토리얼 Lv.1 — 영업 제안서 작성 프로세스를 직접 만들고, 실행해서 끝까지 완료시켜 봅니다.\n고객이 요청사항을 입력하면 영업 담당자가 제안서를 작성해 전달하는 2단계 업무 흐름입니다.',
  flow: ['고객 · 요청사항 입력', '영업 담당자 · 제안서 작성', '전달 완료'],
});
await page.waitForTimeout(900); await shot(1); await page.waitForTimeout(16500);

// ── Scene 2 — 이번 편에서 배울 것 ────────────────────────────────
mark(2);
await slide({
  title: '이번 편에서 배우는 기본 사이클',
  body: 'ProcessGPT의 가장 기본이 되는 네 단계 — 정의, 저장, 실행, 완료를 한 바퀴 돌립니다.',
  cards: [
    { h: '① 정의 (AI 채팅)', p: '수동 BPMN 팔레트 대신, 자연어로 요청하면 딥에이전트가 프로세스와 입력 폼을 자동 생성합니다.' },
    { h: '② 저장', p: '생성된 프로세스 정의가 proc_def에 영속화됩니다.' },
    { h: '③ 실행', p: '인스턴스를 시작해 각 단계의 폼을 제출하며 진행합니다.' },
    { h: '④ 완료', p: '워크아이템 상태 전이를 따라 인스턴스가 COMPLETED에 도달합니다.' },
  ],
});
await page.waitForTimeout(900); await shot(2); await page.waitForTimeout(16000);

// ── Scene 3 — 로그인 (실화면) ────────────────────────────────────
mark(3);
await login();
await page.waitForTimeout(600); await shot(3);
await page.locator('button:has-text("로그인")').click();
await page.waitForTimeout(4000);

// ── Scene 4 — 정의 화면 개요 (실화면) ────────────────────────────
mark(4);
await page.goto(`${BASE}/definition-map`, { waitUntil: 'load', timeout: 30000 });
await page.waitForTimeout(3500); await shot(4);
await page.waitForTimeout(11500);

// ── Scene 5 — AI 채팅에 프롬프트 실타이핑 + 전송 (실화면) ─────────
mark(5);
const ta = page.locator('textarea:not([aria-hidden="true"])').first();
await ta.click();
await ta.type(PROMPT, { delay: 22 });   // 실제 타이핑이 영상에 살아있게
await page.waitForTimeout(600); await shot(5);
await page.locator('.cp-send:visible').first().click();  // 실제 전송
await page.waitForTimeout(7000);        // 사용자 메시지 + 생성 시작이 보이도록
await shot('05b');
await page.waitForTimeout(7500);

// ── Scene 6 — 생성 결과 (사전 생성된 대화방으로 점프) ────────────
// LLM 생성 대기(수 분)를 건너뛰고, 같은 프롬프트로 이미 완성된 대화방을 보여준다.
mark(6);
await page.goto(`${BASE}/chat?roomId=${ROOM_ID}`, { waitUntil: 'load', timeout: 30000 });
await page.waitForTimeout(3500);
await page.mouse.wheel(0, 500);
await page.waitForTimeout(1200); await shot(6);
await page.waitForTimeout(13500);

// ── Scene 7 — 생성된 BPMN 프로세스 정의 (실화면) ─────────────────
mark(7);
await page.goto(`${BASE}/definitions/${PROC_DEF_ID}`, { waitUntil: 'load', timeout: 30000 });
await page.waitForTimeout(6000); await shot(7);
await page.waitForTimeout(10500);

// ── Scene 8 — 실행: 1단계(요청사항 입력) 완료 워크아이템 ─────────
mark(8);
await page.goto(`${BASE}/todolist/${WORKITEM_1}`, { waitUntil: 'load', timeout: 30000 });
await page.waitForTimeout(5000); await shot(8);
await page.waitForTimeout(9000);

// ── Scene 9 — 실행: 2단계(제안서 작성 및 전달) 완료 + 컨텍스트 이어받기 ─
mark(9);
await page.goto(`${BASE}/todolist/${WORKITEM_2}`, { waitUntil: 'load', timeout: 30000 });
await page.waitForTimeout(5000); await shot(9);
await page.waitForTimeout(11000);

// ── Scene 10 — 클로징 ───────────────────────────────────────────
mark(10);
await slide({
  title: '한 바퀴 완주했습니다',
  body: '자연어 한 문장으로 프로세스를 정의하고, 저장하고, 실행해 COMPLETED까지 확인했습니다. 이것이 ProcessGPT의 기본 사이클입니다.',
  cards: [
    { h: '오늘 만든 것', p: '영업 제안서 작성 프로세스 (고객 요청 입력 → 영업 담당자 제안서 작성), 인스턴스 실행 후 COMPLETED.' },
    { h: '다음 편 예고 · Lv.2', p: 'AI 에이전트를 활용한 제안서 작성 — 오늘 만든 이 프로세스에 에이전트를 붙여 제안서를 자동으로 작성해 봅니다.' },
  ],
});
await page.waitForTimeout(900); await shot(10); await page.waitForTimeout(17000);

const video = page.video();
await context.close();
await browser.close();
const recorded = await video.path();
await fs.rm(path.join(rawDir, 'demo-raw.webm'), { force: true });
await fs.rename(recorded, path.join(rawDir, 'demo-raw.webm'));
await fs.writeFile(path.join(root, 'scenes-timing.json'), JSON.stringify(timings, null, 2));
console.log(JSON.stringify({ output: path.join(rawDir, 'demo-raw.webm'), timings }, null, 2));
