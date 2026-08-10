# WMS MCP × Claude Skill — 실습 시나리오 5선

> 대상: "스킬이 뭔지" 처음 배우는 학생/실무자
> 전제: `services/sample-app-wms/mcp` (wms-mcp, 83 tools) 가 떠 있고 Claude Code 에 MCP 로 연결되어 있음

---

## 0-0. 실습 환경 준비 (MCP 연결)

### 1) `.mcp.json` — 프로젝트 루트에 이미 설정되어 있음

```json
{
  "mcpServers": {
    "wms":    { "type": "http", "url": "http://localhost:8199/mcp" },
    "office": { "type": "http", "url": "http://localhost:1192/mcp" }
  }
}
```

- `wms` — 이 문서의 시나리오 1~5 전부가 쓰는 **필수** 서버 (83 tools)
- `office` — 시나리오 3/5 의 `generate_docx` / `generate_hwpx` (국내 공공 제출용 한글 문서) 전용. **선택**
  - DOCX/PPTX 만 필요하면 `docx`·`pptx` 스킬로 충분하므로 이 블록은 지워도 된다

`.mcp.json` 은 프로젝트 스코프라 팀원이 리포를 클론하면 그대로 따라온다.
Claude Code 는 **최초 1회 "이 프로젝트의 MCP 서버를 신뢰할까?" 를 묻는다** — 승인해야 툴이 붙는다.

### 2) 백엔드 기동 (순서 중요)

```bash
# ① Supabase — wms 스키마/RLS/RPC. 이게 없으면 MCP 는 떠도 모든 툴이 Connection refused
cd services/sample-app-wms/supabase && supabase start
#   출력된 anon key 를 ../mcp/.env 의 SUPABASE_ANON_KEY 에 넣는다

# ② wms-mcp
cd ../mcp && pip install -r requirements.txt && cp .env.example .env
python main.py            # → http://localhost:8199/mcp

# ③ (선택) office-mcp — HWPX 가 필요할 때만
cd ../../office-mcp && cp .env.example .env    # SUPABASE_*, LLM key 필요
python main.py            # → http://localhost:1192/mcp
```

### 3) 연결 확인

```bash
# Claude Code 안에서
/mcp                      # wms 가 connected 로 뜨고 tools 83 개가 보이면 성공

# 터미널에서 직접 확인하고 싶다면
curl -s -X POST http://localhost:8199/mcp \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' | head -c 300
```

첫 스모크 테스트 — Claude Code 에 그냥 이렇게 쳐 보면 된다:

```
A창고 설비 상태 조회해줘 (tenant 10000000-0000-0000-0000-00000000000a,
warehouse 20000000-0000-0000-0000-00000000000a)
```

### 4) 실습용 데모 ID (seed.sql 고정값)

| 항목 | 값 |
|---|---|
| Tenant A | `10000000-0000-0000-0000-00000000000a` |
| Warehouse A (WH-A1) | `20000000-0000-0000-0000-00000000000a` |
| Tenant B (RLS 격리 실습용) | `10000000-0000-0000-0000-00000000000b` |
| Warehouse B (WH-B1) | `20000000-0000-0000-0000-00000000000b` |
| 데모 SKU | `SKU-A-001` ~ `SKU-A-003` |
| 로그인 (전부 `Demo1234!`) | `admin-a@` / `buyer-a@` / `approver-a@` / `inbound-a@` / `quality-a@` / `wh-manager-a@` / `wcs-operator-a@` / `auditor-a@demo.local` |

> 스킬을 만들 때 이 ID 들을 SKILL.md 에 하드코딩하지 말고
> `references/demo-env.md` 로 빼두면, 운영 테넌트로 옮길 때 스킬 본문을 안 고쳐도 된다.

### 5) 권한 프롬프트 줄이기

`.claude/settings.json` 에 **읽기 전용 WMS 툴만** 미리 허용해 두었다
(`mcp__wms__get_*`, `mcp__wms__query_audit_log`). 시나리오 1·3 은 승인 클릭 없이 바로 돈다.

