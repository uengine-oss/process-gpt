# 시나리오 — 튜토리얼 Lv.4: ERP 데이터 연동을 통한 재고 관리 (영상 시리즈 4/5)

> **튜토리얼 영상 시리즈 4/5** — `docs/doc-site/content/ko/tutorial/tutorial-lv4.md`
> ("ERP 데이터 연동을 통한 재고 관리")의 **현대화판**이다. 원본은 외부
> `supabase.com` 프로젝트를 만들어 연동했지만, 이 편은 **로컬 스택의 Supabase**
> (docker-infra, Kong `:54321`)를 ERP로 쓴다.
>
> **1~3편과의 관계**: 1~3편이 확장해 온 "영업 제안서 작성" proc_def
> (`b2f50721…`)는 **재사용하지 않는다**. 이번 편은 **별도 proc_def**
> `inv_mgmt_erp_process` "재고 관리 프로세스"를 처음부터 만든다. 1~3편에서
> 확립한 패턴(빌드타임=편집기 실조작 + 필요한 것만 DB, 런타임=API 실증 + 결정론
> 조건 conditionFunction, deepagents 기본·crewai 비노출)은 그대로 계승한다.
>
> **5편에 넘길 것**: §"5편 제작자 참고"에.

전제: 고정 데모 계정(`demo@localhost` / `Demo1234!`, tenant `localhost`).
게이트웨이 `http://localhost:8088`. 데모 계정 auth_uid `bd0e585b-3828-496c-92aa-3f93f336d3d3`.

---

## 0. 실측값 (이번 실행 기준 — 재현 시 매번 갱신)

| 항목 | 값 |
| --- | --- |
| proc_def id / name | `inv_mgmt_erp_process` / **재고 관리 프로세스** (`type=bpmn`, `is_draft=false`) |
| 활동 구성 | `order`(주문 접수, 고객) → `check`(재고 확인, **MRP 에이전트/deepagents/draft**) → `gw_stock`(재고 충분?, exclusiveGateway) → [충분] `ship`(출고 처리, MRP/deepagents) → end / [부족] `produce`(생산 요청, 생산 담당) → `receive`(입고 처리, MRP/deepagents) → `ship`(합류) → end |
| 레인/역할 | 고객(`role_customer`) · 물류 담당(`role_logistics`) · 생산 담당(`role_production`) |
| 게이트웨이 conditionData | `["inv_mgmt_erp_process_check_form.stock_sufficient"]` |
| 분기 조건 (결정론) | `seq_gw_ship` conditionFunction `stock_sufficient == 'true'` (재고 충분) · `seq_gw_produce` `stock_sufficient == 'false'` (재고 부족) |
| `check` 폼 결정 필드 | `stock_sufficient` 라디오 (items `[{"true":"충분"},{"false":"부족"}]`, 값 문자열 `"true"/"false"`) |
| 폼↔ERP 연동 필드 | `order_form.product_name` = **select, `is_dynamic_load="dataBinding"`, `dynamic_data_source="ERP 재고 데이터"`, key/value column `product_name`** |
| MRP 에이전트 id / 팀 | `59f136f9-684d-40f3-863a-21dcb4106563` / 물류팀 `de011f59-d853-4cc9-b724-80ea994ee6a6` |
| MRP 에이전트 tools | `erp-supabase` (tenants.mcp 서버명, CSV) · model `gpt-4.1` |
| 데이터소스 | `data_source` key=`ERP 재고 데이터`, `value.endpoint=http://localhost:54321/rest/v1/product_table?select=*`, headers `apikey`/`Authorization: Bearer <anon>` |
| ERP 테이블 | `public.product_table` (product_name, product_id, category, unit_price, unit, description, stock_quantity, created_at) — 데모 5행 |
| 충분 경로 완주 인스턴스 | `inv_mgmt_erp_process.c0ce3988-5aa6-42fc-8597-1a62a224782b` (COMPLETED, 히터모듈 120→50) |
| 부족 경로 완주 인스턴스 | `inv_mgmt_erp_process.86680016-cbbd-4ed0-9925-f050ec8ac1e9` (COMPLETED, 금형세트 10→110→80) |
| 최종 영상 | `demo-recordings/tutorial-lv4-erp-inventory-narrated.mp4` (voice marin, assemble PASS — §끝) |

