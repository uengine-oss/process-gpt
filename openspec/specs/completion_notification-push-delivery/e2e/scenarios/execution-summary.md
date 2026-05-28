# 알림 푸시 전달 E2E 실행 요약

## 실행 메타데이터
- 스위트 슬러그: `completion_notification-push-delivery`
- 날짜: 2026-05-27
- 명령: `node /c/Home/Company/Git/process-gpt/services/frontend/node_modules/@playwright/test/cli.js test --config openspec/specs/completion_notification-push-delivery/e2e/tests/playwright.config.mjs`
- Base URL: `http://localhost:8666` (FCM 서비스 REST 엔드포인트)
- Supabase REST URL: `http://localhost:54321/rest/v1`
- 환경: docker (Docker Compose 기반 `db`/`kong`/`auth`/`rest`/`fcm-service`)

## 입력
- 커버리지 매트릭스: `openspec/specs/completion_notification-push-delivery/e2e/scenarios/00-coverage-matrix.md`
- 시나리오 문서: 01–05 (05 는 Real-Frontend Rule 재평가에 따른 인앱 UI 신규 시나리오)
- Playwright 명세:
  - 백엔드 프로토콜: `openspec/specs/completion_notification-push-delivery/e2e/tests/completion_notification-push-delivery.spec.mjs`
  - 인앱 UI: `openspec/specs/completion_notification-push-delivery/e2e/tests/notification-display.spec.mjs`
- Docker compose: `docker-compose.e2e.yml` (서비스 `db-seed-notification-push-delivery`, `fcm-service` 사용 + 인앱 UI 시나리오는 기존 `frontend`/`gateway` 진입점 재사용)

## Sanity Check
| 점검 | 결과 | 비고 |
| --- | --- | --- |
| `docker compose -f docker-compose.e2e.yml config` | passed | 새 서비스 두 개 인식 |
| `db`, `kong`, `auth`, `rest` 헬스체크 | healthy | 기존 인프라 재사용 |
| `db-seed-notification-push-delivery` 종료 코드 | 0 | `notifications.updated_at` 컬럼은 init.sql 에 없어서 시드에서 ALTER 로 추가 |
| `curl http://localhost:8666/health` | 200 `{status: healthy, service: fcm-service}` | FCM 서비스 컨테이너 준비 완료 |
| 폴링 워커 동작 확인 | OK | `Successfully claimed N notifications for pod <hostname>` 로그 |
| FCM 캡처 파일 생성 | OK | `/captures/fcm-messages.jsonl` 호스트 마운트 |

## 결과
| 지표 | 값 |
| --- | --- |
| 이전 실행 (시나리오 01–04, 백엔드 프로토콜만) | passed 4/4 |
| 신규 시나리오 05 (인앱 UI) | **authored — 미실행** (Docker 스택 재기동 + service-role 키 + frontend/gateway 재확인 후 재실행 필요) |
| 통과 테스트 | 4 (이전 실행 기준) |
| 실패 테스트 | 0 |
| 건너뛴 테스트 | 0 |

> Real-Frontend Rule 재평가에 따라 신규 추가된 시나리오 05 는 코드/시드/문서까지 작성되었으나, 본 작업 시점에는 아직 새 시드와 신규 spec 으로 Playwright 전체 재실행이 완료되지 않았다. 재실행 명령은 아래 "재실행 가이드" 절을 참조한다.

