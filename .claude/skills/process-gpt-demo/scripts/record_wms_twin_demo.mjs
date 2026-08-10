#!/usr/bin/env node
// WMS "WCS 디지털 트윈" demo — the warehouse as a live floor plan.
//
// Deliberately WMS-ONLY. Unlike record_wms_sequential_dispatch_demo.mjs this
// script never touches ProcessGPT: everything it shows happens on /wcs/twin
// against the WMS Supabase stack alone. That is not a simplification, it is the
// point — the twin's inline paths must work with ProcessGPT switched off, and a
// recording that needed both stacks up would quietly stop proving that.
//
// Prerequisites (both idempotent, run once against the local WMS stack):
//   services/sample-app-wms/supabase/migrations/20260807_wcs_twin_layout.sql
//   services/sample-app-wms/supabase/migrations/20260808_twin_realtime_publication.sql
//   services/sample-app-wms/scripts/setup_twin_layout_demo.sql
// and the WMS frontend running on :5273.
//
// Everything the equipment "does" is driven off-camera through psql as the
// seeded WCS_GATEWAY identity — the same RPCs a real PLC bridge calls. Nothing
// on screen is faked; the browser is only ever watching.
//
// Usage:
//   node record_wms_twin_demo.mjs [outDir] [wmsBase]
//   FAST=1 node record_wms_twin_demo.mjs      # skip the long dwells while iterating

import { chromium } from '../../../../services/frontend/node_modules/playwright/index.mjs';
import { execFileSync } from 'node:child_process';
import fs from 'node:fs/promises';
import path from 'node:path';

const WMS_BASE = process.argv[3] || 'http://localhost:5273';
const root = path.resolve(process.argv[2] || 'demo-recordings/wms-twin-demo');
const rawDir = path.join(root, 'raw');
await fs.mkdir(rawDir, { recursive: true });

const WMS_DB = 'supabase_db_process-gpt-sample-app-wms';
const TENANT = '10000000-0000-0000-0000-00000000000a';
const WH = '20000000-0000-0000-0000-00000000000a';
const CELL = 'DISPATCH-CELL-01';
const PALLET = `PLT-TWIN-DEMO-${Date.now().toString().slice(-5)}`;

function sh(cmd, args, opts = {}) {
  try {
    return execFileSync(cmd, args, { encoding: 'utf8', ...opts }).trim();
  } catch (e) {
    console.error(`  [off-camera] ${cmd} FAILED: ${e.stdout || ''}${e.stderr || ''}`);
    throw e;
  }
}

// The local Postgres blips under load; retry transient connection errors rather
// than losing a whole recording to one of them.
function shRetry(cmd, args, opts = {}, tries = 8, delayMs = 4000) {
  let lastErr;
  for (let i = 0; i < tries; i++) {
    try {
      return execFileSync(cmd, args, { encoding: 'utf8', ...opts }).trim();
    } catch (e) {
      lastErr = e;
      const msg = `${e.stdout || ''}${e.stderr || ''}`;
      if (!/recovery mode|server closed the connection|could not connect/i.test(msg)) throw e;
      console.error(`  [off-camera] transient DB error, retry ${i + 1}/${tries}`);
      execFileSync('sleep', [String(Math.round(delayMs / 1000))]);
    }
  }
  throw lastErr;
}

const psql = (sql) => shRetry('docker',
  ['exec', '-i', WMS_DB, 'psql', '-U', 'postgres', '-d', 'postgres', '-qAt', '-v', 'ON_ERROR_STOP=1', '-c', sql]);

/** Run a plpgsql body as one of the seeded demo identities. */
const asUser = (email, body) => psql(`
do $do$
declare v_actor uuid;
begin
  select id into v_actor from auth.users where email = '${email}';
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_actor::text, 'role', 'authenticated')::text, true);
  set local role authenticated;
  ${body}
end $do$;`);

// ---------------------------------------------------------------- off-camera

function ensureCellIdle() {
  asUser('wcs-gateway-a@demo.local', `
    if (select status from wms.equipment where equipment_code = '${CELL}') <> 'IDLE' then
      perform wms.wms_report_equipment_status(
        p_equipment_id => (select id from wms.equipment where equipment_code = '${CELL}'),
        p_new_status => 'IDLE', p_actor_id => v_actor, p_idempotency_key => gen_random_uuid(),
        p_expected_version => (select version from wms.equipment where equipment_code = '${CELL}'),
        p_correlation_id => 'twin-demo');
    end if;`);
}

