#!/usr/bin/env node
// 튜토리얼 영상 시리즈 3/5 — "조건 분기 설정과 피드백 반영" (튜토리얼 Lv.3)
// scenario-tutorial-lv3.md 참조. 2편이 만든 3단계 proc_def(task3=사람 확인)를 확장한다:
// task3 뒤에 배타 게이트웨이(gw_revision "보완 사항 유무 확인")를 두고,
//   - 보완 필요(needs_revision='true') → task2 제안서 초안 생성으로 루프백
//   - 보완 불필요('false') → 종료
// 빌드타임: BPMN 편집기 직접 조작(편집 모드 진입 · 게이트웨이 팔레트 · 분기 조건 입력
//   [자연어 + 함수 모드 conditionFunction] · task2 체크포인트 추가 · 저장)을 실녹화.
// 런타임: 반려 제출 → 루프백 → 승인 → COMPLETED (실증 인스턴스 실화면).
//
// 실행: node record_tutorial_lv3_demo.mjs [outDir] [BASE]
import { chromium } from '../../../../services/frontend/node_modules/playwright/index.mjs';
import { makeSlides } from './lib_tutorial_slides.mjs';
import fs from 'node:fs/promises';
import path from 'node:path';

const BASE = process.argv[3] || 'http://localhost:8088';
const root = path.resolve(process.argv[2] || 'demo-recordings/tutorial-lv3-conditional-feedback');
const rawDir = path.join(root, 'raw');
await fs.mkdir(rawDir, { recursive: true });

const PID = 'b2f50721_3a7b_4f83_975e_cc046c8618c6';
const LOOP_INST = 'b2f50721_3a7b_4f83_975e_cc046c8618c6.4bcc2ff4-4e6d-41dd-8881-5c6204cbb92e'; // 반려→루프백→승인→COMPLETED
const T3_WI = '82d1b425-a121-4e80-abb5-f45abe2678d2'; // 제안서 확인 워크아이템 (보완 필요 여부 라디오)

const browser = await chromium.launch({ headless: true });
const context = await browser.newContext({
  viewport: { width: 1920, height: 1080 },
  recordVideo: { dir: rawDir, size: { width: 1920, height: 1080 } },
});
const page = await context.newPage();
const slide = makeSlides(page, { level: 3, brand: 'PROCESS GPT · TUTORIAL Lv.3', foot: 'tutorial-lv3 · 조건 분기 설정과 피드백 반영 · 3/5' });

const started = Date.now();
const timings = [];
const mark = (scene) => { timings.push({ scene, start_sec: Number(((Date.now() - started) / 1000).toFixed(2)) }); console.log('scene', scene, ((Date.now()-started)/1000).toFixed(1)+'s'); };
const shot = (n) => page.screenshot({ path: path.join(root, `scene-${String(n).padStart(2,'0')}.png`) }).catch(()=>{});
const wait = (ms) => page.waitForTimeout(ms);

async function login() {
  await page.goto(`${BASE}/auth/login`, { waitUntil: 'load', timeout: 30000 });
  await page.waitForSelector('input[type="text"]', { timeout: 15000 });
  await page.locator('input[type="text"]').first().click();
  await page.locator('input[type="text"]').first().type('demo@localhost', { delay: 45 });
  await page.locator('input[type="password"]').first().click();
  await page.locator('input[type="password"]').first().type('Demo1234!', { delay: 45 });
}

// 편집/저장 토글 버튼(우측 패널 2번째 아이콘, x≈1576). 읽기모드=연필, 편집모드=저장.
async function toggleBtn() {
  const cand = page.locator('button.v-btn').filter({ hasText: /^$/ });
  const n = await cand.count();
  let best = null, bestd = 1e9;
  for (let i = 0; i < n; i++) {
    const bt = cand.nth(i);
    if (!(await bt.isVisible().catch(()=>false))) continue;
    const box = await bt.boundingBox().catch(()=>null);
    if (!box) continue;
    const cx = box.x + box.width/2;
    if (cx > 1555 && cx < 1600 && box.y > 150 && box.y < 230) {
      const d = Math.abs(cx - 1576);
      if (d < bestd) { bestd = d; best = bt; }
    }
  }
  return best;
}
const condOpen = async () => page.locator('text=결정론적 규칙화').first().isVisible().catch(()=>false);
async function edgeRect(id) {
  return page.evaluate((id)=>{ const g=document.querySelector(`[data-element-id="${id}"] .djs-visual`); if(!g) return null; const r=g.getBoundingClientRect(); return {x:r.x,y:r.y,w:r.width,h:r.height}; }, id);
}
async function openEdgePanel(id) {
  const r = await edgeRect(id); if (!r) return false;
  const pts = [[r.x+r.w/2, r.y+r.h/2]];
  for (const fy of [0.3,0.7,0.4,0.6]) pts.push([r.x+Math.max(r.w,1)/2, r.y+r.h*fy]);
  for (const fx of [0.3,0.7]) pts.push([r.x+r.w*fx, r.y+r.h/2]);
  pts.push([r.x+2, r.y+r.h-2], [r.x+r.w-2, r.y+2]);
  for (const [x,y] of pts) { await page.mouse.dblclick(x,y); await wait(900); if (await condOpen()) return true; }
  return false;
}
async function setCondition(id, nl, fn) {
  if (!(await openEdgePanel(id))) { console.log('open FAIL', id); return; }
  await wait(700);
  const condInput = page.locator('.v-text-field:has(.mdi-comment-text-outline) input').first();
  await condInput.click().catch(()=>{});
  await condInput.fill('');
  await condInput.type(nl, { delay: 40 }).catch(()=>{});
  await wait(900);
  // 함수 모드로 전환 → conditionFunction 직접 입력(결정론적 분기)
  await page.locator('.mdi-comment-text-outline').first().click().catch(()=>{});
  await wait(800);
  const fnInput = page.locator('.v-text-field:has(.mdi-function) input').first();
  await fnInput.click().catch(()=>{});
  await fnInput.type(fn, { delay: 35 }).catch(()=>{});
  await wait(1200);
  await page.mouse.click(600, 300); // 패널 닫아 값 flush
  await wait(1000);
}

