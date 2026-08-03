# 조회 성능 튜닝 — 진단부터 검증까지

운영 Supabase(`uengine` 테넌트)에 실제 계정으로 붙어 측정하고, 고치고, 다시 측정한 기록이다.
추정으로 고친 것은 없다. 각 수정은 계측된 수치에 대응한다.

## 1. 측정 방법

읽기 전용 도구 세 개를 만들어 썼다(`services/frontend/playwright/demo/`).

| 스크립트 | 역할 |
|---|---|
| `rest-latency-probe.mjs` | REST 엔드포인트 응답시간·전송량 (curl 수준) |
| `query-profile.mjs` | 화면별 호출 횟수·`select` 모양·전송량 집계 |
| `prod-scenario-bench.mjs` | 운영 로그인 후 시나리오별 실측 (before/after 비교용) |

로컬에서 운영 DB 로 붙이기 위해 `.env` 에 운영 URL/키를 넣고,
테넌트는 `VITE_TENANT_OVERRIDE` 로 지정한다(`main.ts`). 서브도메인으로 테넌트를 정하는
구조라 `localhost` 에서는 이 우회가 없으면 `uengine` 데이터를 볼 수 없다.

## 2. 먼저 배제한 것 — 네트워크

```
운영 Supabase TTFB  ~60ms  (dns 2ms / connect 11ms / tls 32ms)
```

네트워크·지역 문제가 아니다. 여기서부터 쿼리를 의심했다.

## 3. 병목 4가지

### 3-1. 목록이 본문 컬럼까지 실어 나른다

`proc_def` 한 행에는 BPMN 정의 전체(`definition` JSON, `bpmn` XML)가 들어 있다.
목록 화면은 `id`·`name`·`type` 만 쓰는데 `select=*` 로 전량을 받았다.

같은 패턴을 운영 `users` 테이블에서 직접 재보면 비용이 분명하다:

| 쿼리 | 응답 | 전송량 |
|---|---|---|
| `users?select=*` | **909ms** | 674KB |
| `users?select=id,username,email` | **96ms** | 89KB |

행 수는 같은데 9.5배다.

**수정** — `listDefinition` 의 세 경로에 컬럼 투영을 넣었다.
배포 환경마다 스키마가 달라(4-3 참고) 공통 컬럼 + 선택 컬럼 폴백 구조로 만들었다.

```ts
const PROC_DEF_BASE_COLUMNS = 'uuid,id,name,type,isdeleted,tenant_id,owner,agent_id,prod_version';
const PROC_DEF_OPTIONAL_COLUMNS = ['is_draft'];   // 운영에는 없음 → 42703 시 빼고 재시도
```

안전한지 확인한 근거: `listDefinition` 결과를 쓰는 호출부(`BpmnUengineField`, `LanePanel`,
`ParticipantPanel`, `ProcessDefinitionMap`)를 전수 확인해 `.definition`/`.bpmn` 접근이
없음을 확인했다. `ProcessDefinitionMap` 에는 `select('id, name')` 로 바꾸려다 만
주석까지 남아 있었다.

`chat_rooms` 도 같다. 목록은 `id`·`name`·`message`·`participants` 만 쓰고
`context`(방별 컨텍스트 JSON)는 방을 열 때 `getChatRoom` 이 따로 가져온다.

### 3-2. 서버에서 거를 수 있는데 클라이언트에서 걸렀다

유사 프로세스 검색이 이랬다:

```ts
const procDefs = await storage.list('proc_def', { match: { isdeleted: false } }); // 전량
let list = procDefs.filter((item) => vectorResult.includes(item.id));            // 클라에서 필터
```

대상 id 를 이미 알고 있으면서 전체를 내려받았다. `in` 필터로 옮겼다.

```ts
const procDefs = await storage.list('proc_def', {
    match: { isdeleted: false },
    inArray: { column: 'id', values: vectorResult },
    key: 'id,name,bpmn'
});
```

### 3-3. 페이지네이션 인자를 받고도 무시했다

```ts
async getAllInstanceList(page: any, size: any) {
    const list = await storage.list('bpm_proc_inst', withTenantMatch());  // page/size 미사용
```

`range` 로 서버에서 자르고, 인자가 없으면 상한 200 을 둔다.

### 3-4. 같은 조회가 한 화면에서 9번

화면 여러 곳이 각자 사용자 목록을 불러 `users select=*` 가 9회 나갔다(합계 11.3초).
호출부를 전부 고치는 대신 조회 계층에 in-flight 공유 + 3초 캐시를 뒀다.

```ts
function dedupe<T>(key: string, run: () => Promise<T>): Promise<T>
```

실패한 요청은 캐시에 남기지 않아 재시도를 막지 않는다.

## 4. 결과 — 배포본 vs 수정본 (운영 uengine 데이터)

### 4-1. 배포 사이트 실측 — https://uengine.process-gpt.io/definition-map

| 지표 | 값 |
|---|---|
| 네트워크 안정화 | 12.3초 |
| 총 요청 / 전송량 | 327건 / **59.35MB** |
| 그중 API | 55건 / **39.9MB** |
| `proc_def?select=*` (isdeleted) | 5,558KB × **6회** |
| `proc_def?select=*` (type=bpmn) | 5,198KB × 1회 |

