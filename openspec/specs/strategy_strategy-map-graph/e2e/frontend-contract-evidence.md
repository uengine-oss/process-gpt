# 프론트엔드 계약 무변경 증거 (Task 10.6)

## 목적

전략맵/BSC 시각화 프론트엔드가 **그래프 저장소 전환 후에도 무변경으로 동작**함을,
`GET /api/map` 응답의 JSON 키 구조를 **기존(레거시 SQL 구현)** 과 **신규(그래프 구현)**
사이에서 대조해 증명한다.

배포된 프론트엔드는 소스 실행 서버(8114)를 가리키도록 바꿀 수 없고, 배포된 strategy
컨테이너의 DB(supabase-db)에는 AGE 확장이 없어 라이브 UI 스왑이 불가능하다. 따라서
**API 계약 대조**로 증거를 대신한다(실행 중 컨테이너는 수정·재기동하지 않았다).

## 대조 대상

| 구분 | 엔드포인트 | 구현 | 데이터 원천 |
| --- | --- | --- | --- |
| 레거시(기존) | `http://localhost:8014/api/map?tenant_id=localhost` | 관계형 SQL(변경 전) | supabase-db `strategy_*` 테이블(읽기 전용, 미변경) |
| 신규(그래프) | `http://127.0.0.1:8114/api/map?tenant_id=<seed>` | 그래프(AGE) | process-gpt-age-postgres 그래프 노드 |

- 실행 일시: 2026-07-09 19:00 KST
- 레거시 컨테이너 `process-gpt-strategy`(8014, up 2일)는 변경 전 SQL 구현을 그대로 서빙한다.
- 이니셔티브는 레거시 테넌트에 데이터가 없어, 레거시 `strategy_initiatives` **테이블 컬럼
  집합**(레거시 핸들러가 행을 그대로 반환)과 대조했다.

## 결과 — 최상위 구조

| | 레거시 | 신규 | 동일 |
| --- | --- | --- | --- |
| 최상위 키 | `["objectives"]` | `["objectives"]` | ✅ |

## 결과 — `objectives[]` 키

레거시/신규 **완전 동일**:

```
achievement, created_at, description, id, initiatives, kpis,
name, parents, perspective, sort_order, tenant_id, updated_at
```

중첩 구조(`objectives[].kpis`, `objectives[].initiatives`, `parents`, `achievement`,
`perspective`)가 그대로 유지된다 → BSC 4관점 시각화·계층(parents) 렌더링 무변경.

## 결과 — `objectives[].kpis[]` 키

| | 값 |
| --- | --- |
| 레거시 | achievement, baseline_value, created_at, current_value, description, direction, id, last_measured_at, measure_type, name, objective_id, period_end, period_start, proc_def_id, survey_questions, target_value, tenant_id, unit, updated_at |
| 신규 | (좌동) **+ `form_field`** |
| only_legacy | (없음) |
| only_new | `form_field` |

→ **레거시 키는 100% 보존**되고, 신규는 `form_value_sum` 측정 유형용 `form_field` **한
개를 추가(additive)** 한다. 기존 화면은 알지 못하는 추가 키를 무시하며, 사용하던 모든
키(`current_value`, `achievement`, `target_value`, `survey_questions` 등)는 그대로 존재한다.
→ 기존 KPI 카드/게이지 렌더링 무변경.

## 결과 — `objectives[].initiatives[]` 키

레거시 `strategy_initiatives` 테이블 컬럼(= 레거시 핸들러 반환 키)과 신규 응답 키가
**완전 동일**:

```
id, tenant_id, objective_id, name, description, owner_email, status,
progress, proc_def_id, start_date, due_date, created_at, updated_at
```

## 결론

**구조 동일 → 기존 화면 무변경 동작.**

- 최상위·`objectives[]`·`initiatives[]` 키 집합은 레거시와 완전 동일하다.
- `kpis[]` 는 레거시 키를 100% 포함하는 **상위집합**이며, 추가된 `form_field` 하나는
  순수 additive(신규 `form_value_sum` 측정 유형 지원용)라 기존 전략맵/BSC 화면 렌더링에
  영향을 주지 않는다.
- 따라서 저장소를 그래프(AGE)로 전환해도 `GET /api/map` 계약이 유지되어 전략 맵/BSC
  시각화 화면은 코드 변경 없이 동작한다. (Requirement "기존 전략맵 API 계약이 그래프
  저장소 위에서 유지된다" 충족.)

## 재현 방법

```bash
# 신규 소스 실행 서버 기동(8114) 후:
services/strategy/.venv/bin/python \
  openspec/specs/strategy_strategy-map-graph/e2e/frontend_contract_check.py
```
