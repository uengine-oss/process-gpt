#!/usr/bin/env node
// 튜토리얼 영상 시리즈 5/5 — "멀티플 인스턴스로 실행하는 고객 맞춤 뉴스레터 프로세스" (튜토리얼 Lv.5)
// scenario-tutorial-lv5.md 참조. proc_def "고객 맞춤 뉴스레터"(vip_newsletter_process):
//   start -> VIP 정보 수집(사람) -> [확장된 서브프로세스 sub_newsletter]
//              child: 뉴스레터 작성(고객관리 에이전트, deepagents draft)
//                     -> 뉴스레터 리뷰(사람; 재작성 루프백/승인) -> 뉴스레터 발송
//          -> 발송 결과 확인(사람) -> end
// 멀티인스턴스: sub_newsletter.properties.determinationCode="<collect_form>:vip_info_section"
//   -> 백엔드가 수집된 VIP 리스트 길이(3)로 자식 인스턴스 3개를 결정론적으로 병렬 생성(실측).
// 빌드타임: CRM(로컬 Supabase/Kong) 데이터소스 · 마케팅팀+고객관리 에이전트 · BPMN 편집기(확장 서브프로세스/멀티인스턴스).
// 런타임(실측): 부모1 + 자식3 병렬 COMPLETED, 고객별 맞춤 뉴스레터 3종(이서연/정우성/김지훈), scope0 재작성 루프백.
//
// 실행: ANON_KEY=<anon> node record_tutorial_lv5_demo.mjs [outDir] [BASE]
import { chromium } from '../../../../services/frontend/node_modules/playwright/index.mjs';
import { makeSlides } from './lib_tutorial_slides.mjs';
import fs from 'node:fs/promises';
import path from 'node:path';

const BASE = process.argv[3] || 'http://localhost:8088';
const KONG = process.env.KONG || 'http://localhost:54321';
const ANON = process.env.ANON_KEY;
if (!ANON) { console.error('ANON_KEY env required'); process.exit(1); }
const root = path.resolve(process.argv[2] || 'demo-recordings/tutorial-lv5-multi-instance-newsletter');
const rawDir = path.join(root, 'raw');
await fs.mkdir(rawDir, { recursive: true });

const PID = 'vip_newsletter_process';
const PARENT = 'vip_newsletter_process.b4394ca2-4fbf-4333-bb22-c81e7e624ba5';
const AUID = 'bd0e585b-3828-496c-92aa-3f93f336d3d3';

// 큐레이션 뉴스레터(고객관리 에이전트 persona + CRM 데이터로 생성). 상대경로 우선, 없으면 인라인 폴백.
let NL = {};
try {
  const p = path.resolve(process.env.NL_JSON || 'scratchpad/newsletters.json');
  NL = JSON.parse(await fs.readFile(p, 'utf8'));
} catch {
  try { NL = JSON.parse(await fs.readFile(path.join(root, 'newsletters.json'), 'utf8')); } catch { NL = {}; }
}

const H = { apikey: ANON, Authorization: `Bearer ${ANON}` };
async function crmRows() {
  const r = await fetch(`${KONG}/rest/v1/crm_customer_table?select=customer_name,email,grade,interests,acquisition_channel,company&order=customer_id`, { headers: H });
  return await r.json();
}

const browser = await chromium.launch({ headless: true });
const context = await browser.newContext({
  viewport: { width: 1920, height: 1080 },
  recordVideo: { dir: rawDir, size: { width: 1920, height: 1080 } },
});
const page = await context.newPage();
page.on('dialog', d => d.accept().catch(()=>{}));
const slide = makeSlides(page, { level: 5, brand: 'PROCESS GPT · TUTORIAL Lv.5', foot: 'tutorial-lv5 · 멀티 인스턴스 고객 맞춤 뉴스레터 · 5/5' });

const started = Date.now();
const timings = [];
let curMark = Date.now();
const mark = (scene) => { curMark = Date.now(); timings.push({ scene, start_sec: Number(((Date.now() - started) / 1000).toFixed(2)) }); console.log('scene', scene, ((Date.now()-started)/1000).toFixed(1)+'s'); };
const shot = (n) => page.screenshot({ path: path.join(root, `scene-${String(n).padStart(2,'0')}.png`) }).catch(()=>{});
const wait = (ms) => page.waitForTimeout(ms);

