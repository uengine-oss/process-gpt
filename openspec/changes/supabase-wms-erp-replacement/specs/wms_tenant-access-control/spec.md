# WMS 테넌트·접근 제어 명세

## ADDED Requirements

### Requirement: 인증된 테넌트 격리 (WMS-SEC-001)
시스템은 Supabase Auth 사용자와 service identity의 membership을 검증하고 모든 업무 row를 tenant 단위 RLS로 SHALL 격리한다.

#### Scenario: 교차 테넌트 직접 조회
- **GIVEN** 사용자가 테넌트 A에만 속해 있다
- **WHEN** 사용자가 URL 또는 PostgREST filter로 테넌트 B의 문서를 조회한다
- **THEN** RLS는 해당 row를 반환하지 않는다

#### Scenario: 미인증 접근
- **GIVEN** 유효한 인증 session이 없다
- **WHEN** WMS 업무 table, view, RPC, Realtime 또는 Storage에 접근한다
- **THEN** 시스템은 명시적으로 공개된 health 정보 외의 접근을 거부한다

### Requirement: 창고 범위 제한 (WMS-SEC-002)
시스템은 사용자에게 허용된 회사·창고 범위를 조회와 명령 모두에 SHALL 적용한다.

#### Scenario: 다른 창고 재고 조정
- **GIVEN** 재고 담당자가 창고 A에만 권한이 있다
- **WHEN** 창고 B의 재고 조정 RPC를 호출한다
- **THEN** 시스템은 명령을 거부하고 원장·감사 업무 이벤트를 만들지 않는다

### Requirement: 역할과 직무 분리 (WMS-SEC-003)
시스템은 관리자, 재고, 구매, 승인, 입고, 품질, 현장, 출고, 감사 역할과 위험 명령의 직무 분리를 SHALL 지원한다.

#### Scenario: 구매 작성자의 자기 승인
- **GIVEN** 정책이 요청자와 승인자 분리를 요구한다
- **WHEN** 구매 요청 작성자가 같은 PO를 승인하려 한다
- **THEN** 시스템은 승인을 거부하고 적격 승인자를 표시한다

#### Scenario: 폐기 권한 없는 작업자
- **GIVEN** 현장 작업자에게 scrap 승인 권한이 없다
- **WHEN** 작업자가 불합격 재고 폐기를 직접 확정한다
- **THEN** 시스템은 처분 제안만 허용하고 원장 반영을 차단한다

### Requirement: 서비스 계정 최소 권한 (WMS-SEC-004)
시스템은 ProcessGPT·외부 통합별 service identity와 도구 scope를 분리하고 만료·회전 가능한 credential을 SHALL 사용한다.

#### Scenario: 조회 전용 서비스의 쓰기 시도
- **GIVEN** 서비스 계정에 `inventory:read` scope만 있다
- **WHEN** 계정이 PO 확정 또는 재고 이동 도구를 호출한다
- **THEN** WMS MCP는 호출을 거부하고 보안 감사 이벤트를 기록한다

### Requirement: Private Realtime 권한 (WMS-SEC-005)
시스템은 tenant·warehouse private topic 구독과 발행을 membership 및 warehouse scope로 SHALL 제한한다.

#### Scenario: 다른 창고 topic 구독
- **GIVEN** 사용자가 창고 A에만 접근 가능하다
- **WHEN** 창고 B의 Realtime topic에 join하려 한다
- **THEN** 시스템은 channel 권한을 거부한다

### Requirement: Storage 객체 접근 (WMS-SEC-006)
시스템은 ASN, 검사사진, 라벨과 반품 증빙의 object path에 tenant·warehouse·document 범위를 포함하고 RLS로 SHALL 보호한다.

#### Scenario: 검사 사진 URL 재사용
- **GIVEN** 사용자가 테넌트 A의 만료된 signed URL을 보유한다
- **WHEN** URL을 다시 사용하거나 테넌트 B 사용자가 object를 요청한다
- **THEN** 시스템은 접근을 거부하고 새 URL 발급 시 현재 문서 권한을 다시 검증한다

### Requirement: 브라우저 비밀키 금지 (WMS-SEC-007)
시스템은 웹·PWA bundle과 client storage에 Supabase `service_role` 또는 외부 통합 비밀을 SHALL 포함하지 않는다.

#### Scenario: 배포 artifact 보안 검사
- **GIVEN** WMS frontend production bundle이 생성되었다
- **WHEN** CI가 비밀 패턴과 환경 구성을 검사한다
- **THEN** service role 또는 서버 비밀이 발견되면 배포를 실패시킨다
