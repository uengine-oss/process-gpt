# 제안: Supabase 기반 ProcessGPT WMS·경량 구매 ERP 구축

## Why

현재 재고 부족 대응 프로세스는 Odoo ERP의 `stock.quant`, `purchase.order`, `stock.picking`, `stock.scrap` 객체를 MCP 도구로 호출한다. 이 방식은 교육용 데모를 넘어 실제 운영으로 확장할 때 다음 한계를 가진다.

- 재고 부족 감지부터 RFQ, 구매 승인, PO 확정, 공급사 입고, 검수, 폐기 또는 선반 배치까지의 핵심 데이터와 상태가 외부 Odoo에 종속된다.
- ProcessGPT의 프로세스 인스턴스와 WMS 업무 상태 사이에 하나의 추적 가능한 계약이 없다.
- 현장 작업자는 Odoo의 범용 ERP 화면 대신 입고·검수·적치·피킹에 최적화된 별도 모바일 화면이 필요하다.
- 재고 수량을 단순 현재값으로만 저장하면 동시 작업, 부분 입고, 예약, 격리, 폐기, 실사 차이를 감사 가능한 방식으로 설명하기 어렵다.
- 물류학과 실습과 실제 기업 적용 모두를 지원하려면 WMS의 표준 업무 기능을 독립적으로 이해하고 검증할 수 있는 제품 경계가 필요하다.

따라서 Supabase의 Postgres, Auth, RLS, Realtime, Storage, Edge Functions를 기반으로 별도 WMS 프론트엔드와 WMS MCP 서버를 설계한다. 1차 목표는 Odoo 전체 회계 ERP를 복제하는 것이 아니라, 현재 프로세스가 사용하는 재고·구매·입고·품질·폐기 기능을 완전히 대체하고 일반 WMS의 입고부터 출고·실사·추적성까지 확장 가능한 운영 기반을 제공하는 것이다.

## What Changes

- **별도 WMS 제품**: 기존 ProcessGPT 프론트엔드와 분리된 Vue 3·TypeScript 기반 데스크톱 운영 화면과 창고 현장용 PWA를 신설한다.
- **Supabase 중심 아키텍처**: 모든 업무 데이터는 전용 `wms` 스키마의 Postgres에 저장하고, Supabase Auth와 RLS로 테넌트·창고·역할 범위를 강제한다.
- **불변 재고 원장**: 현재 수량을 직접 수정하는 대신 모든 수불을 불변 재고 원장에 기록하고, 가용·예약·격리·이동 중 수량은 원장과 예약의 투영 결과로 제공한다.
- **창고·상품·공급사 기준정보**: 회사, 창고, 존, 로케이션, 도크, 상품, UOM, 포장단위, 바코드, lot/serial 정책, 공급사와 공급 조건을 관리한다.
- **재보충과 구매**: Min/Max·안전재고·리드타임 규칙으로 부족을 감지하고, 구매 필요 제안, RFQ, 견적 비교, 금액 기준 승인, PO 확정, 공급사 통지를 제공한다.
- **입고·ASN·검수**: PO/ASN 기반 입하 예정, 도크 배정, SSCC/LPN 및 상품 스캔, 부분·초과·미달·파손 입고, 품질 검사와 격리 처리를 제공한다.
- **폐기·반품·적치**: 품질 결과에 따라 합격 재고는 putaway 작업으로, 불합격 재고는 폐기·공급사 반품·재작업으로 분기한다.
- **출고 WMS**: 출고 주문, 예약·할당, wave, FEFO/FIFO 피킹, 포장, 라벨, 출하 확정을 제공한다.
- **재고 정확도**: 주기 실사, spot count, blind count, 차이 승인, 조정 원장 기록을 제공한다.
- **GS1 추적성**: GTIN, lot/serial, SSCC/LPN, GLN 선택 지원과 입고부터 출하까지의 계보 조회를 제공한다.
- **창고 작업 관리**: 입고, 이동, 검사, 적치, 보충, 피킹, 포장, 실사 작업의 우선순위, 배정, claim, 중단, 예외, 완료를 통합 관리한다.
- **ProcessGPT 연동**: Odoo MCP 호출을 WMS MCP 명령으로 대체하고, 업무 이벤트를 outbox로 발행해 프로세스 인스턴스와 WMS 문서를 양방향 추적한다.
- **운영 통제**: 재고·입출고·작업·지연 KPI, 감사 로그, 알림, 실패 재처리와 데이터 내보내기를 제공한다.
- **Odoo 전환**: Odoo의 핵심 객체를 새 도메인으로 매핑하고, 기준정보 이관 → 재고 원장 개시 → shadow 검증 → MCP cutover 순으로 전환한다.