**API 전송량의 96%가 `proc_def` 한 테이블이다.** 같은 쿼리를 6번 반복한다.

운영 `proc_def` 한 행의 필드별 크기를 재보면 이유가 분명하다:

| 필드 | 바이트 |
|---|---|
| `bpmn` | 34,305 |
| `definition` | 10,052 |
| 나머지 12개 필드 합계 | < 150 |

**본문 두 컬럼이 한 행의 99.8%** 다. 목록은 `id`·`name`·`type` 만 쓴다.

### 4-2. 쿼리 A/B (같은 조건, 같은 325행)

| 쿼리 | median | rows | 전송량 |
|---|---|---|---|
| 배포본 `select=*` | **4,316ms** | 325 | **5,048KB** |
| 수정본 컬럼 투영 | **200ms** | 325 | **73KB** |

**21배 빠르고 69배 작다.** 화면 기준으로 환산하면 `proc_def` 38.5MB → 약 0.5MB.

### 4-3. 계측에서 배운 것 두 가지

**(1) 가장 느린 쿼리가 0바이트로 보일 수 있다.**
수정 전 계측에서 `proc_def` 는 11.7초에 **0KB** 로 찍혔다. 본문을 읽기 전에 중단된
것이고, 부분 수정 후 같은 쿼리가 완주하면서 비로소 5MB 라는 실체가 드러났다.

**(2) 배포 환경마다 스키마가 다르다 — 실패한 쿼리를 개선으로 오독할 뻔했다.**
처음 만든 컬럼 목록에 `is_draft` 를 넣었다. 로컬 `proc_def` 에는 있지만 **운영에는
없다**. PostgREST 는 없는 컬럼이 하나라도 있으면 42703 으로 쿼리 전체를 실패시킨다.
그래서 "응답 1KB" 가 나왔고 하마터면 성능 개선으로 기록할 뻔했다.
**행 수를 함께 확인하지 않았다면 놓쳤을 오류다.**
이후 A/B 는 양쪽이 같은 325행을 반환하는지 확인하고 비교한다.

대응: 공통 컬럼을 기본으로 쓰고, 선택 컬럼(`is_draft`)은 한 번 시도해 42703 이면
기억해 두고 빼고 재시도한다(`listProcDefWithFallback`).

### 4-4. 로컬에서 앱 화면 단위로 재는 것은 신뢰할 수 없다

로컬(`127.0.0.1`)에서는 서브도메인이 없어 테넌트 게이트가 다르게 동작하고
`/definition-map` 이 랜딩 페이지로 리다이렉트된다. 화면 단위 before/after 는
이 때문에 무의미한 값이 나온다. **쿼리 단위 A/B(4-2)로 비교할 것.**

## 5. 고치지 않은 것 (근거 포함)

### DB 인덱스 부재 — 별도 승인 필요

`chats` · `chat_rooms` · `todolist` · `bpm_proc_inst` 에 **PK 외 인덱스가 하나도 없다**.
특히 채팅 로딩이 구조적으로 느리다:

```sql
SELECT * FROM chats WHERE id = $1 ORDER BY messages->>'timeStamp' DESC
```

- `chats.id`(방 id)에 인덱스 없음 → 전체 스캔
- `messages->>'timeStamp'` 는 **JSONB 표현식 정렬** → 일반 인덱스로 못 탄다

메시지가 쌓일수록 선형으로 느려진다. 권장 인덱스:

```sql
CREATE INDEX CONCURRENTLY idx_chats_id            ON public.chats (id);
CREATE INDEX CONCURRENTLY idx_chats_tenant        ON public.chats (tenant_id);
CREATE INDEX CONCURRENTLY idx_chats_room_ts       ON public.chats (id, (messages->>'timeStamp') DESC);
CREATE INDEX CONCURRENTLY idx_chat_rooms_tenant   ON public.chat_rooms (tenant_id);
CREATE INDEX CONCURRENTLY idx_todolist_tenant     ON public.todolist (tenant_id);
CREATE INDEX CONCURRENTLY idx_inst_tenant_start   ON public.bpm_proc_inst (tenant_id, start_date DESC);
```

운영 스키마 변경이라 이 문서에 남기고 적용은 하지 않았다.

### 화면 컴포넌트의 N+1

`InstanceCard.vue` 가 카드마다 `getInstance()` 를 호출한다. 로컬 프로파일에서 할일 목록
한 화면에 `bpm_proc_inst` 개별 조회가 **65회** 나갔다. `in` 한 번으로 합치는 것이 맞지만
컴포넌트 구조 변경이 필요해 분리했다.

### 남은 상위 비용

수정 후 기준 가장 무거운 것은 `chat_rooms` 목록(537KB, `message` 컬럼이 큼)과
`users select=*`(356KB)다. 둘 다 컬럼을 더 줄이거나 페이지네이션을 넣을 여지가 있다.

## 6. 재현

```bash
cd services/frontend
# .env 에 운영 URL/KEY + VITE_TENANT_OVERRIDE=uengine
npx vite --host 127.0.0.1 --port 5199     # Node 22 필요

BENCH_LABEL=before BENCH_EMAIL=<계정> BENCH_PW=<비번> \
  node playwright/demo/prod-scenario-bench.mjs
```

세 스크립트 모두 읽기 전용이다. 쓰기·스키마 변경은 하지 않는다.
