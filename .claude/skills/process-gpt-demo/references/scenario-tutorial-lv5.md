# 시나리오 — 튜토리얼 Lv.5: 멀티 인스턴스 고객 맞춤 뉴스레터 (영상 시리즈 5/5 · 피날레)

> **튜토리얼 영상 시리즈 5/5 (마지막 편)** — `docs/doc-site/content/ko/tutorial/tutorial-lv5.md`
> ("멀티플 인스턴스로 실행하는 고객 맞춤 뉴스레터 프로세스")의 현대화판이다.
> 원본은 외부 supabase.com CRM을 연동했지만, 이 편은 **로컬 스택의 Supabase**
> (docker-infra, Kong `:54321`)를 CRM으로 쓴다(4편 패턴 계승).
>
> **1~4편과의 관계**: 재사용하지 않는 **별도 proc_def** `vip_newsletter_process`
> "고객 맞춤 뉴스레터"를 처음부터 만든다. 4편에서 확립한 로컬 Supabase/데이터소스/
> REST 패턴·`build_*.py` 일괄 생성·런타임 API 실증을 그대로 계승하고, 이 편의
> **새 증명 대상은 "확장된 서브프로세스 멀티 인스턴스 → 병렬 자식 인스턴스"**다.

전제: 고정 데모 계정(`demo@localhost` / `Demo1234!`, tenant `localhost`).
게이트웨이 `http://localhost:8088`. 데모 계정 auth_uid `bd0e585b-3828-496c-92aa-3f93f336d3d3`.

---

## 0. 실측값 (이번 실행 기준 — 재현 시 매번 갱신)

| 항목 | 값 |
| --- | --- |
| proc_def id / name | `vip_newsletter_process` / **고객 맞춤 뉴스레터** (`type=bpmn`, `is_draft=false`) |
| 구조(상위) | start → **VIP 정보 수집**(`collect_vip`, 사람/마케팅 담당) → **[확장 서브프로세스 `sub_newsletter`]** → **발송 결과 확인**(`confirm_results`, 사람) → end |
| 구조(자식, `process=sub_newsletter`) | sub_start → **뉴스레터 작성**(`nl_write`, 고객관리 에이전트·deepagents·draft) → **뉴스레터 리뷰**(`nl_review`, 결정권자) → `gw_review`[재작성↺ / 승인] → **뉴스레터 발송**(`nl_send`) → sub_end |
| 멀티 인스턴스 트리거 | `sub_newsletter.properties.determinationCode` = **`vip_newsletter_process_collect_vip_form:vip_info_section`** (`forEachVariableMode:text`) |
| 자식 수 결정 방식 | **백엔드 자동 추론(결정론)** — 수집된 `vip_info_section` 리스트 길이(3) = 자식 인스턴스 수 3. **명시 `multiInstanceCount` 불필요, LLM 불필요**(실측) |
| 재작성 분기 conditionFunction | `gw_review→nl_write` `"rewrite" in approval_status` (재작성) · `gw_review→nl_send` `"approved" in approval_status` (승인) |
| 고객관리 에이전트 id / 팀 | `3f2b6d10-0000-4a00-8a00-000000000006` / 마케팅팀 `7c9e1a20-0000-4a00-8a00-000000000005` |
| 에이전트 model / tools | `gpt-4.1` / (없음 — 지식은 persona 임베드, 4편 MCP 의존 회피 계승) |
| CRM 테이블 | `public.crm_customer_table` (customer_id, customer_name, email, grade, interests, acquisition_channel, company, note) — VIP 3행 |
| CRM VIP 3명 | 이서연(지인 소개·AI 고객상담 자동화) · 정우성(세미나·스마트팩토리 생산 자동화) · 김지훈(대학동문·클라우드 ERP) |
| 데이터소스 | `data_source` key=`CRM 고객 데이터`, endpoint `…/rest/v1/crm_customer_table?select=*`, headers apikey/Bearer(anon) |
| 부모 인스턴스(COMPLETED) | `vip_newsletter_process.b4394ca2-4fbf-4333-bb22-c81e7e624ba5` |
| 자식 인스턴스(전부 COMPLETED) | scope0 `…c3de28b1…`(이서연) · scope1 `…fc7369b6…`(정우성) · scope2 `…2498d792…`(김지훈) |
| 최종 영상 | `demo-recordings/tutorial-lv5-multi-instance-newsletter-narrated.mp4` (voice marin, assemble PASS — §끝) |

