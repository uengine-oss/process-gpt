"""HTML proof page for candidate narrowing (eval/scale.json) and, when given, the pgpt-pro
browser gate measurement (bench-browser-gates.mjs output).

Usage: python eval/report_scale.py out.html [gates.json]
"""
import html
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
scale = json.load(open(os.path.join(HERE, "scale.json"), encoding="utf-8"))
gates = json.load(open(sys.argv[2], encoding="utf-8")) if len(sys.argv) > 2 else []
MODES = [("recent8", "기존: 최근 8개"), ("all25", "전부 넣기: 25개"), ("route6", "좁히기: 6개 + 의미 + 재판단")]
NS = sorted({r["n"] for r in scale})
cell = {(r["mode"], r["n"]): r for r in scale}

series = [{"key": m, "label": lab, "acc": [round(cell[(m, n)]["accuracy"] * 100) for n in NS],
           "ms": [round(cell[(m, n)]["median_ms"]) for n in NS],
           "recall": [round(cell[(m, n)]["recall"] * 100) for n in NS],
           "chars": [round(cell[(m, n)]["prompt_chars"]) for n in NS]} for m, lab in MODES]

rows = "".join(
    f"<tr><td>{n}</td>" + "".join(f"<td>{s['acc'][i]}%</td><td>{s['ms'][i]:,}ms</td>" for s in series) + "</tr>"
    for i, n in enumerate(NS))

gate_rows = ""
TASKS = {"books-travel": "책 목록(Travel 3권 제목·가격)", "quotes-delayed": "늦게 뜨는 페이지(첫 명언)", "facebook-wall": "무인 실행 · 페이스북 로그인 벽"}
if gates:
    import statistics as st
    def agg(rs):
        return {"n": len(rs), "correct": sum(r["correct"] for r in rs), "turns": st.mean(r["turns"] for r in rs),
                "llm": st.mean(r["llm"] for r in rs), "gate": st.mean(r["gate_calls"] for r in rs),
                "early": sum(r["early_finish"] for r in rs), "sec": st.mean(r["ms"] for r in rs) / 1000}
    def row(name, rs, on):
        a = agg(rs)
        return (f"<tr><td>{name}</td><td>{'켬' if on else '끔'}</td><td>{a['correct']}/{a['n']}</td><td>{a['turns']:.1f}</td>"
                f"<td>{a['llm']:.1f}</td><td>{a['gate']:.1f}</td><td>{a['early']}</td><td>{a['sec']:.1f}s</td></tr>")
    for t, name in TASKS.items():
        for on in (False, True):
            gate_rows += row(name, [r for r in gates if r["task"] == t and r["gates"] == on], on)
    for on in (False, True):
        gate_rows += row("<b>전체</b>", [r for r in gates if r["gates"] == on], on)

