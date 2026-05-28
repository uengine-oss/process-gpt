---
name: mem0-vecs-table-reinit
description: mem0가 사용하는 vecs.memories 테이블이 컨테이너 재시작/coverage 모드 전환 후 비어 있거나 초기 상태로 돌아가 Playwright가 빈 검색 결과를 받는 현상.
applies-to:
  - mem0
  - supabase-pgvector
  - completion
  - vecs
last-verified: 2026-05-27
metadata:
  type: quirk
---

# mem0 vecs.memories table reset after container restart

`completion_agent-memory-chat` 스위트에서 백엔드 coverage 수집을 위해
completion 컨테이너를 `docker run`으로 재기동했을 때, mem0가 관리하는
`vecs.memories` 테이블이 비어 있는 상태로 시작되어 질의 모드 시나리오가
빈 검색 결과를 받는 현상이 재현됨. 같은 증상이 프론트엔드 coverage
override로 재기동한 직후에도 한 번 더 발생.

## What works

```bash
# completion 컨테이너만 깔끔하게 재시작하면 vecs 스키마가 정상 초기화되어
# 학습 → 질의 흐름이 다시 통과함
docker restart process-gpt-e2e-completion

# 또는 db-seed를 다시 실행해서 사용자/에이전트 프로필을 재확인
docker compose -f docker-compose.e2e.yml run --rm db-seed
```

Playwright 테스트의 학습 시나리오(01)가 질의 시나리오(03)보다 먼저 실행되도록
fileOrdering이나 test 순서를 유지하면, 테스트 자체가 메모리를 채우므로
사전 시드가 필요 없음.

## Why

- mem0의 `Memory.from_config`는 첫 호출 시점에 lazy하게 `vecs.memories`
  테이블/인덱스를 만든다. 컨테이너 교체 시점에 따라 init 순서가 어긋나면
  Playwright가 검색을 호출했을 때 테이블이 비어 있을 수 있다.
- 본질은 race condition이 아니라 "메모리 데이터가 컨테이너 라이프사이클에
  묶여 있다"는 것. db 볼륨(`e2e-db-data`)에는 남아 있지만 mem0 클라이언트의
  내부 상태(임베딩 모델 캐시 등)가 컨테이너 재기동마다 다시 초기화됨.

## How to apply

- Triggered when:
  - completion 컨테이너를 재기동한 직후 처음으로 질의 시나리오를 실행할 때
  - 백엔드/프론트엔드 coverage override로 일부 서비스만 재기동했을 때
  - "학습은 통과하는데 질의가 빈 결과를 받는다"는 증상이 나오는 경우
- Skip if:
  - 컨테이너 라이프사이클을 건드리지 않는 일반 Playwright 재실행
  - mem0를 쓰지 않는 스펙

Related: [[coverage-py-usr2-flush]]
