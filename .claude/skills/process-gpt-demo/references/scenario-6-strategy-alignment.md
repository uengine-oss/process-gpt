# 시나리오 6 — 전략 정합성 게이트

전략맵이 이미 수립된 조직에서 새 프로세스나 개선 제안이 전략 목표와 맞는지
확정·승인 전에 확인하는 흐름을 보여준다. 핵심은 자동 승인이나 자동 KPI 연결이
아니라, 관련 후보와 근거를 제시해 사람이 선택하게 만드는 것이다.

## 전제조건

- 전략 서비스 `http://localhost:8014`가 실행 중이어야 한다.
- tenant는 `localhost`를 사용한다.
- 실제 채팅 생성 흐름을 시연할 때는 deepagents도 실행 중이어야 한다.
- API만 독립 시연할 때는 FastAPI `/docs`를 사용해도 된다.

## 1. 데모 전략맵 준비

`POST /api/objectives?tenant_id=localhost`로 `고객 만족 향상` 목표를 만들고,
반환된 objective id로 `고객 문의 평균 응답시간` KPI를 만든다. 기존 데이터를
초기화하지 않으며 같은 이름이 있으면 기존 id를 재사용한다.

## 2. 관련 후보가 있는 정합성 조회

`POST /api/ai/alignment?tenant_id=localhost`에 다음 본문을 보낸다.

```json
{
  "description": "고객 문의를 자동 분류하고 담당자에게 배정해 평균 응답시간을 줄이는 프로세스"
}
```

`status: matched`, 관련도 순 `candidates`, 각 후보의 `id`, `name`, `type`,
`reason`, `score`, 그리고 `generated_by`가 반환되는지 확인한다. 후보는 제안일
뿐이며 사용자 선택 없이 자동 연결하지 않는다고 설명한다.

## 3. 관련 항목 없음

같은 API에 `사내 주차장 조명 교체 일정 관리`를 보내 오류가 아니라
`status: no_related_items`와 빈 `candidates`가 반환되는지 확인한다. 실제 생성
게이트에서는 계속 진행 여부를 사용자에게 확인하고 `strategyAlignment`에 남긴다.

## 4. 기존 프로세스 연결 구분

기존 프로세스가 있으면 요청에 `proc_def_id`를 함께 넣는다. 신규 텍스트 후보인
`candidates`와 기존 그래프 연결인 `existing_connections`가 구분되는지 확인한다.
조회 기능을 사용할 수 없는 환경도 요청을 실패시키지 않고
`existing_connections_status`에 생략 사실을 표시해야 한다.

## 5. 개선 제안 승인 전 게이트

- `SKILL`: target의 `alignment_evidence`에 후보 또는 없음 상태 기록
- `PROCESS_DEFINITION`: 신규 후보와 기존 연결을 함께 기록
- 전략 서비스 실패: `unavailable`을 기록하되 제안은 `PROPOSED` 유지
- `DMN_RULE`: 정합성 조회와 `alignment_evidence` 모두 제외
- `GET /feedback-proposals`: 승인자가 target별 근거를 확인 가능

## 6. 영상 장면 구성

설명 전용 화면만으로 대체하지 않는다. Playwright로 실제 시스템을 조작하고 다음
장면을 녹화한다. 재현 시 `scripts/record_strategy_alignment_live_demo.mjs`를 사용한다.

1. 짧은 도입 슬라이드 뒤 실제 `/auth/login`에서 데모 계정으로 로그인한다.
2. 실제 `/strategy-board`로 이동해 조회 대상 전략 카드와 KPI 수를 강조한다.
3. Strategy Board 상단의 `전략 정합성 검사`를 열고 관련 프로세스 설명을 입력해
   `정합성 검사 실행`을 클릭한다.
4. 제품 다이얼로그 안의 후보, 점수, 근거를 보여준 뒤 무관한 설명으로 다시
   실행해 `관련 항목 없음` 상태를 확인한다. Swagger/API 문서 화면으로 대신하지 않는다.
5. 사용자 선택 연결과 `strategyAlignment` 기록 원칙을 짧은 결론 슬라이드로 요약한다.

## 데모 후 보고

- 사용한 tenant와 조회 설명
- 관련 후보의 id/name/type/reason/generated_by
- 관련 항목 없음 응답과 기존 연결 조회 상태
- agent-feedback을 시연했다면 target별 `alignment_evidence` 상태
- 최종 영상 경로, 길이, 내레이션 모델/voice, 합성 검증 결과