page = """<!doctype html><html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>맥락 라우터 확장성</title>
<style>
:root{--surface-1:#fcfcfb;--surface-2:#f2f1ed;--text-primary:#1d1d1b;--text-secondary:#5c5b55;--text-muted:#8a897f;--grid:#e4e3dd;
--s1:#2a78d6;--s2:#eb6834;--s3:#1baf7a}
@media (prefers-color-scheme:dark){:root:not([data-theme=light]){--surface-1:#1a1a19;--surface-2:#242422;--text-primary:#f0efec;--text-secondary:#c3c2b7;--text-muted:#8f8e86;--grid:#33332f;--s1:#3987e5;--s2:#d95926;--s3:#199e70}}
:root[data-theme=dark]{--surface-1:#1a1a19;--surface-2:#242422;--text-primary:#f0efec;--text-secondary:#c3c2b7;--text-muted:#8f8e86;--grid:#33332f;--s1:#3987e5;--s2:#d95926;--s3:#199e70}
*{box-sizing:border-box}body{margin:0;background:var(--surface-1);color:var(--text-primary);font:16px/1.55 -apple-system,"Apple SD Gothic Neo","Pretendard",sans-serif}
main{max-width:1120px;margin:0 auto;padding:28px 16px 60px}h1{font-size:30px;margin:0 0 6px}h2{font-size:21px;margin:34px 0 10px}
.sub{color:var(--text-secondary);margin:0 0 18px}section{scroll-margin-top:20px}
.flow{display:flex;gap:10px;align-items:stretch;flex-wrap:wrap}.step{flex:1;min-width:150px;background:var(--surface-2);border-radius:12px;padding:12px 14px}
.step b{display:block;font-size:22px}.step span{color:var(--text-secondary);font-size:14px}.arrow{align-self:center;color:var(--text-muted);font-size:22px}
.grid2{display:grid;grid-template-columns:1fr 1fr;gap:18px}@media(max-width:760px){.grid2{grid-template-columns:1fr}}
.card{background:var(--surface-2);border-radius:12px;padding:14px 14px 8px}.card h3{margin:0 0 4px;font-size:16px}.card p{margin:0;color:var(--text-secondary);font-size:13px}
svg text{fill:var(--text-secondary);font-size:12px}.legend{display:flex;gap:16px;flex-wrap:wrap;margin:8px 0 0;font-size:14px;color:var(--text-secondary)}
.legend i{display:inline-block;width:14px;height:3px;border-radius:2px;margin-right:6px;vertical-align:middle}
table{border-collapse:collapse;width:100%;font-size:14px;margin-top:8px}th,td{padding:7px 8px;border-bottom:1px solid var(--grid);text-align:right}th:first-child,td:first-child{text-align:left}
th{color:var(--text-secondary);font-weight:600}.tip{position:fixed;pointer-events:none;background:var(--text-primary);color:var(--surface-1);padding:6px 9px;border-radius:8px;font-size:13px;display:none;z-index:9}
.note{color:var(--text-secondary);font-size:14px}.kpi{display:flex;gap:14px;flex-wrap:wrap}.kpi div{background:var(--surface-2);border-radius:12px;padding:12px 16px;min-width:170px}
.kpi b{display:block;font-size:28px}.kpi span{color:var(--text-secondary);font-size:13px}
</style></head><body><main>
<h1>대화가 수백 개로 쌓여도 맥락 라우터가 빠르고 정확하려면</h1>
<p class="sub">process-gpt context-router · 22문항(애매한 1문항 제외 21) × 무관한 대화 0·25·100·300개 · 판단 정책 judge(Qwen3-4B) → logprob(frentis) → JSON</p>

<section id="flow"><h2>1. 대화 이력은 넘기지 않는다 — 모델 없이 먼저 좁힌다</h2>
<div class="flow">
<div class="step"><b>최근 30일</b><span>30일 넘게 잠든 대화는 후보 아님</span></div><div class="arrow">→</div>
<div class="step"><b>최근 200 + 검색</b><span>더 오래된 것은 메시지 단어로 저장소 검색</span></div><div class="arrow">→</div>
<div class="step"><b>6개</b><span>진행 중 작업 · 최근 2개 · 단어 겹침 + 의미(bge-m3) 상위, 같은 제목은 한 자리</span></div><div class="arrow">→</div>
<div class="step"><b>판단 모델</b><span>설명은 나이별 압축: 하루 160자 · 일주일 100자 · 그 뒤 60자(요지)</span></div></div>
<p class="note">요약을 바꿀 때 이전 요청은 요지(gist, 120자)로 접혀 남는다. 판단 모델이 근거(겹치는 단어·의미 유사도) 없는 대화를 고르면 판단 모델을 건너뛰고 logprob 으로 다시 판단한다.</p></section>

<section id="result"><h2>2. 결과 — 대화가 늘어도 정확도와 지연이 유지된다</h2>
<div class="kpi" id="kpi"></div>
<div class="grid2" style="margin-top:14px">
<div class="card"><h3>정확도</h3><p>쌓인 무관한 대화 수별 · 높을수록 좋음</p><svg id="acc" viewBox="0 0 520 260" width="100%"></svg></div>
<div class="card"><h3>판단 지연(중앙값)</h3><p>쌓인 무관한 대화 수별 · 낮을수록 좋음</p><svg id="ms" viewBox="0 0 520 260" width="100%"></svg></div></div>
<div class="legend" id="legend"></div>
<table><thead><tr><th>무관한 대화</th>__HEAD__</tr></thead><tbody>__ROWS__</tbody></table>
<p class="note">남은 오답은 대부분 확신이 없어 대화를 옮기지 않은 경우(stay)다. 300개에서 "세금계산서"는 겹치는 단어가 없고 최근 200개 밖이라 찾지 못했다 — DB 벡터 검색(pgvector)이 후속 과제다.</p></section>
__GATES__
</main><div class="tip" id="tip"></div>
<script>
const NS=__NS__, S=__SERIES__, C=['var(--s1)','var(--s2)','var(--s3)'];
const tip=document.getElementById('tip');
function chart(id,key,fmt,max,ticks=4){const svg=document.getElementById(id),W=520,H=260,L=48,R=150,T=14,B=34;
 const x=i=>L+i*(W-L-R)/(NS.length-1), y=v=>T+(H-T-B)*(1-v/max);let g='';
 for(let k=0;k<=ticks;k++){const v=max*k/ticks;g+=`<line x1="${L}" x2="${W-R}" y1="${y(v)}" y2="${y(v)}" stroke="var(--grid)"/><text x="${L-8}" y="${y(v)+4}" text-anchor="end">${fmt(v)}</text>`}
 NS.forEach((n,i)=>g+=`<text x="${x(i)}" y="${H-12}" text-anchor="middle">${n}개</text>`);
 S.forEach((s,j)=>{const p=s[key].map((v,i)=>`${x(i)},${y(v)}`).join(' ');g+=`<polyline points="${p}" fill="none" stroke="${C[j]}" stroke-width="2" stroke-linejoin="round"/>`;
  s[key].forEach((v,i)=>g+=`<circle cx="${x(i)}" cy="${y(v)}" r="4.5" fill="${C[j]}" stroke="var(--surface-2)" stroke-width="2"/><circle cx="${x(i)}" cy="${y(v)}" r="14" fill="transparent" data-t="${s.label} · ${NS[i]}개: ${fmt(v)}"/>`);
});
 // end labels, nudged apart so close finishes stay readable
 const ends=S.map((s,j)=>({j,v:s[key][s[key].length-1],yy:y(s[key][s[key].length-1])})).sort((a,b)=>a.yy-b.yy);
 ends.forEach((e,i)=>{if(i&&e.yy-ends[i-1].yy<15)e.yy=ends[i-1].yy+15});
 ends.forEach(e=>g+=`<text x="${W-R+10}" y="${e.yy+4}" style="fill:var(--text-primary)">${fmt(e.v)} ${S[e.j].label.split(':')[0]}</text>`);
 svg.innerHTML=g;
 svg.querySelectorAll('[data-t]').forEach(c=>{c.onmousemove=e=>{tip.style.display='block';tip.textContent=c.dataset.t;tip.style.left=e.clientX+12+'px';tip.style.top=e.clientY+12+'px'};c.onmouseleave=()=>tip.style.display='none'})}
chart('acc','acc',v=>Math.round(v)+'%',100);
{const m=Math.ceil(Math.max(...S.flatMap(s=>s.ms))/500)*500;chart('ms','ms',v=>(v/1000).toFixed(1)+'s',m,m/500)}
document.getElementById('legend').innerHTML=S.map((s,j)=>`<span><i style="background:${C[j]}"></i>${s.label}</span>`).join('');
const last=NS.length-1, r=S[2], o=S[0], a=S[1];
document.getElementById('kpi').innerHTML=`<div><b>${r.acc[last]}%</b><span>${NS[last]}개에서 좁히기 정확도</span></div><div><b>${o.acc[last]}%</b><span>같은 조건 기존(최근 8개)</span></div><div><b>${(r.ms[last]/1000).toFixed(1)}s</b><span>좁히기 지연 · 전부 넣기는 ${(a.ms[last]/1000).toFixed(1)}s</span></div><div><b>${r.chars[last]}자</b><span>판단 모델이 읽는 후보 설명 · 전부 넣기 ${a.chars[last]}자</span></div>`;
</script></body></html>"""