function seedPallet() {
  asUser('wh-manager-a@demo.local', `
    declare v_wave uuid; v_o uuid; r jsonb; i int;
    begin
      r := wms.wms_open_dispatch_wave('${TENANT}','${WH}', v_actor, gen_random_uuid(), 'twin-demo');
      v_wave := (r->>'wave_id')::uuid;
      for i in 1..3 loop
        r := wms.wms_create_outbound_order('${TENANT}','${WH}', 'STORE-042',
             (select id from wms.products where sku = 'SKU-A-00'||least(i,3) and tenant_id='${TENANT}'),
             10 * i, v_actor, gen_random_uuid(), '${PALLET}-'||i, null, 7 * i, 9 * i, 'twin-demo');
        v_o := (r->>'outbound_order_id')::uuid;
        perform wms.wms_assign_dispatch_sequence(v_o, v_wave, i, '${PALLET}', v_actor,
          gen_random_uuid(), (select version from wms.outbound_orders where id = v_o), 'twin-demo');
      end loop;
    end;`);
}

/**
 * The cell reports back. load_position is REVERSED against sequence_position on
 * purpose — a cell may legitimately load out of order
 * (_wms_propagate_palletize_result), and a bottom layer stamped "계획 #3" is the
 * single clearest argument for drawing a stack instead of a table.
 */
function cellReportsSuccess() {
  asUser('wcs-gateway-a@demo.local', `
    declare v_cmd uuid; v_ver int; v_n int;
    begin
      select c.id into v_cmd from wms.equipment_commands c
       where c.command_type = 'PALLETIZE' and c.payload->>'target_pallet_code' = '${PALLET}'
       order by c.created_at desc limit 1;
      select version into v_ver from wms.equipment_commands where id = v_cmd;
      perform wms.wms_report_command_result(v_cmd, 'IN_PROGRESS', v_actor, gen_random_uuid(), v_ver, null, 'twin-demo');
      select count(*) into v_n from wms.dispatch_sequences where equipment_command_id = v_cmd;
      select version into v_ver from wms.equipment_commands where id = v_cmd;
      perform wms.wms_report_command_result(v_cmd, 'COMPLETED', v_actor, gen_random_uuid(), v_ver,
        jsonb_build_object('outcome','SUCCESS','total_actual_weight_kg', 41.0,
          'loaded_items', (select jsonb_agg(jsonb_build_object(
             'dispatch_sequence_id', s.id, 'item_outcome','LOADED',
             'load_position', v_n + 1 - s.sequence_position))
           from wms.dispatch_sequences s where s.equipment_command_id = v_cmd)),
        'twin-demo');
    end;`);
}

/**
 * A what-if scenario with a projection already computed, so scene 10 has
 * something to show. Created AND run off-camera on purpose: the projection is
 * the interesting artefact, and wms_run_simulation_scenario is WMS_ADMIN /
 * WAREHOUSE_MANAGER only — by scene 10 the demo is logged in as the operator,
 * who can read it but not run it. That asymmetry is the role model working, not
 * a limitation to hide.
 */
function seedScenario() {
  asUser('wh-manager-a@demo.local', `
    declare r jsonb; v_sid uuid;
    begin
      if exists (select 1 from wms.simulation_scenarios
                  where warehouse_id = '${WH}' and name = '출고 셀 단독 처리 10건') then return; end if;
      r := wms.wms_create_simulation_scenario(
        p_tenant_id => '${TENANT}', p_warehouse_id => '${WH}',
        p_name => '출고 셀 단독 처리 10건',
        p_equipment_ids => array[(select id from wms.equipment where equipment_code = '${CELL}')],
        p_command_count => 10, p_actor_id => v_actor,
        p_idempotency_key => gen_random_uuid(), p_correlation_id => 'twin-demo');
      v_sid := (r->>'scenario_id')::uuid;
      perform wms.wms_run_simulation_scenario(v_sid, v_actor, gen_random_uuid(), 'twin-demo');
    end;`);
}

function gatewayRaisesFault(code, severity) {
  asUser('wcs-gateway-a@demo.local', `
    perform wms.wms_raise_equipment_fault(
      p_equipment_id => (select id from wms.equipment where equipment_code = '${CELL}'),
      p_fault_code => '${code}', p_severity => '${severity}',
      p_actor_id => v_actor, p_idempotency_key => gen_random_uuid(),
      p_correlation_id => 'twin-demo');`);
}

