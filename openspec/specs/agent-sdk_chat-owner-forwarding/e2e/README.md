# 에이전트 SDK 채팅 넘겨주기 — 시험

## 실행

```bash
# process-gpt-agent-sdk 작업 트리(feat/chat-owner-forwarding)
docker run -d --rm -p 127.0.0.1:6391:6379 redis:7-alpine
SUPABASE_URL=http://127.0.0.1:9 SUPABASE_KEY=dummy \
CHAT_OWNER_TEST_REDIS_URL=redis://127.0.0.1:6391/0 \
python -m pytest tests/test_chat_owner.py tests/test_chat_owner_processes.py
```

- `test_chat_owner.py`(단위 18): 기록소(잡기 · 갱신 · 만료 · 그 값일 때만 지우기), 턴 보유 수, 미들웨어(새 턴 · 넘기기 · 넘겨받은 요청 · 주인 닿지 않음 · 4xx 예약 해제 · Redis 장애 · 꺼짐), 환경변수.
- `test_chat_owner_processes.py`(6): 서버 프로세스 둘(`tests/owner_forward_app.py`)이 Redis 하나를 같이 쓴다. **넘겨주기를 끄고 돌리면 TestTwoPods 다섯 개가 모두 실패한다** — 시험이 넘겨주기를 실제로 본다는 확인.

VM(실제 딥에이전트 두 대):

```bash
# 튜토리얼 VM(colima pgtut)에 시험용 컨테이너를 따로 띄운다 — 원래 deepagents 는 건드리지 않는다
#   process-gpt-deepagents:owner-test = tutorial-1111 + SDK 0.12.0 휠, 폴링 끔, CHAT_OWNER_FORWARDING=redis
#   deepagents-a(:18881) · deepagents-b(:18882) · owner-redis · owner-nginx(:18088, 두 대를 번갈아)
python3 e2e_deepagents.py                      # HTTP: A 에서 시작 → B 로 재접속 · 수정 지시 · 중지 · 새 질문
NODE_PATH=…/node_modules node ui_owner.mjs     # 포털 화면: 새로고침 세 번 · 답변 중 입력 · 중지
```

스크립트와 Dockerfile 은 `/Users/uengine/pgfix/owner-vmtest/`(로컬)에 있다.

## 스펙 시나리오 ↔ 시험

| 시나리오 | 시험 | 결과(2026-11-11) |
|---|---|---|
| OWN-01 다른 파드로 다시 붙기 | `test_A_의_턴에_B_로_다시_붙으면_A_의_본문을_받는다` · VM 2 | ✅ (VM: 스냅샷 463자 + 실시간) |
| OWN-02 다른 파드로 방향 바꾸기 | `test_B_로_온_방향_바꾸기가_A_의_턴에_반영된다` · VM 3 | ✅ (VM: accepted → steer_applied 0.3초) |
| OWN-03 다른 파드로 중지 | `test_B_로_온_중지가_A_의_턴을_멈춘다` · VM 4 | ✅ |
| OWN-04 다른 파드로 새 질문 | `test_B_로_온_같은_방의_새_질문은_A_가_처리한다` · VM 5 | ✅ |
| OWN-05 끝나면 기록 삭제 | `test_턴이_끝나면_주인_기록이_사라진다` · VM 4 뒤 | ✅ |
| OWN-06 앞 턴 · 새 턴 겹침 | `test_앞_턴이_새_턴보다_먼저_끝나도_기록은_남는다` | ✅ |
| OWN-07 주인이 죽으면 | `test_주인이_죽으면_B_가_직접_처리한다` · 단위 `주인에게_닿지_않으면…` | ✅ |
| OWN-08 넘겨받은 요청 | `test_넘겨받은_요청은_다시_넘기지_않는다` | ✅ |
| (Redis 장애 · 4xx 예약 해제 · 꺼짐) | 단위 | ✅ |
| OWN-VM-01 | `e2e_deepagents.py` → `results/vm-two-pods-e2e.txt` | ✅ B 로그 넘김 4경로 |
| OWN-VM-02 | `ui_owner.mjs` → `results/vm-ui-two-pods.txt` · `results/*.png` | ✅ 새로고침 3번 모두 SSE, 그중 1번 B→A 넘김 |

## 증거

`results/` 는 저장소에 올리지 않는다(.gitignore). 2026-11-11 실행:
- `sdk-tests.txt` — 24 통과(SDK 전체 235 통과)
- `vm-two-pods-e2e.txt` — 실제 딥에이전트 · 실제 LLM
- `vm-ui-two-pods.txt` · `1-streaming.png` ~ `4-stopped.png`

## 아직 확인하지 않은 것

- 운영 클러스터(파드 5개) — 운영 반영 뒤 같은 HTTP 시험을 시험 계정으로 돌린다.
- 포털 화면의 중지 단추를 다른 파드로 보낸 경우(화면 시험에서는 수정 지시 뒤 답변이 끝나 단추가 사라졌다). HTTP 시험(OWN-03)은 통과.