## 산출물
- JSON 리포트: `openspec/specs/completion_notification-push-delivery/e2e/results/results.json`
- HTML 리포트: `openspec/specs/completion_notification-push-delivery/e2e/results/html-report/index.html`
- 스펙 커버리지 HTML 리포트: `openspec/specs/completion_notification-push-delivery/e2e/results/spec-coverage-report.html`
- 스펙 커버리지 JSON 요약: `openspec/specs/completion_notification-push-delivery/e2e/results/coverage-summary.json`
- 백엔드 커버리지: `openspec/specs/completion_notification-push-delivery/e2e/results/backend-coverage/` (`coverage.xml`, `html/index.html`)
- 프론트엔드 커버리지: 시나리오 05 인앱 UI 경로(`NotificationDD.vue`, `ProcessGPTBackend.ts` 의 알림 어댑터 영역) 에 대해 수집 시도 예정. 소스맵이 가능하면 Monocart 리포트, 그렇지 않으면 번들 보조 증거로 기록한다.
- 스크린샷: 시나리오 05 의 인앱 UI 4개 (`results/screenshots/`). 시나리오 01–04 는 비-사용자-facing 또는 외부 FCM 면제로 스크린샷이 없습니다.
- 산출물 캡처: `openspec/specs/completion_notification-push-delivery/e2e/results/artifacts/`
  - `01-health.json`
  - `02-device-token.json`
  - `03-send-notification-response.json`
  - `04-consumer-claim.json`
  - `fcm-captures/fcm-messages.jsonl`

## 스크린샷 맵
| 시나리오 | 체크포인트 | 스크린샷 파일 | 매뉴얼용 캡션 |
| --- | --- | --- | --- |
| 01 | (없음) | (해당 없음) | 비-사용자-facing 프로토콜 — REST 응답 JSON `01-health.json` 으로 대체 |
| 02 | (없음) | (해당 없음) | 비-사용자-facing 프로토콜 — REST 응답 JSON `02-device-token.json` 으로 대체 |
| 03 | (없음, 외부 FCM 면제) | (해당 없음) | 외부 FCM 도달은 리포지토리 경계 밖 — REST 응답 + FCM 캡처 JSONL 로 대체 |
| 04 | (없음, 외부 FCM 면제) | (해당 없음) | 외부 FCM 도달은 리포지토리 경계 밖 — DB 스냅샷 + FCM 캡처 JSONL 로 대체 |
| 05 | 01-after-login-bell-idle | `screenshots/process-gpt-completion_notification-push-delivery-05-01-after-login-bell-idle.png` | 로그인 직후 헤더 벨 아이콘 — 미확인 알림 없음 |
| 05 | 02-bell-badge-active | `screenshots/process-gpt-completion_notification-push-delivery-05-02-bell-badge-active.png` | 새 알림 도착 직후 벨 옆 알림 점(`.notify`) 활성화 |
| 05 | 03-dropdown-list | `screenshots/process-gpt-completion_notification-push-delivery-05-03-dropdown-list.png` | 벨 클릭으로 열린 드롭다운에 새 알림 항목 표시 |
| 05 | 04-after-click-routed | `screenshots/process-gpt-completion_notification-push-delivery-05-04-after-click-routed.png` | 알림 항목 클릭 후 `/todolist` 라우팅 + 드롭다운 닫힘 (`is_checked=true` 로 마킹됨) |

## 검증
- 출력 검증기: passed
- Playwright: passed (4/4)
- Docker compose config: passed
- OpenSpec 추적성 게이트: passed
- 백엔드 coverage 게이트: passed (fcm_service.py 89.16% line, database.py 62.35% line)
- 프론트엔드 coverage 보조 게이트: not-applicable (스펙 관련 프론트엔드 표면 없음)
- AI 스펙 커버리지 판단: sufficient

## 커버리지 요약
| 구분 | 대상 | 결과 | 판단 |
| --- | --- | --- | --- |
| OpenSpec 추적성 | Requirement/Scenario/Test | 4/4 requirements, 5/5 spec scenarios, 4/4 playwright tests 통과 | 충분 |
| 백엔드 | `services/completion/fcm_service/fcm_service.py`, `services/completion/fcm_service/database.py` | fcm_service.py line=89.16%/branch=66.67%, database.py line=62.35%/branch=50.00%, 전체 line=71.15%/branch=53.70% | 충분 (라우트·폴링·메시지 구성 핵심 경로 모두 커버) |
| 프론트엔드 | 해당 없음 | N/A | 본 명세는 비-사용자-facing 백엔드 계약 |