head = "".join(f"<th>{html.escape(lab)} 정확도</th><th>지연</th>" for _, lab in MODES)
gate_html = ""
if gates:
    gate_html = ("<section id=\"gates\"><h2>3. 같은 판단을 브라우저 에이전트에 — 빠른 판단 게이트</h2>"
                 "<p class=\"note\">새 페이지마다 상태(로딩·로그인 벽·캡차·본문)를, 사실을 기록할 때마다 목표 달성 여부를 같은 POST /decide 로 판단한다. 확실할 때만 따른다.</p>"
                 "<table><thead><tr><th>과제 (3회 평균)</th><th>게이트</th><th>정답</th><th>턴</th><th>큰 모델 호출</th><th>게이트 판단</th><th>조기 종료</th><th>시간</th></tr></thead>"
                 f"<tbody>{gate_rows}</tbody></table>"
                 "<p class=\"note\">게이트를 켜면 턴이 평균 21%, 큰 모델 호출이 15% 줄고 정답 수는 같다(각 8/9). 늦게 뜨는 페이지의 한 회는 양쪽 모두 40턴 한도에 걸려 실패했고, 시간 평균은 이런 회차에 크게 흔들려 이번 측정으로는 결론을 내지 않는다.</p></section>")
out = (page.replace("__HEAD__", head).replace("__ROWS__", rows).replace("__GATES__", gate_html)
       .replace("__NS__", json.dumps(NS)).replace("__SERIES__", json.dumps(series, ensure_ascii=False)))
open(sys.argv[1], "w", encoding="utf-8").write(out)
print("wrote", sys.argv[1])
