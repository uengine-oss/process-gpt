#!/usr/bin/env node
// WMS sample-app demo recording — services/sample-app-wms.
// Opening/closing HTML slides + real UI: shortage -> RFQ -> HITL approval ->
// PO -> receiving -> quality -> putaway, switching real logins per role
// (buyer/approver/inbound/quality) against the real local Supabase-backed app.
import { chromium } from '../../../../services/sample-app-wms/frontend/node_modules/playwright/index.mjs';
import fs from 'node:fs/promises';
import path from 'node:path';

const BASE = process.argv[3] || 'http://localhost:5273';
const root = path.resolve(process.argv[2] || 'demo-recordings/wms-demo');
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
const mark = scene => { timings.push({ scene, start_sec: Number(((Date.now() - started) / 1000).toFixed(2)) }); console.log('scene', scene); };
const shot = async n => page.screenshot({ path: path.join(root, `scene-${String(n).padStart(2, '0')}.png`) });

async function slide(title, body, flow = '') {
  await page.setContent(`<!doctype html><html lang="ko"><head><meta charset="utf-8"><style>
  *{box-sizing:border-box}body{margin:0;background:#0b1626;color:#eef5ff;font-family:-apple-system,BlinkMacSystemFont,"Pretendard",sans-serif}.shell{height:1080px;padding:70px 90px;background:radial-gradient(circle at 88% 3%,#1c5a4a 0,transparent 35%),linear-gradient(135deg,#0b1626,#0f2a24)}.brand{color:#7fe3c0;font-weight:800;letter-spacing:.08em;font-size:22px}.brand:before{content:'●';color:#3ddc97;margin-right:14px;text-shadow:0 0 20px #3ddc97}h1{font-size:54px;line-height:1.2;margin:40px 0 22px;letter-spacing:-.03em;white-space:pre-line}.body{font-size:23px;line-height:1.65;color:#b7c9d9;white-space:pre-line;max-width:1500px}.flow{display:flex;gap:12px;align-items:center;margin-top:40px;flex-wrap:wrap}.node{padding:14px 20px;border:1px solid #2f6e5a;background:#123027;border-radius:14px;font-size:18px;font-weight:700}.arrow{font-size:24px;color:#4fd8a4}.foot{position:absolute;left:90px;right:90px;bottom:42px;display:flex;justify-content:space-between;color:#6f8a9c;font-size:16px}
  </style></head><body><main class="shell"><div class="brand">PROCESS GPT · WMS SAMPLE APP</div><h1>${title}</h1><div class="body">${body}</div><div class="flow">${flow}</div><div class="foot"><span>process-gpt-sample-app-wms demo</span><span>Supabase · FastMCP · Vue 3</span></div></main></body></html>`);
}

async function login(email) {
  await page.goto(`${BASE}/login`, { waitUntil: 'load', timeout: 30000 });
  await page.getByLabel('Email').fill(email);
  await page.getByLabel('Password').fill('Demo1234!');
  await page.getByRole('button', { name: /sign in/i }).click();
  await page.waitForURL(/overview/, { timeout: 15000 });
  await page.waitForTimeout(600);
}

async function logout() {
  await page.getByRole('button', { name: /sign out/i }).click();
  await page.waitForURL(/login/, { timeout: 15000 });
}

// Scene 1 — opening slide
mark(1);
await slide(
  '이 데모가 대체하는 것',
  'ProcessGPT의 재고 부족 대응 프로세스는 지금까지 Odoo ERP를 MCP로 호출했습니다.\n이 샘플 앱은 Supabase(Postgres·Auth·RLS)와 자체 MCP 서버로 그 자리를 대체합니다 —\n부족 감지부터 RFQ, 구매 승인, 입고, 검수, 폐기·적치까지 전 과정을 직접 실행합니다.',
  '<div class="node">Odoo MCP</div><div class="arrow">→</div><div class="node">wms-mcp + Supabase</div>'
);
await page.waitForTimeout(800); await shot(1); await page.waitForTimeout(21000);

// Scene 2 — opening slide: flow overview
mark(2);
await slide(
  '이번 데모가 실제로 실행하는 흐름',
  '재고 부족 감지 → RFQ 생성 → 구매 승인(HITL) → PO 확정 → 하역장 접수 → 입고 →\n품질 검사 → 적치(가용재고 전환), 총 7단계를 역할별로 실제 로그인해 진행합니다.\n모든 단계는 낙관적 동시성·멱등성·테넌트 RLS가 적용된 실제 Postgres RPC를 호출합니다.',
  '<div class="node">구매담당</div><div class="arrow">→</div><div class="node">승인자</div><div class="arrow">→</div><div class="node">입고담당</div><div class="arrow">→</div><div class="node">품질담당</div>'
);
await page.waitForTimeout(800); await shot(2); await page.waitForTimeout(21000);