쓰기 툴(`register_*`, `dispatch_*`, `apply_*`, `resolve_*` …)은 **일부러 빼 두었다** —
학생이 "지금 시스템에 실제로 쓰는 중" 을 매번 눈으로 확인하게 하는 것이 교육 목적상 낫다.

---

## 0. 먼저 개념 — 프롬프트 / 스킬 / MCP / 프로세스

같은 일을 시키는 4가지 층위가 있고, **무엇을 어디에 두느냐**가 이 실습의 핵심입니다.

| 층위 | 정체 | 예 | 재사용성 |
|---|---|---|---|
| **프롬프트** | 그때그때 치는 자연어 | "설비 상태 보고 지연된 웨이브 알려줘" | 없음 (매번 다시 침) |
| **MCP** | 시스템이 제공하는 **동사(도구)** | `get_equipment_status`, `dispatch_palletize_command` | 높음, 단 "한 번의 동작"뿐 |
| **스킬** | 그 동사들을 엮는 **절차 + 판단 기준 + 산출물 규격** | `wms-daily-briefing` | 높음, 이름으로 불러 씀 |
| **프로세스(BPMN)** | 사람·기한·결재가 붙은 **조직의 공식 흐름** | `wms_replenishment_process` | 조직 전체, 감사 가능 |

핵심 문장 한 줄:

> **MCP 는 "무엇을 할 수 있는가", 스킬은 "우리 회사에선 그걸 이렇게 한다".**

MCP 툴 84개를 다 외워서 매번 순서대로 부르라고 프롬프트를 치는 건 사람이 할 짓이 아닙니다.
"이 순서로, 이 검증을 거쳐, 이 포맷으로" 를 한 번 적어두고 이름을 붙인 것이 **스킬**입니다.

스킬 하나는 이렇게 생겼습니다:

```
.claude/skills/wms-daily-briefing/
  SKILL.md          ← 언제 트리거되는가(description) + 절차(본문)
  references/       ← 판단 기준표, 사내 규칙 (필요할 때만 읽힘)
  scripts/          ← 반복 계산은 코드로 (토큰 절약 + 결정론적)
```

---

## 시나리오 1 — 아침 현황 브리핑 (난이도 ★)

**스킬명**: `wms-daily-briefing`
**한 줄**: 매일 아침 팀장이 5번씩 치던 조회 프롬프트를 한 단어로 줄인다.
**성격**: 읽기 전용, MCP 조회 N회 + 고정 포맷 요약. **스킬의 최소 형태.**

### 지금(스킬 없이) 하는 일

```
"A창고 설비 상태 보여줘"          → get_equipment_status
"작업오더 밀린 거 있어?"          → get_work_order_status
"웨이브 지연 신호 뽑아줘"          → get_dispatch_delay_signals
"인력 쏠림은?"                    → get_labor_balance_signals
"오늘 도크 예약 어떻게 돼?"        → get_dock_schedule
"...이거 다 합쳐서 3줄로 요약해줘"
```

매일 아침 6번. 사람이 바뀌면 순서도 기준도 바뀜.

### 스킬로 굳히면

```
사용자: /wms-daily-briefing A창고
```

SKILL.md 가 규정하는 것:

```
1) 병렬 조회
   get_equipment_status(tenant_id, warehouse_id, event_limit=20)
   get_work_order_status(tenant_id, warehouse_id)
   get_dispatch_delay_signals(tenant_id, warehouse_id, delay_threshold_minutes=30)
   get_labor_balance_signals(tenant_id, warehouse_id)   # 기본 최근 24h
   get_dock_schedule(tenant_id, warehouse_id, from_ts=오늘00:00, to_ts=오늘24:00)

2) 판정 기준 (references/thresholds.md — 사내 룰)
   🔴 BLOCKING 장애 1건 이상 | 지연 웨이브 3건 이상 | 도크 이중예약
   🟡 MAINTENANCE 설비 존재 | 인력 편차 > 30%
   🟢 그 외

3) 출력 포맷 (항상 동일)
   [신호등] 한 줄 결론 → 조치 필요 항목 3개 → 상세 표
```