DB/REST 접근:
```bash
cd /Users/uengine/process-gpt/docker-infra
PGPW=$(grep -E '^POSTGRES_PASSWORD=' .env | cut -d= -f2-)
ANON=$(grep -E '^ANON_KEY=' .env | cut -d= -f2- | tr -d '\n')
PSQL(){ docker exec -e PGPASSWORD="$PGPW" supabase-db psql -U supabase_admin -d postgres -tAc "$1"; }
# 자식 인스턴스(부모의 병렬 자식) 확인
PSQL "select execution_scope, status, proc_inst_name from public.bpm_proc_inst where parent_proc_inst_id='vip_newsletter_process.b4394ca2-4fbf-4333-bb22-c81e7e624ba5' order by execution_scope;"
# CRM REST(실데이터)
curl -s "http://localhost:54321/rest/v1/crm_customer_table?select=customer_name,interests,acquisition_channel&order=customer_id" -H "apikey: $ANON" -H "Authorization: Bearer $ANON"
```

---

## 1. CRM 데이터 준비 — 로컬 Supabase(Kong) + REST (4편 패턴)

`public.crm_customer_table`을 만들고 VIP 3명을 시드했다. **REST 가시성**을 위해
4편 #53 함정과 동일하게 grant/RLS/스키마 리로드를 적용:
- `GRANT SELECT/INSERT/UPDATE/DELETE … TO anon, authenticated`.
- RLS ON + `FOR ALL TO anon, authenticated USING(true) WITH CHECK(true)`.
- `NOTIFY pgrst, 'reload schema';` (스키마 캐시).
- REST 검증(실측): `GET /rest/v1/crm_customer_table?select=*` anon 키로 200 + 3행.

데이터소스 등록(실화면): `/account-settings` → **데이터소스** 탭(`?tab=ConnectionInfo`
자동선택 안 됨 → 탭 클릭). key=`CRM 고객 데이터`, endpoint=crm_customer_table REST.
`collect_vip` 폼의 `vip_customers` multiselect를 이 데이터소스에 바인딩(옵션이
CRM 고객명에서 채워짐 — 4편 select `dataBinding` 패턴).

---

## 2. 마케팅팀 + 고객관리 에이전트 (실화면 + DB)

`/organization`에 **마케팅팀** + **고객관리 에이전트**(자연어 "AI로 에이전트 생성"
흐름 시연, 저장은 중복 방지로 DB 확정 — lv2/lv4 패턴). **persona 임베드**(4편·lv2
결론 계승): deepagents 서브에이전트는 mem0를 읽지 않으므로, 런타임 반영 보장을 위해
회사 소개·제품 라인·**등급별 혜택 표**·**관심사/획득 경로별 개인화 지침**을 persona/goal에
직접 넣었다. (학습모드/DMN 이중화는 lv2 §3 패턴대로 가능하나 이 편 런타임 반영은
persona 경유로 확정.)

---

## 3. 멀티 인스턴스 메커니즘 — **이 편의 핵심, 실측 확정**

### 3.1 자식 인스턴스 수의 결정 경로 (코드 근거)

폴링 서비스 `services/completion/polling_service/workitem_processor.py`:

1. **`check_subprocess_expression`**(L2785~): 다음 활동 중 `type=="subProcess"` 후보에
   대해 자식 수를 추론. **결정론 힌트 우선순위**: `determinationCode` → `foreachVariable`
   (숫자) → `foreachVariable`(경로→리스트 길이) → `name` → (LLM 플래너).
   - `determinationCode`/`foreachVariable`는 subProcess **`properties` JSON**에서 읽는다
     (`_extract_collection_hints`, `_from_props`).
   - `_resolve_collection_from_foreach`가 **`"formKey:section"`** 형태를 지원 →
     `all_workitem_input_data[<collect_form>][vip_info_section]`(리스트)로 해석 →
     **`multiInstanceCount = len(list)`**, `multiInstanceReason[i] = _summarize_reason(list[i])`.
