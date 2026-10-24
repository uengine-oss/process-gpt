## 1. 후보 좁히기와 압축 (context-router)

- [x] 1.1 저장소: 잠든 맥락 제외(`ROUTER_DORMANT_DAYS`), 최근 `ROUTER_SCAN` 개 + 내용어 검색(`store.search`). 완료 기준: 300개 규모에서 20일 전 "부가세 납부" 가 후보에 든다(`eval/scale.py`, 실제 PostgREST 로 "해운대" 검색 확인).
- [x] 1.2 좁히기(`router/select.py`): 진행 중 작업·최근 2개 고정, 단어 겹침 + 의미 유사도 + 최근성, 같은 제목 한 자리. 완료 기준: `tests/test_select.py` 통과.
- [x] 1.3 나이별 설명 압축(160/100/60자)과 요지 누적(`gist_of`, `sql/002_context_gist.sql` 적용). 완료 기준: `test_hint_shrinks_with_age`, `test_gist_folds_the_replaced_request_into_keywords` 통과.
- [x] 1.4 근거 없는 판단 모델 선택의 재판단(`Decider.decide(skip=)`). 완료 기준: 120개 맥락에서 "숙소" 메시지가 재판단으로 출장 대화에 이어짐(`notes` 확인).
- [x] 1.5 참조 판단 서버의 `/embeddings`(bge-m3)와 라우터 임베딩 클라이언트(`router/embed.py`, 캐시, 실패 시 단어 겹침만).

## 2. 브라우저 에이전트 판단 게이트 (pgpt-pro)

- [x] 2.1 `server/lib/decide.js`: 라우터 `/decide` 클라이언트, 측정된 확신도만 신뢰(`sure`).
- [x] 2.2 페이지 상태 게이트(로딩 대기, 무인 실행의 로그인 벽·캡차 안내), 목표 달성 게이트(조기 종료, `finish` 강제), 보관함 값 가림.
- [x] 2.3 측정 기록(`result.stats`)과 `scripts/bench-browser-gates.mjs`.

## 3. 검증과 증거

- [x] 3.1 단위 검증 18건 → `specs/context-router_conversation-routing/e2e/unit-tests.log`
- [x] 3.2 규모 측정(0·25·100·300 × 4방식) → `e2e/scale.json`, `scale.log`, `scale-report.html`
- [x] 3.3 실제 화면(pgpt-pro, 맥락 120개, 메시지 3개) → `e2e/README.md`
- [x] 3.4 브라우저 게이트 3과제 × 3회 → `specs/pgpt-pro_browser-decision-gates/e2e/`
- [x] 3.5 시연 영상(나레이션) → `specs/context-router_conversation-routing/docs/context-router-scaling-demo.mp4`
- [ ] 3.6 `context_threads` 임베딩 열(pgvector)과 저장소 유사도 검색
- [ ] 3.7 브라우저 게이트 시간 효과의 반복 측정(실패 회차 분리)