// ── Scene 1 — 오프닝 ─────────────────────────────────────────────
mark(1);
await slide({
  title: '조건 분기 설정과 피드백 반영',
  body: 'ProcessGPT 튜토리얼 Lv.3 — 2편에서 만든 제안서 프로세스에\nBPMN 편집기로 직접 조건 분기(게이트웨이)와, 반려 시 되돌아가는 피드백 루프를 그려 넣습니다.',
  flow: ['제안서 확인', '보완 사항 유무 확인 (게이트웨이)', '보완 필요 → 초안 재작성', '보완 없음 → 종료'],
});
await wait(900); await shot(1); await wait(12500);

// ── Scene 2 — 이번 편에서 배울 것 ────────────────────────────────
mark(2);
await slide({
  title: '이번 편에서 배우는 것',
  body: '채팅만으로는 한계가 있는 흐름 제어를, BPMN 편집기에서 직접 게이트웨이를 놓고 조건을 입력하며 만듭니다.',
  cards: [
    { h: '① 편집기에서 게이트웨이 배치', p: '편집 모드로 전환해 팔레트에서 배타 게이트웨이를 캔버스에 놓습니다.' },
    { h: '② 분기 조건 입력', p: '각 분기 플로우에 자연어 조건과 결정론적 규칙(conditionFunction)을 직접 입력합니다.' },
    { h: '③ 체크포인트 추가', p: '초안 생성 단계에 오탈자·첨부·고객요청 반영 체크포인트를 더합니다.' },
    { h: '④ 피드백 루프', p: '반려되면 초안 생성 단계로 되돌아가 검토 의견과 함께 다시 작성하게 합니다.' },
  ],
});
await wait(900); await shot(2); await wait(14000);

// ── Scene 3 — 2편 브릿지 ─────────────────────────────────────────
mark(3);
await slide({
  title: '2편에서 만든 프로세스를 확장합니다',
  body: '2편에서는 "요청 입력 → AI 에이전트 초안 생성 → 담당자 확인" 3단계를 만들었습니다.\n이번 편에서는 확인 단계 뒤에 분기와 되돌림을 붙여, 반려된 제안서가 다시 다듬어지게 만듭니다.',
  flow: ['(2편) 요청 입력', '(2편) 에이전트 초안', '(2편) 담당자 확인', '→', '(3편) 분기 + 피드백 루프'],
});
await wait(900); await shot(3); await wait(10000);

// ── Scene 4 — 로그인 (실화면) ────────────────────────────────────
mark(4);
await login();
await wait(600); await shot(4);
await page.locator('button:has-text("로그인")').click();
await wait(4500);

// ══════════════ 빌드타임 — BPMN 편집기 직접 조작 (실화면) ══════════════

// ── Scene 5 — 디자이너 열기 + 편집 모드 진입 ─────────────────────
mark(5);
await page.goto(`${BASE}/definitions/${PID}`, { waitUntil: 'load', timeout: 30000 });
await wait(7000); await shot(5);
const tb = await toggleBtn();
if (tb) { await tb.click().catch(()=>{}); }
await wait(6500); // 편집 모드 모델러 렌더 대기
await shot('05b');
await wait(1500);

// ── Scene 6 — 팔레트에서 배타 게이트웨이 배치 제스처 (배치 후 undo) ─
mark(6);
const gwEntry = page.locator('.djs-palette .entry[data-action="create.exclusive-gateway"]').first();
if (await gwEntry.isVisible().catch(()=>false)) {
  await gwEntry.hover().catch(()=>{});
  await wait(700);
  await gwEntry.click().catch(()=>{}); // create 모드 활성
  await wait(600);
  await page.mouse.move(560, 620); await wait(400);
  await page.mouse.click(560, 620).catch(()=>{}); // 빈 캔버스에 배치(데모 제스처)
  await wait(1500); await shot(6);
  await page.keyboard.press('Control+z').catch(()=>{}); // 배치 취소(구조 오염 방지)
  await wait(1200);
} else { await shot(6); }
await wait(1500);

