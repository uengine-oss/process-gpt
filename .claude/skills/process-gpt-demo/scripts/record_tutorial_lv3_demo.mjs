#!/usr/bin/env node
// 튜토리얼 영상 시리즈 3/5 — "조건 분기 설정과 피드백 반영" (튜토리얼 Lv.3)
// scenario-tutorial-lv3.md 참조. 2편이 만든 3단계 proc_def(task3=사람 확인)를 확장한다:
// task3 뒤에 배타 게이트웨이(gw_revision "보완 사항 유무 확인")를 두고,
//   - 보완 필요(needs_revision=true) → task2 제안서 초안 생성으로 루프백(피드백 반영 재작성)
//   - 보완 불필요(false) → 종료
// 빌드타임은 BPMN 편집기 직접 조작(게이트웨이 배치·시퀀스 조건 입력·체크포인트 추가)을 실녹화한다.
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
// 실증 완료 인스턴스(런타임 실화면용, scenario §0).
const LOOP_INST = 'b2f50721_3a7b_4f83_975e_cc046c8618c6.4bcc2ff4-4e6d-41dd-8881-5c6204cbb92e'; // 반려→루프백→승인→COMPLETED
const T2_WI = '18d3c4a4-406a-4f4f-ae55-96b4fb550b96'; // 제안서 초안 생성 워크아이템(루프백 대상)
const T3_WI = '82d1b425-a121-4e80-abb5-f45abe2678d2'; // 제안서 확인 워크아이템(반려/승인)

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
  title: '조건 분기 설정과 피드백 반영',
  body: 'ProcessGPT 튜토리얼 Lv.3 — 2편에서 만든 제안서 프로세스에\n"확인 → 보완 필요 여부"에 따라 흐름이 갈라지는 조건 분기와, 반려 시 되돌아가는 피드백 루프를 직접 설계합니다.',
  flow: ['제안서 확인', '보완 사항 유무 확인 (게이트웨이)', '보완 필요 → 초안 재작성', '보완 없음 → 종료'],
});
await page.waitForTimeout(900); await shot(1); await page.waitForTimeout(13000);

// ── Scene 2 — 이번 편에서 배울 것 ────────────────────────────────
mark(2);
await slide({
  title: '이번 편에서 배우는 것',
  body: 'BPMN 편집기에서 직접 게이트웨이를 배치하고 분기 조건을 입력하며, 체크포인트로 품질 기준을 명시하고, 반려 시 이전 단계로 되돌리는 루프를 만듭니다.',
  cards: [
    { h: '① 배타 게이트웨이 배치', p: '편집기 팔레트에서 게이트웨이를 캔버스에 놓고, 확인 단계 뒤에 연결합니다.' },
    { h: '② 분기 조건 입력', p: '각 분기 플로우에 "보완 사항 있음/없음" 조건을 편집기 패널에서 직접 입력합니다.' },
    { h: '③ 체크포인트 추가', p: '초안 생성 단계에 오탈자·첨부·고객요청 반영 체크포인트를 더합니다.' },
    { h: '④ 피드백 루프', p: '반려되면 초안 생성 단계로 되돌아가 검토 의견을 반영해 다시 작성하게 합니다.' },
  ],
});
await page.waitForTimeout(900); await shot(2); await page.waitForTimeout(14000);

// ── Scene 3 — 2편 브릿지 ─────────────────────────────────────────
mark(3);
await slide({
  title: '2편에서 만든 프로세스를 확장합니다',
  body: '2편에서는 "요청 입력 → AI 에이전트 초안 생성 → 담당자 확인" 3단계를 만들었습니다.\n이번 편에서는 확인 단계 뒤에 분기와 되돌림을 붙여, 반려된 제안서가 자동으로 다시 다듬어지게 만듭니다.',
  flow: ['(2편) 요청 입력', '(2편) 에이전트 초안', '(2편) 담당자 확인', '→', '(3편) 분기 + 피드백 루프'],
});
await page.waitForTimeout(900); await shot(3); await page.waitForTimeout(10500);

// ── Scene 4 — 로그인 (실화면) ────────────────────────────────────
mark(4);
await login();
await page.waitForTimeout(600); await shot(4);
await page.locator('button:has-text("로그인")').click();
await page.waitForTimeout(4500);

// ══════════════════════════════════════════════════════════════════
//  빌드타임 — BPMN 편집기 직접 조작 (실녹화)
//  ※ 편집기 셀렉터/제스처는 editor-research 결과로 확정해 채운다.
// ══════════════════════════════════════════════════════════════════
// (SCENE 5~9 자리 — editor build 섹션)

// ══════════════════════════════════════════════════════════════════
//  런타임 — 반려 → 루프백 → 재작성 → 승인 → COMPLETED (실화면)
// ══════════════════════════════════════════════════════════════════
// (SCENE 10~13 자리 — runtime 섹션)

// ── 클로징 ───────────────────────────────────────────────────────
mark(99);
await slide({
  title: '흐름이 갈라지고, 되돌아옵니다',
  body: 'BPMN 편집기에서 직접 게이트웨이와 분기 조건, 체크포인트, 되돌림 루프를 그려 넣었습니다.\n이제 제안서가 반려되면 자동으로 초안 생성 단계로 돌아가 검토 의견과 함께 다시 다듬어지고, 승인되면 종료됩니다.',
  cards: [
    { h: '오늘 설계한 것', p: '조건 분기(배타 게이트웨이) · 분기 조건 · 품질 체크포인트 · 반려 시 피드백 루프.' },
    { h: '다음 편 예고 · Lv.4', p: 'ERP 데이터 연동을 통한 재고 관리 — 외부 데이터소스를 프로세스에 연결합니다.' },
  ],
});
await page.waitForTimeout(900); await shot(99); await page.waitForTimeout(13500);

const video = page.video();
await context.close();
await browser.close();
const recorded = await video.path();
await fs.rm(path.join(rawDir, 'demo-raw.webm'), { force: true });
await fs.rename(recorded, path.join(rawDir, 'demo-raw.webm'));
await fs.writeFile(path.join(root, 'scenes-timing.json'), JSON.stringify(timings, null, 2));
console.log(JSON.stringify({ output: path.join(rawDir, 'demo-raw.webm'), timings }, null, 2));