DB/REST 접근:
```bash
cd /Users/uengine/process-gpt/docker-infra
PGPW=$(grep -E '^POSTGRES_PASSWORD=' .env | cut -d= -f2-)
ANON=$(grep -E '^ANON_KEY=' .env | cut -d= -f2- | tr -d '\n')
PSQL(){ docker exec -e PGPASSWORD="$PGPW" supabase-db psql -U supabase_admin -d postgres -tAc "$1"; }
# ERP REST 확인 (실제로 데이터 반환)
curl -s "http://localhost:54321/rest/v1/product_table?select=product_name,stock_quantity&order=product_id" \
  -H "apikey: $ANON" -H "Authorization: Bearer $ANON"
```

---

## 1. ERP 데이터 준비 — 로컬 Supabase(Kong) + REST

원본 튜토리얼의 외부 supabase.com 대신 **docker-infra 스택의 Supabase**를 ERP로
쓴다. `public.product_table`을 만들고 데모 재고를 시드한 뒤, PostgREST/Kong으로
REST 노출한다.

- **스키마 생성은 PRODUCT_CHANGES 대상 아님**(데모 스키마). 단 **REST 가시성**을
  위해 grant/RLS가 필요하다(연구로 확정):
  - PostgREST는 `anon` 롤로 전환해 접근 → **`GRANT SELECT/INSERT/UPDATE/DELETE ON
    public.product_table TO anon, authenticated`** 필수.
  - RLS를 켜면 정책이 없으면 **0행 반환**(빈 배열)이 되는 함정(`data_source`
    테이블이 실제로 이 상태) → 이번엔 RLS ON + **`FOR SELECT/ALL TO anon,
    authenticated USING(true)`** 허용 정책을 넣어 튜토리얼의 "RLS 정책 설정"
    단계를 재현하면서 실제로 조회·수정되게 했다.
  - 새 테이블은 PostgREST 스키마 캐시가 stale → **`NOTIFY pgrst, 'reload
    schema';`** 반드시 실행.
- **REST 검증(실측)**: `GET /rest/v1/product_table?select=*`, `PATCH …?product_id=eq.P-1001`
  (stock_quantity 갱신) 모두 anon 키로 **200 + 실데이터/실변경** 확인.
- 데모 데이터: 히터모듈(P-1001) 120 · 금형세트(P-1002) 10 · 센서보드 80 · 제어유닛 45 · 배선하네스 200.

시드/권한 SQL은 scratchpad `build_lv4.py`(정의/폼 생성) + 인라인 DDL로 적용했다.

---

## 2. 데이터소스 등록 (실화면) — `data_source` 는 key/value 저장소

`/account-settings` → **데이터소스** 탭(`ConnectionInfoTab.vue`, "실험적 기능"
배지). `?tab=ConnectionInfo` 쿼리만으로는 탭이 자동 선택되지 않으니 **"데이터소스"
탭을 클릭**해야 한다(녹화 주의).

- 저장 shape(실측, `saveDataSource()`): `data_source.key` = **Name 문자열**(uuid 아님),
  `data_source.value`(jsonb) = `{method, endpoint, headers:[{key,value}], parameters:[], auth:{...}}`,
  `version=1`, `tenant_id`는 백엔드가 스탬프.
- 이번 값: key=`ERP 재고 데이터`, endpoint=`…/rest/v1/product_table?select=*`,
  headers `apikey=<anon>`, `Authorization=Bearer <anon>`.
- **기본 더미 5건 주의**: 데이터소스 목록의 더미는 프론트 기본값이며 DB엔 없다
  (실측: `data_source` 테이블은 신규 등록 전까지 비어 있음).

### 폼 필드 ↔ 데이터소스 연동 (실측 확정)

`SelectField.vue` + `CommonSettingInfos.vue`. **서버측 옵션 리졸버는 없다** —
프론트 `ProcessGPTBackend.callDataSource`가 브라우저에서 endpoint를 직접 fetch하고
JSONPath로 옵션을 만든다. 폼 필드(form_def)에 저장하는 키:

```
{ "key":"product_name", "type":"select", "items":[],
  "is_dynamic_load":"dataBinding",
  "dynamic_data_source":"ERP 재고 데이터",     // = data_source.key 와 일치해야 함
  "dynamic_load_url_name":"",                   // endpoint 뒤에 붙는 경로
  "dynamic_load_key_column":"product_name",     // 옵션 value
  "dynamic_load_value_column":"product_name" }  // 옵션 label(표시)
```
`:54321` 엔드포인트는 프론트가 자동으로 `Authorization: Bearer <anon>`를 주입한다.

---

## 3. MRP 에이전트 등록 (실화면 + DB) & ERP 접근 경로 실측 (이 편의 핵심)