// ── Scene 7 — 분기 조건 입력 (SequenceFlowPanel: 자연어 + 함수 모드) ─
mark(7);
await setCondition('SequenceFlow_gw_task2', '보완 사항 있음', "needs_revision == 'true'");
await shot(7);
await setCondition('SequenceFlow_gw_end', '보완 사항 없음', "needs_revision == 'false'");
await shot('07b');
await wait(1500);

// ── Scene 8 — 초안 생성 단계에 체크포인트 추가 (설정 탭) ──────────
mark(8);
await page.locator('[data-element-id="task2"]').first().dblclick({ force: true }).catch(()=>{});
await wait(2200);
await page.locator('.v-tab[value="setting"]').first().click().catch(()=>{});
await wait(1800); await shot(8);
// '+' 로 체크포인트 추가 제스처
const before = await page.locator('.check-points-field-box input, .user-task-panel-check-points input').count();
await page.locator('.user-task-panel-check-points .mdi-plus').first().click().catch(()=>{});
await wait(900);
const after = await page.locator('.check-points-field-box input, .user-task-panel-check-points input').count();
if (after > before) {
  const inp = page.locator('.check-points-field-box input, .user-task-panel-check-points input').nth(after-1);
  await inp.click().catch(()=>{});
  await inp.type('고객 요청 반영', { delay: 40 }).catch(()=>{});
}
await wait(1500); await shot('08b');
await page.mouse.click(600, 300); // 패널 닫기
await wait(1200);

// ── Scene 9 — 저장 (편집기 1차 저장 경로) ────────────────────────
mark(9);
const sb = await toggleBtn();
if (sb) { await sb.click().catch(()=>{}); }
await wait(2500);
// 저장/버전 확인 다이얼로그가 있으면 확인
for (const label of ['저장', '확인', '예']) {
  const btn = page.locator(`.v-dialog button:has-text("${label}"), .v-overlay button:has-text("${label}")`).first();
  if (await btn.isVisible().catch(()=>false)) { await btn.click().catch(()=>{}); await wait(2500); break; }
}
await wait(2500); await shot(9);
await wait(1500);

// ══════════════ 런타임 — 반려 → 루프백 → 승인 → COMPLETED (실화면) ══════════════

// ── Scene 10 — 확인 단계 워크아이템: 보완 필요 여부 (반려 결정 지점) ─
mark(10);
await page.goto(`${BASE}/todolist/${T3_WI}`, { waitUntil: 'load', timeout: 30000 });
await wait(5500); await shot(10);
await wait(8500);

// ── Scene 11 — 인스턴스 뷰어: 루프백 경로 + 전 구간 통과 ──────────
mark(11);
await page.goto(`${BASE}/instance-viewer/${LOOP_INST}`, { waitUntil: 'load', timeout: 30000 });
await wait(6000); await shot(11);
await wait(9000);

// ── Scene 12 — 완주(COMPLETED) 확인 ──────────────────────────────
mark(12);
await page.goto(`${BASE}/todolist/${T3_WI}`, { waitUntil: 'load', timeout: 30000 });
await wait(5500); await shot(12);
await wait(7500);

// ── Scene 13 — 클로징 ────────────────────────────────────────────
mark(13);
await slide({
  title: '흐름이 갈라지고, 되돌아옵니다',
  body: 'BPMN 편집기에서 직접 게이트웨이와 분기 조건, 체크포인트, 되돌림 루프를 그려 넣었습니다.\n이제 제안서가 반려되면 초안 생성 단계로 돌아가 검토 의견과 함께 다시 다듬어지고, 승인되면 종료됩니다.',
  cards: [
    { h: '오늘 설계한 것', p: '조건 분기(배타 게이트웨이) · 결정론적 분기 조건 · 품질 체크포인트 · 반려 시 피드백 루프.' },
    { h: '다음 편 예고 · Lv.4', p: 'ERP 데이터 연동을 통한 재고 관리 — 외부 데이터소스를 프로세스에 연결합니다.' },
  ],
});
await wait(900); await shot(13); await wait(13000);

const video = page.video();
await context.close();
await browser.close();
const recorded = await video.path();
await fs.rm(path.join(rawDir, 'demo-raw.webm'), { force: true });
await fs.rename(recorded, path.join(rawDir, 'demo-raw.webm'));
await fs.writeFile(path.join(root, 'scenes-timing.json'), JSON.stringify(timings, null, 2));
console.log(JSON.stringify({ output: path.join(rawDir, 'demo-raw.webm'), timings }, null, 2));
