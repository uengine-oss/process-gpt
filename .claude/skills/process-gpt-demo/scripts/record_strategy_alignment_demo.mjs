#!/usr/bin/env node
import { chromium } from '../../../../services/frontend/node_modules/playwright/index.mjs';
import fs from 'node:fs/promises';
import path from 'node:path';

const root = path.resolve(process.argv[2] || 'demo-recordings/strategy-alignment-check');
const rawDir = path.join(root, 'raw');
await fs.mkdir(rawDir, { recursive: true });

const endpoint = 'http://127.0.0.1:8014/api/ai/alignment?tenant_id=localhost';
async function lookup(description) {
  const response = await fetch(endpoint, {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ description }),
  });
  if (!response.ok) throw new Error(`alignment API ${response.status}`);
  return response.json();
}

const matchedText = '교육 웨비나 고객 문의를 자동 분류하고 후속 상담 담당자에게 배정해 응답 리드타임을 줄이는 프로세스';
const emptyText = '사내 주차장 조명 교체 일정 관리';
const matched = await lookup(matchedText);
const empty = await lookup(emptyText);

const browser = await chromium.launch({ headless: true });
const context = await browser.newContext({
  viewport: { width: 1920, height: 1080 },
  recordVideo: { dir: rawDir, size: { width: 1920, height: 1080 } },
});
const page = await context.newPage();
const started = Date.now();
const timings = [];
const mark = scene => timings.push({ scene, start_sec: Number(((Date.now() - started) / 1000).toFixed(2)) });