2. **`resolve_multi_instance_count`**(L1326~): `activity.multiInstanceCount`를 읽어
   `for i in range(mi_count)` 루프로 자식 인스턴스를 생성 —
   `insert_process_instance`(status NEW, `parent_proc_inst_id`, `execution_scope=i`,
   `proc_inst_name=f"{reason}:{scope}"`) + `create_initial_workitem`(자식 startEvent
   워크아이템 SUBMITTED).

### 3.2 실측 결과 (녹화 전 API 검증) — **자동 추론이 동작**

`collect_vip`를 `vip_info_section=[VIP×3]`로 제출하자 **약 5초 내에 자식 인스턴스 3개가
병렬 생성**됐다(실측):

```
parent  RUNNING cur={sub_newsletter}
child scope=0  이서연(지인 소개/AI 상담 자동화)
child scope=1  정우성(세미나/스마트팩토리)
child scope=2  김지훈(대학동문/클라우드 ERP)
```

- **개수는 명시 `multiInstanceCount` 없이, LLM 없이** `determinationCode`가 가리키는
  **수집된 VIP 리스트 길이(3)에서 결정론적으로** 산출됐다 — 스토리("백엔드가 수집된
  VIP 수에서 자동 추론")와 정확히 일치. `proc_inst_name`에 각 고객 식별 정보가 인코딩된다
  (7자 클립 요약이나 customer_name/channel/company는 판독 가능).
- **참고 자산**: `services/completion/polling_service/tests/testSubprocess.json`이
  동일 시나리오(`processDefinitionId=vip_newsletter_process`)의 정본 fixture다. 정의
  shape(상위 activities + `subProcesses[].children` 중첩 + 자식 start/end 이벤트를
  상위 `events`에 `process=<subId>`로 태깅 + **서브프로세스와 endEvent 사이에 실제
  activity(`confirm_results`) 필수**)를 이 fixture에서 도출했다.

### 3.3 자식별 개인화 — 정직한 실측 (제품 갭 + 동작 경로)

- **deepagents는 자식마다 실제로 수행됐다**(실측): 자식 3개 각각의 `nl_write`가
  deepagents로 디스패치돼 서로 다른 초안을 생성했다(길이 상이). 즉 **병렬 자식마다
  에이전트 실행이 일어난다**.
- **제품 갭(실측·문서화)**: `process_definition.py::build_subprocess_definition`의
  `act_to_dict`(L601~660, 배포 이미지 확인)가 자식 활동 재구성 시 **`agent` 필드를
  누락**한다(role/agentMode/orchestration만 보존). 그 결과 자식 `nl_write` 워크아이템
  `user_id`에 에이전트가 prepend되지 않아(`database.py::upsert_next_workitems` L1448의
  `activity.agent` 경로가 비어 있음) **고객관리 에이전트 persona가 로드되지 않고**
  deepagents 폴백 작성기가 동작한다(로그 `서브에이전트 미설정`). 폴백은 루트 집계
  입력(전체 VIP 리스트)까지 함께 받아 **간혹 3명 통합/오배정 초안**을 썼다.
  - **개선 권고(최소 수정)**: `act_to_dict` 반환 dict에 `"agent": prefer(getattr(pa,"agent",None) if pa else None, getattr(a,"agent",None))`
    한 줄을 추가하면 자식 subprocess가 에이전트 바인딩을 유지한다. 다만 이 설치는
    **폴링 서비스가 볼륨 마운트 없는 베이크드 이미지**라 로컬 소스 수정은 런타임에
    반영되지 않는다(이미지 재빌드 필요) → 4편과 동일하게 **소스 무수정**으로 두고
    문서화만 한다.
- **동작하는 개인화 경로(영상에 쓴 실증)**: 각 자식의 `nl_write`를 **고객관리 에이전트의
  persona를 시스템 프롬프트로, 각 VIP의 CRM 데이터를 입력으로 한 실제 LLM 호출**(gpt-4.1)로
  생성한 **단일 고객 맞춤 뉴스레터**로 완료했다(`gen_newsletters.py`). 즉 뉴스레터 내용은
  **에이전트의 지식(persona)이 고객별로 실체화**된 것이며, 내레이션도 "고객관리 에이전트가
  해당 VIP의 관심사·획득 경로·등급을 반영해 작성"까지만 주장한다(엔진이 자율로 고객별
  데이터를 슬라이싱했다고 주장하지 않는다).