`/organization`에 **물류팀** + **MRP 에이전트**(자연어 "AI로 에이전트 생성" 흐름
시연, 저장은 중복 방지로 DB 확정 — lv2 패턴). persona에 ERP 접근 지침(product_table
컬럼·SELECT/UPDATE 예시)을 임베드했다.

### 에이전트의 실제 DB 접근 경로 — **실측 결론**

목표: **stock_quantity가 에이전트 수행으로 실제 변하는지**를 실측으로 확정.

1. **도구 경로는 존재한다(코드 확인)**: deepagents executor(`services/deepagents/
   executor.py:786~`)가 `tenants.mcp`를 읽어 `core/llm/mcp.py::_load_mcp_tools_grouped`
   로 MCP 서버의 도구를 로드하고, **`core/agents/subagents.py:72~`가 에이전트의
   `tools`(CSV)에 명시된 서버만** 서브에이전트에 바인딩한다. 즉 `postgres-mcp`의
   `execute_sql`(unrestricted → UPDATE 가능)을 붙이려면 **에이전트 `tools`에 서버명이
   있어야** 한다.
2. **컨테이너 네트워크 함정(실측)**: `deepagents`는 `process-gpt-infra-docker_default`
   네트워크, `supabase-db`는 `docker-infra_default`로 **서로 다른 네트워크**다.
   컨테이너 안에서 `localhost:54322`는 실패하고(`db:5432`도 해석 불가), **오직
   `host.docker.internal:54322`만 도달**한다(TCP·자격증명 검증 완료). 반면 시나리오 7의
   host 기반 venv는 `localhost:54322`가 맞다(host에선 `host.docker.internal` 미해석).
   → **충돌 회피**: 기존 `supabase-mcp`(localhost, 시나리오 7)를 건드리지 않고,
   `tenants.mcp`에 **`erp-supabase`(host.docker.internal:54322, unrestricted)** 를
   **추가**하고 MRP 에이전트 `tools='erp-supabase'`로 지정했다.
3. **런타임 실측(중요·정직)**: 위 구성으로 `재고 확인` 태스크를 deepagents로
   디스패치하자, **에이전트는 실제로 실행되어 draft를 생성했으나** 그 내용은
   *"ERP 서버 접속 실패로 product_table에서 조회할 수 없습니다"* 였다 — 즉
   **에이전트가 MCP(execute_sql)로 ERP를 읽/쓰는 데 이번 실행에선 성공하지 못했다.**
   (도구 미바인딩/`postgres-mcp` uvx 콜드스타트 추정. 태스크는 `agent-router`가
   라우팅하는데, deepagents 컨테이너 로그엔 이 활동 실행 흔적이 없어 러너 경유가
   달랐다.) 반복 디버깅 대신, 아래 **동작하는 경로로 영상을 구성하고 내레이션은
   사실만** 담았다.
4. **동작하는 ERP 변경 경로(실증)**: 재고의 실제 변경은 **데이터소스와 동일한
   Kong REST(anon) PATCH**로 수행한다 — `출고 처리`에서 `stock_quantity -= 주문량`,
   `입고 처리`에서 `+= 생산량`. 이는 프로세스가 ERP 데이터소스와 연동되어 재고를
   갱신함을 **실데이터로** 보여준다(아래 §5에서 120→50, 10→110→80 실증). **내레이션은
   "에이전트가 SQL로 DB를 직접 수정했다"고 주장하지 않고, "출고·입고 단계에서 ERP의
   재고가 실제로 차감·가산된다"까지만** 말한다.

> **결론**: 이 설치에서 deepagents의 자율 MCP DB 쓰기는 **기본 구성만으로는
> 재현되지 않았다**(실측). 확실히 동작하는 경로 = **데이터소스 REST(anon) 갱신**.
> 에이전트는 재고 확인 등에서 실제로 수행되며, 재고 수치 변경은 REST로 실증한다.

---

## 4. 프로세스 모델링 (편집기 실습 + 결정론 조건)

빌드타임 교육 목표는 편집기 실조작이다. `/definitions/inv_mgmt_erp_process`
디자이너(세로 스윔레인 3레인)에서:

- **편집 모드**: 우측 패널 연필 토글(x≈1576) → 편집 도구/팔레트.
- **게이트웨이 분기 조건**: 분기 플로우 더블클릭 → `SequenceFlowPanel` 조건 필드에
  자연어("재고 충분/부족") + 함수 모드로 conditionFunction 입력.
- **재고 확인 태스크**: 더블클릭 → **에이전트 탭** = 딥 에이전트 + MRP 에이전트 연결.
- **주문 폼**: 물품명 select를 ERP 데이터소스에 바인딩(§2).

