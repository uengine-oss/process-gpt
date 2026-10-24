# 판단 전략 검증 (e2e)

## 실행 환경
- Docker 인프라: Supabase(local, `desktop-linux` 컨텍스트)
- 소스 실행 서비스
  - context-router: `services/context-router`, `.venv/bin/python server.py` (포트 8895)
  - 참조 판단 서버: `HF_HUB_OFFLINE=1 JUDGE_MODEL=Qwen/Qwen3-4B-Instruct-2507 JUDGE_PERMUTATIONS=2 .venv-judge/bin/python judge_server.py` (포트 8896, Apple MPS)
  - 판단 LLM: 사내 frentis(SGLang, Qwen3.6 35B, OpenAI 호환) / OpenAI `gpt-4o-mini`·`gpt-4.1-nano`·`o4-mini`
- 환경 변수: `DECIDE_STRATEGIES=judge,logprob,json`, `DECIDE_JUDGE_URL`, `DECIDE_LLM_*`, `DECIDE_ESCALATE_BELOW=0.9`

## 실행
```bash
cd services/context-router
.venv/bin/python -m pytest -v                 # 단위 검증 → unit-tests.log
JUDGE_URL=http://localhost:8896/judge FRENTIS_URL=... FRENTIS_KEY=... OPENAI_KEY=... \
  .venv/bin/python eval/bench.py              # 측정 → results.json
.venv/bin/python eval/report.py report.html   # 보고서
```

## 문항
`cases.json`: 맥락 5개(유튜브 채널, 부산 출장, 진행 중 팟캐스트 작업, SNS 대응 프로세스, 부가세 납부) + 새 주제, 메시지 22개(모호 1개는 정확도에서 제외).

## 결과 요약 (2026-10-23)
| 구성 | 정확도 | p50 | 판단 주체 |
|---|---|---|---|
| 정책 judge→logprob(frentis)→json, 에스컬레이션 0.9 | 95% | 538ms | judge 16 · logprob 6(에스컬레이션) |
| 정책 judge DOWN→logprob(frentis)→json | 100% | 128ms | logprob 22 |
| 정책 judge DOWN→logprob(o4-mini, 미지원)→json(o4-mini) | 95% | 2840ms | json 22 |
| judge 단독 · so1 Qwen3-4B-Instruct(로컬) | 76% | 522ms | judge 22 |
| logprob · frentis | 100% | 150ms | logprob 22 |
| json · frentis | 95% | 230ms | json 22 |
| logprob · gpt-4o-mini | 95% | 745ms | logprob 22 |
| json · gpt-4o-mini | 90% | 855ms | json 22 |
| logprob · gpt-4.1-nano | 48% | 613ms | logprob 22 |

- 전략 패턴 증명: 같은 코드 경로에서 판단 모델이 있으면 판단 모델이 먼저 판단하고(16건 확정), 확신이 낮은 6건만 logprob 으로 올라갔다. 판단 모델이 내려가면 logprob, logprob 을 거부하는 모델이면 JSON 으로 자동 전환됐다.
- 판단 모델 단독(4B)은 "새 주제"를 고르지 못하는 약점이 있으나, 측정된 확신도가 오답에서 낮아(정답 0.97 / 오답 0.67) 에스컬레이션으로 보완된다.
- 상세: `results.json`, `report.html`.