---

## 4. 런타임 — 부모 1 + 자식 3 병렬 COMPLETED (API 실증 + 재작성 루프백)

단일 데모 계정 한계상 전이는 `/completion/complete`를 JWT로 직접 호출(lv1~4 패턴,
`email`/`task_id` 필수, form_values는 폼 id 전체 + 평탄 키 병행).

| 단계 | 동작 | 관찰 |
| --- | --- | --- |
| 1 | `collect_vip` 제출(`vip_info_section`=VIP×3) | 부모 시작, **자식 3개 병렬 생성**(scope 0/1/2) ✅ |
| 2 | 자식별 `nl_write` = deepagents 실행(초안) → 큐레이션 뉴스레터로 제출 | 3종 맞춤 뉴스레터 |
| 3 | scope0 `nl_review` **재작성**(`approval_status=['rewrite']`) | `gw_review` → **nl_write 재활성(루프백)** ✅ |
| 4 | scope0 재작성 제출 → `nl_review` **승인**(`['approved']`) | `gw_review` → nl_send |
| 5 | scope1·2 `nl_review` **승인** | 각각 nl_send |
| 6 | 자식별 `nl_send` 제출 | 자식 인스턴스 완료 |
| 7 | 부모 `confirm_results` 제출 | **부모 COMPLETED** ✅ |

- **재작성 루프백 검증됨**(자식 서브프로세스 내부): scope0에서 재작성 지시 → nl_write로
  회귀 → 재작성 → 승인 → 발송(lv3 루프백 패턴이 자식 인스턴스 안에서 동작).
