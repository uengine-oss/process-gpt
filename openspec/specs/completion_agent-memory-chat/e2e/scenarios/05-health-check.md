# E2E 시나리오 05: GET /multi-agent/health-check 가 healthy 상태를 반환한다

## 메타데이터
- 스위트 슬러그: `completion_agent-memory-chat`
- 원본 명세 ID: `completion_agent-memory-chat`
- 시나리오 ID: `05`
- Playwright 테스트 제목: `GET /multi-agent/health-check 가 healthy 상태를 반환한다`
- 원본 명세:
  - `openspec/specs/completion_agent-memory-chat/spec.md`

## 목적
헬스체크 라우트가 게이트웨이 경유로 정상 동작하며 `{status:"healthy"}` 를 반환하는지 확인하는 보조 프로토콜 시나리오입니다. UI 표면이 없으므로 스크린샷 매뉴얼 증거를 요구하지 않습니다.

## 사전 조건
- nginx 게이트웨이가 `/completion/*` 를 completion 컨테이너로 라우팅하고 있습니다.

## 테스트 데이터 및 Stub
| 이름 | 유형 | 경로 또는 route | 목적 |
| --- | --- | --- | --- |
| 헬스체크 | request | `GET /completion/multi-agent/health-check` | 상태 점검 응답 검증 |

## 절차
1. Playwright `request` 로 `GET /completion/multi-agent/health-check` 를 호출합니다.
2. 응답 상태와 JSON 본문을 검증합니다.

## 기대 결과
- 응답 상태는 `200` 입니다.
- 응답 본문은 `{"status":"healthy"}` 입니다.

## 커버하는 요구사항
| 명세 | 요구사항 | 시나리오 |
| --- | --- | --- |
| `completion_agent-memory-chat` | 에이전트 서비스 상태 점검 | 상태 점검 응답 |

## 산출물
- 스크린샷 체크포인트: 본 시나리오는 보조 프로토콜 검증으로 UI 표면이 없어 스크린샷 매뉴얼 증거를 요구하지 않습니다.
- Trace/video: Playwright 실패 시 보존됩니다.
- 결과 JSON: `openspec/specs/completion_agent-memory-chat/e2e/results/results.json`