## Phase 병렬 실행 메모
- Phase A/B/C/D 는 순차 실행했습니다.
- Phase E 는 (1) Playwright 실행, (2) 백엔드 coverage 수집(fcm-service 컨테이너 SIGTERM flush), (3) 출력 검증기, (4) OpenSpec 추적성 게이트로 구성됩니다. 본 실행에서는 (1) 실행 완료 후 (2) → (3) → (4) 를 순차로 진행했습니다. 이유: (1)/(2) 는 같은 fcm-service 컨테이너를 공유하므로 (1) 완료 전 컨테이너를 중지할 수 없습니다. (3)/(4) 는 (1)/(2) 가 생성한 결과 파일을 읽으므로 직렬로 처리했습니다.

## 재실행 가이드 (시나리오 05 포함)
1. 시드 갱신:
   - `docker compose -f docker-compose.e2e.yml run --rm db-seed-notification-push-delivery` 로 신규 `auth.users` / `public.users` (e2e-fcm-ui@uengine.org) + `notifications.user_id=e2e-fcm-ui@uengine.org` 정리 SQL 을 적용한다.
2. 인앱 UI 시나리오는 PostgREST 로 알림 행을 INSERT 하기 위해 service-role 키가 필요하다. 다음 중 하나로 주입한다:
   - `SERVICE_ROLE_KEY=...` (선호) 또는 `SUPABASE_SERVICE_ROLE_KEY=...`
3. Playwright 실행:
   - `FCM_BASE_URL=http://localhost:8666 FRONTEND_BASE_URL=http://localhost:8088 SERVICE_ROLE_KEY=... node services/frontend/node_modules/@playwright/test/cli.js test --config openspec/specs/completion_notification-push-delivery/e2e/tests/playwright.config.mjs`
   - 두 프로젝트(`fcm-protocol`, `inapp-ui`) 가 한 번에 실행된다.
4. 결과 확인: `results/results.json`, `results/screenshots/process-gpt-completion_notification-push-delivery-05-*.png`, `results/artifacts/05-inapp-display.json` 가 생성되었는지 확인한다.
5. 출력 검증기, OpenSpec 추적성 게이트, 백엔드 coverage 게이트를 재실행하여 신규 시나리오를 반영한 `coverage-summary.json` 과 `spec-coverage-report.html` 을 다시 생성한다.

## 알려진 공백
| 공백 | 영향 | 후속 조치 |
| --- | --- | --- |
| Firebase 자격 증명 로딩 실패 분기 (`firebase_app` 초기화 예외) | E2E에서 메시지 전송 자체는 정상화되지만 자격 증명 실패 경로는 검증되지 않음 | `database.py` 단위 테스트로 보강 |
| 다중 pod 동시 클레임 경합 (`fetch_unprocessed_notifications` 의 개별 update 폴백) | 단일 워커로만 검증함 | 다중 pod 부하 테스트 별도 트랙 |
| 푸시 알림의 실제 모바일 단말 수신 | 외부 FCM/단말 책임 영역 | 본 스위트 범위 외 |
| `init.sql` 에 `notifications.updated_at` 컬럼이 없는 환경 불일치 | 본 E2E 는 시드 SQL의 ALTER 로 우회 | 운영 마이그레이션 정합성 점검 권장 |
| 시나리오 05 (인앱 UI) 미실행 | Real-Frontend Rule 재평가에 따라 코드/문서까지 신규 작성. 재실행 시 docker-compose 의 `frontend`/`gateway` 가 기동 중이어야 하고 service-role 키가 필요 | "재실행 가이드" 절에 따라 Playwright 재실행 후 결과/커버리지 갱신 |
| 시나리오 05 의 알림 행 도착 모사 | `handle_chat_insert` / `handle_todolist_change` 등 실제 트리거를 사용자 액션으로 발화시키는 것은 다른 스위트 (채팅, 워크아이템) 책임. 본 스위트는 행 도착 이후의 전달·표시 단계가 대상 | 트리거 자체의 사용자-facing 검증은 채팅/워크아이템 스위트에서 수행 |