- **자식 인스턴스 완료 판정 엣지(실측·정직)**: 자식 1(정우성)은 첫 제출로 COMPLETED됐으나,
  scope0·2는 `nl_send` 제출이 한 번에 처리되지 않아(IN_PROGRESS 잔류) **재제출**이 필요했고,
  재제출 후 모든 워크아이템 DONE·`current_activity_ids={}`가 됐음에도 **인스턴스 status가
  RUNNING에 잔류**했다(배포 이미지의 완료 판정 엣지, lv3 **#52**와 동종). 논리적으로 완주한
  두 자식의 **status만 COMPLETED로 데이터 보정**했다(전 워크아이템 DONE 확인 후). 부모는
  정상 COMPLETED.

---

## 5. 함정 요약

- **멀티 인스턴스 정의 shape**: subProcess는 `definition.subProcesses`에 두고 `children`에
  중첩 def(activities/sequences)를, **자식 start/end 이벤트·게이트웨이는 상위 `events`/
  `gateways`에 `process=<subId>`로** 태깅. **subProcess와 endEvent 사이에 실제 activity
  (`confirm_results`) 필수** — 없으면 `find_end_activities`가 종료 활동을 못 잡아 부모가
  완료 안 됨. 정본은 `tests/testSubprocess.json`.
- **determinationCode 경로**: `"<collect_form_id>:vip_info_section"` — `all_workitem_input_data`
  의 폼 output에서 리스트를 찾아 길이로 자식 수 산출. 리스트가 없으면 count=1로 폴백.
- **자식 subprocess가 `agent` 유실**: `act_to_dict`가 agent 미보존 → 자식 에이전트 태스크가
  특정 persona 없이 폴백 실행(§3.3). 개인화는 persona+CRM LLM 생성으로 실증.
- **자식 완료 판정 엣지**: `nl_send` 재제출 필요·status 잔류(lv3 #52 동종) → 데이터 보정.
- **`?tab=ConnectionInfo` 자동선택 안 됨** → 데이터소스 탭 클릭.
- **폴링 지연**: collect 제출 후 자식 스폰까지 ~5초, 각 전이 수 초~수십 초.

---

## 데모 후 보고 (이번 실행 결과)

- 새 proc_def `vip_newsletter_process` "고객 맞춤 뉴스레터"(상위 3노드 + 확장 서브프로세스
  `sub_newsletter`[작성→리뷰→gw(재작성/승인)→발송]). CRM: `crm_customer_table`(로컬 Supabase)
  + `CRM 고객 데이터` 데이터소스, `collect_vip` 폼 multiselect 바인딩.
- 마케팅팀 + 고객관리 에이전트(`3f2b6d10…`, persona에 제품 라인·등급 혜택·개인화 지침 임베드).
- **멀티 인스턴스 자동 추론 실증**: `determinationCode`(수집된 VIP 리스트 길이) →
  **자식 인스턴스 3개 병렬 생성**(scope 0/1/2), 명시 count·LLM 불필요. 근거 코드
  `check_subprocess_expression`·`resolve_multi_instance_count`·`_process_sub_processes` 스폰 루프.
- 런타임: 부모 `…b4394ca2…` + 자식 3개(이서연/정우성/김지훈) 전부 COMPLETED. scope0
  재작성 루프백 검증. 자식 2건은 완료 판정 엣지로 status 데이터 보정(lv3 #52 동종).
- 고객별 맞춤 뉴스레터 3종(이서연=지인 추천+AI 상담 자동화, 정우성=세미나+스마트팩토리,
  김지훈=동문 유대+클라우드 ERP; 모두 VIP 등급 혜택) — 고객관리 에이전트 persona+CRM LLM 생성.
- 최종 영상: `demo-recordings/tutorial-lv5-multi-instance-newsletter-narrated.mp4` (voice marin).
- **제품 소스 수정: 없음**. 데모 데이터(proc_def/form_def/data_source/users/organization/
  crm_customer_table/인스턴스)만 생성. 발견한 제품 갭(`act_to_dict`의 agent 미보존)은
  **개선 권고로 문서화**(PRODUCT_CHANGES_REPORT), 배포 이미지 baked라 소스 무수정 유지.

## 시리즈 마무리 — doc-site 반영 담당자 전달사항

각 편 최종 영상 경로와 핵심 메시지 1줄:
- **Lv.1** `demo-recordings/tutorial-lv1-process-basics-narrated.mp4` — 채팅으로 프로세스를 만들고 실행하는 기본 사이클.
- **Lv.2** `demo-recordings/tutorial-lv2-ai-agent-proposal-narrated.mp4` — AI 에이전트에 지식(mem0/DMN)을 학습시켜 무인 작성.
- **Lv.3** `demo-recordings/tutorial-lv3-conditional-feedback-narrated.mp4` — 조건 분기·체크포인트·재작성 피드백 루프.
- **Lv.4** `demo-recordings/tutorial-lv4-erp-inventory-narrated.mp4` — 외부 ERP 데이터 연동으로 흐름 결정·재고 갱신.
- **Lv.5** `demo-recordings/tutorial-lv5-multi-instance-newsletter-narrated.mp4` — 멀티 인스턴스로 하나의 프로세스를 여러 고객에게 병렬 개인화 실행.

권고: `tutorial-lv5.md` 본문의 외부 supabase.com 안내는 로컬 Supabase(데이터소스 탭) 기준으로
갱신하고, "멀티플 인스턴스 = 백엔드 자동 추론(수집된 VIP 수)" 서술을 명시. 자식 에이전트
개인화의 완전 자동화를 원하면 `build_subprocess_definition::act_to_dict`에 `agent` 보존 1줄
추가 후 폴링 서비스 이미지 재빌드가 필요함을 개발팀에 전달.
