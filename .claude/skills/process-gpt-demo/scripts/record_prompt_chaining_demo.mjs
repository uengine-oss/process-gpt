#!/usr/bin/env node
// Prompt Chaining 에이전틱 패턴 데모 녹화 — scenario-9-prompt-chaining.md
// 오프닝/클로징 슬라이드 + 실제 Process GPT UI(로그인/채팅 생성/BPMN/에이전트 모니터) 혼합.
import { chromium } from '../../../../services/frontend/node_modules/playwright/index.mjs';
import fs from 'node:fs/promises';
import path from 'node:path';

const BASE = process.argv[3] || 'http://localhost:5199';
const root = path.resolve(process.argv[2] || 'demo-recordings/prompt-chaining-demo');
const rawDir = path.join(root, 'raw');
await fs.mkdir(rawDir, { recursive: true });

// 이번 데모에서 실제로 만들어진 값(재실행 시 갱신 필요).
const ROOM_ID = '09e7eb19-f766-4695-adc6-7ce5c8d34bb0';
const TREND_WORKITEM_ID = '26350e83-323f-4861-b0bf-0a92b617ea55';
const EMAIL_WORKITEM_ID = '1c2b7a19-c285-4d87-ab79-cd522c8188d4';

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
  *{box-sizing:border-box}body{margin:0;background:#07111f;color:#eef5ff;font-family:-apple-system,BlinkMacSystemFont,"Pretendard",sans-serif}.shell{height:1080px;padding:70px 90px;background:radial-gradient(circle at 88% 3%,#1b497a 0,transparent 35%),linear-gradient(135deg,#07111f,#0d1c31)}.brand{color:#8fbfff;font-weight:800;letter-spacing:.08em;font-size:22px}.brand:before{content:'●';color:#4f9cff;margin-right:14px;text-shadow:0 0 20px #4f9cff}h1{font-size:56px;line-height:1.18;margin:40px 0 22px;letter-spacing:-.04em;white-space:pre-line}.body{font-size:23px;line-height:1.6;color:#aebfd2;white-space:pre-line;max-width:1500px}.flow{display:flex;gap:14px;align-items:center;margin-top:40px;flex-wrap:wrap}.node{padding:16px 22px;border:1px solid #3d6791;background:#142c49;border-radius:16px;font-size:19px;font-weight:750}.arrow{font-size:28px;color:#66aaf7}.foot{position:absolute;left:90px;right:90px;bottom:42px;display:flex;justify-content:space-between;color:#71879c;font-size:16px}
  .cards{display:grid;grid-template-columns:1fr 1fr;gap:20px;margin-top:36px;max-width:1500px}.card{background:rgba(17,34,57,.9);border:1px solid #294563;border-radius:18px;padding:22px 26px}.card b{color:#8fbfff;font-size:19px}.card p{margin:10px 0 0;font-size:17px;color:#c3d2e4;line-height:1.5}
  </style></head><body><main class="shell"><div class="brand">PROCESS GPT · PROMPT CHAINING</div><h1>${title}</h1><div class="body">${body}</div><div class="flow">${flow}</div><div class="foot"><span>prompt-chaining-demo · scenario 9</span><span>Process GPT + deepagents</span></div></main></body></html>`);
}

// Scene 1 — 오프닝: Prompt Chaining 패턴 설명
mark(1);
await slide(
  'Prompt Chaining\n복잡한 과제를 단계별 LLM 호출로 연결한다',
  '이전 단계의 출력을 다음 단계의 입력으로 전달해, 각 단계가 좁고 명확한 역할만 맡게 하는 에이전틱 패턴입니다.\n순차적 의존성 · 작업 분해 · 단계별 최적화 · 명확한 관찰 가능성, 4가지가 핵심입니다.',
  '<div class="node">보고서 요약</div><div class="arrow">→</div><div class="node">트렌드 식별</div><div class="arrow">→</div><div class="node">이메일 작성</div>'
);
await page.waitForTimeout(900); await shot(1); await page.waitForTimeout(19500);

mark(2);
await slide(
  '이번 데모: 시장조사 인사이트 체인',
  '사람은 시장조사 보고서 원문만 입력합니다. 이후 2단계(핵심 트렌드 식별)와 3단계(마케팅팀 이메일 초안 작성)는\n사람 개입 없이 딥에이전트(orchestration=deepagents)가 순서대로 자동 처리하며,\n각 단계는 이전 단계 출력을 실제로 참조합니다 — 요약이 아니라 근거 기반 체이닝입니다.',
  '<div class="node">담당자 입력</div><div class="arrow">→</div><div class="node">딥에이전트 · 트렌드 식별</div><div class="arrow">→</div><div class="node">딥에이전트 · 이메일 초안</div>'
);
await page.waitForTimeout(900); await shot(2); await page.waitForTimeout(21200);

// Scene 3 — 실제 UI: 로그인
mark(3);
await page.goto(`${BASE}/auth/login`, { waitUntil: 'load', timeout: 30000 });
await page.waitForSelector('input[type="text"]', { timeout: 15000 });
await page.locator('input[type="text"]').first().fill('demo@localhost');
await page.locator('input[type="password"]').first().fill('Demo1234!');
await page.waitForTimeout(800);
await shot(3);
await page.locator('button:has-text("로그인")').click();
await page.waitForTimeout(3000);

// Scene 4 — 실제 UI: 채팅으로 만든 체이닝 프로세스 (승인된 대화 스크롤)
mark(4);
await page.goto(`${BASE}/definition-map?roomId=${ROOM_ID}`, { waitUntil: 'load', timeout: 30000 });
await page.waitForTimeout(2000);
const sidebarEntry = page.getByText('시장조사 보고서를 분석해', { exact: false }).first();
if (await sidebarEntry.count()) { await sidebarEntry.click(); await page.waitForTimeout(1500); }
await page.mouse.wheel(0, 400);
await page.waitForTimeout(1000);
await shot(4);
await page.waitForTimeout(16000);

// Scene 5 — 실제 UI: 스킬/에이전트 후보 선택 확인 지점까지 스크롤
mark(5);
await page.mouse.wheel(0, 900);
await page.waitForTimeout(1000);
await shot(5);
await page.waitForTimeout(19000);

// Scene 6 — 실제 UI: 워크아이템 상세의 BPMN 스윔레인(담당자/딥에이전트 역할 분리)
mark(6);
await page.goto(`${BASE}/todolist/${TREND_WORKITEM_ID}`, { waitUntil: 'load', timeout: 30000 });
await page.waitForTimeout(2000);
await shot(6);
await page.waitForTimeout(13000);

// Scene 7 — 실제 UI: 핵심 트렌드 식별 — 에이전트에 맡기기 탭(실패→성공 실측 이력)
mark(7);
await page.getByText('에이전트에 맡기기', { exact: true }).click();
await page.waitForTimeout(2000);
await shot(7);
await page.waitForTimeout(18000);

// Scene 8 — 실제 UI: 마케팅팀 이메일 초안 — 체이닝된 최종 산출물
mark(8);
await page.goto(`${BASE}/todolist/${EMAIL_WORKITEM_ID}`, { waitUntil: 'load', timeout: 30000 });
await page.waitForTimeout(2000);
await page.getByText('에이전트에 맡기기', { exact: true }).click();
await page.waitForTimeout(2000);
await shot(8);
await page.waitForTimeout(18500);

// Scene 9 — 클로징 슬라이드
mark(9);
await slide(
  '체이닝 성과 요약',
  '사람 개입 1회(보고서 입력) → 딥에이전트 2단계 무인 자동 완료 → bpm_proc_inst.status = COMPLETED.\n3단계 이메일 초안은 2단계가 식별한 구체 수치(68%, 42%, 55%, CAC 22% 등)를 그대로 인용해,\n체이닝이 실제로 이전 단계 산출물을 근거로 동작했음을 보여줍니다.',
  '<div class="node">순차적 의존성</div><div class="arrow">→</div><div class="node">단계별 전문 스킬</div><div class="arrow">→</div><div class="node">관찰 가능한 실행 이력</div>'
);
await page.waitForTimeout(900); await shot(9); await page.waitForTimeout(19000);

const video = page.video();
await context.close();
await browser.close();
const recorded = await video.path();
await fs.rm(path.join(rawDir, 'demo-raw.webm'), { force: true });
await fs.rename(recorded, path.join(rawDir, 'demo-raw.webm'));
await fs.writeFile(path.join(root, 'scenes-timing.json'), JSON.stringify(timings, null, 2));
console.log(JSON.stringify({ output: path.join(rawDir, 'demo-raw.webm'), timings }, null, 2));
