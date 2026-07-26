#!/usr/bin/env node
// 튜토리얼 영상 시리즈 2/5 — "AI 에이전트를 활용한 제안서 작성" (튜토리얼 Lv.2)
// scenario-tutorial-lv2.md 참조. 1편(record_tutorial_lv1_demo.mjs)이 만든 proc_def를
// 확장한다: task2를 제안서 작성 에이전트(deepagents, draft)가 무인 수행하고, 사람이 확인.
// 오프닝/클로징 슬라이드 + 실제 Process GPT UI(조직도 에이전트 생성 · 학습 · DMN ·
// 빌드타임 패널 · 런타임 무인 수행/결과) 혼합.
//
// 실행: node record_tutorial_lv2_demo.mjs [outDir] [BASE]
import { chromium } from '../../../../services/frontend/node_modules/playwright/index.mjs';
import { makeSlides } from './lib_tutorial_slides.mjs';
import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';

const BASE = process.argv[3] || 'http://localhost:8088';
const root = path.resolve(process.argv[2] || 'demo-recordings/tutorial-lv2-ai-agent-proposal');
const rawDir = path.join(root, 'raw');
await fs.mkdir(rawDir, { recursive: true });

// 1편에서 이어받은 실측값 (scenario-tutorial-lv2.md §0).
const PROC_DEF_ID = 'b2f50721_3a7b_4f83_975e_cc046c8618c6';
const AGENT_ID    = 'fa3a2d21-cd7c-4078-931a-91220b4fd9e1'; // 제안서 작성 에이전트
const DMN_ID      = 'dmn_region_proposal_policy';           // 지역별 단가·납기·인증 규칙 (agent_id 연결)
const AUTH_UID    = 'bd0e585b-3828-496c-92aa-3f93f336d3d3';
// 사전 완주한 쇼케이스 인스턴스(결과/COMPLETED 화면용).
const DONE_INST   = 'b2f50721_3a7b_4f83_975e_cc046c8618c6.5a88c640-dfcb-4674-92bf-c4f993c07c6b';
const DONE_T2WI   = '076dcdbe-3207-4816-aefa-e518bdc46f0d'; // 제안서 초안 생성 (COMPLETED, 초안 보유)
// 이번 녹화에서 즉석 트리거할 새 인스턴스(시작 트리거 + '에이전트 작업중' 실화면용).
const FRESH_UUID  = crypto.randomUUID();
const FRESH_INST  = `${PROC_DEF_ID}.${FRESH_UUID}`;
const CUSTOMER_REQ = '미국(북미) 바이어에게 스마트팩토리 센서 모듈 50개 견적을 제안하려 합니다. FOB 조건으로 단가·납기·필수 인증을 안내해 주세요.';
const AGENT_NL = '미국·유럽·국내 지역별 단가와 납기, 필수 인증을 반영해 영업 제안서 초안을 자동으로 작성하는 제안서 작성 에이전트';
const PRICING_TABLE = `아래는 제안서 작성에 필요한 지역별 단가·납기 정책이니 학습해.

KR 대한민국(내수): 최소 주문 수량 10개, 기본 단가 420,000원/개, 배송료 15,000원(30개 이상 무료), 납기 5일 이내 출고, 인증 없음(내수용).
US 북미(미국/캐나다): 최소 주문 수량 50개, 기본 단가 USD 320/개(FOB), 배송료 약 180,000원(50개 기준), 납기 7일~10일, FCC 인증 필수.
EU 유럽(독일/프랑스): 최소 주문 수량 50개, 기본 단가 USD 320/개(FOB), 배송료 약 210,000원(50개 기준), 납기 7일~12일, CE 인증 필수.`;

