# 분기 판단 이력 (Gateway Decision Journal)

프로세스 엔진이 "다음에 어느 갈래로 갈 것인가"를 판단할 때마다, 그 판단의 **결과·근거·입력**을
이벤트 저장소에 남긴다. 승인·심사처럼 분기 자체가 업무적으로 중요한 프로세스에서
"이 건은 왜 임원 승인으로 가지 않았나"에 답할 수 있게 하는 것이 목적이다.

관련 스펙: `openspec/changes/gateway-decision-journal/`

## 1. 왜 필요한가

이 기능이 들어오기 전까지 분기 판단의 흔적은 **"생성되지 않은 워크아이템의 부재"로만** 역추적됐다.

- 게이트웨이는 `todolist` 행을 만들지 않는다. 판단 지점 자체가 흔적을 남기지 않는다.
- 시퀀스별 판정 결과와 근거는 처리 도중 구조화된 형태로 만들어지지만, 처리 종료와 함께 버려졌다.
- 자연어 조건 판정 모델 호출은 파이프라인에서 **유일하게 워크아이템 로그에도 남지 않는** 모델 호출이었다.
  분기가 잘못 갔을 때 재현할 입력도, 모델이 제시한 근거도 남아 있지 않았다.

## 2. 어디에 남는가

`events` 테이블을 재사용한다. 새 워크아이템 테이블을 만들지 않은 이유는 성격이 다르기 때문이다 —
`todolist` 는 **덮어쓰기 기반 현재 상태** 테이블이고, 판단 이력은 **추가 전용 저널**이다.
`todolist` 에 넣으면 회차별 판단 변화를 겹쳐 쓰게 되고, 칸반·할일 목록·담당자 필터가 오염된다.

| 이벤트 종류 | 내용 | 개수 |
| --- | --- | --- |
| `gateway_decision` | 판단 주체 노드 하나에 대한 분기 판단 결과 | 판단 지점마다 1건 |
| `gateway_decision_trace` | 자연어 조건 판정의 모델 프롬프트·응답 원문 | 모델 호출마다 1건 |

한 워크아이템 처리에서 게이트웨이를 연달아 통과하면 이벤트도 그만큼 생긴다.
같은 처리에서 나온 이벤트는 `events.job_id`(= `data.correlationId`)로 묶인다.

### 컬럼 매핑

| `events` 컬럼 | 값 |
| --- | --- |
| `job_id` | 상관 식별자. 같은 워크아이템 처리에서 나온 이벤트를 묶는다 |
| `todo_id` | 판단을 유발한 워크아이템 |
| `proc_inst_id` | 프로세스 인스턴스 |
| `event_type` | `gateway_decision` 또는 `gateway_decision_trace` |
| `data` | 아래 본문 |
| `tenant_id` | 테넌트 |

## 3. 판단 이력 본문 (`gateway_decision`)

```jsonc
{
  "decisionId": "…",
  "correlationId": "…",              // 같은 처리에서 나온 판단들을 묶는다

  // 판단 좌표
  "procInstId": "…",
  "rootProcInstId": "…",
  "executionScope": "…",             // 반복 하위 프로세스 구분
  "procDefId": "…",
  "procDefVersion": "…",
  "triggerActivityId": "Task_A",     // 이 판단을 유발한 활동
  "workitemId": "…",
  "reworkCount": 0,                  // 재실행 회차

  // 판단 주체
  "source": {
    "id": "Gateway_1",
    "name": "금액 구분",
    "type": "gateway",               // gateway | activity
    "branchType": "exclusiveGateway"
  },

  "selectionRule": "single-true",    // 아래 표 참고
  "outcome": "advanced",             // advanced | waiting | undecided

  // 시퀀스별 평가
  "evaluations": [
    {
      "sequenceId": "Flow_3",
      "method": "expression",        // expression | natural-language | unconditional
      "verdict": "true",             // true | false | undetermined
      "effective": true,             // 엔진이 실제로 사용한 값
      "expression": "amount >= 10000000",
      "reason": "신청 금액이 1200만원입니다",
      "error": null,
      "inputSnapshot": { "form_a": { "amount": 12000000 } },
      "selected": true
    }
  ],

  "selectedSequenceIds": ["Flow_3"],
  "unselectedSequenceIds": ["Flow_4"],
  "selectedTargets": [{ "activityId": "Task_B", "activityName": "팀장 승인", "type": "userTask" }],

  // outcome=waiting 인 경우
  "deferredTargets": [...],
  "waitingFor": [{ "activity_id": "Task_C", "activity_name": "임원 승인", "status": "IN_PROGRESS" }],

  "traceIds": ["…"],                 // 대응하는 모델 원문 이벤트
  "decidedAt": "2026-08-06T…Z",
  "decidedBy": "system"
}
```