### 학생에게 심어줄 것

- 스킬 = **절차의 고정** + **판단 기준의 고정** + **출력 포맷의 고정**
- `description` 이 곧 트리거다. "브리핑", "아침 현황", "창고 상태" 를 넣어야 자연어로도 불림
- 조회만 하는 스킬은 안전하다 → **첫 스킬은 항상 읽기 전용으로 만들어라**

---

## 시나리오 2 — 엑셀 수기입력 자동화 (난이도 ★★)

**스킬명**: `wms-bulk-onboarding`
**한 줄**: 신규 창고 오픈 때 손으로 300줄 치던 마스터 등록을 엑셀 한 장으로 끝낸다.
**성격**: **쓰기(write)** 스킬. 검증 → dry_run → 실행 → 실패 리포트 루프.

### 지금 하는 일

신규 창고 오픈 시 담당자가 엑셀을 보며 관리화면에 손으로 입력:
설비 40대, 도크 8개, 보관위치 250개, SKU-위치 배정 180건. 반나절 + 오타.

### 스킬로 굳히면

```
사용자: 이 엑셀로 B창고 마스터 등록해줘  [warehouse-b-master.xlsx 첨부]
```

```
1) 파싱 & 컬럼 매핑
   시트별로 대상 MCP 툴 결정
     [설비]     → register_equipment(equipment_code, equipment_type, ...)
     [도크]     → register_dock(code, name)
     [보관위치] → register_storage_location(zone_code, location_code, accessibility_rank)
     [SKU배정] → assign_sku_location(product_id, location_id)
   컬럼명이 사내 표준과 다르면 references/column-aliases.md 로 자동 매핑

2) 사전 검증 (MCP 호출 전)
   - 필수값 누락 / enum 위반(equipment_type ∈ SRM|CONVEYOR|SORTER|AGV|AMR|ROBOT_CELL)
   - 파일 내부 중복 코드
   → 위반 행은 실행 대상에서 빼고 목록화

3) dry_run 리허설
   각 툴을 dry_run=True 로 먼저 전량 호출 → 서버측 거부 예상 건 확보
   사용자에게 "정상 268 / 거부 예상 12" 요약 후 AskUserQuestion 으로 진행 확인

4) 실제 실행
   idempotency_key = f"{파일해시}:{시트}:{행번호}"   ← 중간에 끊겨도 재실행 안전
   행 단위로 호출, 실패해도 전체 중단하지 않음

5) 결과 리포트
   성공/실패/스킵을 원본 시트에 열 3개 붙여 xlsx 로 반환
   (실패 행만 고쳐서 같은 스킬을 다시 돌리면 멱등키 덕분에 성공분은 재등록되지 않음)
```

### 학생에게 심어줄 것

- **dry_run 과 idempotency_key 는 이 MCP 가 준 안전장치** — 스킬이 그걸 "항상 쓰도록" 강제하는 자리
- 부분 실패를 예외로 보지 말고 **정상 경로로 설계**하라 (전부 롤백 vs 실패목록 반환)
- 사람 확인 지점(AskUserQuestion)을 스킬이 정해준다 → 매번 "진행할까요?" 를 판단하지 않아도 됨

---

## 시나리오 3 — 주간 운영 리포트 PPTX/DOCX (난이도 ★★★)

**스킬명**: `wms-ops-report`
**한 줄**: 데이터를 뽑는 스킬과 문서를 만드는 스킬을 **연결**한다.
**성격**: **스킬이 다른 스킬을 부르는 첫 사례.**

### 지금 하는 일

주간 회의 자료를 만들려고 조회 결과를 복사 → 엑셀 → 차트 → PPT 붙여넣기. 2~3시간.

### 스킬로 굳히면

```
사용자: 지난주 A창고 운영 리포트 PPTX 로 뽑아줘
```