function cleanup() {
  psql(`
    update wms.equipment_faults f set status='RESOLVED',
           resolution_note='demo cleanup', resolved_at=now()
      from wms.equipment e
     where e.id = f.equipment_id and e.warehouse_id = '${WH}' and f.status='OPEN';

    -- Resolving fault rows directly skips wms_resolve_equipment_fault, which is
    -- what normally walks a machine back out of FAULT. Without this the next run
    -- finds the cell stuck in FAULT with nothing open to explain it, and
    -- ensureCellIdle() is then correctly refused — the status RPC will not move a
    -- machine out of FAULT, that is resolve's job alone.
    update wms.equipment set status='IDLE', version=version+1, updated_at=now()
     where warehouse_id = '${WH}' and status='FAULT'
       and not exists (select 1 from wms.equipment_faults f
                        where f.equipment_id = equipment.id and f.status='OPEN');

    delete from wms.dispatch_sequences where target_pallet_code like 'PLT-TWIN-DEMO-%';
    delete from wms.outbound_orders where order_number like 'PLT-TWIN-DEMO-%';

    delete from wms.simulation_scenario_runs r using wms.simulation_scenarios s
     where s.id = r.scenario_id and s.name = '출고 셀 단독 처리 10건';
    delete from wms.simulation_scenarios where name = '출고 셀 단독 처리 10건';`);
}

// ------------------------------------------------------------------- capture

const browser = await chromium.launch({ headless: false, args: ['--window-size=1920,1080'] });
const context = await browser.newContext({
  viewport: { width: 1920, height: 1080 },
  recordVideo: { dir: rawDir, size: { width: 1920, height: 1080 } },
  locale: 'ko-KR',
});
const page = await context.newPage();

const started = Date.now();
const timings = [];
let curMark = Date.now();
const mark = (scene) => {
  curMark = Date.now();
  timings.push({ scene, start_sec: Number(((Date.now() - started) / 1000).toFixed(2)) });
  console.log(`scene ${scene}  t=${((Date.now() - started) / 1000).toFixed(1)}s`);
};

// Hold each scene for as long as its narration actually runs, so the audio
// never spills into the next shot. Generate the narration first
// (gen_narration_openai.py), then record — durations.json is the input that
// paces the video, not the other way round. Without it the scene dwells fall
// back to a flat 9s and the mix overlaps badly.
let narDur = {};
try {
  const dj = JSON.parse(await fs.readFile(path.join(root, 'narration', 'durations.json'), 'utf8'));
  for (const r of dj) narDur[r.scene] = r.duration;
  console.log(`  [pacing] narration durations loaded for ${Object.keys(narDur).length} scenes`);
} catch {
  console.log('  [pacing] no narration/durations.json — using flat dwells');
}
const holdN = async (scene, buffer = 1200, min = 1500) => {
  if (FAST) return page.waitForTimeout(200);
  const want = ((narDur[scene] || 9) * 1000) + buffer;
  const spent = Date.now() - curMark;
  await page.waitForTimeout(Math.max(min, want - spent));
};
const shot = (n) => page.screenshot({ path: path.join(root, `scene-${String(n).padStart(2, '0')}.png`) }).catch(() => {});
const FAST = !!process.env.FAST;
const wait = (ms) => page.waitForTimeout(FAST && ms >= 3000 ? 350 : ms);

