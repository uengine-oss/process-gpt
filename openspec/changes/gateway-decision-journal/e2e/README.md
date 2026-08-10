# 분기 판단 이력 E2E 검증

실제 데이터베이스를 상대로 "판단 이력 저장 → 조회" 왕복을 확인한다.
단위·통합 테스트(`services/completion/polling_service/tests/`)는 DB 없이 돌지만,
이 스크립트는 마이그레이션 적용 여부와 조회 계약을 실물로 확인하는 용도다.

## 사전 조건

- Supabase(Postgres)가 떠 있어야 한다. 로컬은 `docker-infra` 로 기동한다.
- `docker-infra/volumes/db/migration.sql` 의 "분기 판단 이력" 섹션이 적용되어 있어야 한다.
  적용 여부는 다음으로 확인한다.

```bash
docker exec supabase-db psql -U postgres -d postgres -t -c \
  "SELECT enumlabel FROM pg_enum WHERE enumtypid=(SELECT oid FROM pg_type WHERE typname='event_type_enum') ORDER BY enumsortorder;"
```

`gateway_decision`, `gateway_decision_trace` 가 보여야 한다.

- 루트 `.env` 에 `SUPABASE_URL` 과 `SERVICE_ROLE_KEY` 가 있어야 한다.

## 실행

```bash
cd services/completion/polling_service
.venv/bin/python ../../../openspec/changes/gateway-decision-journal/e2e/decision-journal-roundtrip.py
```

## 검증 항목

| 항목 | 대응 요구사항 |
| --- | --- |
| 판단 이력·모델 원문이 각각 이벤트로 저장된다 | 분기 판단 이력 기록 / 모델 판정 원문 보존 |
| 인스턴스 단위·워크아이템 단위 조회가 동작한다 | 판단 이력 조회 |
| 지나간 시퀀스 집합이 확정되고 미선택 갈래가 빠진다 | 판단 이력 조회 |
| 판단 이력과 원문이 서로를 참조한다 | 모델 판정 원문 보존 |
| 근거·입력 스냅샷이 판단 이력 본문에 남는다 | 판단 방식과 근거 기록 / 판단 입력 스냅샷 기록 |
| 다른 테넌트로 조회하면 결과가 비어 있다 | 판단 입력 스냅샷 기록(테넌트 격리) |
| 이력 없는 인스턴스는 빈 결과(오류 아님) | 판단 이력 조회 |
| 재실행 회차가 덮어쓰지 않고 누적된다 | 재실행 회차별 이력 누적 |

스크립트는 실행 전후로 자기 테스트 인스턴스(`journal.e2e.instance.1`)의 이벤트만 지운다.