## Capabilities

### New Capabilities

- `wms_master-data`: 회사·창고·존·로케이션·상품·UOM·포장·바코드·공급사 기준정보와 유효성 관리.
- `wms_inventory-ledger`: 불변 수불 원장, 재고 잔량·가용량 투영, 예약, 상태 격리, 조정과 동시성 제어.
- `wms_replenishment-planning`: Min/Max·안전재고·리드타임 기반 부족 감지와 구매 필요 제안.
- `wms_purchase-ordering`: RFQ, 공급사 견적, 구매 승인, PO 확정·변경·취소와 입고 예정 연결.
- `wms_inbound-receiving`: ASN·PO 기반 입하 예정, 도크 접수, 바코드/LPN 입고, 부분·초과·미달·파손 처리.
- `wms_quality-disposition`: 품질 계획·샘플링·검사, 격리, 합격·불합격 판정, 폐기·반품·재작업 처분.
- `wms_putaway-transfer`: 적치 규칙, 용량·호환성 검증, 로케이션 추천과 내부 이동 작업.
- `wms_outbound-fulfillment`: 출고 주문, 예약·할당, wave, 피킹, 포장, 출하와 short-pick 처리.
- `wms_return-logistics`: 고객 반품 접수, 원출고 추적, 검사, 재입고·수리·폐기·환불 연계 처분.
- `wms_cycle-counting`: 주기·임계·spot 실사, blind count, 차이 검토·승인과 재고 조정.
- `wms_traceability-scanning`: GTIN, lot/serial, SSCC/LPN 바코드 식별, 라벨, 계보와 회수 범위 조회.
- `wms_warehouse-task-execution`: 창고 작업 생성, 우선순위, 배정, claim, 모바일 수행, 예외와 오프라인 재전송.
- `wms_process-orchestration`: ProcessGPT 프로세스, MCP 명령, 업무 이벤트, HITL 승인과 보상 처리 연결.
- `wms_tenant-access-control`: Supabase Auth, RLS, 역할·창고 범위 권한, 서비스 계정과 문서 접근 제어.
- `wms_operations-observability`: 운영 대시보드, KPI, 감사 로그, 알림, outbox 실패와 성능 상태 관찰.

### Modified Capabilities

- `completion_automated-task-execution`: 프로세스 자동 작업이 Odoo MCP 대신 WMS MCP의 멱등 명령을 호출하고 구조화된 업무 결과를 다음 활동에 전달할 수 있어야 한다.
- `completion_process-workitem-submission`: 구매 승인, 품질 판정 등 사람 작업이 WMS 문서 식별자와 버전을 보존해 제출되어야 한다.

## Impact

- **신규 앱**: 별도 WMS 데스크톱·PWA 프론트엔드. 기존 ProcessGPT UI에는 WMS 문서 deep link와 상태 요약만 추가한다.
- **신규 서비스**: WMS MCP 서버와 외부 통지·EDI·라벨·웹훅을 담당하는 Supabase Edge Functions.
- **데이터베이스**: Supabase Postgres의 전용 `wms` 스키마, RLS 정책, RPC 명령 함수, Realtime Broadcast 트리거, outbox·감사 로그.
- **ProcessGPT**: 현재 재고 부족–구매–입고–검수–폐기/적치 BPMN의 각 service task가 WMS MCP 도구를 사용하도록 전환된다.
- **기존 Odoo**: `stock.quant`, `stock.move`, `purchase.order`, `stock.picking`, `stock.scrap` 데이터를 이관하고 cutover 이후 읽기 전용 보관한다.
- **운영 범위**: 재고·구매·창고 운영은 대체하지만, 총계정원장, 세무 신고, 급여, CRM, 제조 MRP 전체는 1차 범위에 포함하지 않는다. 확정 PO·입고·반품·재고평가 이벤트는 외부 회계 시스템이 소비할 수 있게 제공한다.
- **보안**: 브라우저가 `service_role` 키를 보유하지 않으며, 모든 노출 테이블과 Storage 객체에 RLS가 적용된다.
- **QA**: 각 capability는 하나의 독립 E2E suite로 검증하고, 핵심 수불 시나리오는 동시성·멱등성·테넌트 격리를 포함한다.