const browser = await chromium.launch({ headless: true });
const context = await browser.newContext({
  viewport: { width: 1920, height: 1080 },
  recordVideo: { dir: rawDir, size: { width: 1920, height: 1080 } },
});
const page = await context.newPage();
const slide = makeSlides(page, { level: 2, brand: 'PROCESS GPT · TUTORIAL Lv.2', foot: 'tutorial-lv2 · AI 에이전트를 활용한 제안서 작성 · 2/5' });

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
async function getToken() {
  return await page.evaluate(() => {
    for (const k of Object.keys(localStorage)) {
      if (k.includes('auth-token')) { const v = JSON.parse(localStorage.getItem(k)); return v.access_token ?? v.currentSession?.access_token; }
    }
  });
}
async function triggerFresh(token) {
  const body = { input: {
    process_definition_id: PROC_DEF_ID, process_instance_id: FRESH_INST, activity_id: 'task1',
    email: 'demo@localhost', user_id: AUTH_UID, username: 'demo',
    form_values: { [`${PROC_DEF_ID}_task1_form`]: { request_details: CUSTOMER_REQ }, request_details: CUSTOMER_REQ },
  } };
  return await page.evaluate(async ({ BASE, token, body }) => {
    const r = await fetch(`${BASE}/completion/complete`, { method: 'POST', headers: { 'Authorization': `Bearer ${token}`, 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
    return { status: r.status };
  }, { BASE, token, body });
}

// ── Scene 1 — 오프닝 ─────────────────────────────────────────────
mark(1);
await slide({
  title: 'AI 에이전트를 활용한 제안서 작성',
  body: 'ProcessGPT 튜토리얼 Lv.2 — 1편에서 만든 영업 제안서 프로세스에 AI 에이전트를 붙여,\n제안서 초안을 사람 개입 없이 자동으로 작성하게 만듭니다.',
  flow: ['고객 · 요청 입력', 'AI 에이전트 · 초안 자동 생성', '영업 담당자 · 확인'],
});
await page.waitForTimeout(900); await shot(1); await page.waitForTimeout(13000);

// ── Scene 2 — 이번 편에서 배울 것 ────────────────────────────────
mark(2);
await slide({
  title: '이번 편에서 배우는 것',
  body: '조직도에 업무용 AI 에이전트를 만들고, 회사 지식을 가르쳐, 프로세스 단계에 붙여 무인으로 일하게 합니다.',
  cards: [
    { h: '① 조직도 에이전트 생성', p: '영업팀에 "제안서 작성 에이전트"를 자연어로 생성합니다.' },
    { h: '② 지식 학습 (mem0 + DMN)', p: '지역별 단가·납기·인증 표를 학습시키고, 규칙성 지식은 DMN 결정 테이블로도 등록합니다.' },
    { h: '③ 프로세스에 에이전트 결합', p: '초안 생성 단계를 딥에이전트(deepagents)로 무인 수행하도록 지정합니다.' },
    { h: '④ 무인 수행 → 사람 확인', p: '에이전트가 학습·규칙을 반영해 초안을 만들고, 사람은 확인만 하면 됩니다.' },
  ],
});
await page.waitForTimeout(900); await shot(2); await page.waitForTimeout(13500);

// ── Scene 3 — 1편 요약 브릿지 ────────────────────────────────────
mark(3);
await slide({
  title: '1편에서 만든 프로세스를 확장합니다',
  body: '1편에서는 "고객 요청 입력 → 영업 담당자 제안서 작성" 2단계 프로세스를 만들어 실행했습니다.\n이번 편에서는 제안서 작성 단계를 AI 에이전트가 대신하도록 확장합니다.',
  flow: ['(1편) 요청 입력', '(1편) 담당자가 직접 작성', '→', '(2편) 에이전트가 초안 자동 생성'],
});
await page.waitForTimeout(900); await shot(3); await page.waitForTimeout(10500);

// ── Scene 4 — 로그인 (실화면) + 런타임 인스턴스 사전 트리거 ────────
mark(4);
await login();
await page.waitForTimeout(600); await shot(4);
await page.locator('button:has-text("로그인")').click();
await page.waitForTimeout(4000);
// 백그라운드로 새 인스턴스 시작 → deepagents가 뒤에서 초안 생성 시작(런타임 장면까지 완료됨)
try { const tk = await getToken(); const r = await triggerFresh(tk); console.log('fresh trigger', r.status, FRESH_INST); } catch (e) { console.log('trigger err', e.message); }

// ── Scene 5 — 조직도: 영업팀 + 제안서 작성 에이전트 (실화면) ──────
mark(5);
await page.goto(`${BASE}/organization`, { waitUntil: 'load', timeout: 30000 });
await page.waitForTimeout(4000); await shot(5);
await page.waitForTimeout(8000);

// ── Scene 6 — 에이전트 생성: 자연어 입력 + AI 생성 (실화면, 저장 안 함) ─
mark(6);
await page.locator('.v-tab:has-text("에이전트 생성")').first().click().catch(()=>{});
await page.waitForTimeout(1500);
const genTa = page.locator('.user-input-generator-textarea textarea:not([aria-hidden="true"])').first();
await genTa.click().catch(()=>{});
await genTa.type(AGENT_NL, { delay: 18 }).catch(()=>{});
await page.waitForTimeout(700); await shot(6);
await page.locator('button:has-text("AI로 에이전트 생성")').first().click().catch(()=>{}); // 실제 생성 트리거(프로필 자동 생성)
await page.waitForTimeout(6000); await shot('06b'); // 생성 진행/결과가 보이도록
await page.waitForTimeout(2000);

// ── Scene 7 — 생성된 에이전트 프로필 (실화면, 조직도의 에이전트를 클릭) ─
mark(7);
await page.goto(`${BASE}/agent-chat/${AGENT_ID}`, { waitUntil: 'load', timeout: 30000 });
await page.waitForTimeout(3500); await shot(7);
await page.waitForTimeout(7500);

// ── Scene 8 — 에이전트 학습: 지역별 단가/납기 표 붙여넣기 (실화면) ──
mark(8);
await page.locator('text=학습 모드').first().click().catch(()=>{});
await page.waitForTimeout(2000);
const learnInput = page.getByPlaceholder('메시지 입력').first();
await learnInput.click().catch(()=>{});
await learnInput.fill(PRICING_TABLE).catch(()=>{});
await page.waitForTimeout(700); await shot(8);
// 전송 (학습 모드 send — 종이비행기 버튼)
await page.locator('.cp-send:visible').first().click({ timeout: 5000 }).catch(async () => {
  await learnInput.press('Enter').catch(()=>{});
});
await page.waitForTimeout(7000); await shot('08b'); // "학습했습니다" 응답
await page.waitForTimeout(2500);

// ── Scene 9 — 지식 관리 탭: 학습된 지식이 화면에 남음 (실화면) ─────
mark(9);
await page.locator('text=지식 관리').first().click().catch(()=>{});
await page.waitForTimeout(3500); await shot(9);
await page.waitForTimeout(7500);

// ── Scene 10 — DMN 결정 테이블: 지역별 규칙성 지식 (실화면) ────────
//   같은 지역별 표를 DMN 결정 테이블로도 등록해, 규칙 회수를 결정 로직으로
//   고정한다. 에이전트에 연결된 DMN(proc_def type='dmn', agent_id)을 dmn-js로 표시.
mark(10);
await page.goto(`${BASE}/dmn/${DMN_ID}`, { waitUntil: 'load', timeout: 30000 });
await page.waitForTimeout(6000); await shot(10);
await page.waitForTimeout(8500);

// ── Scene 11 — MCP 서버 탭: 도구는 MCP로 확장 (실화면, 소개만) ────
mark(11);
await page.goto(`${BASE}/account-settings`, { waitUntil: 'load', timeout: 30000 });
await page.waitForTimeout(3000);
await page.locator('text=MCP 서버').first().click().catch(()=>{});
await page.waitForTimeout(3000); await shot(11);
await page.waitForTimeout(6500);

// ── Scene 12 — 빌드타임: 초안 생성 단계에 에이전트 결합 (실화면) ──
mark(12);
await page.goto(`${BASE}/definitions/${PROC_DEF_ID}`, { waitUntil: 'load', timeout: 30000 });
await page.waitForTimeout(6500); await shot(12);
// task2 더블클릭 → 에이전트 탭
await page.locator('[data-element-id="task2"]').first().dblclick({ force: true }).catch(()=>{});
await page.waitForTimeout(2500);
await page.locator('.v-tab:has-text("에이전트")').first().click().catch(()=>{});
await page.waitForTimeout(2000); await shot('12b'); // 딥에이전트 + 초안 + 미리설정 에이전트
await page.waitForTimeout(7000);

// ── Scene 13 — 런타임: 시작 트리거 + '에이전트 작업중' (새 인스턴스 실화면) ─
mark(13);
await page.goto(`${BASE}/instance-viewer/${FRESH_INST}`, { waitUntil: 'load', timeout: 30000 });
await page.waitForTimeout(5000); await shot(13);
await page.waitForTimeout(7500);

// ── Scene 14 — 에이전트에 맡기기: 무인 수행 결과 (초안이 단가/납기 반영) ─
mark(14);
await page.goto(`${BASE}/todolist/${DONE_T2WI}`, { waitUntil: 'load', timeout: 30000 });
await page.waitForTimeout(5000);
await page.locator('text=에이전트에 맡기기').first().click().catch(()=>{});
await page.waitForTimeout(3500); await shot(14);
await page.waitForTimeout(10000);

// ── Scene 15 — 사람 확인 → COMPLETED (실화면) ────────────────────
mark(15);
await page.goto(`${BASE}/instance-viewer/${DONE_INST}`, { waitUntil: 'load', timeout: 30000 });
await page.waitForTimeout(5000); await shot(15);
await page.waitForTimeout(7500);

// ── Scene 16 — 클로징 ───────────────────────────────────────────
mark(16);
await slide({
  title: '에이전트가 대신 초안을 썼습니다',
  body: '조직도에 만든 AI 에이전트에 회사 지식을 가르치고, 프로세스 단계에 붙여 무인으로 제안서 초안을 생성했습니다.\n생성된 초안은 학습·규칙으로 넣은 지역별 단가·납기·인증을 그대로 반영했습니다.',
  cards: [
    { h: '오늘 확장한 것', p: '제안서 작성 에이전트 생성 · 지식 학습 · 초안 생성 단계를 deepagents 무인 수행으로 결합.' },
    { h: '다음 편 예고 · Lv.3', p: '조건 분기(게이트웨이) 설정과 피드백 반영 — 확인 단계에서 승인/반려로 흐름을 나눠 봅니다.' },
  ],
});
await page.waitForTimeout(900); await shot(16); await page.waitForTimeout(13500);

const video = page.video();
await context.close();
await browser.close();
const recorded = await video.path();
await fs.rm(path.join(rawDir, 'demo-raw.webm'), { force: true });
await fs.rename(recorded, path.join(rawDir, 'demo-raw.webm'));
await fs.writeFile(path.join(root, 'scenes-timing.json'), JSON.stringify(timings, null, 2));
console.log(JSON.stringify({ output: path.join(rawDir, 'demo-raw.webm'), fresh_inst: FRESH_INST, timings }, null, 2));