async function slide(title, body, flow = '') {
  await page.setContent(`<!doctype html><html lang="ko"><head><meta charset="utf-8"><style>
  *{box-sizing:border-box}body{margin:0;background:#0b1220;color:#eef5ff;font-family:-apple-system,BlinkMacSystemFont,"Pretendard",sans-serif}
  .shell{height:1080px;padding:70px 90px;background:radial-gradient(circle at 88% 3%,#22406e 0,transparent 35%),radial-gradient(circle at 6% 96%,#1c5a4a 0,transparent 30%),linear-gradient(135deg,#0b1220,#0f1b2e)}
  .brand{color:#8fd6c4;font-weight:800;letter-spacing:.08em;font-size:22px}.brand:before{content:'●';color:#3ddc97;margin-right:14px;text-shadow:0 0 20px #3ddc97}
  h1{font-size:52px;line-height:1.2;margin:36px 0 22px;letter-spacing:-.03em;white-space:pre-line}
  .body{font-size:23px;line-height:1.7;color:#b7c9d9;white-space:pre-line;max-width:1560px}
  .flow{display:flex;gap:10px;align-items:center;margin-top:38px;flex-wrap:wrap}
  .node{padding:13px 18px;border:1px solid #3d6791;background:#152742;border-radius:14px;font-size:17px;font-weight:700}
  .arrow{font-size:22px;color:#66aaf7}
  .foot{position:absolute;left:90px;right:90px;bottom:42px;display:flex;justify-content:space-between;color:#6f8a9c;font-size:16px}
  </style></head><body><main class="shell"><div class="brand">PROCESS GPT · WMS 디지털 트윈</div><h1>${title}</h1><div class="body">${body}</div><div class="flow">${flow}</div>
  <div class="foot"><span>/wcs/twin · wms.layout_* · supabase_realtime</span><span>ProcessGPT · wms-mcp · Supabase</span></div></main></body></html>`);
}

async function wmsLogin(email) {
  await page.goto(`${WMS_BASE}/login`, { waitUntil: 'load', timeout: 60000 });
  await page.getByLabel('Email').fill(email);
  await page.getByLabel('Password').fill('Demo1234!');
  await page.getByRole('button', { name: /sign in/i }).click();
  await page.waitForURL(/overview/, { timeout: 60000 });
}

/**
 * Zoom the canvas onto the palletizing cell. At the default fit-to-canvas zoom a
 * 1200x700 floor plan renders about half size, and the whole argument of scenes
 * 5-8 — layer order, the planned-vs-actual stamp, the weight gauge — is
 * unreadable at that scale. Uses the same "설비로 이동" control an operator has.
 */
async function focusCell() {
  await page.getByTestId(`twin-node-${CELL}`).click();
  await wait(600);
  await page.getByRole('button', { name: '설비로 이동' }).first().click();
  await wait(1200);
}

async function openTwin(lens) {
  await page.goto(`${WMS_BASE}/wcs/twin`, { waitUntil: 'load', timeout: 60000 });
  await page.getByTestId('twin-connection-state').waitFor({ timeout: 30000 });
  if (lens) await page.getByTestId(`twin-lens-${lens}`).click();
  await wait(1200);
}

// ═══════════════════════════════════════════════ 1 · Opening
mark(1);
await slide(
  '창고를 표가 아니라 도면으로',
  '시장조사(docs/04-wms-wcs-market-feature-catalog.md)가 말하는 "디지털 트윈"은 두 갈래입니다.\nSwisslog SynQ 의 사전검증 에뮬레이션, 그리고 두산·SAP /SCWM/MON 의 실시간 가시화.\n\n이 저장소는 앞의 것을 이미 갖고 있었습니다 — 시뮬레이션 4테이블·12 RPC 와 게이트웨이 워커.\n없던 것은 뒤의 것, 즉 눈(도면)과 신경(푸시 채널)이었습니다.',
  '<div class="node">wms.layout_*</div><div class="arrow">→</div><div class="node">SVG 2D</div><div class="arrow">→</div><div class="node">supabase_realtime</div>'
);
await wait(1000); await shot(1); await holdN(1);

// ═══════════════════════════════════════════════ 2 · The floor plan
mark(2);
cleanup();
ensureCellIdle();
seedScenario();
await wmsLogin('wh-manager-a@demo.local');
await openTwin();
await shot(2);
await holdN(2);

// ═══════════════════════════════════════════════ 3 · Nothing is hidden
mark(3);
await slide(
  '없는 것을 그리지 않고, 모르는 것은 모른다고 말합니다',
  'wms 도메인에는 원래 좌표가 없습니다. wms.equipment 에는 자유 텍스트 zone_code 뿐이고,\nstorage_locations 의 accessibility_rank 는 위치가 아니라 서수입니다.\n\n그래서 좌표는 신규 테이블 4개에만 넣었고, 도면에 자리가 없는 설비는 버리지 않고\n점선으로 자동 배치한 뒤 "위치 미지정" 이라고 적습니다 —\n트윈이 /wcs/equipment 보다 적은 수의 기계를 보여주는 것은 크래시보다 나쁘기 때문입니다.',
  '<div class="node">has_layout=false → 기본 프레임</div><div class="arrow">·</div><div class="node">unmapped_equipment → 점선</div>'
);
await wait(900); await shot(3); await holdN(3);

