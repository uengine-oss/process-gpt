#!/usr/bin/env node
// WMS sample-app FULL demo recording — services/sample-app-wms.
//
// One day in the warehouse, across every area the 11-part implementation
// effort added: yard/dock scheduling, labor tracking, WCS equipment control,
// the digital-twin simulator, WES material flow, bottleneck routing,
// sequential dispatch / palletising, slotting optimisation, agentic
// operations and the operations audit log.
//
// Same shape as record_wms_demo.mjs (slide()/login()/logout()/mark()/shot(),
// playwright resolved out of the sample app's own node_modules), extended
// with:
//   sh()      — run something OFF-CAMERA between UI shots (the simulator
//               worker, a psql backdate, the agent filing a proposal). The
//               browser holds its last frame while this runs, which is
//               exactly the "meanwhile, out on the floor..." beat we want.
//   scrollTo()— several of the new boards are far taller than 1080px.
import { chromium } from '../../../../services/sample-app-wms/frontend/node_modules/playwright/index.mjs';
import { execFileSync } from 'node:child_process';
import fs from 'node:fs/promises';
import path from 'node:path';

const BASE = process.argv[3] || 'http://localhost:5273';
const root = path.resolve(process.argv[2] || 'demo-recordings/wms-full-demo');
const rawDir = path.join(root, 'raw');
const APP = '/Users/uengine/process-gpt/services/sample-app-wms';
const DB = 'supabase_db_process-gpt-sample-app-wms';
await fs.mkdir(rawDir, { recursive: true });

function sh(cmd, args, opts = {}) {
  try {
    const out = execFileSync(cmd, args, { encoding: 'utf8', ...opts });
    console.log(`  [off-camera] ${cmd} ok`);
    return out.trim();
  } catch (e) {
    console.error(`  [off-camera] ${cmd} FAILED: ${e.stdout || ''}${e.stderr || ''}`);
    throw e;
  }
}
const psql = sql => sh('docker', ['exec', '-i', DB, 'psql', '-U', 'postgres', '-d', 'postgres', '-qAt', '-v', 'ON_ERROR_STOP=1', '-c', sql]);
const simulator = () => sh(`${APP}/mcp/.venv/bin/python`, ['-m', 'wms_mcp.simulator.wcs_gateway_simulator', '--once', '-q'], { cwd: `${APP}/mcp` });

const browser = await chromium.launch({ headless: true });
const context = await browser.newContext({
  viewport: { width: 1920, height: 1080 },
  timezoneId: 'Asia/Seoul',
  recordVideo: { dir: rawDir, size: { width: 1920, height: 1080 } },
});
const page = await context.newPage();
const started = Date.now();
const timings = [];
const mark = scene => {
  timings.push({ scene, start_sec: Number(((Date.now() - started) / 1000).toFixed(2)) });
  console.log(`scene ${scene}  t=${((Date.now() - started) / 1000).toFixed(1)}s`);
};
const shot = async n => page.screenshot({ path: path.join(root, `scene-${String(n).padStart(2, '0')}.png`) });
const shotAs = async name => page.screenshot({ path: path.join(root, `scene-${name}.png`) });
const scrollTo = async y => { await page.evaluate(v => window.scrollTo({ top: v, behavior: 'smooth' }), y); await page.waitForTimeout(900); };
// FAST=1 collapses the scene holds (everything >= 4s) so selector breakage can
// be found in ~90s instead of ~7min. Never set it for the real take.
const FAST = !!process.env.FAST;
const wait = ms => page.waitForTimeout(FAST && ms >= 4000 ? 250 : ms);
// selectOption({label}) only takes exact strings; these <option> labels are
// composed at render time ("SKU-A-001 · Corrugated Box (Medium)"), so pick by
// substring and hand back the bound value.
async function pick(select, substring) {
  const value = await select.locator('option', { hasText: substring }).first().getAttribute('value');
  await select.selectOption(value);
}

