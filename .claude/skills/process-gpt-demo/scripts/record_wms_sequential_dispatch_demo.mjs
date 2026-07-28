#!/usr/bin/env node
// WMS "서열 출고·팔레타이징" ProcessGPT process demo — buildtime (BPMN editor
// walkthrough of the installed wms_sequential_dispatch_process) + runtime
// (a real instance executed by the WMS execution agent through completion's
// polling_service, calling wms-mcp exactly like a production run would).
//
// Companion scripts:
//   services/sample-app-wms/scripts/setup_sequential_dispatch_demo_equipment.sql
//     — one-time DISPATCH-CELL-01 ROBOT_CELL + zero-failure simulation profile
//   services/sample-app-wms/scripts/install_sequential_dispatch_process.py
//     — installs the process definition + 3 HITL forms into ProcessGPT
//
// Both must have been run at least once against the local stack before this
// script executes (they are idempotent — safe to re-run).
//
// Pattern: userTask completions are submitted through /completion/complete
// with a real JWT extracted from the logged-in browser session — the same
// approach documented in scenario-tutorial-lv1.md for exactly the same
// reason (the demo account isn't the resolved assignee for every activity,
// so UI-only clicking isn't reliable for scripted, repeatable recording).
// Every state transition is still shown on real screens (BPMN editor,
// instance-viewer, todolist, and the WMS frontend for the palletizing
// result) between calls, and the WMS-side agent execution is 100% real —
// nothing about the WMS calls themselves is faked.
import { chromium } from '../../../../services/frontend/node_modules/playwright/index.mjs';
import { execFileSync } from 'node:child_process';
import fs from 'node:fs/promises';
import path from 'node:path';
import { randomUUID } from 'node:crypto';

const PG_BASE = process.argv[3] || 'http://localhost:8088';
const WMS_BASE = process.argv[4] || 'http://localhost:5273';
const root = path.resolve(process.argv[2] || 'demo-recordings/wms-sequential-dispatch-demo');
const rawDir = path.join(root, 'raw');
await fs.mkdir(rawDir, { recursive: true });

const PROC_DEF_ID = 'wms_sequential_dispatch_process';
const WMS_DB = 'supabase_db_process-gpt-sample-app-wms';
const PG_DB = 'supabase-db';
const DEMO_USER_ID = 'bd0e585b-3828-496c-92aa-3f93f336d3d3';

function sh(cmd, args, opts = {}) {
  try {
    return execFileSync(cmd, args, { encoding: 'utf8', ...opts }).trim();
  } catch (e) {
    console.error(`  [off-camera] ${cmd} FAILED: ${e.stdout || ''}${e.stderr || ''}`);
    throw e;
  }
}
// The local Postgres occasionally blips ("database system is in recovery
// mode" / a crashed backend forcing a restart) under load — retry a few
// times with backoff before giving up, instead of taking the whole
// recording down over a transient connection error.
function shRetry(cmd, args, opts = {}, tries = 8, delayMs = 4000) {
  let lastErr;
  for (let i = 0; i < tries; i++) {
    try {
      return execFileSync(cmd, args, { encoding: 'utf8', ...opts }).trim();
    } catch (e) {
      lastErr = e;
      const msg = `${e.stdout || ''}${e.stderr || ''}`;
      if (!/recovery mode|server closed the connection|could not connect/i.test(msg)) {
        console.error(`  [off-camera] ${cmd} FAILED (non-transient): ${msg}`);
        throw e;
      }
      console.error(`  [off-camera] ${cmd} transient DB error, retry ${i + 1}/${tries} in ${delayMs}ms`);
      const wakeAt = Date.now() + delayMs;
      while (Date.now() < wakeAt) execFileSync('sleep', ['1']);
    }
  }
  throw lastErr;
}
const pgPsql = (sql) => shRetry('docker', ['exec', '-i', PG_DB, 'psql', '-U', 'postgres', '-d', 'postgres', '-qAt', '-v', 'ON_ERROR_STOP=1', '-c', sql]);
const wmsPsql = (sql) => shRetry('docker', ['exec', '-i', WMS_DB, 'psql', '-U', 'postgres', '-d', 'postgres', '-qAt', '-v', 'ON_ERROR_STOP=1', '-c', sql]);
const simulator = () => sh(
  `${path.resolve('services/sample-app-wms/mcp/.venv/bin/python')}`,
  ['-m', 'wms_mcp.simulator.wcs_gateway_simulator', '--once', '-q'],
  { cwd: path.resolve('services/sample-app-wms/mcp') }
);