// ═══════════════════════════════════════════════ 4 · Sequential dispatch
mark(4);
seedPallet();
await openTwin('dispatch');
await shot(4);
await holdN(4);

// ═══════════════════════════════════════════════ 5 · Dispatch the palletize
mark(5);
await page.getByTestId(`twin-dispatch-${PALLET}`).click();
await page.getByTestId('twin-notice').waitFor({ timeout: 40000 });
await wait(1500);
await focusCell();
await shot(5);
await holdN(5);

// ═══════════════════════════════════════════════ 6 · The stack builds itself
mark(6);
console.log('  [off-camera] the cell reports SUCCESS with a reversed load order');
cellReportsSuccess();
await wait(3500); await shot(6);
await holdN(6);

// ═══════════════════════════════════════════════ 7 · Fault → alarm
mark(7);
await page.getByTestId('twin-lens-recovery').click();
await wait(1200);
console.log('  [off-camera] the gateway raises two faults');
gatewayRaisesFault('GRIPPER_MISALIGN', 'CRITICAL');
gatewayRaisesFault('DUST_SENSOR', 'WARNING');
await page.getByTestId('twin-alarm').first().waitFor({ timeout: 40000 });
await wait(1500);
await focusCell();
await shot(7);
await holdN(7);

// ═══════════════════════════════════════════════ 8 · Resolve, honestly
mark(8);
await wmsLogout();
await wmsLogin('wcs-operator-a@demo.local');
await openTwin('recovery');
const firstAlarm = page.getByTestId('twin-alarm').first();
await firstAlarm.getByRole('button', { name: '해소' }).click();
await firstAlarm.locator('input').fill('그리퍼 재정렬 및 원점 복귀 완료');
await wait(1500);
await firstAlarm.getByRole('button', { name: '장애 해소' }).click();
await page.getByTestId('twin-notice').waitFor({ timeout: 40000 });
await wait(2500); await shot(8);
await holdN(8);

// ═══════════════════════════════════════════════ 9 · Bottleneck lens
mark(9);
await page.getByTestId('twin-lens-reroute').click();
await wait(2000); await shot(9);
await holdN(9);

// ═══════════════════════════════════════════════ 10 · What-if lens
mark(10);
await page.getByTestId('twin-lens-whatif').click();
await wait(2500); await shot(10);
await holdN(10);

// ═══════════════════════════════════════════════ 11 · Closing
mark(11);
await slide(
  '이번 데모가 실증한 것',
  '설비 상태·팔레트 적재·장애가 새로고침 없이 도면에서 움직였고, 운영자가 그 화면에서\n기존 RPC 를 그대로 호출해 조치했습니다. 트윈만 내릴 수 있는 명령은 하나도 없습니다.\n\n그리고 화면은 RPC 가 붙인 경고를 요약하지 않습니다 — "다른 장애가 남아 설비는 FAULT 유지",\n"OPTIMISTIC_ESTIMATE: no queueing, no retries". 확신에 차 보이는 대시보드보다\n자기 한계를 말하는 도면이 낫기 때문입니다.\n\n경쟁 제품의 트윈은 "감지하고 빨갛게 표시"에서 끝납니다.\nProcessGPT 에서는 그 감지가 BPMN 인스턴스를 기동합니다.',
  '<div class="node">SVG 2D · 의존성 0</div><div class="arrow">·</div><div class="node">4 렌즈</div><div class="arrow">·</div><div class="node">신규 권한 0</div>'
);
await wait(900); await shot(11); await holdN(11, 2500);

async function wmsLogout() {
  await page.goto(`${WMS_BASE}/overview`, { waitUntil: 'load', timeout: 60000 });
  const signOut = page.getByRole('button', { name: /sign out/i });
  if (await signOut.count()) { await signOut.click(); await wait(1500); }
}

const video = page.video();
await context.close();
await browser.close();
const recorded = await video.path();
await fs.rm(path.join(rawDir, 'demo-raw.webm'), { force: true });
await fs.rename(recorded, path.join(rawDir, 'demo-raw.webm'));
await fs.writeFile(path.join(root, 'scenes-timing.json'), JSON.stringify(timings, null, 2));
console.log(JSON.stringify({ output: path.join(rawDir, 'demo-raw.webm'), timings, pallet: PALLET }, null, 2));