async function slide(title, body, flow = '') {
  await page.setContent(`<!doctype html><html lang="ko"><head><meta charset="utf-8"><style>
  *{box-sizing:border-box}body{margin:0;background:#0b1626;color:#eef5ff;font-family:-apple-system,BlinkMacSystemFont,"Pretendard",sans-serif}.shell{height:1080px;padding:70px 90px;background:radial-gradient(circle at 88% 3%,#1c5a4a 0,transparent 35%),linear-gradient(135deg,#0b1626,#0f2a24)}.brand{color:#7fe3c0;font-weight:800;letter-spacing:.08em;font-size:22px}.brand:before{content:'●';color:#3ddc97;margin-right:14px;text-shadow:0 0 20px #3ddc97}h1{font-size:52px;line-height:1.2;margin:36px 0 22px;letter-spacing:-.03em;white-space:pre-line}.body{font-size:23px;line-height:1.7;color:#b7c9d9;white-space:pre-line;max-width:1560px}.flow{display:flex;gap:10px;align-items:center;margin-top:38px;flex-wrap:wrap}.node{padding:13px 18px;border:1px solid #2f6e5a;background:#123027;border-radius:14px;font-size:17px;font-weight:700}.arrow{font-size:22px;color:#4fd8a4}.foot{position:absolute;left:90px;right:90px;bottom:42px;display:flex;justify-content:space-between;color:#6f8a9c;font-size:16px}
  </style></head><body><main class="shell"><div class="brand">PROCESS GPT · WMS SAMPLE APP</div><h1>${title}</h1><div class="body">${body}</div><div class="flow">${flow}</div><div class="foot"><span>process-gpt-sample-app-wms · full-suite demo</span><span>Supabase · FastMCP · Vue 3</span></div></main></body></html>`);
}

async function login(email) {
  await page.goto(`${BASE}/login`, { waitUntil: 'load', timeout: 30000 });
  await page.getByLabel('Email').fill(email);
  await page.getByLabel('Password').fill('Demo1234!');
  await page.getByRole('button', { name: /sign in/i }).click();
  await page.waitForURL(/overview/, { timeout: 15000 });
  await wait(700);
}
async function logout() {
  await page.getByRole('button', { name: /sign out/i }).click();
  await page.waitForURL(/login/, { timeout: 15000 });
}
async function go(route) {
  await page.goto(`${BASE}${route}`, { waitUntil: 'load' });
  await wait(1400);
}

// ───────────────────────────────────────────── Scene 1 — opening slide
mark(1);
await slide(
  '한 대의 Odoo 대체 앱에서\n WMS + WES + WCS 풀스택으로',
  '처음 이 샘플 앱은 ProcessGPT의 재고 부족 대응 프로세스가 부르던 Odoo MCP를 대체하는 것이 전부였습니다.\n지금은 11개 영역이 더 붙어, 상위 재고·구매·입고·품질 위에\n야드/도크 예약 · 인력 계측 · 슬로팅 최적화, 그리고 설비제어 · 자재흐름 · 분류 · 병목 라우팅 ·\n서열출고 · 디지털트윈 시뮬레이션, 그 위에 에이전트 협업과 감사 로그까지 한 몸으로 돌아갑니다.',
  '<div class="node">WMS</div><div class="arrow">+</div><div class="node">WES</div><div class="arrow">+</div><div class="node">WCS</div><div class="arrow">+</div><div class="node">Agent · Audit</div>'
);
await wait(900); await shot(1); await wait(28000);

// ───────────────────────────────────────────── Scene 2 — the day's story
mark(2);
await slide(
  '오늘 창고의 하루를 한 번에 따라갑니다',
  '확정된 구매 발주의 차량이 도크에 예약을 잡고 들어오고, 작업자의 검수 시간이 계측됩니다.\n등록된 AGV가 디지털 트윈 위에서 웨이브 명령을 스스로 완료하고, 병목 판정 보드가 그 부하를 읽습니다.\n출고 서열은 팔레타이징 로봇 셀로 묶여 나가고, 슬로팅은 출하 속도로 재배치를 추천합니다.\n마지막으로 에이전트가 낸 제안을 사람이 승인하고, 감사관이 그 모든 것을 한국어 문장으로 되짚습니다.',
  '<div class="node">도크</div><div class="arrow">→</div><div class="node">인력</div><div class="arrow">→</div><div class="node">설비·웨이브</div><div class="arrow">→</div><div class="node">서열출고</div><div class="arrow">→</div><div class="node">슬로팅</div><div class="arrow">→</div><div class="node">에이전트</div><div class="arrow">→</div><div class="node">감사</div>'
);
await wait(900); await shot(2); await wait(27000);