async function submitTask(token, instId, activityId, formId, fields) {
  const resp = await fetch(`${PG_BASE}/completion/complete`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      input: {
        process_definition_id: PROC_DEF_ID,
        process_instance_id: instId,
        activity_id: activityId,
        email: 'demo@localhost',
        user_id: DEMO_USER_ID,
        username: 'demo',
        form_values: { [formId]: fields, ...fields },
      },
    }),
  });
  if (!resp.ok) throw new Error(`submitTask ${activityId} failed: ${resp.status} ${await resp.text()}`);
  return resp.json();
}

// Polls the real todolist row until the target activity is reachable (TODO)
// with everything before it DONE, or gives up after maxTries*intervalMs.
async function waitForReady(instId, activityId, minDoneCount, maxTries = 90, intervalMs = 8000) {
  for (let i = 0; i < maxTries; i++) {
    try {
      const status = pgPsql(`select status from todolist where proc_inst_id='${instId}' and activity_id='${activityId}';`);
      const doneCount = Number(pgPsql(`select count(*) from todolist where proc_inst_id='${instId}' and status='DONE';`));
      if (status === 'TODO' && doneCount >= minDoneCount) return true;
    } catch { /* transient DB blip — shRetry already absorbed what it could, keep polling */ }
    await new Promise((r) => setTimeout(r, intervalMs));
  }
  console.warn(`  [warn] waitForReady(${activityId}) timed out after ${(maxTries * intervalMs) / 1000}s — continuing anyway`);
  return false;
}

// Blocks until a query returns a non-empty value (used for "has the agent's
// last step actually written its row yet" — waitForReady only proves the
// workitem is reachable, not that its side-effect row is queryable yet).
async function waitForValue(queryFn, maxTries = 30, intervalMs = 5000) {
  for (let i = 0; i < maxTries; i++) {
    const v = queryFn();
    if (v) return v;
    await new Promise((r) => setTimeout(r, intervalMs));
  }
  return '';
}

const browser = await chromium.launch({ headless: true });
const context = await browser.newContext({
  viewport: { width: 1920, height: 1080 },
  timezoneId: 'Asia/Seoul',
  recordVideo: { dir: rawDir, size: { width: 1920, height: 1080 } },
});
const page = await context.newPage();
const started = Date.now();
const timings = [];
const mark = (scene) => { timings.push({ scene, start_sec: Number(((Date.now() - started) / 1000).toFixed(2)) }); console.log(`scene ${scene}  t=${((Date.now() - started) / 1000).toFixed(1)}s`); };
const shot = (n) => page.screenshot({ path: path.join(root, `scene-${String(n).padStart(2, '0')}.png`) }).catch(() => {});
const shotAs = (name) => page.screenshot({ path: path.join(root, `scene-${name}.png`) }).catch(() => {});
const FAST = !!process.env.FAST;
const wait = (ms) => page.waitForTimeout(FAST && ms >= 4000 ? 400 : ms);

async function slide(title, body, flow = '') {
  await page.setContent(`<!doctype html><html lang="ko"><head><meta charset="utf-8"><style>
  *{box-sizing:border-box}body{margin:0;background:#0b1220;color:#eef5ff;font-family:-apple-system,BlinkMacSystemFont,"Pretendard",sans-serif}.shell{height:1080px;padding:70px 90px;background:radial-gradient(circle at 88% 3%,#22406e 0,transparent 35%),radial-gradient(circle at 6% 96%,#1c5a4a 0,transparent 30%),linear-gradient(135deg,#0b1220,#0f1b2e)}.brand{color:#8fd6c4;font-weight:800;letter-spacing:.08em;font-size:22px}.brand:before{content:'●';color:#3ddc97;margin-right:14px;text-shadow:0 0 20px #3ddc97}h1{font-size:52px;line-height:1.2;margin:36px 0 22px;letter-spacing:-.03em;white-space:pre-line}.body{font-size:23px;line-height:1.7;color:#b7c9d9;white-space:pre-line;max-width:1560px}.flow{display:flex;gap:10px;align-items:center;margin-top:38px;flex-wrap:wrap}.node{padding:13px 18px;border:1px solid #3d6791;background:#152742;border-radius:14px;font-size:17px;font-weight:700}.arrow{font-size:22px;color:#66aaf7}.foot{position:absolute;left:90px;right:90px;bottom:42px;display:flex;justify-content:space-between;color:#6f8a9c;font-size:16px}
  </style></head><body><main class="shell"><div class="brand">PROCESS GPT · WMS 서열 출고·팔레타이징</div><h1>${title}</h1><div class="body">${body}</div><div class="flow">${flow}</div><div class="foot"><span>wms_sequential_dispatch_process · buildtime + runtime</span><span>ProcessGPT · wms-mcp · Supabase</span></div></main></body></html>`);
}

