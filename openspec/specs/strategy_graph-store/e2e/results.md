# strategy_graph-store E2E 실행 결과

- 실행 일시: 2026-07-09 (KST)
- 인프라: process-gpt-age-postgres (127.0.0.1:55433) / uvicorn 소스 실행(러너 제어, 포트 8115)
- 결과: **15/15 PASS**

## Pass/Fail 표

| # | 시나리오 | 결과 |
| --- | --- | --- |
| 1 | S1 기동/health(AGE 기본 저장소) | PASS |
| 2 | S1 AGE 어댑터 그래프 자동 초기화 로그 | PASS |
| 3 | S4 테넌트 A 목표 생성 | PASS |
| 4 | S4 테넌트 B 목표 생성 | PASS |
| 5 | S4 A 조회에 A 목표만 포함(격리) | PASS |
| 6 | S4 B 조회에 B 목표만 포함(격리) | PASS |
| 7 | S4 교차 테넌트 수정 404 | PASS |
| 8 | S4 교차 수정 후 A 데이터 불변 | PASS |
| 9 | S2 재기동 후 health | PASS |
| 10 | S2 재기동 시 그래프 중복 생성/오류 없음 | PASS |
| 11 | S2 재기동 후 기존 노드/관계 보존 | PASS |
| 12 | S3 unknown-db 기동 실패(health 안 뜸) | PASS |
| 13 | S3 오류에 지원 구현체 목록 포함 | PASS |
| 14 | S5 AGE 미설치 Postgres 기동 실패 | PASS |
| 15 | S5 AGE 확장 필요 오류 로그 | PASS |

## 주요 로그 발췌

기동 로그(server_run1.log):

```
INFO:app.graph.factory:그래프 저장소 구현체 'age' 선택
INFO:app.graph.age_adapter:AGE 그래프 'corp_ontology_e2e_store' 준비 완료
INFO:     Application startup complete.
```

unknown-db 기동 실패(server_unknown.log):

```
ValueError: 지원하지 않는 GRAPH_STORE 값 'unknown-db' 입니다. 지원 가능한 구현체: ['age']
ERROR:    Application startup failed. Exiting.
```

AGE 미설치 Postgres(server_noage.log): `RuntimeError`에 "AGE" 포함, 기동 실패.

## 실행 콘솔

```
PASS - S1 기동/health(AGE 기본 저장소)
PASS - S1 AGE 어댑터 그래프 자동 초기화 로그
PASS - S4 테넌트 A 목표 생성
PASS - S4 테넌트 B 목표 생성
PASS - S4 A 조회에 A 목표만 포함(격리)
PASS - S4 B 조회에 B 목표만 포함(격리)
PASS - S4 교차 테넌트 수정 404
PASS - S4 교차 수정 후 A 데이터 불변
PASS - S2 재기동 후 health
PASS - S2 재기동 시 그래프 중복 생성/오류 없음
PASS - S2 재기동 후 기존 노드/관계 보존
PASS - S3 unknown-db 기동 실패(health 안 뜸)
PASS - S3 오류에 지원 구현체 목록 포함
PASS - S5 AGE 미설치 Postgres 기동 실패
PASS - S5 AGE 확장 필요 오류 로그

=== SUMMARY: 15/15 PASSED ===
```