### `verdict` 와 `effective` 를 반드시 함께 볼 것

이 기능에서 가장 중요한 구분이다.

엔진은 **평가가 아예 성립하지 않은 시퀀스를 거짓처럼 취급**한다. 조건식 평가가 예외로 실패했을 때도,
모델이 어떤 시퀀스의 판정을 빠뜨렸을 때도 결과적으로는 "가지 않는다"로 처리된다.
이력에서는 이 두 경우를 `verdict: "undetermined"` 로 남기고, 엔진이 실제로 쓴 값은 `effective` 에 따로 적는다.

| `verdict` | `effective` | 의미 |
| --- | --- | --- |
| `true` | `true` | 조건을 충족한다고 판정했다 |
| `false` | `false` | 조건을 충족하지 않는다고 판정했다 |
| `undetermined` | `false` | **판정하지 못했다.** 엔진이 거짓으로 처리했을 뿐이다 |

오분기 조사는 대부분 `undetermined` 를 찾는 데서 시작한다. `error` 필드에 원인이 적힌다
(조건식 예외, 모델 호출 실패, 모델 응답에 판정 누락 등).

### `selectionRule`

| 값 | 의미 |
| --- | --- |
| `unconditional` | 조건 없는 단일 경로 |
| `single-true` | 참인 갈래가 하나여서 그것을 선택 |
| `priority` | 참인 갈래가 여럿이어 우선순위로 하나 선택 |
| `default-flow` | 참인 갈래가 없어 기본 흐름 선택 |
| `no-candidate` | **참인 갈래도 기본 흐름도 없음 → 진행 불가** |
| `all-branches` | 병렬 분기라 모든 갈래 진행 |
| `filtered` | 포함 분기 등에서 통과한 갈래만 진행 |

### `outcome`

| 값 | 의미 |
| --- | --- |
| `advanced` | 갈래를 골라 다음 활동을 만들었다 |
| `waiting` | 병합 지점에서 다른 갈래의 완료를 기다린다 (`waitingFor` 참고) |
| `undecided` | 갈 수 있는 갈래가 없어 진행하지 못했다 |

`undecided` 는 이 기능이 도입되기 전까지 **조용히 멈추던 상태**다. 이제 관측 가능한 신호가 된다.

## 4. 모델 원문 (`gateway_decision_trace`)

```jsonc
{
  "traceId": "…",
  "correlationId": "…",
  "decisionIds": ["…"],        // 이 판정이 기여한 판단 이력
  "sequenceIds": ["Flow_3", "Flow_4"],
  "prompt": { … },
  "response": "…",
  "promptTruncated": false,
  "responseTruncated": false,
  "recordedAt": "…"
}
```

판단 이력 본문과 **별도 이벤트로 분리**했다. 원문은 본문보다 수십 배 크고 보존 요구도 다르기 때문이다.
감사 목적의 "어느 갈래로 왜 갔는가"는 오래 보관해야 하지만, 디버깅 목적의 원문은 짧게 보관해도 된다.

원문이 만료·삭제되어도 판단 이력 본문은 자립적으로 읽힌다 — **근거 문구(`reason`)는 원문이 아니라
본문에 복사**되어 있다.

조건식만으로 판정된 분기에는 원문 이벤트가 생기지 않는다.

## 5. 조회

```python
from database import (
    fetch_decision_events_by_proc_inst_id,
    fetch_decision_events_by_todo_id,
    fetch_traversed_sequence_ids,
)

events = fetch_decision_events_by_proc_inst_id(proc_inst_id, tenant_id)   # 판단 시각 순
events = fetch_decision_events_by_todo_id(todo_id, tenant_id)
sequences = fetch_traversed_sequence_ids(proc_inst_id, tenant_id)         # 실제 지나간 시퀀스
```