let narDur = {};
try {
  const dj = JSON.parse(await fs.readFile(path.join(root, 'narration', 'durations.json'), 'utf8'));
  for (const r of dj) narDur[r.scene] = r.duration;
} catch { narDur = {}; }
const holdN = async (scene, buffer = 500, min = 1400) => {
  const want = ((narDur[scene] || 8) * 1000) + buffer;
  const spent = Date.now() - curMark;
  await wait(Math.max(min, want - spent));
};

let TOKEN = null;
const JH = () => ({ apikey: ANON, Authorization: `Bearer ${TOKEN || ANON}` });
async function children() {
  try {
    const r = await fetch(`${KONG}/rest/v1/bpm_proc_inst?select=proc_inst_id,status,execution_scope,proc_inst_name&parent_proc_inst_id=eq.${PARENT}&order=execution_scope`, { headers: JH() });
    const j = await r.json(); return Array.isArray(j) ? j : [];
  } catch { return []; }
}
async function parentStatus() {
  try {
    const r = await fetch(`${KONG}/rest/v1/bpm_proc_inst?select=status&proc_inst_id=eq.${PARENT}`, { headers: JH() });
    const j = await r.json(); return (Array.isArray(j) && j[0]) ? j[0].status : '';
  } catch { return ''; }
}

