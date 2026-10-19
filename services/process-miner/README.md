# process-miner

핸드오버 로그(`public.handover_events`)에서 프로세스를 도출해 **PR 로 제안**하는 서비스.

살아 있는 `proc_def` 는 절대 건드리지 않는다. `proc_def_version` 에 draft 를 넣고
`resource_pull_requests` 에 `resource_type='bpmn'` PR 을 열어 사람이 승인하게 한다.

## 상관키

케이스는 `origin_room_id` 로 묶는다 — "이 업무가 최초로 시작된 채팅방". 인계할 때마다
수신자 방의 `context.handover.origin_room_id` 로 전파되므로, 이메일이 References 로
루트 Message-ID 를 끌고 가는 것과 같은 방식으로 여러 방에 걸친 인계가 한 스레드로 모인다.

## 파이프라인

```
handover_events → eventlog(케이스별 활동 시퀀스)
                → dfg(직후관계 + 노이즈 필터)
                → inductive(컷 재귀 탐지 → 프로세스 트리)
                → to_procdef(ProcessGPT flattened proc_def JSON)
                → proposal(draft version + PR)
```

LLM 을 쓰지 않는다. 트리에서 변환하므로 교착·도달 불가 노드가 구조적으로 생길 수 없다.
pm4py 대신 직접 구현한 이유는 pm4py 가 GPLv3 라 상용 배포에 라이선스 검토가 필요하기 때문.

모든 케이스에 등장하지 않는 구간은 `xor(구간, τ)` 로 감싸 **선택적 단계**로 표현한다.
(이 처리가 없으면 8건 중 3건에만 있던 단계가 필수 단계로 굳어져 로그와 안 맞는 모델이 된다.)
선택 여부는 표준 IM 처럼 **컷마다 나눈 하위 로그**로 센다. 배타 분기의 한 갈래에서 늘 하는 단계는 필수로 남는다.

- 반복: 시작·종료 활동을 본체로 두는 표준 반복 컷. 반려 후 재검토(검토 → 수정 → 검토)가 `loop(검토, 수정)` 으로 나온다.
- 컷을 못 찾으면 순서 없는 반복 `⟲(τ, a, b, …)` 으로 둔다. 로그에 없는 "하나만 한다" 를 만들지 않는다.

## 이벤트 로그 규칙

- 스레드의 첫 인계(`chat_handover`/`todolist`)에서 넘긴 사람이 적은 '지금까지 한 일'(`activity_label`)이
  첫 단계가 된다. 두 사람 사이의 단순 인계도 단계 2개짜리 케이스로 분석된다.
- 활동명이 없는 에이전트 위임(`agent_delegation`)은 제어 흐름에 넣지 않는다(대화 원문 차단).
  대신 위임한 사람이 그때 맡고 있던 활동에 귀속해 인계 네트워크·자동화율·활동별 자격에 넣는다.
- 인계 네트워크는 행에 적힌 `from → to` 로 센다. 위임을 마치고 돌려주면(`returned_at`) 에이전트 → 위임한 사람도 센다.

## 실행

```bash
python3 -m venv .venv && ./.venv/bin/pip install -r requirements-dev.txt
export DB_PASSWORD=...            # .env.example 참고
export SUPABASE_URL=http://127.0.0.1:54321 SUPABASE_KEY=<anon key>   # 요청자 JWT 검증

./.venv/bin/python main.py                                 # API 서버 :8015 (strategy 가 :8014)

./.venv/bin/python -m pytest tests -q                     # 단위 테스트(결정론적, DB 불필요)
./.venv/bin/python scripts/seed_demo_handovers.py         # 데모 데이터 시드
./.venv/bin/python scripts/run_mining.py --tenant localhost --dry-run   # PR 없이 도출만
./.venv/bin/python scripts/run_mining.py --tenant localhost             # PR 생성
./.venv/bin/python scripts/export_threads.py localhost threads.json     # 스레드 묶음 내보내기
```

## 테넌트와 인증

모든 API 는 `Authorization: Bearer <Supabase access token>` 이 필요하다. agent SDK 의
`tenant_auth` 로 토큰을 검증하고, 그 사용자가 속한 테넌트만 읽는다. 요청의 `tenant_id` 는
그 집합 안에 있을 때만 통과한다(아니면 403). `MINER_AUTH=off` 는 로컬 확인용이며
그때도 `tenant_id` 가 없으면 400 이다. 어느 경우에도 테넌트 없이 전체 기록을 돌려주지 않는다.

CORS 는 기본으로 열지 않는다(vite 프록시·게이트웨이로 같은 출처). 직접 부를 출처만
`MINER_CORS_ORIGINS` 에 쉼표로 적는다.

읽기 연결은 autocommit 이라 쿼리가 실패해도 다음 요청이 계속 실패하지 않는다. 제안 등록은
한 트랜잭션으로 묶고, 정의 단위 잠금 아래에서 다음 버전 번호(최대 번호 + 1)를 정한다.

## 아직 없는 것

- 게이트웨이(nginx)·docker-compose·k8s 배포 경로 (지금은 vite 개발 프록시만)
- 백그라운드 폴러
- 활동명 LLM 정규화, 게이트웨이 조건 보강
- 조직 마이닝(핸드오버 매트릭스는 계산하지만 조직도 제안까지는 안 감)
- `todolist` 실행 이력 인제스천