// ───────────────────────────────────────────── Scene 3 — dock appointment + yard move
mark(3);
await login('inbound-a@demo.local');
await go('/inbound/dock-schedule');
await shotAs('03a');
await pick(page.getByLabel('Appointment Dock'), 'DOCK-01');
await page.getByLabel('Appointment Type').selectOption('INBOUND');
await page.getByLabel('Appointment PO').selectOption({ index: 0 });
await page.getByLabel('Appointment Start').fill('09:00');
await page.getByLabel('Appointment End').fill('10:00');
await page.getByLabel('Appointment Carrier').fill('한빛운수');
await page.getByLabel('Appointment Plate').fill('12가3456');
await wait(600);
await page.getByRole('button', { name: 'Schedule Appointment' }).click();
await wait(1800);
await shot(3);
await wait(9000);
// same scene: the truck arrives and backs onto the door
await page.locator('tr[data-window="DOCK-01 09:00"]').getByRole('button', { name: 'Check In' }).click();
await wait(1600);
await page.locator('tr[data-window="DOCK-01 09:00"]').getByRole('button', { name: 'Dock Vehicle' }).click();
await wait(1800);
await shotAs('03b');
await wait(13000);

// ───────────────────────────────────────────── Scene 4 — labor tracking
mark(4);
await go('/labor');
await page.getByLabel('Activity Type').selectOption('RECEIVING');
await page.getByLabel('Activity Label').fill('DOCK-01 입고 검수 · SKU-A-001 170개');
await wait(600);
await page.getByRole('button', { name: 'Start Activity' }).click();
await wait(1800);
await shotAs('04a');
await wait(8000);
// off-camera: wind started_at back so the screen shows the duration the
// contract actually computes instead of 0s.
psql(`update wms.labor_activities set started_at = started_at - make_interval(secs => 1490)
      where activity_label = 'DOCK-01 입고 검수 · SKU-A-001 170개' and status = 'IN_PROGRESS';`);
await page.reload({ waitUntil: 'load' }); await wait(1400);
await page.getByLabel('unit count for RECEIVING').fill('170');
await wait(500);
await page.getByLabel('complete RECEIVING').click();
await wait(2000);
await shot(4);
await wait(8000);
await logout();

// ───────────────────────────────────────────── Scene 5 — WCS equipment registry
mark(5);
await login('wh-manager-a@demo.local');
await go('/wcs/equipment');
await shotAs('05a');
await page.getByPlaceholder('AGV-07').fill('AGV-07');
await page.locator('select').first().selectOption('AGV');
await page.getByPlaceholder('ZONE-B').first().fill('ZONE-B');
await wait(600);
await page.getByRole('button', { name: 'Register Equipment' }).click();
await wait(2000);
await shot(5);
await wait(7000);
// off-camera: the machine announces itself, exactly as a real PLC bridge would.
psql(`do $$ begin perform set_config('request.jwt.claims',
        json_build_object('sub',(select id::text from auth.users where email='wcs-gateway-a@demo.local'),
                          'role','authenticated')::text,false); end $$;
      select wms.wms_report_equipment_status(
        (select id from wms.equipment where equipment_code='AGV-07'), 'IDLE',
        (select id from auth.users where email='wcs-gateway-a@demo.local'), gen_random_uuid(),
        (select version from wms.equipment where equipment_code='AGV-07'));`);
await page.reload({ waitUntil: 'load' }); await wait(1600);
await shotAs('05b');
await wait(13500);

// ───────────────────────────────────────────── Scene 6 — digital twin
mark(6);
await go('/wcs/simulation');
await shotAs('06a');
await page.locator('tr[data-equipment-code="AGV-07"]').getByRole('button', { name: 'Simulate' }).click();
await wait(1800);
await pick(page.getByLabel('profile equipment'), 'AGV-07');
await wait(600);
await page.getByRole('button', { name: 'Save Profile' }).click();
await wait(2000);
await shot(6);
await wait(21000);