정확성은 lv3처럼 `build_lv4.py`로 `proc_def.definition`+`bpmn`(레인/DI 포함)과
5개 `form_def`, `data_source`를 한 번에 확정했다(편집기 저장은 conditionFunction을
떨어뜨리는 lv3 한계가 동일 전제).

> **영상 실측(편집기 패널 조작 한계, 정직)**: 헤드리스 bpmn-js에서 **엣지 조건
> 패널 더블클릭이 캔버스를 교란**하고(마우스 스프레이가 "버전 업" 저장
> 다이얼로그를 띄우는 부작용 관찰), 뒤이은 **태스크 패널 dblclick이 30초
> actionability 타임아웃**으로 매달렸다(lv3 §2 "헤드리스 팔레트 불안정"과 동일
> 계열). 그래서 최종 영상은 **편집 모드 진입(연필 토글)까지는 실화면으로**
> 보여주고, 게이트웨이 조건·태스크 에이전트 탭·폼 데이터소스 매핑의 **정확한
> 설정값은 오버레이 슬라이드로 명시**했다(값은 DB 실측·런타임 검증과 100% 일치).
> 런타임(충분/부족 2경로)은 전부 실 API·실 재고 변경 라이브 녹화다.

### ⚠️ conditionFunction 평가의 실제 제약 (수치 비교 함정 — 중요)

`workitem_processor._evaluate_sequence_conditions`(L2181~)의 eval은
**`{"__builtins__": {}}`** 컨텍스트다 → **`int()`/`float()` 사용 불가**. 또한 각
평가 컨텍스트는 **단일 dict**(모든 입력 dict를 각각 시도) → **두 피연산자가 같은
dict 안에** 있어야 한다. 폼 number 값이 문자열로 저장되면 `'120' >= '70'`은
**사전식 비교로 오판**한다.

→ 그래서 "재고>=주문량" 수치 비교를 **게이트웨이에서 직접** 하지 않고, **`재고
확인` 단계에서 판정한 `stock_sufficient`('true'/'false')**를 게이트웨이가
문자열 등가 비교(`== 'true'` / `== 'false'`)로 결정론 분기한다(lv3의 라디오 패턴과
동일, 검증됨). 수치 비교(120 vs 70, 10 vs 30)는 재고 확인 단계의 판정 근거로 남는다.

---

## 5. 런타임 — 두 경로 모두 COMPLETED (API 실증 + 실 재고 변경)

단일 데모 계정 한계상 전이는 `/completion/complete`를 JWT로 직접 호출(lv1~3 패턴,
`email` 필수, form_values는 폼 id 전체 + 평탄 키 병행). 재고 변경은 Kong REST PATCH.

**(a) 충분 경로 — 히터모듈 70 주문 (재고 120):**

| 단계 | 동작 | 관찰 |
| --- | --- | --- |
| 1 | order 제출(히터모듈 70) | 인스턴스 시작 |
| 2 | check 제출(stock 120, `stock_sufficient='true'`) | 게이트웨이 → **ship**(충분), produce/receive 건너뜀 ✅ |
| 3 | 출고 처리: REST PATCH 120→**50** + ship 제출 | ERP 재고 실제 차감 |
| 4 | 폴링 | `bpm_proc_inst.status = COMPLETED` ✅ |

**(b) 부족 경로 — 금형세트 30 주문 (재고 10):**

| 단계 | 동작 | 관찰 |
| --- | --- | --- |
| 1 | order 제출(금형세트 30) | 인스턴스 시작 |
| 2 | check 제출(stock 10, `stock_sufficient='false'`) | 게이트웨이 → **produce**(부족) ✅ |
| 3 | produce 제출(생산 100) | receive 활성 |
| 4 | 입고 처리: REST PATCH 10→**110** + receive 제출 | ERP 재고 가산 |
| 5 | 출고 처리: REST PATCH 110→**80** + ship 제출 | ERP 재고 차감, `ship→end` |
| 6 | 폴링 | **COMPLETED** ✅ (최종 재고 80) |

- **게이트웨이 결정론 분기 양방향 검증됨**: `stock_sufficient` 값으로 충분→ship /
  부족→produce 정확 라우팅.
