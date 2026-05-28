# E2E 시나리오 02: 상태 점검 백엔드 계약

## 메타데이터
- 스위트 슬러그: `completion_llm-chat-gateway`
- 원본 명세 ID: `completion_llm-chat-gateway`
- 시나리오 ID: `02`
- Playwright 테스트 제목: `02 GET sanity-check 는 is_sanity_check true 를 반환한다`
- 분류: 백엔드 계약 전용 (Real-Frontend Rule 에 따라 스크린샷 의무 면제)
- 원본 명세:
  - `openspec/specs/completion_llm-chat-gateway/spec.md`

## 목적
`GET /langchain-chat/sanity-check` 가 게이트웨이(`:8088`) → completion 백엔드 경로를 거쳐 항상 `{is_sanity_check: true}` 200 JSON 으로 응답하는지 검증한다. completion 컨테이너의 라우트 등록(`process_chat.py:35`) 과 nginx 프록시 동작이 함께 검증된다.

## 분류 근거
`GET /langchain-chat/sanity-check` 은 프론트엔드 코드(`services/frontend/src/components/ai/AIGenerator.js:checkBackendConnection`)에서 호출되지만, 이는 `generate()` 내부의 자동 사전 점검이며 사용자가 직접 트리거하는 UI 표면이 아니다. Real-Frontend Rule 에 따라 별도의 사용자 화면을 합성해 띄우는 대신, 본 시나리오는 백엔드 계약(엔드포인트가 게이트웨이를 통해 200/`{is_sanity_check: true}` 를 반환하는지)만 직접 검증하고 스크린샷 의무를 면제한다.

## 사전 조건
- `gateway`(`:8088`) 와 `completion` 컨테이너가 healthy.
- nginx 가 `/completion/` 를 strip 하여 `completion:8000/langchain-chat/sanity-check` 로 프록시.

## 테스트 데이터 및 Stub
| 이름 | 유형 | 경로 또는 route | 목적 |
| --- | --- | --- | --- |
| (없음) | - | - | mock-llm 호출 없음 |

## 절차
1. Playwright `request` 컨텍스트로 `GET http://localhost:8088/completion/langchain-chat/sanity-check` 를 호출한다.
2. 응답 상태와 본문을 확인한다.

## 기대 결과
- HTTP 상태 200.
- `Content-Type` 이 `application/json`.
- 응답 본문이 정확히 `{"is_sanity_check": true}`.

## 커버하는 요구사항
| 명세 | 요구사항 | 시나리오 |
| --- | --- | --- |
| `completion_llm-chat-gateway` | 상태 점검 | 상태 점검 응답 |

## 산출물
- 스크린샷 체크포인트: 없음 (Real-Frontend Rule 면제 — 사유는 위 "분류 근거" 참조).
- Trace/video: Playwright 실패 시 보존됩니다.
- 결과 JSON: `openspec/specs/completion_llm-chat-gateway/e2e/results/results.json`
