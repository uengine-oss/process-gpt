# 구현 작업: Supabase 기반 ProcessGPT WMS·경량 구매 ERP

## 진행 상황 (2026-07-26): 데모 우선 핵심 수직 slice

구현은 별도 저장소 `process-gpt-sample-app-wms`(로컬 git repo, `services/sample-app-wms`에
submodule로 편입 예정 — 원격 저장소는 아직 미생성)에서 진행 중이다. 아래 55개 항목은
엔터프라이즈 전체 백로그이며, 이번 세션은 **사용자가 명시적으로 선택한 "데모 우선
핵심 수직 slice"**(부족감지→RFQ→HITL승인→PO→입고→검수→폐기/적치 전체 흐름을 실제로
작동시키되, 동시성/오프라인 PWA/대규모 적치/Odoo 실 데이터 이관/출고·반품·실사·추적성은
생략)만 다룬다. 완전 이행이 아니므로 아래 체크박스는 그대로 두고, 이 slice가 실제로
구현한 부분은 각 항목 아래 인용줄로 표시한다. 상세 근거는
`services/sample-app-wms/docs/{01-baseline-scope,02-contracts,03-processgpt-integration}.md`.

**로컬 검증 완료**: Supabase 로컬 인스턴스(migration+RLS+9개 RPC)를 psql로 happy path·
교차 테넌트 RLS 차단·역할 기반 FORBIDDEN·낙관적 동시성 CONFLICT·멱등성까지 확인했고,
Vue 프론트엔드는 Playwright E2E(`frontend/playwright/e2e/wms-flow.spec.ts`, 5개 역할
로그인 전환 포함 전체 흐름)가 통과했으며, wms-mcp는 fastmcp Client로 도구 3종 실호출을
확인했다. 구체적으로 확인한 버그 2건(프론트엔드 RPC 함수명 불일치, supabase-py
ClientOptions import 오류)은 수정 완료.

**미착수/의도적 생략** (엔터프라이즈 전체 범위 대비): 8장(출고/반품/실사/추적성) 전체,
7.3–7.5(모바일 PWA·오프라인 큐·실단말 테스트), 11.2–11.6(백업/PITR, Odoo 실 이관,
shadow run, 부하/동시성 테스트) — 그린필드 데모이므로 이관 자체가 해당 없음.

## 1. 기준선과 계약 확정

- [ ] 1.1 1차 운영 범위, 창고 수, 테넌트 수, 상품·주문·원장 예상 건수와 가용성 목표를 확정한다.
- [ ] 1.2 BPMN의 각 활동을 WMS MCP 도구, 입력·출력 스키마, 보상 명령에 매핑한다.
- [ ] 1.3 Odoo 객체와 새 WMS 객체의 필드·상태·식별자 매핑표 및 cutover 기준을 승인한다.
- [ ] 1.4 업무 용어집과 상태 enum을 확정하고 OpenAPI/JSON Schema 계약을 생성한다.

## 2. Supabase 기반 구축

- [ ] 2.1 `wms` 스키마, 공통 ID·감사·버전 컬럼, enum, migration 검증 환경을 만든다.
- [ ] 2.2 Supabase Auth claim, 테넌트 membership, 창고 scope, 역할과 RLS helper 함수를 구현한다.
- [ ] 2.3 익명·교차 테넌트·교차 창고 접근을 차단하는 RLS 테스트를 작성한다.
- [ ] 2.4 private Realtime Broadcast topic과 Storage bucket/policy를 구성한다.
- [ ] 2.5 `integration_outbox`, inbox, idempotency, audit와 worker/Edge Function 재시도 기반을 구현한다.

## 3. 기준정보와 권한

- [ ] 3.1 `wms_master-data` 명세에 따라 회사·창고·존·로케이션·도크 모델과 관리 API를 구현한다.
- [ ] 3.2 상품·UOM·포장·바코드·lot/serial 정책과 공급사·공급조건 모델을 구현한다.
- [ ] 3.3 위치 용량·상품 호환성·putaway/removal/reorder 규칙 유효성 검사를 구현한다.
- [ ] 3.4 `wms_tenant-access-control` 명세에 따라 사용자·서비스 계정 권한과 위험 명령 승인을 구현한다.

## 4. 재고 원장

- [ ] 4.1 `wms_inventory-ledger`의 movement, ledger entry, balance projection, hold, reservation 모델을 구현한다.
- [ ] 4.2 원자적 이동·예약·해제·조정 RPC와 expected version 및 idempotency 검사를 구현한다.
- [ ] 4.3 가용·예정·격리 수량 조회 view와 원인 문서별 원장 timeline을 구현한다.
- [ ] 4.4 동시 예약, 중복 재시도, 단위 환산, 음수 재고 방지 property/integration 테스트를 작성한다.

## 5. 재보충과 구매

- [ ] 5.1 `wms_replenishment-planning`의 Min/Max·안전재고·리드타임 규칙과 부족 계산 job을 구현한다.
- [ ] 5.2 제안의 계산 근거, 중복 병합, 수동 수정·승인과 구매 요청 전환을 구현한다.
- [ ] 5.3 `wms_purchase-ordering`의 RFQ, 견적 비교, 승인, PO 확정·변경·취소를 구현한다.
- [ ] 5.4 금액·품목·공급사별 승인 정책과 공급사 통지 outbox를 구현한다.
- [ ] 5.5 부분 입고와 미입고 잔량, 납기 변경, 입고·송장 대조용 수량 투영을 검증한다.

