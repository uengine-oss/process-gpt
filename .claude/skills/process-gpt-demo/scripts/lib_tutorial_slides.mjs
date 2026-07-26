// 공용 튜토리얼 슬라이드 헬퍼 — 튜토리얼 영상 시리즈(Lv.1~5)가 공유하는 슬라이드 렌더러.
// record_prompt_chaining_demo.mjs 의 slide() 를 일반화한 것.
//
// 사용법:
//   import { makeSlides } from './lib_tutorial_slides.mjs';
//   const slide = makeSlides(page, { level: 1, brand: 'PROCESS GPT · TUTORIAL Lv.1', foot: 'tutorial-lv1 · 1/5' });
//   await slide({ title: '제목\n둘째줄', body: '본문 …', flow: ['A','B','C'] });
//   await slide({ title: '요약', body: '…', cards: [{ h:'제목', p:'설명' }, ...] });
//
// flow: 문자열 배열 → 화살표로 연결된 노드 행으로 렌더.
// cards: {h,p} 배열 → 2열 카드 그리드로 렌더 (flow 대신).
// makeSlides 는 page.setContent 를 호출하는 async 함수를 돌려준다.

export function makeSlides(page, opts = {}) {
  const brand = opts.brand || `PROCESS GPT · TUTORIAL Lv.${opts.level ?? 1}`;
  const foot = opts.foot || `tutorial-lv${opts.level ?? 1}`;
  const footRight = opts.footRight || 'Process GPT + deepagents';

  const nodesHtml = (flow = []) =>
    flow
      .map((n, i) =>
        (i ? '<div class="arrow">→</div>' : '') + `<div class="node">${n}</div>`
      )
      .join('');

  const cardsHtml = (cards = []) =>
    cards.map((c) => `<div class="card"><b>${c.h}</b><p>${c.p}</p></div>`).join('');

  return async function slide({ title = '', body = '', flow = null, cards = null } = {}) {
    const flowBlock = cards
      ? `<div class="cards">${cardsHtml(cards)}</div>`
      : flow
      ? `<div class="flow">${nodesHtml(flow)}</div>`
      : '';
    await page.setContent(`<!doctype html><html lang="ko"><head><meta charset="utf-8"><style>
    *{box-sizing:border-box}body{margin:0;background:#07111f;color:#eef5ff;font-family:-apple-system,BlinkMacSystemFont,"Pretendard",sans-serif}
    .shell{position:relative;height:1080px;padding:70px 90px;background:radial-gradient(circle at 88% 3%,#1b497a 0,transparent 35%),linear-gradient(135deg,#07111f,#0d1c31)}
    .brand{color:#8fbfff;font-weight:800;letter-spacing:.08em;font-size:22px}
    .brand:before{content:'●';color:#4f9cff;margin-right:14px;text-shadow:0 0 20px #4f9cff}
    h1{font-size:56px;line-height:1.18;margin:40px 0 22px;letter-spacing:-.04em;white-space:pre-line}
    .body{font-size:23px;line-height:1.6;color:#aebfd2;white-space:pre-line;max-width:1500px}
    .flow{display:flex;gap:14px;align-items:center;margin-top:44px;flex-wrap:wrap}
    .node{padding:16px 22px;border:1px solid #3d6791;background:#142c49;border-radius:16px;font-size:19px;font-weight:750}
    .arrow{font-size:28px;color:#66aaf7}
    .foot{position:absolute;left:90px;right:90px;bottom:42px;display:flex;justify-content:space-between;color:#71879c;font-size:16px}
    .cards{display:grid;grid-template-columns:1fr 1fr;gap:20px;margin-top:40px;max-width:1500px}
    .card{background:rgba(17,34,57,.9);border:1px solid #294563;border-radius:18px;padding:22px 26px}
    .card b{color:#8fbfff;font-size:19px}.card p{margin:10px 0 0;font-size:17px;color:#c3d2e4;line-height:1.5}
    </style></head><body><main class="shell"><div class="brand">${brand}</div><h1>${title}</h1><div class="body">${body}</div>${flowBlock}<div class="foot"><span>${foot}</span><span>${footRight}</span></div></main></body></html>`);
  };
}