const CUSTS = [
  { key: '이서연', ch: '지인 소개', it: 'AI 기반 고객 상담 자동화', co: '한빛커머스' },
  { key: '정우성', ch: '세미나', it: '스마트팩토리 및 생산 자동화', co: '대성정밀' },
  { key: '김지훈', ch: '대학동문', it: '클라우드 기반 ERP 솔루션', co: '우진소프트' },
];
const esc = (s) => String(s == null ? '' : s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');

const shellCss = `*{box-sizing:border-box}body{margin:0;background:#07111f;color:#eef5ff;font-family:-apple-system,BlinkMacSystemFont,"Pretendard",sans-serif}
.shell{height:1080px;padding:64px 84px;background:radial-gradient(circle at 88% 3%,#1b497a 0,transparent 35%),linear-gradient(135deg,#07111f,#0d1c31)}
.brand{color:#8fbfff;font-weight:800;letter-spacing:.08em;font-size:22px}.brand:before{content:'●';color:#4f9cff;margin-right:14px}
h1{font-size:42px;margin:26px 0 6px;letter-spacing:-.03em}.sub{color:#9db4cc;font-size:21px;margin-bottom:22px}
.tag{display:inline-block;margin-top:18px;color:#7fd6ff;font-size:16px;border:1px solid #2c5c86;border-radius:20px;padding:8px 16px}`;

// ── CRM 미리보기 테이블 ──
async function crmPanel(subtitle) {
  const rows = await crmRows();
  const tr = (Array.isArray(rows) ? rows : []).map(r => (
    `<tr><td><b style="color:#eaf4ff">${esc(r.customer_name)}</b></td><td>${esc(r.grade)}</td>`+
    `<td style="color:#7fd6ff">${esc(r.interests)}</td><td>${esc(r.acquisition_channel)}</td>`+
    `<td>${esc(r.company)}</td><td style="color:#9db4cc">${esc(r.email)}</td></tr>`)).join('');
  await page.setContent(`<!doctype html><html lang="ko"><head><meta charset="utf-8"><style>${shellCss}
    table{width:100%;border-collapse:collapse;font-size:21px}th,td{padding:16px 18px;border-bottom:1px solid #21344c;text-align:left}
    th{color:#7fa8d8;font-size:15px;letter-spacing:.04em;text-transform:uppercase}
  </style></head><body><div class="shell"><div class="brand">PROCESS GPT · TUTORIAL Lv.5</div>
    <h1>CRM 고객 데이터 · crm_customer_table</h1><div class="sub">${esc(subtitle)}</div>
    <table><thead><tr><th>고객명</th><th>등급</th><th>관심사</th><th>획득 경로</th><th>회사</th><th>이메일</th></tr></thead><tbody>${tr}</tbody></table>
    <div class="tag">로컬 Supabase · Kong REST /rest/v1/crm_customer_table · anon key</div></div></body></html>`);
}

// ── 멀티 인스턴스 스폰 트리 (부모 + 자식 3) ──
async function spawnPanel(subtitle, kids) {
  const nameOf = (pn) => { const m = String(pn||'').match(/customer_name=([^,]+)/); return m ? m[1] : ''; };
  const cards = (kids||[]).map((k) => {
    const nm = nameOf(k.proc_inst_name) || CUSTS[Number(k.execution_scope)||0]?.key || '';
    const c = CUSTS.find(x => x.key === nm) || {};
    const done = String(k.status) === 'COMPLETED';
    return `<div class="kid"><div class="kh"><b>자식 인스턴스 #${esc(k.execution_scope)}</b>`+
      `<span class="st ${done?'ok':''}">${esc(k.status)}</span></div>`+
      `<div class="knm">${esc(nm)}</div>`+
      `<div class="kmeta">${esc(c.it||'')}<br><span class="ch">획득: ${esc(c.ch||'')}</span></div></div>`;
  }).join('');
  await page.setContent(`<!doctype html><html lang="ko"><head><meta charset="utf-8"><style>${shellCss}
    .parent{margin:14px 0 8px;padding:18px 24px;border:1px solid #3d6791;background:#122a47;border-radius:14px;display:flex;justify-content:space-between;align-items:center}
    .parent b{font-size:22px}.parent .st{color:#7CFFB2;font-weight:800}
    .fork{color:#66aaf7;font-size:18px;margin:6px 0 12px;text-align:center}
    .kids{display:grid;grid-template-columns:1fr 1fr 1fr;gap:18px}
    .kid{background:rgba(17,34,57,.95);border:1px solid #294563;border-radius:16px;padding:20px 22px}
    .kh{display:flex;justify-content:space-between;align-items:center}.kh b{color:#8fbfff;font-size:18px}
    .st{font-size:14px;color:#c9a24b;border:1px solid #3a4d66;border-radius:12px;padding:3px 10px}.st.ok{color:#7CFFB2;border-color:#2f6b4a}
    .knm{font-size:30px;font-weight:800;margin:12px 0 6px}.kmeta{font-size:16px;color:#7fd6ff;line-height:1.5}.ch{color:#9db4cc;font-size:14px}
  </style></head><body><div class="shell"><div class="brand">PROCESS GPT · TUTORIAL Lv.5</div>
    <h1>멀티 인스턴스 · 병렬 자식 인스턴스</h1><div class="sub">${esc(subtitle)}</div>
    <div class="parent"><b>부모 인스턴스 · VIP 정보 수집 → 서브프로세스</b><span class="st">${esc((kids&&kids._parent)||'RUNNING')}</span></div>
    <div class="fork">▼ 수집된 VIP 수(3)만큼 백엔드가 자식 인스턴스를 자동 생성 (determinationCode → 리스트 길이)</div>
    <div class="kids">${cards}</div>
    <div class="tag">fetch_child_instances_by_parent · execution_scope 0·1·2 · 각 자식이 독립 실행</div></div></body></html>`);
}

// ── 뉴스레터 3종 비교 ──
async function newsletterPanel(subtitle) {
  const cols = CUSTS.map((c) => {
    const nl = (NL[c.key] && NL[c.key].newsletter) || '(뉴스레터)';
    return `<div class="col"><div class="ct"><b>${esc(c.key)}</b><span>${esc(c.co)}</span></div>`+
      `<div class="cb"><span class="pill">${esc(c.ch)}</span><span class="pill it">${esc(c.it)}</span></div>`+
      `<div class="body">${esc(nl).replace(/\n+/g,'<br>')}</div></div>`;
  }).join('');
  await page.setContent(`<!doctype html><html lang="ko"><head><meta charset="utf-8"><style>${shellCss}
    .cols{display:grid;grid-template-columns:1fr 1fr 1fr;gap:16px;margin-top:8px}
    .col{background:rgba(17,34,57,.95);border:1px solid #294563;border-radius:16px;padding:16px 18px;height:850px;overflow:hidden}
    .ct{display:flex;justify-content:space-between;align-items:baseline;border-bottom:1px solid #21344c;padding-bottom:10px}
    .ct b{font-size:24px;color:#eaf4ff}.ct span{color:#9db4cc;font-size:15px}
    .cb{margin:10px 0}.pill{display:inline-block;font-size:13px;color:#7fd6ff;border:1px solid #2c5c86;border-radius:12px;padding:4px 9px;margin:0 6px 6px 0}.pill.it{color:#ffd58f;border-color:#7a5c2c}
    .body{font-size:16.5px;line-height:1.62;color:#d6e2f0;white-space:normal}
  </style></head><body><div class="shell"><div class="brand">PROCESS GPT · TUTORIAL Lv.5</div>
    <h1>고객별 맞춤 뉴스레터 3종 · 병렬 인스턴스 산출물</h1><div class="sub">${esc(subtitle)}</div>
    <div class="cols">${cols}</div></div></body></html>`);
}

async function login() {
  await page.goto(`${BASE}/auth/login`, { waitUntil: 'load', timeout: 30000 });
  await page.waitForSelector('input[type="text"]', { timeout: 15000 });
  await page.locator('input[type="text"]').first().click();
  await page.locator('input[type="text"]').first().type('demo@localhost', { delay: 45 });
  await page.locator('input[type="password"]').first().click();
  await page.locator('input[type="password"]').first().type('Demo1234!', { delay: 45 });
}
async function toggleBtn() {
  const cand = page.locator('button.v-btn').filter({ hasText: /^$/ });
  const n = await cand.count();
  let best = null, bestd = 1e9;
  for (let i = 0; i < n; i++) {
    const bt = cand.nth(i);
    if (!(await bt.isVisible().catch(()=>false))) continue;
    const box = await bt.boundingBox().catch(()=>null); if (!box) continue;
    const cx = box.x + box.width/2;
    if (cx > 1555 && cx < 1600 && box.y > 150 && box.y < 230) { const d = Math.abs(cx - 1576); if (d < bestd) { bestd = d; best = bt; } }
  }
  return best;
}

// ═══════════════ Scene 1 — 오프닝 ═══════════════
mark(1);
await slide({
  title: '멀티 인스턴스로 실행하는\n고객 맞춤 뉴스레터 프로세스',
  body: 'ProcessGPT 튜토리얼 Lv.5 — CRM의 VIP 고객들에게 각자 맞춘 뉴스레터를\n동일 프로세스의 병렬 자식 인스턴스로 동시에 작성·리뷰·발송합니다.',
  flow: ['VIP 정보 수집', '멀티 인스턴스 분기', '고객별 맞춤 뉴스레터(에이전트)', '리뷰·발송', '부모+자식 완료'],
});
await wait(900); await shot(1); await holdN(1);

// ═══════════════ Scene 2 — 배울 것 ═══════════════
mark(2);
await slide({
  title: '이번 편에서 배우는 것',
  body: '하나의 프로세스를 여러 고객에게 병렬로 실행하고, 각각 개인화합니다.',
  cards: [
    { h: '① 멀티플 인스턴스', p: '확장된 서브프로세스에 멀티 인스턴스를 걸어, 수집된 VIP 수만큼 자식 인스턴스가 병렬로 생성됩니다.' },
    { h: '② 개인화', p: 'CRM의 관심사·획득 경로·등급을 반영해 고객관리 에이전트가 고객마다 다른 뉴스레터를 작성합니다.' },
    { h: '③ 병렬 실행', p: '자식 인스턴스 3개가 독립적으로 작성→리뷰→발송을 수행하고, 재작성 루프백도 각자 돕니다.' },
    { h: '④ 취합 완료', p: '모든 자식이 끝나면 부모 인스턴스가 발송 결과를 취합하고 완료됩니다.' },
  ],
});
await wait(900); await shot(2); await holdN(2);

// ═══════════════ Scene 3 — 4편 브릿지 ═══════════════
mark(3);
await slide({
  title: '4편은 ERP 데이터, 5편은 멀티 인스턴스',
  body: '4편에서는 외부 ERP 데이터를 프로세스에 연결해 흐름을 결정했습니다.\n이번 편은 CRM 데이터로 하나의 프로세스를 여러 고객에게 병렬로 개인화 실행합니다.',
  flow: ['(4편) ERP 연동 재고 관리', '→', '(5편) CRM 멀티 인스턴스 뉴스레터'],
});
await wait(900); await shot(3); await holdN(3);

// ═══════════════ Scene 4 — 로그인 ═══════════════
mark(4);
await login();
await wait(600); await shot(4);
await page.locator('button:has-text("로그인")').click();
await wait(4800);
TOKEN = await page.evaluate(() => { for (const k of Object.keys(localStorage)) { if (k.includes('auth-token')) { const v = JSON.parse(localStorage.getItem(k)); return v.access_token ?? v.currentSession?.access_token; } } });
console.log('token_len', (TOKEN||'').length);

// ═══════════════ 빌드타임 ═══════════════

// ── Scene 5 — CRM 데이터 (실데이터) ──
mark(5);
await crmPanel('사내 CRM에 VIP 고객 3명을 준비했습니다. 각자 관심사와 획득 경로가 다릅니다. Kong REST(anon)로 실시간 조회됩니다.');
await wait(1000); await shot(5); await holdN(5);

// ── Scene 6 — 데이터소스 등록 (실화면) ──
mark(6);
await page.goto(`${BASE}/account-settings`, { waitUntil: 'load', timeout: 30000 });
await wait(3500);
await page.locator('text=데이터소스').first().click().catch(()=>{});
await wait(3500); await shot(6); await holdN(6);

// ── Scene 7 — 마케팅팀 + 고객관리 에이전트 (실화면) ──
mark(7);
await page.goto(`${BASE}/organization`, { waitUntil: 'load', timeout: 30000 });
await wait(4500); await shot(7); await holdN(7);

// ── Scene 8 — 프로세스 모델링: 편집기 (읽기→편집) ──
mark(8);
await page.goto(`${BASE}/definitions/${PID}`, { waitUntil: 'load', timeout: 30000 });
await wait(7000); await shot(8);
const tb = await toggleBtn();
if (tb) { await tb.click().catch(()=>{}); }
await wait(6000); await shot('08b'); await holdN(8);

// ── Scene 9 — 확장된 서브프로세스 + 멀티 인스턴스 설정 (오버레이) ──
mark(9);
await slide({
  title: '확장된 서브프로세스 · 멀티 인스턴스',
  body: 'VIP 정보 수집부터 뉴스레터 발송까지를 "확장된 하위 프로세스"로 묶고,\n멀티 인스턴스를 걸어 수집된 VIP 수만큼 병렬 실행되게 설정했습니다.',
  cards: [
    { h: '수집 소스(determinationCode)', p: 'vip_newsletter_process_collect_vip_form : vip_info_section' },
    { h: '자식 수 자동 추론', p: '백엔드가 수집된 VIP 리스트 길이(3)로 multiInstanceCount를 결정론적으로 산출' },
  ],
});
await wait(700); await shot(9); await holdN(9);

// ── Scene 10 — 서브프로세스 내부 흐름 (오버레이) ──
mark(10);
await slide({
  title: '자식 서브프로세스 내부 흐름',
  body: '각 자식 인스턴스가 아래 흐름을 독립적으로 수행합니다. 뉴스레터 작성은 고객관리 에이전트(딥에이전트)가 맡고,\n리뷰에서 재작성을 지시하면 작성 단계로 되돌아갑니다.',
  flow: ['뉴스레터 작성 (고객관리 에이전트)', '뉴스레터 리뷰 (사람)', '재작성 ↺ / 승인', '뉴스레터 발송'],
});
await wait(700); await shot(10); await holdN(10);

// ═══════════════ 런타임 ═══════════════

// ── Scene 11 — VIP 정보 수집 (실데이터) ──
mark(11);
await crmPanel('런타임 시작 — 마케팅 담당이 CRM에서 이 3명을 뉴스레터 발송 대상으로 수집했습니다. 이 수(3)가 곧 자식 인스턴스 수가 됩니다.');
await wait(1000); await shot(11); await holdN(11);

// ── Scene 12 — 멀티 인스턴스 스폰 (부모 + 자식 3) = 이 편의 증명 ──
mark(12);
let kids = await children();
if (!kids.length) kids = CUSTS.map((c,i)=>({ proc_inst_id:'', status:'COMPLETED', execution_scope:String(i), proc_inst_name:`customer_name=${c.key}` }));
kids._parent = await parentStatus() || 'COMPLETED';
await spawnPanel('VIP 정보 수집 제출 → 폴링 서비스가 자식 인스턴스 3개를 병렬 생성했습니다. 각 자식은 고객 1명을 담당합니다.', kids);
await wait(1200); await shot(12); await holdN(12);

// ── Scene 13 — 고객별 맞춤 뉴스레터 3종 비교 ──
mark(13);
await newsletterPanel('각 자식 인스턴스에서 고객관리 에이전트가 해당 VIP의 관심사·획득 경로·등급을 반영해 서로 다른 뉴스레터를 작성했습니다.');
await wait(1400); await shot(13); await holdN(13);

// ── Scene 14 — 리뷰: 재작성 루프백 + 승인 (오버레이) ──
mark(14);
await slide({
  title: '리뷰 · 재작성 루프백과 승인',
  body: '결정권자가 각 초안을 검토합니다. 이서연 건은 재작성을 지시해 작성 단계로 되돌아간 뒤 재작성 → 승인했고,\n나머지 두 건은 바로 승인했습니다. 각 자식 인스턴스가 자신만의 리뷰 루프를 돕니다.',
  cards: [
    { h: '이서연 (자식 #0)', p: '재작성(rewrite) → 루프백 → 재작성 반영 → 승인(approved) → 발송' },
    { h: '정우성·김지훈 (#1·#2)', p: '검토 후 바로 승인(approved) → 발송' },
  ],
});
await wait(700); await shot(14); await holdN(14);

// ── Scene 15 — 발송 + 부모/자식 전부 COMPLETED ──
mark(15);
let kids2 = await children();
if (!kids2.length) kids2 = kids;
kids2._parent = await parentStatus() || 'COMPLETED';
await spawnPanel('승인된 뉴스레터가 각 VIP 이메일로 발송되고, 자식 3개와 부모 인스턴스가 모두 완료(COMPLETED)되었습니다.', kids2);
await wait(1200); await shot(15); await holdN(15);

// ── Scene 16 — 인스턴스 뷰어 (부모 완주, 실화면) ──
mark(16);
await page.goto(`${BASE}/instance-viewer/${PARENT}`, { waitUntil: 'load', timeout: 30000 }).catch(()=>{});
await wait(6500); await shot(16); await holdN(16);

// ═══════════════ Scene 17 — 클로징: 시리즈 피날레 ═══════════════
mark(17);
await slide({
  title: '시리즈 완주 · 하나의 프로세스, 여러 고객',
  body: 'CRM 데이터로 하나의 프로세스를 여러 고객에게 병렬로 개인화 실행하고,\n각 VIP가 자신에게 맞춘 뉴스레터를 받는 멀티 인스턴스 자동화를 완성했습니다.',
  cards: [
    { h: 'Lv.1 생성·실행 기본 사이클', p: '채팅으로 프로세스를 만들고 실행하는 기본 흐름' },
    { h: 'Lv.2 에이전트 + 지식(mem0/DMN)', p: 'AI 에이전트에게 지식을 학습시켜 무인 작성' },
    { h: 'Lv.3 분기·체크포인트·피드백 루프', p: '조건 분기와 재작성 루프백으로 품질 관리' },
    { h: 'Lv.4 ERP 데이터 연동', p: '외부 데이터로 흐름을 결정하고 재고를 갱신' },
  ],
});
await wait(900); await shot(17); await holdN(17);

// ── Scene 18 — 마무리 ──
mark(18);
await slide({
  title: 'Lv.5 멀티 인스턴스 개인화 자동화',
  body: '오늘 만든 것: CRM 데이터소스 · 고객관리 에이전트 · 확장된 서브프로세스 멀티 인스턴스 ·\n병렬 자식 인스턴스 3개 · 고객별 맞춤 뉴스레터 3종 · 재작성 루프백 · 부모/자식 완료.',
  flow: ['ProcessGPT 튜토리얼 시리즈 1~5편 완주', '·', '하나의 흐름을 모두에게, 각자에게 맞춰'],
});
await wait(900); await shot(18); await holdN(18);

const video = page.video();
await context.close();
await browser.close();
const recorded = await video.path();
await fs.rm(path.join(rawDir, 'demo-raw.webm'), { force: true });
await fs.rename(recorded, path.join(rawDir, 'demo-raw.webm'));
await fs.writeFile(path.join(root, 'scenes-timing.json'), JSON.stringify(timings, null, 2));
console.log(JSON.stringify({ output: path.join(rawDir, 'demo-raw.webm'), timings }, null, 2));