// Scene 3 — real UI: buyer-a login, Overview shows real shortage
mark(3);
await login('buyer-a@demo.local');
await page.goto(`${BASE}/overview`, { waitUntil: 'load' });
await page.waitForTimeout(1200);
await shot(3);
await page.waitForTimeout(13000);

// Scene 4 — real UI: Replenishment, create RFQ
mark(4);
await page.goto(`${BASE}/replenishment`, { waitUntil: 'load' });
await page.waitForTimeout(1000);
await shot(4);
await page.locator('.card', { hasText: 'SKU-A-001' }).getByRole('button', { name: 'Create RFQ' }).click();
await page.waitForTimeout(1500);
await shot(4);
await page.waitForTimeout(14000);
await logout();

// Scene 5 — real UI: approver-a login, approve
mark(5);
await login('approver-a@demo.local');
await page.goto(`${BASE}/procurement/purchase-orders`, { waitUntil: 'load' });
await page.waitForTimeout(1000);
await shot(5);
await page.getByRole('button', { name: 'Approve' }).first().click();
await page.waitForTimeout(1200);
await shot(5);
await page.waitForTimeout(14500);
await logout();

// Scene 6 — real UI: buyer-a login, confirm PO
mark(6);
await login('buyer-a@demo.local');
await page.goto(`${BASE}/procurement/purchase-orders`, { waitUntil: 'load' });
await page.waitForTimeout(1000);
await page.getByRole('button', { name: 'Confirm PO' }).first().click();
await page.waitForTimeout(1200);
await shot(6);
await page.waitForTimeout(13500);
await logout();

// Scene 7 — real UI: inbound-a login, register arrival + receive
mark(7);
await login('inbound-a@demo.local');
await page.goto(`${BASE}/inbound/receipts`, { waitUntil: 'load' });
await page.waitForTimeout(1000);
await shot(7);
await page.getByRole('button', { name: 'Register Arrival' }).first().click();
await page.waitForTimeout(1200);
await page.getByRole('button', { name: 'Receive' }).first().click();
await page.waitForTimeout(1200);
await shot(7);
await page.waitForTimeout(15000);
await logout();

// Scene 8 — real UI: quality-a login, pass inspection
mark(8);
await login('quality-a@demo.local');
await page.goto(`${BASE}/quality/inspections`, { waitUntil: 'load' });
await page.waitForTimeout(1000);
await shot(8);
await page.getByRole('button', { name: 'Pass' }).first().click();
await page.waitForTimeout(1200);
await shot(8);
await page.waitForTimeout(14000);
await logout();

// Scene 9 — real UI: inbound-a login, putaway -> AVAILABLE
mark(9);
await login('inbound-a@demo.local');
await page.goto(`${BASE}/quality/inspections`, { waitUntil: 'load' });
await page.waitForTimeout(1000);
await shot(9);
await page.getByRole('button', { name: /Putaway/ }).first().click();
await page.waitForTimeout(1200);
await shot(9);
await page.waitForTimeout(14000);

// Scene 10 — real UI: back to Overview, shortage resolved
mark(10);
await page.goto(`${BASE}/overview`, { waitUntil: 'load' });
await page.waitForTimeout(1200);
await shot(10);
await page.waitForTimeout(13000);
await logout();

// Scene 11 — closing slide
mark(11);
await slide(
  '이번 데모가 실증한 것',
  '7단계 전체가 실제 Postgres RPC·RLS·Supabase Auth를 통과했습니다.\n테넌트 경계를 넘는 접근, 잘못된 역할의 명령, 오래된 버전의 재시도는 모두 서버에서 거부됩니다.\n같은 명령 세트는 FastMCP 서버(wms-mcp)를 통해 ProcessGPT 에이전트가 그대로 호출할 수 있습니다.',
  '<div class="node">RLS 격리</div><div class="arrow">→</div><div class="node">낙관적 동시성</div><div class="arrow">→</div><div class="node">멱등 RPC</div><div class="arrow">→</div><div class="node">MCP 도구</div>'
);
await page.waitForTimeout(800); await shot(11); await page.waitForTimeout(24500);

const video = page.video();
await context.close();
await browser.close();
const recorded = await video.path();
await fs.rm(path.join(rawDir, 'demo-raw.webm'), { force: true });
await fs.rename(recorded, path.join(rawDir, 'demo-raw.webm'));
await fs.writeFile(path.join(root, 'scenes-timing.json'), JSON.stringify(timings, null, 2));
console.log(JSON.stringify({ output: path.join(rawDir, 'demo-raw.webm'), timings }, null, 2));