`fetch_traversed_sequence_ids` 는 `outcome == "advanced"` 인 판단의 `selectedSequenceIds` 만 모은다.
선택되지 않은 갈래, 대기 중인 갈래, 진행 불가는 모두 빠진다.

이력이 없는 과거 인스턴스는 **빈 결과**를 돌려준다(오류가 아니다).

## 6. 설정

| 환경 변수 | 기본값 | 의미 |
| --- | --- | --- |
| `DECISION_JOURNAL_SNAPSHOT_LIMIT` | `8192` | 입력 스냅샷 저장 크기 상한(직렬화 후 문자 수) |
| `DECISION_JOURNAL_TRACE_LIMIT` | `65536` | 모델 프롬프트·응답 원문 상한 |

상한을 넘으면 **기록을 생략하지 않고** 잘라서 남긴다.

```jsonc
"inputSnapshot": { "truncated": true, "originalLength": 51200, "preview": "…" },
"inputSnapshotTruncated": true
```

## 7. 진행 경로 보호와 그 대가

판단 이력 기록은 **프로세스 진행의 임계 경로에 들어가지 않는다.** 관측 기능이 실행 기능을
망가뜨리는 것이 최악이기 때문이다.

- 기록은 별도 큐로 넘어가고 백그라운드 워커가 저장한다.
- 이벤트 저장이 실패해도 예외를 전파하지 않고 `[ERROR] decision journal: …` 로그만 남긴다.
- 다음 활동 워크아이템 생성은 이력 기록의 성공이나 지연에 묶이지 않는다.

**대가는 이력이 유실될 수 있다는 점이다.** 프로세스가 죽거나 이벤트 저장소가 계속 실패하면
그 판단은 남지 않는다. 감사 목적으로 유실 불가가 요구되면 동기 쓰기로 바꿔야 하는데,
그러면 진행 경로가 이벤트 저장소 가용성에 종속된다. 현재는 **진행 보호를 우선**한 선택이다.

## 8. 운영 조회 예시

**어떤 인스턴스가 왜 그 갈래로 갔는가**

```sql
SELECT
  data->'source'->>'name'      AS gateway,
  data->>'selectionRule'       AS rule,
  data->>'outcome'             AS outcome,
  data->'selectedSequenceIds'  AS selected,
  jsonb_pretty(data->'evaluations') AS evaluations
FROM public.events
WHERE proc_inst_id = :proc_inst_id
  AND event_type = 'gateway_decision'
ORDER BY timestamp;
```

**멈춰 있는 인스턴스 찾기 (진행 불가)**

```sql
SELECT proc_inst_id, todo_id, data->'source'->>'id' AS gateway, timestamp
FROM public.events
WHERE event_type = 'gateway_decision'
  AND data->>'outcome' = 'undecided'
  AND timestamp > now() - interval '1 day'
ORDER BY timestamp DESC;
```

**판정하지 못한 조건 찾기 (오분기 조사의 출발점)**

```sql
SELECT proc_inst_id,
       data->'source'->>'id' AS gateway,
       e.value->>'sequenceId' AS sequence_id,
       e.value->>'error'      AS error
FROM public.events,
     LATERAL jsonb_array_elements(data->'evaluations') AS e(value)
WHERE event_type = 'gateway_decision'
  AND e.value->>'verdict' = 'undetermined'
ORDER BY timestamp DESC;
```

**모델이 실제로 무엇을 보고 판정했는가**

```sql
SELECT jsonb_pretty(data->'prompt') AS prompt, data->>'response' AS response
FROM public.events
WHERE event_type = 'gateway_decision_trace'
  AND data->'decisionIds' ? :decision_id;
```

## 9. 마이그레이션

`docker-infra/volumes/db/migration.sql` 의 "분기 판단 이력" 섹션이 다음을 수행한다.

1. `event_type_enum` 에 `gateway_decision`, `gateway_decision_trace` 추가
2. `events.tenant_id` 컬럼 추가 (기본값 `public.tenant_id()`)
3. `proc_inst_id` / `todo_id` / `tenant_id` / `event_type` 인덱스 생성

