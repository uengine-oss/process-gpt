#!/usr/bin/env node
// Prompt Chaining agentic pattern demo recording (English) — scenario-9-prompt-chaining.en.md
// Opening/closing slides + real Process GPT UI (English locale: login/chat creation/BPMN/agent delegation).
import { chromium } from '../../../../services/frontend/node_modules/playwright/index.mjs';
import fs from 'node:fs/promises';
import path from 'node:path';

const BASE = process.argv[3] || 'http://localhost:5199';
const root = path.resolve(process.argv[2] || 'demo-recordings/prompt-chaining-demo-en');
const rawDir = path.join(root, 'raw');
await fs.mkdir(rawDir, { recursive: true });

const LOGGED_OUT_STATE = 'demo-recordings/prompt-chaining-demo/scripts/en-state-loggedout.json';
const ROOM_ID = '468a73b4-bba3-487d-a302-1edf23543d71';
const TREND_WORKITEM_ID = '7c4fc40f-a830-4dfc-b0e2-4c0405f216e7';
const EMAIL_WORKITEM_ID = '112af58c-0c6b-4634-ab13-7ca7399657ff';

const browser = await chromium.launch({ headless: true });
const context = await browser.newContext({
  viewport: { width: 1920, height: 1080 },
  recordVideo: { dir: rawDir, size: { width: 1920, height: 1080 } },
  storageState: LOGGED_OUT_STATE,
});
const page = await context.newPage();
const started = Date.now();
const timings = [];
const mark = scene => { timings.push({ scene, start_sec: Number(((Date.now() - started) / 1000).toFixed(2)) }); console.log('scene', scene); };
const shot = async n => page.screenshot({ path: path.join(root, `scene-${String(n).padStart(2, '0')}.png`) });

async function slide(title, body, flow = '') {
  await page.setContent(`<!doctype html><html lang="en"><head><meta charset="utf-8"><style>
  *{box-sizing:border-box}body{margin:0;background:#07111f;color:#eef5ff;font-family:-apple-system,BlinkMacSystemFont,"Inter",sans-serif}.shell{height:1080px;padding:70px 90px;background:radial-gradient(circle at 88% 3%,#1b497a 0,transparent 35%),linear-gradient(135deg,#07111f,#0d1c31)}.brand{color:#8fbfff;font-weight:800;letter-spacing:.08em;font-size:22px}.brand:before{content:'●';color:#4f9cff;margin-right:14px;text-shadow:0 0 20px #4f9cff}h1{font-size:56px;line-height:1.18;margin:40px 0 22px;letter-spacing:-.04em;white-space:pre-line}.body{font-size:23px;line-height:1.6;color:#aebfd2;white-space:pre-line;max-width:1500px}.flow{display:flex;gap:14px;align-items:center;margin-top:40px;flex-wrap:wrap}.node{padding:16px 22px;border:1px solid #3d6791;background:#142c49;border-radius:16px;font-size:19px;font-weight:750}.arrow{font-size:28px;color:#66aaf7}.foot{position:absolute;left:90px;right:90px;bottom:42px;display:flex;justify-content:space-between;color:#71879c;font-size:16px}
  </style></head><body><main class="shell"><div class="brand">PROCESS GPT · PROMPT CHAINING</div><h1>${title}</h1><div class="body">${body}</div><div class="flow">${flow}</div><div class="foot"><span>prompt-chaining-demo (EN) · scenario 9</span><span>Process GPT + deepagents</span></div></main></body></html>`);
}

// Scene 1 — Opening: Prompt Chaining pattern explainer
mark(1);
await slide(
  'Prompt Chaining\nChain complex work across LLM calls, step by step',
  'Each step’s output becomes the next step’s input, so every step can stay narrow and focused.\nFour traits matter most: sequential dependency, task decomposition, per-step optimization, and clear observability.',
  '<div class="node">Summarize report</div><div class="arrow">→</div><div class="node">Identify trends</div><div class="arrow">→</div><div class="node">Draft email</div>'
);
await page.waitForTimeout(900); await shot(1); await page.waitForTimeout(15500);

