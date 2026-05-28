# E2E 시나리오 01: 발신자 식별

## 메타데이터
- 스위트 슬러그: `completion_callbot-task-management`
- 원본 명세 ID: `completion_callbot-task-management`
- 시나리오 ID: `01`
- Playwright 테스트 제목: `발신자 식별: 등록 사용자와 익명 발신자에 대해 인사말을 반환한다`
- 원본 명세:
  - `openspec/specs/completion_callbot-task-management/spec.md`

## 목적
콜봇 클라이언트가 `GET /complete-callbot/caller-info`를 호출했을 때 등록 사용자의 신원과 한국어 인사말을 정확히 반환하는지, 익명/식별 실패 발신자에 대해서도 통화 흐름을 끊지 않는 기본 응답을 200으로 반환하는지를 확인한다.

## 사전 조건
- `docker-compose.e2e.yml`로 `db`/`kong`/`completion`이 기동되어 있고 `completion`이 healthy 상태이다.
- `db-seed-callbot` 잡이 완료되어 다음 row가 존재한다:
  - `public.users`: id=`c5c11111-1111-1111-1111-111111111111`, username=`콜봇테스트사용자`, email=`callbot-e2e@uengine.org`, tenant_id=`localhost`.
- 요청은 `X-Forwarded-Host`가 없거나 `localhost`이므로 미들웨어가 tenant를 `localhost`로 해석한다.

## 테스트 데이터 및 Stub
| 이름 | 유형 | 경로 또는 route | 목적 |
| --- | --- | --- | --- |
| 콜봇 테스트 사용자 | seed | `public.users` row (id=`c5c1...`) | 등록 사용자 조회 경로 통과 |
| Anonymous 폴백 | constant | `from_number=client:Anonymous` | 코드의 하드코딩된 user_id 경로 검증 |
| 미존재 사용자 | constant | `user_id=00000000-0000-0000-0000-000000000000` | 식별 실패 시 200 기본 인사말 반환 검증 |

## 절차
1. 콜봇 클라이언트가 `GET /complete-callbot/caller-info?user_id=c5c11111-1111-1111-1111-111111111111`을 호출한다.
2. 콜봇 클라이언트가 `GET /complete-callbot/caller-info?from_number=client:Anonymous`을 호출한다 (코드 내 하드코딩된 기본 user_id 경로).
3. 콜봇 클라이언트가 `GET /complete-callbot/caller-info?user_id=00000000-0000-0000-0000-000000000000`을 호출한다 (미존재 사용자 → 기본 인사말).

## 기대 결과
- 1번 응답: HTTP 200, `success=true`, `username=콜봇테스트사용자`, `user_id=c5c1...`, `email=callbot-e2e@uengine.org`, `tenant_id=localhost`, `greeting`이 `콜봇테스트사용자님 안녕하세요`를 포함한다.
- 2번 응답: HTTP 200, `success=true`, `greeting` 문자열이 비어 있지 않다 (하드코딩 user_id 경로 또는 기본 인사말 어느 쪽이든 통과).
- 3번 응답: HTTP 200, `success=true`, `username=고객`, `greeting=고객님 안녕하세요`.

## 커버하는 요구사항
| 명세 | 요구사항 | 시나리오 |
| --- | --- | --- |
| `completion_callbot-task-management` | 발신자 식별 | 등록 사용자 발신자 식별 |
| `completion_callbot-task-management` | 발신자 식별 | 식별 실패 시 기본 응답 |

## 산출물
- 스크린샷 체크포인트: 본 스펙은 비-사용자-facing protocol API로 UI 상태가 존재하지 않으므로 스크린샷은 캡처하지 않는다 (커버리지 매트릭스의 예외 메모 참조).
- Trace/video: Playwright 실패 시 보존됩니다.
- 결과 JSON: `openspec/specs/completion_callbot-task-management/e2e/results/results.json`
