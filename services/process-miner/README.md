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

## 실행

```bash
python3 -m venv .venv && ./.venv/bin/pip install -r requirements-dev.txt
export DB_PASSWORD=...            # .env.example 참고

./.venv/bin/python -m pytest tests -q                     # 단위 테스트(결정론적, DB 불필요)
./.venv/bin/python scripts/seed_demo_handovers.py         # 데모 데이터 시드
./.venv/bin/python scripts/run_mining.py --tenant localhost --dry-run   # PR 없이 도출만
./.venv/bin/python scripts/run_mining.py --tenant localhost             # PR 생성
./.venv/bin/python scripts/export_threads.py localhost threads.json     # 스레드 묶음 내보내기
```

## 아직 없는 것

- FastAPI 서버 / 백그라운드 폴러 (지금은 CLI 로만 실행)
- 활동명 LLM 정규화, 게이트웨이 조건 보강
- 조직 마이닝(핸드오버 매트릭스는 계산하지만 조직도 제안까지는 안 감)
- `todolist` 실행 이력 인제스천
