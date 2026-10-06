# E2E 결과 — 에이전트 SDK 워크아이템 점유 만료·회수 — 2026-10-06

## 요약
| 서비스 | 대상 버전 | 결과 |
|---|---|---|
| deepagents | SDK **0.10.1** | **6/6 PASS** |
| codex | SDK 0.10.0 | **6/6 PASS** |
| cli-agent | SDK 0.10.0 | **5/6 PASS**, SVC-LEASE-05 SKIP |
| deepagents | SDK 0.9.0 (lease 이전, 대조군) | 01 FAIL, 04·05·06 ERROR — 회귀를 잡는다 |

cli-agent 의 05 는 두 작업이 모두 `COMPLETED`여야 비교할 수 있다. 로컬 litellm proxy 가 Claude
모델 호출에 응답하지 않아 cli-agent 의 실행은 타임아웃(`FAILED`)으로 끝난다. lease 판정
(01–04, 06)에는 영향이 없다 — 오히려 실제 claude CLI 서브프로세스가 LLM 을 기다리며 오래 도는
구간에서 연장과 회수를 확인했다.

## 대조군: lease 이전 SDK 0.9.0 (deepagents)
| ID | 관찰 |
|---|---|
| SVC-LEASE-01 | 점유는 되지만 `lease_until`이 비어 있음 — 이 워커가 죽으면 아무도 회수하지 못한다 |
| SVC-LEASE-04 | A 를 죽인 뒤 B 가 끝내 점유하지 않음(대기 시간 초과) — 고아 `STARTED` |
| SVC-LEASE-05·06 | 04 의 준비 단계가 실패해 판정 불가(ERROR) |

## 실측 (테스트용 lease 8초 / heartbeat 2초)
같은 날 lease 20초로 수동 검증한 수치(재점유 23–25초, 이론 상한 lease+폴링 10초=30초 이내):

| 서비스 | 정상 수행 중 연장 유지 | kill -9 후 재점유 | 끝 상태 |
|---|---|---|---|
| deepagents | 23초 수행(lease 의 1.2배) | 25초 | `COMPLETED`, `claim_count`=2 |
| cli-agent | 56초 수행(2.8배) | 23초 | `FAILED`(타임아웃), `claim_count`=2 |
| codex | 40초 수행(2배) | 25초 | `COMPLETED`, `task_completed` 1건 |

운영 기본값(lease 120초)으로 환산하면 워커 사망 후 재점유까지 약 60–130초다.

## 이번 검증에서 드러난 것
1. **실행기가 종결 상태 없이 반환하면 고아가 남는다(SVC-LEASE-03 위반 경로).** cli-agent 는
   출력 형식 불일치처럼 실행기가 `error` 이벤트만 남기고 예외 없이 반환하면, 런타임이 정상
   종료로 보고 점유를 풀어 작업이 `STARTED`·`lease_until` 비어 있음으로 남는다. 첫 수동 실행에서
   CLI 가 "Not logged in"으로 끝났을 때 관찰했다. lease 이전에도 같은 고아였으므로 회귀는 아니다.
   이 suite 는 그 경로를 결정적으로 재현하지 못한다 — 재현되면 03 이 실패하도록 판정은 되어 있다.
2. **`notice` 이벤트가 저장되지 않는다.** cli-agent 가 보내는 `event_type = 'notice'`가
   `event_type_enum`에 없어 `record_events_bulk`가 세 번 재시도 끝에 실패하고 그 묶음이 유실된다.
   로컬 DB 와 인프라 저장소의 스키마 정의 모두에 없다. lease 와 무관.
3. **deepagents 는 한 번의 실행에 `task_completed`를 2건 남긴다.** 그래서 05 의 기준을 같은
   서비스의 정상 수행으로 잡았다.
4. 로컬 실행 환경 메모: codex 로컬 이미지 `process-gpt-codex:local`이 amd64 라 arm64 맥에서
   bwrap 이 실패한다(`Failed to make / slave`). codex `.env.example`의 이미지 이름
   `processgpt-codex:local`은 실제 이름과 다르다. codex 의 샘플링 프록시는 `temperature`를
   붙여 gpt-5 계열이 거절한다. 종료 유예(`CODEX_POLLING_DRAIN_SECONDS`, 기본 600초) 동안
   포트를 쥐고 있어 다음 워커가 같은 포트로 뜨지 못한다 — suite 는 5초로 둔다.

## 남은 과제
- [ ] 1 의 경로에서 작업이 `STARTED`로 남지 않게 하고, 그 경로를 재현하는 시나리오를 더한다
- [ ] cli-agent 가 로컬에서 `COMPLETED`까지 가는 자격증명을 마련해 05 를 건너뛰지 않게 한다
- [ ] 운영 배포 후 `STARTED` 행의 `lease_until`이 채워지는지 확인한다(01 의 운영 관찰)
- [ ] 도입 이전의 고아 `STARTED` 행(`lease_until` 없음)을 운영자가 확인 후 정리한다