```
1) 데이터 수집 (wms-ops-report 본체)
   get_labor_productivity(period_start, period_end)
   get_labor_leaderboard(period_start, period_end)
   compute_sku_velocity(window_start, window_end)   → batch_id 확보
   get_dispatch_sequence_status(...)                → 웨이브 처리량/서열 준수율
   get_equipment_status(event_limit=200)            → 가동률/장애 이력
   query_audit_log(date_from, date_to)              → 승인·반려·예외 건수

2) 지표 계산은 스크립트로
   scripts/aggregate.py 가 원시 JSON → 주차별 지표 테이블
   (LLM 이 숫자를 손으로 더하지 않게 한다 — 결정론적 + 토큰 절약)

3) 차트 규격은 dataviz 스킬에 위임
   Skill(dataviz) → 색상·축·범례 규칙을 받아 SVG/PNG 생성

4) 문서 조립은 표현 스킬에 위임
   PPTX 요청 → Skill(pptx)
   DOCX 요청 → Skill(docx)  또는  office-mcp 의 generate_docx
   HWPX 요청 → office-mcp 의 generate_hwpx      ← 국내 공공 제출용
   슬라이드 구성(표지/신호등/지표 4장/이슈/부록)은 references/report-outline.md 고정
```

### 학생에게 심어줄 것 — **스킬 조합 3패턴**

```
① 위임(delegate)      wms-ops-report ──Skill()──▶ pptx
                      "내가 데이터, 너는 표현" — 관심사 분리

② 팬아웃(fan-out)     wms-ops-report ──▶ dataviz (차트 6장 병렬)

③ 산출물 핸드오프      wms-ops-report 가 만든 report.json 을
                      다음 스킬의 입력 파일로 넘김 (대화 컨텍스트 대신 파일로)
```

> 원칙: **도메인 스킬(WMS 를 아는 것)과 표현 스킬(문서를 아는 것)을 절대 한 덩어리로 만들지 마라.**
> pptx 스킬은 WMS 를 몰라야 재사용되고, wms-ops-report 는 PPTX 문법을 몰라야 HWPX 로 갈아탈 수 있다.

---

## 시나리오 4 — 슬로팅 최적화 제안·승인·적용 (난이도 ★★★★)

**스킬명**: `wms-slotting-optimizer`
**한 줄**: 분석 → 제안 → **사람 승인** → 적용까지 한 흐름으로. 감사 근거까지 남긴다.
**성격**: HITL(Human-in-the-loop) + 낙관적 동시성(expected_version) + 상태머신.

### 지금 하는 일

물류 컨설턴트가 분기에 한 번 오는데, 그 사이 A등급 SKU 가 창고 안쪽에 방치됨.

### 스킬로 굳히면

```
사용자: A창고 최근 3개월 기준으로 슬로팅 최적화 돌려줘
```

```
1) 속도 등급 산출
   compute_sku_velocity(window_start=90일전, window_end=오늘)  → velocity_batch_id

2) 정책 확인 / 없으면 등록 유도
   register_slotting_class_policy(velocity_class='A', max_accessibility_rank=3)
   (A등급은 접근성 3순위 이내에 있어야 한다 — 사내 규칙)

3) 추천 생성
   generate_slotting_recommendations(velocity_batch_id)
   → "SKU-1042 를 BULK_STORAGE(rank 9) → PACK_ADJACENT(rank 2) 로" 형태 N건

4) 판단 근거를 시스템에 기록  ★ 스킬이 반드시 하게 만드는 부분
   log_agent_decision(reasoning="90일 출고 상위 8%인데 rank 9 …", proposal_type='SLOTTING')
   propose_agent_action(proposal_type='SLOTTING_MOVE', reasoning=..., ...)
   → 나중에 "AI 가 왜 이렇게 했냐" 는 질문에 감사로그로 답할 수 있게 됨

5) 사람 승인 (건별 아님 — 묶어서 한 번)
   상위 임팩트 10건을 표로 제시 → AskUserQuestion
   승인분:  review_slotting_recommendation(decision='APPROVE', expected_version=N)
   반려분:  review_slotting_recommendation(decision='REJECT',  review_reason=...)
            reject_agent_proposal(reason=...)   ← 반려 사유는 필수

6) 적용
   apply_slotting_recommendation(recommendation_id, expected_version)
   confirm_agent_proposal(decision_id, expected_version)
   버전 충돌(다른 사람이 먼저 옮김) → 재조회 후 1회 재시도, 그래도 충돌이면 사람에게 보고

7) 사후 문서   ← 시나리오 3 재사용
   Skill(wms-ops-report) 에 "슬로팅 변경 근거서" 템플릿으로 DOCX 생성 위임
```