mark(2);
await slide(
  'Today’s demo: Market Insight Chain',
  'A human only enters the market research report text. From there, identifying key trends and drafting the\nmarketing team email run automatically, in order, with no human involvement — and each step actually\nreferences the previous step’s output. This is evidence-based chaining, not summarization.',
  '<div class="node">Human input</div><div class="arrow">→</div><div class="node">DeepAgent · identify trends</div><div class="arrow">→</div><div class="node">DeepAgent · draft email</div>'
);
await page.waitForTimeout(900); await shot(2); await page.waitForTimeout(17000);

// Scene 3 — real UI: login
mark(3);
await page.goto(`${BASE}/auth/login`, { waitUntil: 'load', timeout: 30000 });
await page.waitForSelector('input[type="text"]', { timeout: 15000 });
await page.locator('input[type="text"]').first().fill('demo@localhost');
await page.locator('input[type="password"]').first().fill('Demo1234!');
await page.waitForTimeout(800);
await shot(3);
await page.locator('button:has-text("Sign In")').click();
await page.waitForTimeout(3000);

// Scene 4 — real UI: the chat that created the chaining process (scroll through)
mark(4);
await page.goto(`${BASE}/definition-map?roomId=${ROOM_ID}`, { waitUntil: 'load', timeout: 30000 });
await page.waitForTimeout(2000);
const sidebarEntry = page.getByText('Create a process that analyzes', { exact: false }).first();
if (await sidebarEntry.count()) { await sidebarEntry.click(); await page.waitForTimeout(1500); }
await page.mouse.wheel(0, 400);
await page.waitForTimeout(1000);
await shot(4);
await page.waitForTimeout(7000);

// Scene 5 — real UI: skill/agent candidate selection point
mark(5);
await page.mouse.wheel(0, 900);
await page.waitForTimeout(1000);
await shot(5);
await page.waitForTimeout(13000);

// Scene 6 — real UI: workitem detail BPMN swimlanes (Person in Charge / DeepAgent)
mark(6);
await page.goto(`${BASE}/todolist/${TREND_WORKITEM_ID}`, { waitUntil: 'load', timeout: 30000 });
await page.waitForTimeout(2000);
await shot(6);
await page.waitForTimeout(10000);

// Scene 7 — real UI: Identify Key Trends — Agent Delegation tab
mark(7);
await page.getByText('Agent Delegation', { exact: true }).click();
await page.waitForTimeout(2000);
await shot(7);
await page.waitForTimeout(15000);

// Scene 8 — real UI: Draft Marketing Team Insight Email — final chained output
mark(8);
await page.goto(`${BASE}/todolist/${EMAIL_WORKITEM_ID}`, { waitUntil: 'load', timeout: 30000 });
await page.waitForTimeout(2000);
await page.getByText('Agent Delegation', { exact: true }).click();
await page.waitForTimeout(2000);
// Scroll the delegation panel down to the final (successful, chained) attempt card.
await page.mouse.move(735, 600);
for (let i = 0; i < 8; i++) {
  await page.mouse.wheel(0, 2500);
  await page.waitForTimeout(300);
}
await page.waitForTimeout(700);
await shot(8);
await page.waitForTimeout(15000);

// Scene 9 — closing slide
mark(9);
await slide(
  'Chaining results, in summary',
  'One human touchpoint (entering the report) → two DeepAgent steps completed automatically → bpm_proc_inst.status = COMPLETED.\nThe step-3 email draft quotes the exact figures step 2 identified (71%, 39% vs 33%, 61% vs 26%, -19% CAC, -11pt),\nproving the chain actually ran on the previous step’s output — not a summary.',
  '<div class="node">Sequential dependency</div><div class="arrow">→</div><div class="node">Per-step specialized skills</div><div class="arrow">→</div><div class="node">Observable execution history</div>'
);
await page.waitForTimeout(900); await shot(9); await page.waitForTimeout(16000);

const video = page.video();
await context.close();
await browser.close();
const recorded = await video.path();
await fs.rm(path.join(rawDir, 'demo-raw.webm'), { force: true });
await fs.rename(recorded, path.join(rawDir, 'demo-raw.webm'));
await fs.writeFile(path.join(root, 'scenes-timing.json'), JSON.stringify(timings, null, 2));
console.log(JSON.stringify({ output: path.join(rawDir, 'demo-raw.webm'), timings }, null, 2));