// ───────────────────────────────────────────── Scene 7 — WES wave dispatch
mark(7);
await go('/wes/dispatch');
await page.getByRole('button', { name: 'Open Wave' }).click();
await wait(1800);
await shotAs('07a');
const woSelects = page.locator('.card', { hasText: '업무 오더 등록' }).locator('select');
await woSelects.nth(0).selectOption({ index: 0 });   // Receipt
await woSelects.nth(1).selectOption('AGV');           // Equipment Type
await page.locator('.card', { hasText: '업무 오더 등록' }).getByPlaceholder('ZONE-B').fill('ZONE-B');
await woSelects.nth(2).selectOption('MOVE');          // Command
await page.locator('.card', { hasText: '업무 오더 등록' }).getByPlaceholder('ZONE-C').fill('ZONE-C');
await woSelects.nth(3).selectOption('WAVE');          // Dispatch Mode
await wait(600);
await page.getByRole('button', { name: 'Create Work Order' }).click();
await wait(2000);
await shotAs('07b');
await wait(7000);
await page.getByRole('button', { name: /^Release wave/i }).click();
await wait(2200);
await shot(7);
await wait(9000);

// ───────────────────────────────────────────── Scene 8 — the twin completes it
mark(8);
await go('/wcs/monitor');
await shotAs('08a');
await wait(4000);
simulator();          // off-camera: the WCS_GATEWAY worker drives the command
await page.reload({ waitUntil: 'load' }); await wait(1800);
await shot(8);
await wait(9000);
await go('/wes/dispatch');
await scrollTo(500);
await shotAs('08b');
await wait(5500);

// ───────────────────────────────────────────── Scene 9 — bottleneck routing
mark(9);
await go('/wcs/routing');
await shot(9);
await wait(7000);
// give the AGV fleet an explicit bottleneck threshold instead of the system default
await page.getByLabel('new policy equipment type').selectOption('AGV');
await page.getByLabel('new queue threshold').fill('3');
await page.getByLabel('new fault threshold').fill('1');
await wait(500);
await page.getByRole('button', { name: 'Register Policy' }).click();
await wait(1800);
await shotAs('09b');
await wait(6000);
// and pull one machine out of automatic routing for planned maintenance
await page.getByLabel('exclusion reason for AGV-08').fill('계획 정비 — 배터리 교체');
await wait(500);
await page.locator('.card', { hasText: 'AGV-08' }).getByRole('button', { name: 'Exclude from Routing' }).click();
await wait(2000);
await shotAs('09c');
await wait(11000);

// ───────────────────────────────────────────── Scene 10 — outbound sequencing
mark(10);
await go('/wcs/sequential-dispatch');
await page.getByRole('button', { name: 'Open Wave' }).click();
await wait(1800);
const orderCard = page.locator('.card', { hasText: '출고 단위 등록' });
for (const [num, store, sku, qty, kg, l] of [
  ['OB-2026-0101', 'STORE-042', 'SKU-A-001', '40', '18', '30'],
  ['OB-2026-0102', 'STORE-042', 'SKU-A-002', '25', '11', '22'],
]) {
  await orderCard.getByLabel('order number').fill(num);
  await orderCard.getByLabel('store code').fill(store);
  await pick(orderCard.getByLabel('product'), sku);
  await orderCard.getByLabel('qty').fill(qty);
  await orderCard.getByLabel('declared weight').fill(kg);
  await orderCard.getByLabel('declared volume').fill(l);
  await wait(500);
  await orderCard.getByRole('button', { name: 'Create Outbound Order' }).click();
  await wait(1700);
}
await shotAs('10a');
const seqCard = page.locator('.card', { hasText: '서열 배정' }).first();
for (const [pos, order] of [['1', 'OB-2026-0101'], ['2', 'OB-2026-0102']]) {
  await pick(seqCard.getByLabel('outbound order'), order);
  await seqCard.getByLabel('sequence position').fill(pos);
  await seqCard.getByLabel('target pallet code').fill('PLT-2026-A1');
  await wait(500);
  await seqCard.getByRole('button', { name: 'Assign Sequence' }).click();
  await wait(1700);
}
await scrollTo(700);
await shot(10);
await wait(18000);