## 6. 입고·품질·적치

- [ ] 6.1 `wms_inbound-receiving`의 ASN, 입하 예정, 도크, receipt와 예외 모델을 구현한다.
- [ ] 6.2 PO/LPN/GTIN 스캔 기반 부분·초과·미달·파손 입고 RPC를 구현한다.
- [ ] 6.3 `wms_quality-disposition`의 검사 계획, 샘플, 증빙, 격리와 처분을 구현한다.
- [ ] 6.4 폐기·공급사 반품·재작업 명령과 승인·사유·첨부 필수 규칙을 구현한다.
- [ ] 6.5 `wms_putaway-transfer`의 규칙 평가, 위치 추천, 작업 생성과 원자적 이동을 구현한다.
- [ ] 6.6 입하→검수→적치 완료 전 가용재고가 증가하지 않는 E2E 테스트를 작성한다.

## 7. 현장 작업과 스캔

- [ ] 7.1 `wms_warehouse-task-execution`의 작업 lifecycle, 우선순위, 배정·claim·예외·SLA를 구현한다.
- [ ] 7.2 `wms_traceability-scanning`의 GTIN, lot/serial, SSCC/LPN 해석과 중첩 handling unit을 구현한다.
- [ ] 7.3 모바일 PWA의 system-directed 작업, 단계별 스캔, 피드백과 접근성 UX를 구현한다.
- [ ] 7.4 오프라인 명령 queue, 순서 보존, 멱등 재전송과 버전 충돌 해결 화면을 구현한다.
- [ ] 7.5 카메라·하드웨어 스캐너·수동 입력을 포함한 실제 단말 Playwright 테스트를 작성한다.

## 8. 출고·반품·실사

- [ ] 8.1 `wms_outbound-fulfillment`의 주문, 예약·할당, wave, 피킹, 포장, 출하를 구현한다.
- [ ] 8.2 FIFO/FEFO/lot 제약, short-pick, 출고 보충 의존성과 취소 복원을 검증한다.
- [ ] 8.3 `wms_return-logistics`의 RMA, 원출고 연결, 반품 입고·검사·처분을 구현한다.
- [ ] 8.4 `wms_cycle-counting`의 계획, blind count, 차이 검토·승인과 조정 원장을 구현한다.
- [ ] 8.5 lot/serial/SSCC 기준 정방향·역방향 추적과 회수 범위 조회를 검증한다.

## 9. 별도 WMS 프론트엔드

- [ ] 9.1 `services/wms-frontend`에 Vue 3·TypeScript·Vite·PWA shell과 인증·창고 선택을 구현한다.
- [ ] 9.2 overview, 재고, 재보충, RFQ/PO, 입고, 품질, 작업, 출고, 실사, 반품, 추적 화면을 구현한다.
- [ ] 9.3 모든 변경 화면에 preview, 버전 충돌, 업무 오류, 권한 오류와 감사 context를 일관되게 표시한다.
- [ ] 9.4 private Realtime 갱신, 연결 상태, 재조회와 알림 center를 구현한다.
- [ ] 9.5 역할별 desktop/mobile 핵심 여정의 Playwright 접근성·회귀 테스트를 작성한다.

## 10. WMS MCP와 ProcessGPT 연결

- [ ] 10.1 `services/wms-mcp`에 읽기·쓰기 도구, JSON Schema, service identity와 권한 scope를 구현한다.
- [ ] 10.2 모든 쓰기 도구에 dry-run, idempotency, expected version, correlation과 구조화된 오류를 구현한다.
- [ ] 10.3 `wms_process-orchestration` 명세에 따라 process link, signal outbox와 deep link를 구현한다.
- [ ] 10.4 `completion_automated-task-execution`에 WMS MCP 실행 결과·재시도·승인 요구 처리를 연결한다.
- [ ] 10.5 `completion_process-workitem-submission`에 WMS 문서 ID·버전 검증과 승인 결정을 연결한다.
- [ ] 10.6 첨부 BPMN의 부족 감지→RFQ→HITL→PO→입고→검수→폐기/적치 전체 E2E를 검증한다.

## 11. 운영·이관·출시

- [ ] 11.1 `wms_operations-observability`의 KPI, 지연·부족·격리 알림, 감사와 outbox DLQ 운영 화면을 구현한다.
- [ ] 11.2 데이터 보존, 백업·복구, PITR, 개인정보·첨부 정책과 운영 runbook을 검증한다.
- [ ] 11.3 Odoo 기준정보와 open balance를 staging에 이관하고 SKU·lot·location별 합계를 대조한다.
- [ ] 11.4 shadow run 동안 Odoo와 새 WMS의 PO·입고·재고 변동을 자동 대조한다.
- [ ] 11.5 MCP endpoint를 새 WMS로 전환하고 rollback window와 읽기 전용 Odoo 보관을 운영한다.
- [ ] 11.6 부하·동시성·오프라인·보안·장애복구 acceptance test와 사용자 교육 후 출시한다.