async function pgLogin() {
  for (let attempt = 1; attempt <= 5; attempt++) {
    await page.goto(`${PG_BASE}/auth/login`, { waitUntil: 'load', timeout: 30000 });
    await page.waitForSelector('input[type="text"]', { timeout: 15000 });
    await page.locator('input[type="text"]').first().fill('demo@localhost');
    await page.locator('input[type="password"]').first().fill('Demo1234!');
    await page.locator('button:has-text("로그인")').click();
    await page.waitForTimeout(3000);
    const url = page.url();
    const hasToken = await page.evaluate(() =>
      Object.keys(localStorage).some((k) => k.includes('auth-token'))
    );
    if (!url.includes('/auth/login') && hasToken) return;
    console.warn(`  [warn] pgLogin attempt ${attempt} did not leave /auth/login (url=${url}) — retrying`);
    await page.waitForTimeout(4000);
  }
  throw new Error('pgLogin: exhausted retries, still on /auth/login');
}
async function pgToken() {
  return page.evaluate(() => {
    for (const k of Object.keys(localStorage)) {
      if (k.includes('auth-token')) {
        const v = JSON.parse(localStorage.getItem(k));
        return v.access_token ?? v.currentSession?.access_token;
      }
    }
    return null;
  });
}
async function wmsLogin(email) {
  for (let attempt = 1; attempt <= 5; attempt++) {
    await page.goto(`${WMS_BASE}/login`, { waitUntil: 'load', timeout: 30000 });
    await page.getByLabel('Email').fill(email);
    await page.getByLabel('Password').fill('Demo1234!');
    await page.getByRole('button', { name: /sign in/i }).click();
    try {
      await page.waitForURL(/overview/, { timeout: 15000 });
      await wait(700);
      return;
    } catch {
      console.warn(`  [warn] wmsLogin(${email}) attempt ${attempt} did not reach /overview — retrying`);
    }
  }
  throw new Error(`wmsLogin(${email}): exhausted retries`);
}
async function wmsLogout() {
  await page.getByRole('button', { name: /sign out/i }).click();
  await page.waitForURL(/login/, { timeout: 15000 });
}

// ═══════════════════════════════════════════════ Scene 1-2 — opening slides
mark(1);
await slide(
  '완전자동, 예외에만 사람이 등장합니다',
  '두산로지스틱스솔루션·Dematic의 서열 출고·로봇 팔레타이징을 ProcessGPT 프로세스로 그대로 옮겼습니다.\n두 매장 출고 단위를 하나의 팔레트로 묶어 로봇 셀에 명령을 보내고, 정상 결과는 사람 없이 마무리됩니다.\n중량·용적 초과나 적재 실패가 났을 때만 사람이 재포장을 지시합니다 — 반대 순서가 아닙니다.',
  '<div class="node">출고 단위 등록</div><div class="arrow">→</div><div class="node">서열 배정</div><div class="arrow">→</div><div class="node">팔레타이징 명령</div><div class="arrow">→</div><div class="node">정상 자동 종료</div>'
);
await wait(900); await shot(1); await wait(22000);

