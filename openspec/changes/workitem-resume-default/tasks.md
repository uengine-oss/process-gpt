## 1. SDK 재개 신호 (process-gpt-agent-sdk)

- [x] 1.1 재개 사유 판정 시나리오 테스트 작성: 신규·재점유(2회차)·답변 중 재점유·질문 답변·반려·`kind` 없는 과거 항목·문자열 feedback·깨진 feedback (RS-1.1, RS-2.1, RS-2.2, RS-3.1–RS-3.5) — `process-gpt-agent-sdk/tests/test_resume.py`
- [x] 1.2 재개 정보 값 객체·행 해석·실행 문맥 해석 구현, 공개 API로 내보내기 (RS-1, RS-4.2)
- [x] 1.3 워크아이템 실행 문맥의 `extras`·`metadata`에 `resume` 싣기, 기존 필드 유지 테스트 (RS-1.2, RS-4.1)
- [x] 1.4 표준 이어서 지시 문구와 테스트 (RS-5.1)

## 2. 화면 구분 표시 (process-gpt-vue3)

- [x] 2.1 질문 카드 답 패치에 `kind`=`human_answer` 기록 + 단위 테스트 (RS-6.1)
- [x] 2.2 결과 화면 피드백 전송 항목을 함수로 꺼내 `kind`=`revision` 기록 + 단위 테스트 (RS-6.2)

## 3. deepagents

- [x] 3.1 재점유 + 그래프 미완료 → 입력 `None`, interrupt 우선, 완료 그래프는 기존 입력 — 결정 함수 시나리오 테스트 (RE-1.1, RE-1.2, RE-3.1)
- [x] 3.2 실제 LangGraph(가짜 모델) 회귀 테스트: 도구 실행 중 중단 → 재점유 재개에서 완료 도구 재호출 0 (RE-1.1)
- [x] 3.3 executor 연결: 그래프 생성 뒤 `next` 확인해 입력 교체
- [x] 3.4 체크포인터: `DB_*` 설정 + 초기화 실패 → 기동 실패 / 실행 시 예외, 재시도 가능 / `DB_*` 없음 → InMemory (RE-4.1–RE-4.3)

## 4. cli-agent

- [x] 4.1 세션 ID 조기 저장·조회 테스트 (RE-1.4)
- [x] 4.2 재개 계획 결정 함수 시나리오 테스트: reclaim+세션 / reclaim+세션 없음 / human_answer / kind 없는 답+pending / fresh·revision 기존 동작 (RE-1.3, RE-1.5, RE-2.1, RE-2.2, RE-3.1)
- [x] 4.3 executor 연결: 실행 첫 세션 이벤트에서 저장, 결정 함수로 프롬프트·세션 선택, 사람 답변 결함 수정

## 5. codex

- [x] 5.1 reclaim이면 이어서 지시 + 원래 지시 참고, 그 외 기존 프롬프트 — 시나리오 테스트 (RE-1.6, RE-3.1)
- [x] 5.2 워크아이템 실행 경로 연결

## 6. 실측 재검증 (E1–E4 같은 조건)

- [x] 6.1 E1: 네 상황(신규·재점유·답변·반려)에서 실제 RPC가 돌려준 행으로 SDK 재개 사유 확인
- [x] 6.2 E2: deepagents 크래시 재점유, 서비스 결정 함수 경로로 완료 도구 재호출 0·LLM 추가 0 (3회)
- [x] 6.3 E3: cli-agent 크래시 재점유, 조기 저장된 세션으로 step1 재실행 0 (2회) + 사람 답변 경로 원문·세션 확인
- [x] 6.4 E4: codex 같은 파드 재점유, 서비스 프롬프트 함수로 step1 재실행 0 (2회)
- [x] 6.5 검증 결과 문서화(통과 못 한 항목은 이유 포함)

## 7. 클러스터 e2e (kind + 로컬 Supabase + 실제 브라우저) — `e2e/`

- [x] 7.1 kind 스택 매니페스트·이미지 빌드·시드·기동 스크립트 (`k8s/stack.yaml`, `build-images.sh`, `seed.py`, `up.sh`)
- [x] 7.2 화면 반려 → revision (RS-3.2, RS-6.2)
- [x] 7.3 deepagents 파드 사망 → 다른 파드가 체크포인트부터 (RE-1.1)
- [x] 7.4 cli-agent 파드 사망 → 새 파드가 실행 시작 직후 기록한 세션으로 (RE-1.3, RE-1.4)
- [x] 7.5 codex 같은 파드 재시작 → 같은 thread 로 이어서 지시 (RE-1.6)
- [x] 7.6 cli-agent 권한 거부 → 질문 카드 답변 → 같은 세션 + 답 원문 (RE-2.0, RE-2.1, RS-6.1)
- [x] 7.7 deepagents 체크포인터 저장소 불가 → 기동 실패 (RE-4.1)
- [x] 7.8 e2e 가 찾은 결함 수정 + 단위 회귀: SDK 종료 신호 시 lease 유지(RS-2.3), cli-agent 거부 인식·멈춤 규칙·`human_asked` 이벤트(RE-2.0)
- [x] 7.9 결과 기록 (`e2e/results.md`)
- [x] 7.10 업무 시나리오(구매 요청 처리, 3 태스크) 를 deepagents·cli-agent·codex 로 각각 — 대장 기록 직후 크래시, 대장 1줄·인스턴스 완료 (`e2e/purchase.spec.ts`)
- [x] 7.11 SDK: 종료 취소를 끝까지 전달해 종료 중인 워커가 다시 집지 않게 (RS-2.3, `ShutdownStopsPollingTest`)
