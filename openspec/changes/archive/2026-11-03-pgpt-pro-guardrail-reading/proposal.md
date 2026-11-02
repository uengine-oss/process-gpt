## Why

가드레일의 결정은 규칙으로 잘 돌지만, 규칙에 넣을 값 가운데 뜻을 읽어야 하는 것까지 정규식으로 뽑고 있었다. 「권고사직 면담 메모」처럼 돌려 말한 글은 놓치고, 「서버 건강 점검」 같은 글은 잘못 잡는다. 판단 모델은 라우팅과 추천에만 쓰이고 보안 판단에는 쓰이지 않았다.

## What Changes

- 맥락의 민감 판별: 형식 정규식 → 모델(logprob) → 모델이 답하지 못하면 낱말.
- 외부 메일의 기밀 분류: 모델이 읽고, 답하지 못하면 표시 낱말.
- 판별 방법·확률·모델을 결정 원장에 남기고 주인 카드와 원장 화면에 보인다. 모델이 답하지 못하면 정책 화면에 경고.
- 사례 430건과 품질 하한 회귀 시험.

## Capabilities

### New
- `pgpt-pro_guardrail-reading`

### Modified
- `pgpt-pro_context-visibility`, `pgpt-pro_context-access-request`, `pgpt-pro_agentic-guardrails`