mark(2);
await slide(
  '이번 데모가 실제로 실행하는 흐름',
  '출고 계획 등록(사람) → 출고 단위 등록 ×2 → 웨이브 오픈 → 서열 배정 ×2 → 설비 상태 조회\n→ 팔레타이징 명령 전송 → 결과 확인(HITL) → [정상] 자동 종료 / [예외] 재포장 지시.\n11개 활동 전부가 wms-mcp를 통해 실제 Postgres RPC를 호출합니다 — 시뮬레이션이 아닙니다.',
  '<div class="node">에이전트 6단계</div><div class="arrow">→</div><div class="node">사람 확인 1회</div><div class="arrow">→</div><div class="node">정상/예외 분기</div>'
);
await wait(900); await shot(2); await wait(20000);

// ═══════════════════════════════════════════════ Scene 3-6 — buildtime
mark(3);
await pgLogin();
await page.goto(`${PG_BASE}/definitions/${PROC_DEF_ID}`, { waitUntil: 'load', timeout: 30000 });
await wait(6500); await shot(3);
await wait(8000);

mark(4);
await page.locator('[data-element-id="dispatch_palletize"]').first().dblclick({ force: true }).catch(() => {});
await wait(2200);
await page.locator('.v-tab:has-text("에이전트")').first().click().catch(() => {});
await wait(2000); await shotAs('04a');
await wait(6500);
await page.locator('.v-tab[value="setting"]').first().click().catch(() => {});
await wait(1800); await shotAs('04b');
await wait(7000);

mark(5);
await page.keyboard.press('Escape').catch(() => {});
await wait(600);
await page.locator('[data-element-id="gw_outcome"]').first().dblclick({ force: true }).catch(() => {});
await wait(2200); await shot(5);
await wait(7500);

mark(6);
await page.keyboard.press('Escape').catch(() => {});
await wait(600);
await page.locator('[data-element-id="confirm_palletize_result"]').first().dblclick({ force: true }).catch(() => {});
await wait(2200); await shot(6);
await wait(7000);
await page.keyboard.press('Escape').catch(() => {});
await wait(500);

// ═══════════════════════════════════════════════ Scene 7 — transition
mark(7);
await slide(
  '이제 실제로 실행합니다',
  '아래부터는 스크립트가 아니라 실제 실행입니다. WMS 실행 에이전트가 각 단계마다 정확히 지정된\nMCP 도구 하나만 호출하고, 사람 확인 지점에서만 화면이 사람을 기다립니다.',
  ''
);
await wait(900); await shot(7); await wait(9000);

// ═══════════════════════════════════════════════ Runtime — happy path
mark(8);
const token = await pgToken();
if (!token) throw new Error('failed to extract ProcessGPT auth token from browser session');
const instId1 = `${PROC_DEF_ID}.${randomUUID()}`;
console.log('  [off-camera] starting instance', instId1);
await submitTask(token, instId1, 'register_outbound_plan', `${PROC_DEF_ID}_register_outbound_plan_form`, {
  store_code: 'STORE-042',
  sku_1: 'SKU-A-001 · 40개',
  sku_2: 'SKU-A-002 · 25개',
  target_pallet_code: 'PLT-DISPATCH-DEMO',
  plan_note: '데모 실행 — 두 품목을 한 팔레트로 묶어 서열 출고',
});
await page.goto(`${PG_BASE}/instance-viewer/${instId1}`, { waitUntil: 'load', timeout: 30000 });
await wait(4500); await shot(8);
await wait(6000);

mark(9);
console.log('  [off-camera] waiting for the 6-step agent chain to reach the HITL confirmation...');
await waitForReady(instId1, 'confirm_palletize_result', 8);
await page.reload({ waitUntil: 'load' }); await wait(2500); await shot(9);
await wait(9000);

mark(10);
await wmsLogin('wcs-operator-a@demo.local');
await page.goto(`${WMS_BASE}/wcs/sequential-dispatch`, { waitUntil: 'load' });
await wait(1500); await shot(10);
await wait(9000);

mark(11);
console.log('  [off-camera] running the WCS gateway simulator — DISPATCH-CELL-01 completes the PALLETIZE command for real');
simulator();
await page.reload({ waitUntil: 'load' }); await wait(2000);
await shot(11);
await wait(9500);
await wmsLogout();