// ───────────────────────────────────────────── Scene 11 — palletise + manifest
mark(11);
await scrollTo(0);
const palCard = page.locator('.card', { hasText: '팔레타이징' });
await pick(palCard.getByLabel('robot cell'), 'CELL-01');
await palCard.getByLabel('palletize pallet code').fill('PLT-2026-A1');
await palCard.getByLabel('max weight').fill('250');
await wait(600);
await palCard.getByRole('button', { name: 'Dispatch PALLETIZE' }).click();
await wait(2200);
await shotAs('11a');
await wait(4000);
simulator();          // off-camera: CELL-01 stacks the pallet and reports back
await page.reload({ waitUntil: 'load' }); await wait(2000);
await scrollTo(1500);
await shot(11);
await wait(9000);
await scrollTo(2400);
await shotAs('11b');
await wait(3000);

// ───────────────────────────────────────────── Scene 12 — slotting
mark(12);
await go('/slotting');
await scrollTo(1250);
await shotAs('12a');
await page.getByRole('button', { name: 'Compute Velocity' }).click();
await wait(2200);
await shotAs('12b');
await wait(8000);
await page.getByRole('button', { name: 'Generate Recommendations' }).click();
await wait(2200);
await scrollTo(1900);
await shot(12);
await wait(9000);
await page.getByLabel('approve SKU-A-001').click();
await wait(1800);
await page.getByLabel('apply SKU-A-001').click();
await wait(2000);
await scrollTo(1900);
await shotAs('12c');
await wait(11000);

// ───────────────────────────────────────────── Scene 13 — agent collaboration
mark(13);
// off-camera: the ProcessGPT agent files what it saw, as PROCESS_AGENT, over
// the same RPCs the UI uses. It cannot execute either of these itself.
sh('/bin/bash', [path.resolve(path.dirname(new URL(import.meta.url).pathname), 'wms_full_demo_agent_proposals.sh')]);
await go('/agent/decisions');
await shot(13);
await wait(11000);
await page.locator('summary', { hasText: '제안된 조치' }).first().click();
await wait(1200);
await shotAs('13b');
await wait(6000);
await page.getByLabel('confirm SLOTTING_POLICY_GAP').click();
await wait(2200);
await shotAs('13c');
await wait(10000);
await scrollTo(1400);
await shotAs('13d');
await wait(8000);
await logout();

// ───────────────────────────────────────────── Scene 14 — audit log
mark(14);
await login('auditor-a@demo.local');
await go('/operations/audit-log');
await shot(14);
await wait(8000);
await pick(page.getByLabel('Actor Filter'), 'process-agent-a');
await page.getByRole('button', { name: 'Search' }).click();
await wait(2000);
await shotAs('14b');
await wait(13000);
await logout();

// ───────────────────────────────────────────── Scene 15 — closing slide
mark(15);
await slide(
  '이번 데모가 실증한 것',
  '11개 영역, 37개 테이블, 82개 Postgres RPC, 85개 MCP 도구가 하나의 스키마 안에서 맞물립니다.\n도크 예약의 시간창 겹침은 DB 배제 제약이, 설비 명령의 재시도는 멱등성 키가,\n동시 편집은 낙관적 버전이, 테넌트 경계는 RLS가 막습니다 — 화면이 아니라 서버가 막습니다.\n에이전트는 같은 RPC를 MCP로 호출하지만, 실행 권한이 없는 조치는 제안으로만 쌓입니다.\nPlaywright E2E 스위트는 23개 시나리오 전부 통과합니다.',
  '<div class="node">37 tables</div><div class="arrow">·</div><div class="node">82 RPC</div><div class="arrow">·</div><div class="node">85 MCP tools</div><div class="arrow">·</div><div class="node">E2E 23/23</div>'
);
await wait(900); await shot(15); await wait(31000);

const video = page.video();
await context.close();
await browser.close();
const recorded = await video.path();
await fs.rm(path.join(rawDir, 'demo-raw.webm'), { force: true });
await fs.rename(recorded, path.join(rawDir, 'demo-raw.webm'));
await fs.writeFile(path.join(root, 'scenes-timing.json'), JSON.stringify(timings, null, 2));
console.log(JSON.stringify({ output: path.join(rawDir, 'demo-raw.webm'), timings }, null, 2));