재실행해도 안전하다.

## 10. 알려진 한계

- **DB 레벨 테넌트 격리는 아직 없다.** `events` 테이블에는 RLS 를 켜지 않았다. 다른 서비스들이 이
  테이블에 쓰고 있고 과거 행의 `tenant_id` 가 NULL 이라, 지금 RLS 를 켜면 기존 조회가 끊긴다.
  현재는 **조회 계층에서 `tenant_id` 로 필터링**한다. DB 레벨 격리는 백필 이후 별도 변경 대상이다.
- **소급 생성은 하지 않는다.** 기능 도입 이전에 실행된 인스턴스에는 이력이 없다. 진행 중이던
  인스턴스는 도입 시점 이후의 판단부터 기록된다.
- **유실 가능성**이 있다(7장 참고).
- **보존 기간 정책이 아직 정해지지 않았다.** 현재는 이벤트가 무기한 쌓인다. 판단 이력 본문과
  모델 원문 각각의 보존 기간, 그리고 입력 스냅샷의 개인정보 마스킹 여부는 후속 결정 대상이다.

## 11. 모니터링 화면과의 관계 — 이력 있으면 사실, 없으면 추론

프론트엔드의 "흘러간 경로" 표시는 원래 프로세스 정의 그래프를 역추론했다. 이 방식에는 두 가지
구조적 한계가 있다.

- **판정 불가**: 배타 분기의 모든 갈래가 종료 이벤트로만 이어지면 어느 쪽으로 갔는지 알 수 없다.
  안전을 위해 아무 갈래도 표시하지 않는다.
- **과잉 표시**: 두 갈래가 통과 노드(게이트웨이)만 거쳐 다시 합류하면, 양쪽 모두 "뒤에 실행 흔적이
  있다"고 판정되어 두 갈래가 전부 강조된다.

판단 이력이 이 두 한계를 모두 해소한다. 다만 **인스턴스 단위로 둘 중 하나를 고르지 않는다.**
이력은 워크아이템이 완료될 때부터 쌓이므로, 시작 이벤트에서 첫 활동으로 들어오는 간선처럼
이력이 다룰 수 없는 구간이 늘 남고, 기능 도입 시점을 걸쳐 실행된 인스턴스는 이력이 중간부터
시작한다. 인스턴스 단위로 전환하면 이런 인스턴스는 앞부분이 통째로 비어 보인다.

그래서 **판단 지점 단위로** 결정한다.

| 판단 지점 | 표시 근거 |
| --- | --- |
| 이력이 그 분기를 다뤘다 | 이력이 고른 갈래만 (사실) |
| 이력이 없다 | 그래프 추론 |

이력이 다룬 분기에서는 선택되지 않은 갈래가 **분기 지점에서 끊긴다.** 그래서 이력에 명시적으로
"선택되지 않았다"고 기록된 간선뿐 아니라 **그 갈래의 하위 구간까지 함께** 강조에서 빠진다.
사후에 간선을 빼는 방식으로는 얻을 수 없는 결과다.

판단 이력 조회는 진행 상태 조회와 분리되어 있어, 이력 조회가 느리거나 실패해도 진행 표시는
추론만으로 정상 동작한다.

동작 비교 영상: `docs/demo/instance-progress-journal-demo.mp4`
(녹화 스크립트: `services/frontend/e2e/instance-progress/record-journal-demo.mjs`)

## 12. 테스트

```bash
cd services/completion/polling_service

# 저널 자료구조 단위 테스트 (DB 불필요)
.venv/bin/python -m pytest tests/test_decision_journal.py -q

# 엔진 경로 배선 + 분기 결과 회귀 (DB 불필요)
.venv/bin/python -m pytest tests/test_decision_journal_wiring.py -q

# 실제 DB 왕복 (Supabase 기동 + 마이그레이션 적용 필요)
.venv/bin/python ../../../openspec/changes/gateway-decision-journal/e2e/decision-journal-roundtrip.py
```

배선 테스트에는 **레코더를 붙여도 분기 선택 결과가 달라지지 않음**을 확인하는 회귀 테스트가 들어 있다.
이 기능은 순수한 관측 계층이며 판단 로직을 바꾸지 않는다.