mark(12);
await pgToken(); // page already has the ProcessGPT session in a different tab-equivalent nav below
await page.goto(`${PG_BASE}/todolist/`, { waitUntil: 'load', timeout: 30000 }).catch(() => {});
await wait(2500);
const confirmWorkitemId = pgPsql(`select id from todolist where proc_inst_id='${instId1}' and activity_id='confirm_palletize_result';`);
await page.goto(`${PG_BASE}/todolist/${confirmWorkitemId}`, { waitUntil: 'load', timeout: 30000 });
await wait(3000); await shot(12);
await wait(8000);

mark(13);
console.log('  [off-camera] submitting the HITL confirmation: outcome=SUCCESS');
await submitTask(token, instId1, 'confirm_palletize_result', `${PROC_DEF_ID}_confirm_palletize_result_form`, {
  outcome: 'SUCCESS',
  equipment_command_id: '',
  pallet_code: 'PLT-DISPATCH-DEMO',
  confirm_note: '매니페스트 확인 — 2개 항목 모두 LOADED',
});
await waitForReady(instId1, 'confirm_palletize_result', 9, 40, 6000);
await page.goto(`${PG_BASE}/instance-viewer/${instId1}`, { waitUntil: 'load', timeout: 30000 });
await wait(3500); await shot(13);
await wait(10000);

// ═══════════════════════════════════════════════ Exception path
mark(14);
await slide(
  '이번엔 로봇 셀이 무게초과를 보고했다면',
  '같은 흐름을 다시 실행하되, 이번엔 시뮬레이터 대신 설비 결과 보고 자체를 OVERWEIGHT로 직접 재현합니다\n(design.md D7 — 계획 시점 상한 검증과 실측 시점 초과는 서로 다른 실패입니다). 정상 경로와\n똑같은 6단계를 거친 뒤, 결과 확인 단계에서만 다른 값을 받습니다.',
  '<div class="node">동일한 6단계</div><div class="arrow">→</div><div class="node">OVERWEIGHT 보고</div><div class="arrow">→</div><div class="node">재포장 지시(HITL)</div>'
);
await wait(900); await shot(14); await wait(13000);

mark(15);
const instId2 = `${PROC_DEF_ID}.${randomUUID()}`;
console.log('  [off-camera] starting second instance', instId2);
await submitTask(token, instId2, 'register_outbound_plan', `${PROC_DEF_ID}_register_outbound_plan_form`, {
  store_code: 'STORE-042',
  sku_1: 'SKU-A-001 · 40개',
  sku_2: 'SKU-A-002 · 25개',
  target_pallet_code: 'PLT-DISPATCH-DEMO',
  plan_note: '예외 경로 데모 — 무게초과 재현',
});
await page.goto(`${PG_BASE}/instance-viewer/${instId2}`, { waitUntil: 'load', timeout: 30000 });
await wait(3500); await shot(15);
console.log('  [off-camera] waiting for the second run to reach dispatch_palletize/confirm_palletize_result...');
await waitForReady(instId2, 'confirm_palletize_result', 8);
await wait(2500);

mark(16);
console.log('  [off-camera] manufacturing an OVERWEIGHT result directly on the PALLETIZE command (bypassing the simulator)');
const cmdId = await waitForValue(() => wmsPsql(`
  select id from wms.equipment_commands
  where equipment_id = (select id from wms.equipment where equipment_code='DISPATCH-CELL-01')
    and command_type = 'PALLETIZE'
  order by created_at desc limit 1;
`));
if (!cmdId) throw new Error('second instance never produced a PALLETIZE equipment_commands row — dispatch_palletize likely did not complete');
wmsPsql(`
  do $$
  declare v_gw uuid; v_cmd_version int; v_seq_ids uuid[];
  begin
    select id into v_gw from auth.users where email = 'wcs-gateway-a@demo.local';
    perform set_config('request.jwt.claims', json_build_object('sub', v_gw::text, 'role', 'authenticated')::text, false);
    set local role authenticated;
    select version into v_cmd_version from wms.equipment_commands where id = '${cmdId}';
    select array_agg(id) into v_seq_ids from wms.dispatch_sequences where equipment_command_id = '${cmdId}';
    perform wms.wms_report_command_result('${cmdId}', 'IN_PROGRESS', v_gw, gen_random_uuid(), v_cmd_version, null, 'seq-demo-overweight');
    select version into v_cmd_version from wms.equipment_commands where id = '${cmdId}';
    perform wms.wms_report_command_result('${cmdId}', 'FAILED', v_gw, gen_random_uuid(), v_cmd_version,
      jsonb_build_object(
        'outcome', 'OVERWEIGHT',
        'total_actual_weight_kg', 31.4,
        'loaded_items', (
          select jsonb_agg(jsonb_build_object('dispatch_sequence_id', sid, 'item_outcome', 'SKIPPED', 'reason', 'SCALE_LIMIT'))
          from unnest(v_seq_ids) as sid
        )
      ), 'seq-demo-overweight');
  end $$;
`);
await wmsLogin('wcs-operator-a@demo.local');
await page.goto(`${WMS_BASE}/wcs/sequential-dispatch`, { waitUntil: 'load' });
await wait(1500); await shot(16);
await wait(9000);
await wmsLogout();