await page.setContent(`<!doctype html><html lang="ko"><head><meta charset="utf-8"><style>
*{box-sizing:border-box} body{margin:0;background:#07111f;color:#eaf2ff;font-family:-apple-system,BlinkMacSystemFont,"Pretendard",sans-serif;overflow:hidden}
.shell{height:1080px;padding:64px 88px;background:radial-gradient(circle at 85% 5%,#173f6b 0,transparent 34%),linear-gradient(135deg,#07111f,#0d1c31)}
.brand{display:flex;align-items:center;gap:16px;color:#8fbfff;font-weight:750;letter-spacing:.08em;font-size:23px}.dot{width:16px;height:16px;border-radius:50%;background:#4f9cff;box-shadow:0 0 24px #4f9cff}
h1{font-size:58px;line-height:1.13;margin:34px 0 14px;letter-spacing:-.045em}.lead{font-size:25px;color:#9fb3ca;line-height:1.55;margin:0 0 36px}
.stage{display:none}.stage.active{display:block;animation:up .65s ease both}@keyframes up{from{opacity:0;transform:translateY(22px)}to{opacity:1;transform:none}}
.grid{display:grid;grid-template-columns:1.05fr .95fr;gap:26px}.card{background:rgba(17,34,57,.92);border:1px solid #294563;border-radius:24px;padding:30px;box-shadow:0 22px 70px #0005}
.label{font-size:17px;color:#70aefb;font-weight:800;text-transform:uppercase;letter-spacing:.09em}.query{font-size:28px;line-height:1.5;margin-top:19px;color:#fff}
.api{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;color:#7ee3b3;font-size:18px}.status{display:inline-flex;padding:10px 17px;border-radius:999px;font-size:18px;font-weight:850;background:#153c32;color:#7ee3b3}.status.none{background:#40331a;color:#ffd27a}
.candidate{display:flex;gap:18px;padding:21px 0;border-bottom:1px solid #263e58}.candidate:last-child{border:0}.rank{width:42px;height:42px;border-radius:13px;background:#214b7a;display:grid;place-items:center;font-weight:900}.cname{font-size:23px;font-weight:800}.meta{color:#93aac1;margin-top:7px;font-size:17px}.reason{color:#d6e3ef;margin-top:10px;font-size:17px}.score{margin-left:auto;color:#75b3ff;font-weight:850;font-size:20px}
.flow{display:flex;align-items:center;gap:14px;margin-top:30px}.node{padding:18px 22px;border-radius:18px;background:#172d49;border:1px solid #315276;font-size:20px;font-weight:750}.arrow{font-size:30px;color:#5fa4f6}.human{border-color:#4f9cff;background:#133963}.record{border-color:#5dcf9b;background:#12392f}.big-none{height:390px;display:grid;place-items:center;text-align:center}.big-none .icon{font-size:75px}.big-none strong{font-size:34px}.big-none p{font-size:21px;color:#9fb3ca;line-height:1.5}
.footer{position:absolute;left:88px;right:88px;bottom:42px;display:flex;justify-content:space-between;color:#6f879f;font-size:16px}.pill{padding:8px 13px;border-radius:10px;background:#142942;color:#9bc5f7}
</style></head><body><main class="shell"><div class="brand"><span class="dot"></span> PROCESS GPT · STRATEGY ALIGNMENT</div>
<section id="s1" class="stage"><h1>프로세스를 확정하기 전에<br>전략과 먼저 맞춰봅니다</h1><p class="lead">자유 텍스트 설명을 조직의 전략목표·KPI와 비교하고,<br>관련 근거를 승인자와 사용자에게 투명하게 제시합니다.</p><div class="flow"><div class="node">프로세스 초안</div><div class="arrow">→</div><div class="node">정합성 조회</div><div class="arrow">→</div><div class="node human">사용자 선택</div><div class="arrow">→</div><div class="node record">근거 기록</div></div></section>
<section id="s2" class="stage"><h1>실제 전략 데이터로 후보 조회</h1><div class="grid"><div class="card"><div class="label">Process draft</div><div class="query">${matchedText}</div><p class="api">POST /api/ai/alignment · tenant=localhost</p></div><div class="card"><div class="label">Current strategy map</div><div class="candidate"><div class="rank">K</div><div><div class="cname">후속 상담 응답 리드타임</div><div class="meta">KPI · 고객 응답 속도</div></div></div><div class="candidate"><div class="rank">S</div><div><div class="cname">교육·컨설팅 기반 리드 전환</div><div class="meta">Strategy · 고객 관점</div></div></div></div></div></section>
<section id="s3" class="stage"><h1>관련도 순 후보와 근거</h1><div class="card"><div style="display:flex;justify-content:space-between;align-items:center"><span class="status">${matched.status}</span><span class="pill">generated_by · ${matched.generated_by}</span></div><div id="candidates"></div></div></section>
<section id="s4" class="stage"><h1>관련 항목이 없어도 오류가 아닙니다</h1><div class="grid"><div class="card"><div class="label">Unrelated draft</div><div class="query">${emptyText}</div><p class="api">POST /api/ai/alignment · tenant=localhost</p></div><div class="card big-none"><div><div class="icon">◎</div><strong>${empty.status}</strong><p>후보 목록은 비어 있습니다.<br>사용자에게 알리고 계속 진행할지 확인합니다.</p></div></div></div></section>
<section id="s5" class="stage"><h1>확인은 필수, 결정은 사람에게</h1><p class="lead">후보가 있어도 자동 연결하지 않습니다. 선택한 KPI만 연결하고,<br>없음·미연결·확인 불가 결과까지 프로세스 정의와 개선 제안에 남깁니다.</p><div class="flow"><div class="node">후보 제시</div><div class="arrow">→</div><div class="node human">KPI 선택 또는 미연결</div><div class="arrow">→</div><div class="node record">strategyAlignment</div></div><div class="card" style="margin-top:34px"><div class="label">Approval evidence</div><div class="query">SKILL · PROCESS_DEFINITION에는 근거 기록<br><span style="color:#9fb3ca">DMN_RULE은 범위에서 제외 · 서비스 실패 시에도 제안 흐름 유지</span></div></div></section>
<div class="footer"><span>strategy-alignment-check demo</span><span>live API response · ${new Date().toISOString().slice(0,10)}</span></div></main>
<script>const rows=${JSON.stringify(matched.candidates.slice(0,3))};document.querySelector('#candidates').innerHTML=rows.map((c,i)=>\`<div class="candidate"><div class="rank">\${i+1}</div><div><div class="cname">\${c.name}</div><div class="meta">\${c.type.toUpperCase()} · id \${c.id.slice(0,8)}…</div><div class="reason">\${c.reason}</div></div><div class="score">\${c.score}</div></div>\`).join('');</script>
</body></html>`);

for (const [scene, wait] of [[1,13000],[2,14000],[3,18000],[4,14000],[5,15000]]) {
  mark(scene);
  await page.evaluate(n => {
    document.querySelectorAll('.stage').forEach(el => el.classList.remove('active'));
    document.querySelector(`#s${n}`).classList.add('active');
  }, scene);
  await page.screenshot({ path: path.join(root, `scene-${String(scene).padStart(2,'0')}.png`) });
  await page.waitForTimeout(wait);
}

const video = page.video();
await context.close();
await browser.close();
const recorded = await video.path();
await fs.rename(recorded, path.join(rawDir, 'demo-raw.webm'));
await fs.writeFile(path.join(root, 'scenes-timing.json'), JSON.stringify(timings, null, 2));
await fs.writeFile(path.join(root, 'api-results.json'), JSON.stringify({ matchedText, matched, emptyText, empty }, null, 2));
console.log(JSON.stringify({ output: path.join(rawDir, 'demo-raw.webm'), timings, matched: matched.candidates.length, empty: empty.status }, null, 2));