### 학생에게 심어줄 것

- **expected_version 은 협업 시스템의 기본기.** 스킬이 "조회 → 버전 확보 → 쓰기 → 충돌 시 1회 재시도" 를 절차로 못 박는다
- **사람 개입 지점을 스킬이 설계한다.** 10건마다 물어보면 아무도 안 씀 / 한 번도 안 물어보면 아무도 못 믿음
- `log_agent_decision` / `propose_agent_action` — **AI 의 판단을 시스템 기록으로 남기는 습관.** 이게 있어야 자동화가 조직에서 승인된다

---

## 시나리오 5 — 설비 장애·병목 대응 오케스트레이션 (난이도 ★★★★★)

**스킬명**: `wms-incident-response`
**한 줄**: 여러 스킬을 지휘하고, 위험한 조치는 **시뮬레이터로 먼저 리허설**하고, 끝나면 이 절차 자체를 BPMN 프로세스로 승격한다.
**성격**: 오케스트레이터 스킬. 스킬 → 스킬 → 스킬, 그리고 스킬 → 프로세스.

### 상황

야간에 SORTER-02 가 `SORTATION_JAM` 으로 멈춤. 웨이브 3개가 물리고, 팔레타이징 로봇셀은 대기, 아침 출고 트럭 도크 예약은 그대로.

### 스킬로 굳히면

```
사용자: SORTER-02 장애 대응해줘
```

```
[1] 진단
    get_equipment_status(equipment_id=SORTER-02, event_limit=100)
    get_equipment_routing_status(...)        → 병목 판정/큐 깊이
    get_dispatch_delay_signals(...)          → 영향받는 웨이브
    get_work_order_status(...)               → 물린 작업오더
    get_dock_schedule(...)                   → 아침 출고 데드라인 역산

[2] 조치안 수립 → 시뮬레이터로 리허설  ★ 이 시나리오의 하이라이트
    create_simulation_scenario(name='SORTER-02 우회안', equipment_ids=[...])
    run_simulation_scenario(scenario_id)
    get_simulation_scenario_status(scenario_id)
    → "우회 시 처리량 -18%, 도크 08:00 마감 충족" 을 확인하고 나서 실물에 손댐
    (안 되면 조치안 B 로 다시 리허설)

[3] 실제 조치 (승인 후)
    exclude_equipment_from_routing(equipment_id=SORTER-02, reason='SORTATION_JAM 대응')
    cancel_equipment_command(...)            → 물려있는 명령 정리
    retry_work_order_dispatch(...)           → 우회 경로로 재투입
    assign_dispatch_sequence(...) / cancel_dispatch_sequence(...)
    dispatch_palletize_command(equipment_id=ROBOT-CELL-01, wave_id, target_pallet_code)
    get_pallet_manifest(...)                 → 재배정 결과 검증

[4] 복구
    resolve_equipment_fault(fault_id, resolution_note, expected_version)
    clear_equipment_routing_exclusion(override_id, expected_version)
    report_equipment_status(equipment_id, new_status='IDLE', expected_version)

[5] 사후 — 여기서 다른 스킬들을 부른다
    query_audit_log / export_audit_log(date_from=장애시각, ...)
    Skill(wms-ops-report)  → 인시던트 보고서 DOCX (타임라인·영향·조치·재발방지)
    Skill(wms-daily-briefing) → 다음 아침 브리핑에 "어제 인시던트" 섹션 자동 포함

[6] 승격  ★★ 마지막 교육 포인트
    Skill(bpmn-process-generation-skill)
    → 방금 실행한 이 절차를 ProcessGPT 의 정식 BPMN 프로세스로 만든다
       (감지 → 진단 → 시뮬 → 승인 게이트 → 조치 → 복구 → 보고)
       사람 담당자·SLA·결재선이 붙고, 다음부터는 프로세스가 이 스킬을 호출한다
```