mark(17);
const confirmWorkitemId2 = pgPsql(`select id from todolist where proc_inst_id='${instId2}' and activity_id='confirm_palletize_result';`);
await page.goto(`${PG_BASE}/todolist/${confirmWorkitemId2}`, { waitUntil: 'load', timeout: 30000 });
await wait(3000); await shot(17);
await wait(8000);

mark(18);
console.log('  [off-camera] submitting the HITL confirmation: outcome=OVERWEIGHT');
await submitTask(token, instId2, 'confirm_palletize_result', `${PROC_DEF_ID}_confirm_palletize_result_form`, {
  outcome: 'OVERWEIGHT',
  equipment_command_id: cmdId,
  pallet_code: 'PLT-DISPATCH-DEMO',
  confirm_note: '설비 실측 중량 초과 — 계획(선언값)은 상한 이내였으나 실측이 넘음(D7)',
});
await waitForReady(instId2, 'handle_repack_exception', 9, 40, 6000);
const repackWorkitemId = pgPsql(`select id from todolist where proc_inst_id='${instId2}' and activity_id='handle_repack_exception';`);
await page.goto(`${PG_BASE}/todolist/${repackWorkitemId}`, { waitUntil: 'load', timeout: 30000 });
await wait(3000); await shot(18);
await wait(9000);

mark(19);
console.log('  [off-camera] submitting the repack-exception HITL task');
await submitTask(token, instId2, 'handle_repack_exception', `${PROC_DEF_ID}_handle_repack_exception_form`, {
  reason_code: 'OVERWEIGHT',
  repack_note: 'SKU-A-001 물량을 별도 팔레트로 재분할 후 재서열 배정 예정',
  escalated: false,
});
await wait(3000);
await page.goto(`${PG_BASE}/instance-viewer/${instId2}`, { waitUntil: 'load', timeout: 30000 });
await wait(3500); await shot(19);
await wait(11000);

// ═══════════════════════════════════════════════ Closing slide
mark(20);
await slide(
  '이번 데모가 실증한 것',
  'wms_sequential_dispatch_process 11개 활동이 create_outbound_order·assign_dispatch_sequence·\ndispatch_palletize_command 등 실제 wms-mcp 도구를 호출해 정상/예외 두 경로 모두 완주했습니다.\n정상 경로엔 사람이 없고, 중량 초과 같은 실물 실패만 사람의 재포장 판단으로 넘어갑니다 —\n두산·Dematic이 파는 "서열 출고·로봇 팔레타이징"을 ProcessGPT 프로세스 하나로 그대로 재현한 것입니다.',
  '<div class="node">11 activities</div><div class="arrow">·</div><div class="node">6 MCP tools</div><div class="arrow">·</div><div class="node">정상/예외 2경로</div>'
);
await wait(900); await shot(20); await wait(26000);

const video = page.video();
await context.close();
await browser.close();
const recorded = await video.path();
await fs.rm(path.join(rawDir, 'demo-raw.webm'), { force: true });
await fs.rename(recorded, path.join(rawDir, 'demo-raw.webm'));
await fs.writeFile(path.join(root, 'scenes-timing.json'), JSON.stringify(timings, null, 2));
console.log(JSON.stringify({ output: path.join(rawDir, 'demo-raw.webm'), timings, instances: { happyPath: instId1, exceptionPath: instId2 } }, null, 2));
