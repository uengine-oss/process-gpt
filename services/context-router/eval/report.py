"""Render eval/results.json as a one-page HTML report (the proof shown in the demo video)."""
import html
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
res = json.load(open(os.path.join(HERE, "results.json"), encoding="utf-8"))
out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "report.html")

def row(r, policy=False):
    s = r["summary"]
    by = " · ".join(f"{k} {v}" for k, v in s["decided_by"].items() if k)
    acc = f'{s["accuracy"]*100:.0f}%'
    cls = "pol" if policy else ""
    return (f'<tr class="{cls}"><td>{html.escape(s["label"])}</td><td class="n">{acc}</td><td class="n">{s["p50_ms"]}ms</td>'
            f'<td class="n">{s["conf_right"] if s["conf_right"] is not None else "-"} / {s["conf_wrong"] if s["conf_wrong"] is not None else "-"}</td>'
            f'<td>{html.escape(by)}{" · escalated "+str(s["escalated"]) if s.get("escalated") else ""}</td></tr>')

single = [r for r in res if not r["summary"]["label"].startswith("policy")]
policy = [r for r in res if r["summary"]["label"].startswith("policy")]
doc = f"""<!doctype html><html lang="ko"><head><meta charset="utf-8"><title>판단 전략 검증</title>
<style>
body{{margin:0;background:#0f172a;color:#e2e8f0;font:17px/1.5 "Pretendard Variable",Pretendard,-apple-system,"Apple SD Gothic Neo",sans-serif}}
main{{max-width:1180px;margin:0 auto;padding:36px 40px}}
h1{{font-size:30px;margin:0 0 6px}} .sub{{color:#94a3b8;margin:0 0 22px}}
.chain{{display:flex;gap:10px;align-items:center;margin:0 0 26px;flex-wrap:wrap}}
.box{{background:#1e293b;border:1px solid #334155;border-radius:14px;padding:12px 16px}} .box b{{display:block;font-size:17px}} .box small{{color:#94a3b8}}
.box.first{{border-color:#38bdf8;box-shadow:0 0 0 2px #38bdf855}} .arrow{{color:#64748b;font-size:22px}}
table{{width:100%;border-collapse:collapse;margin:8px 0 26px;font-size:15.5px}} th,td{{padding:9px 10px;border-bottom:1px solid #1e293b;text-align:left}}
th{{color:#94a3b8;font-weight:500}} td.n{{font-family:ui-monospace,Menlo,monospace;white-space:nowrap}} tr.pol td:first-child{{color:#7dd3fc}}
h2{{font-size:19px;margin:10px 0 4px}}
</style></head><body><main>
<h1>판단 전략 — 전략 패턴 검증</h1>
<p class="sub">대화 맥락 라우팅 22문항 (5개 맥락 + 새 주제, 모호 1건) · 같은 코드 경로(decide.Decider)로 측정</p>
<div class="chain">
 <div class="box first"><b>① 판단 모델 (judge)</b><small>설정돼 있으면 최우선 · so1 Qwen3-4B</small></div><span class="arrow">→</span>
 <div class="box"><b>② logprob</b><small>LLM 이 logprobs 를 주면 · 한 글자 확률</small></div><span class="arrow">→</span>
 <div class="box"><b>③ JSON</b><small>어디서나 · 확신도는 자기 보고</small></div>
 <div class="box"><b>확신도 &lt; 0.9 이면 다음 전략으로 에스컬레이션</b><small>DECIDE_ESCALATE_BELOW</small></div>
</div>
<h2>정책(전략 체인) — 누가 판단했나</h2>
<table><tr><th>구성</th><th>정확도</th><th>p50</th><th>확신도 정답/오답</th><th>판단 주체</th></tr>{''.join(row(r, True) for r in policy)}</table>
<h2>단일 전략 비교</h2>
<table><tr><th>전략 · 모델</th><th>정확도</th><th>p50</th><th>확신도 정답/오답</th><th>판단 주체</th></tr>{''.join(row(r) for r in single)}</table>
</main></body></html>"""
open(out, "w", encoding="utf-8").write(doc)
print(out)