- **lv3의 게이트웨이→endEvent COMPLETED 버그(#52)는 재현 안 됨** — 이 프로세스는
  end_event 직전이 게이트웨이가 아니라 **`ship`(태스크)**이라 `find_end_activity`가
  종료 활동을 정상 판정한다(합류를 게이트웨이가 아닌 태스크에서 하도록 설계).
- 화면: 인스턴스 뷰어(전 구간 통과, 부족 경로는 생산→입고→출고 하이라이트),
  ERP 미리보기(REST 실데이터로 120→50, 10→110→80).

---

## 6. 함정 요약

- **데이터소스는 key/value 저장소**: `data_source.key`=Name, `value`=jsonb(method/
  endpoint/headers/parameters/auth). 폼 연동은 **프론트 client-side fetch**(서버
  리졸버 없음).
- **RLS 함정**: 새 테이블에 grant만으론 부족, RLS ON이면 정책 없으면 0행. `NOTIFY
  pgrst, 'reload schema'` 필수(스키마 캐시).
- **컨테이너 DB 도달**: deepagents는 `host.docker.internal:54322`만 됨(`localhost`/
  `db` 불가, 네트워크 분리). tenants.mcp에 `erp-supabase` 별도 추가(시나리오 7의
  `supabase-mcp`/localhost 보존).
- **conditionFunction eval**: `{"__builtins__":{}}` → `int/float` 불가, 단일 dict
  컨텍스트 → **boolean 판정 필드(`stock_sufficient`)로 문자열 등가 비교**.
- **에이전트 자율 MCP 쓰기 미재현(실측)**: 재고 변경은 데이터소스 REST로 실증.
- **`?tab=ConnectionInfo` 자동선택 안 됨** → 데이터소스 탭 클릭.
- **폴링 지연**: order 제출 후 재고 확인 태스크 생성까지 ~15초, 각 전이 수 초~수십 초.

---

## 데모 후 보고 (이번 실행 결과)

- 새 proc_def `inv_mgmt_erp_process` "재고 관리 프로세스"(6활동+배타 게이트웨이,
  3레인). 게이트웨이 `gw_stock` 결정론 분기(`stock_sufficient=='true'/'false'`).
- ERP: `public.product_table`(로컬 Supabase) + Kong REST(anon) — GET/PATCH 실증.
  데이터소스 `ERP 재고 데이터` 등록, 주문 폼 `product_name` select ↔ product_table.
- MRP 에이전트(`59f136f9…`, 물류팀) + tenants.mcp `erp-supabase`(host.docker.internal).
  **에이전트 자율 MCP DB 쓰기는 기본 구성으로 재현 실패(실측·문서화)** — 재고 변경은
  데이터소스 REST 경로로 실증.
- 런타임 2경로 COMPLETED: 충분(히터모듈 120→50), 부족(금형세트 10→110→80).
- 최종 영상: `demo-recordings/tutorial-lv4-erp-inventory-narrated.mp4` (voice marin).
- 제품 수정: **소스 무수정**. tenants.mcp에 데모 MCP 서버(`erp-supabase`) 1건 추가
  (additive·가역, PRODUCT_CHANGES #4). 나머지는 데모 데이터(proc_def/form_def/
  data_source/users/organization/product_table).

## 5편 제작자 참고 (멀티 인스턴스 뉴스레터)

- **재사용 자산**: 물류팀·생산팀 조직 노드, `ERP 재고 데이터` 데이터소스 패턴
  (data_source key/value shape + 폼 select `dataBinding`), Kong REST(anon) GET/PATCH
  헬퍼, `build_*.py` 방식의 proc_def+bpmn+form_def 일괄 생성.
- **5편 = 멀티플 인스턴스**: `create.subprocess-expanded`(bpmn:SubProcess isExpanded) +
  JSON `multiInstanceCount`/`multiInstanceReason`. **실행 시 개수는 백엔드 자동 추론**
  (`workitem_processor.py`가 runtimeContext로 count 추론, `fetch_child_instances_by_parent`
  로 병렬 자식 인스턴스) — ui-research §멀티인스턴스 참고. CRM 테이블도 이번 편처럼
  **로컬 Supabase 테이블 + 데이터소스**로 만들면 된다(product_table 재활용 가능).
- **런타임 전이**: `/completion/complete`(task_id+email) + DB/REST 폴링, 화면은
  인스턴스 뷰어·워크아이템. deepagents 자동 단계(뉴스레터 초안)는 lv2/9처럼 프로필
  경유로 반영 보장(mem0 미조회 전제).
- **결정론 조건**: conditionFunction은 `{"__builtins__":{}}`·단일 dict 제약 →
  boolean 판정 필드로 문자열 등가 비교(수치/캐스팅 금지).
- **녹화/TTS/합성**: `lib_tutorial_slides.mjs` level=5, `record_tutorial_lv4_demo.mjs`
  구조(슬라이드+실화면+ERP 미리보기+라이브 API 실행) 그대로 재사용, voice marin.
