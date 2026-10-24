# 브라우저 에이전트 판단 게이트 검증

## 실행 환경
- pgpt-pro 서버 코드(`server/lib/browser.js`, `server/lib/decide.js`), 큰 모델: frentis(`PRO_LLM_MODEL=frentis-ai-model`)
- 판단: context-router `POST /decide`(8895) → judge(Qwen3-4B-Instruct, 8896) → logprob(frentis) → JSON
- 측정 스크립트: `pgpt-pro/server/scripts/bench-browser-gates.mjs` — 같은 과제를 게이트 끔/켬으로 번갈아 실행, 매번 브라우저 세션을 새로 연다

## 과제
| 과제 | 시작 | 정답 판정 |
|---|---|---|
| 책 목록 | books.toscrape.com, Travel 처음 세 권의 제목·가격 | 세 제목과 세 가격이 모두 결과에 있음 |
| 늦게 뜨는 페이지 | quotes.toscrape.com/js-delayed, 첫 명언과 저자 | Einstein |
| 무인 실행 · 로그인 벽 | 페이스북 그룹(로그인 없음), 실패하면 데모 피드 | RMF |

## 결과 (3회)
| 과제 | 게이트 | 정답 | 턴 | 큰 모델 호출 | 게이트 판단 | 조기 종료 |
|---|---|---|---|---|---|---|
| 책 목록 | 끔 | 3/3 | 11.3 | 12.3 | 0 | 0 |
| 책 목록 | 켬 | 3/3 | 8.0 | 9.7 | 7.0 | 2 |
| 늦게 뜨는 페이지 | 끔 | 2/3 | 24.7 | 25.7 | 0 | 0 |
| 늦게 뜨는 페이지 | 켬 | 2/3 | 20.7 | 22.3 | 3.7 | 2 |
| 로그인 벽(무인) | 끔 | 3/3 | 6.0 | 7.0 | 0 | 0 |
| 로그인 벽(무인) | 켬 | 3/3 | 4.3 | 6.0 | 3.0 | 2 |
| **전체** | 끔 | 8/9 | 14.0 | 15.0 | 0 | 0 |
| **전체** | 켬 | 8/9 | 11.0 | 12.7 | 4.6 | 6 |

- 턴 21%, 큰 모델 호출 15% 감소, 정답 수 동일.
- 늦게 뜨는 페이지에서는 로딩 판단으로 두 번 기다린 뒤 읽었다(`waits`). 로그인 벽에서는 무인 실행 안내(`hints`)가 붙었다.
- 늦게 뜨는 페이지의 한 회는 양쪽 모두 40턴 한도에 걸려 실패했다. 시간 평균(끔 32.3초 / 켬 28.5초)은 이런 회차에 크게 흔들리므로 이번 측정으로는 시간에 대한 결론을 내지 않는다.
- 증거: `bench-results.json`(회차별 수치와 게이트 판단 목록), `bench-runs.log`
- 시연 영상(마지막 장면): `../../context-router_conversation-routing/docs/context-router-scaling-demo.mp4`
