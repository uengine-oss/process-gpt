## 1. 판단 전략

- [x] 1.1 판단 계약(상태·질문·선택지 → 선택·확률·전략·보정 여부·지연)과 `POST /decide` 를 제공한다. 검증 대상: `context-router_decision-strategies` "선택지 중 하나와 확률을 돌려주는 판단 API".
- [x] 1.2 판단 모델(judge) → logprob → JSON 체인을 설정 순서대로 구성하고, 앞 전략이 없거나 실패하면 다음으로 넘어가며 기록을 남긴다. 완료 기준: 단위 검증 `test_no_logprobs_falls_through_to_json`, `test_judge_used_first_when_configured` 통과.
- [x] 1.3 측정된 확신도가 기준 미만이면 다음 전략으로 에스컬레이션한다. 완료 기준: `test_doubtful_judge_escalates_to_logprob`, `test_confident_judge_is_final` 통과.
- [x] 1.4 logprob 가용성 자동 판별(거부·미반환·생각 모드 재시도·형식 기억). 완료 기준: `test_logprob_switches_thinking_off_and_remembers` 통과, frentis 실측에서 첫 호출 이후 재시도 없음.
- [x] 1.5 추론 모델 파라미터 차이(`max_completion_tokens`, 온도) 자동 보정. 완료 기준: o4-mini 로 JSON 전략 22문항 응답.
- [x] 1.6 참조 판단 서버(open-alternative-jev, Qwen3-4B-Instruct, MPS)를 같은 계약으로 제공한다.

## 2. 대화 맥락 라우팅

- [x] 2.1 사용자별 맥락 저장(`context_threads`)과 후보 수집(저장 맥락 + 클라이언트 맥락).
- [x] 2.2 `continue` / `new` / `stay` 판정과 확신 기준(자기 보고는 더 엄격). 완료 기준: `tests/test_route.py` 5건 통과.
- [x] 2.3 `POST /chat/stream` 라우팅 후 에이전트로 전달, 앞에 `metadata` 이벤트, 응답 후 요약 갱신.
- [x] 2.4 그 밖의 경로 투명 전달. 완료 기준: 라우터 `/health`, `/skills` 가 deepagents 응답 그대로 200.
- [x] 2.5 요청별 선택 라우팅(`metadata.auto_route`, 기본 끔)과 `route_text` 우선.

## 3. 검증과 증거

- [x] 3.1 22문항 측정(전략·모델별, 정책 체인 3종) → `specs/context-router_decision-strategies/e2e/results.json`, `report.html`.
- [x] 3.2 pgpt-pro 통합 채팅에서 메시지 4개 라우팅 → `specs/context-router_conversation-routing/e2e/pgpt-pro-routing.tsv`, `router-decisions.log`.
- [x] 3.3 시연 영상(나레이션) → `specs/context-router_conversation-routing/docs/context-router-demo.mp4`.
- [ ] 3.4 게이트웨이 `process-gpt-deepagents` 경로를 라우터로 돌리는 배포 설정과 process-gpt 프론트엔드 통합 채팅의 `auto_route` 사용.
- [x] 3.5 브라우저 에이전트의 빠른 상태 판단에 `POST /decide` 적용 — `context-router-scaling-browser-gates` 변경에서 완료(엔진 LLM 분기 판단 적용은 남음).