### 학생에게 심어줄 것

- **오케스트레이터 스킬은 자기가 일을 다 하지 않는다.** 순서·게이트·중단조건만 갖고 나머지는 위임
- **위험한 쓰기 전에 시뮬레이션.** 이 MCP 는 `create/run/get_simulation_scenario` 로 리허설 경로를 제공한다 — 스킬이 그걸 "건너뛸 수 없게" 만든다
- **스킬의 최종 목적지는 프로세스다.** 개인이 반복하면 스킬, 조직이 반복하면 프로세스(BPMN). 스킬 → 프로세스 승격 경로가 있다는 게 ProcessGPT 의 차별점

---

## 난이도 사다리 한눈에

| # | 스킬 | 난이도 | 새로 배우는 것 | 주 MCP 툴 | 부르는 다른 스킬 |
|---|---|---|---|---|---|
| 1 | `wms-daily-briefing` | ★ | 절차·기준·포맷의 고정 | 조회 5종 | — |
| 2 | `wms-bulk-onboarding` | ★★ | dry_run · 멱등키 · 부분실패 | register_* / assign_* | (xlsx) |
| 3 | `wms-ops-report` | ★★★ | **스킬이 스킬을 호출** | 집계·감사 조회 | dataviz, pptx, docx |
| 4 | `wms-slotting-optimizer` | ★★★★ | HITL · expected_version · 판단기록 | slotting 7종 + agent_decision | wms-ops-report |
| 5 | `wms-incident-response` | ★★★★★ | 오케스트레이션 · 시뮬 리허설 · **프로세스 승격** | WCS/WES/시뮬 전역 | 위 전부 + bpmn 생성 |

---

## 부록 A — 다른 스킬을 부르는 3가지 방법

```
① 명시적 호출 (권장, 오케스트레이터가 쓰는 방식)
   SKILL.md 안에:  "차트가 필요하면 Skill 툴로 `dataviz` 를 호출한다"
   → 결정론적. 학생에게 가르칠 기본형.

② 자연어 트리거 (사용자가 쓰는 방식)
   description 에 트리거 어휘를 충분히 박아둔다:
     "…'브리핑', '아침 현황', '창고 상태 알려줘' 라고 하면 반드시 이 스킬을 사용하라"
   → description 이 부실하면 스킬은 있어도 안 불린다. 가장 흔한 실패 원인.

③ 슬래시 커맨드
   /wms-daily-briefing A창고
   → 사용자가 확실히 그 스킬을 원할 때. 데모/시연에 좋다.
```

## 부록 B — 스킬로 만들 값어치가 있는지 판별하는 3문항

1. **두 번 이상 같은 순서로 했는가?** (아니면 그냥 프롬프트)
2. **사람마다 결과가 달라지면 곤란한가?** (그렇다면 판단 기준을 스킬에 박아라)
3. **다른 사람에게 설명해야 하는가?** (설명문 = 곧 SKILL.md 본문)

## 부록 C — 흔한 안티패턴

| 안티패턴 | 왜 나쁜가 | 대신 |
|---|---|---|
| MCP 툴 하나를 그대로 감싼 스킬 | 스킬의 부가가치 0 | 최소 3~4 호출을 엮고 판단 기준을 넣어라 |
| 도메인 + 문서 포맷을 한 스킬에 | HWPX 요청 오면 통째로 재작성 | 도메인/표현 분리 (시나리오 3) |
| 숫자 집계를 LLM 이 직접 | 비결정론적 + 토큰 낭비 | `scripts/` 에 코드로 |
| dry_run 없이 대량 쓰기 | 300건 잘못 들어감 | 리허설 → 확인 → 실행 |
| description 이 한 줄 | 자연어로 트리거 안 됨 | 사용자가 쓸 표현을 5개 이상 나열 |
