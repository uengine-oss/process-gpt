# E2E 시나리오 07: 역할 기본값 즉시 해소 (백엔드 계약)

## 메타데이터
- 스위트 슬러그: `completion_process-workitem-submission`
- 원본 명세 ID: `completion_process-workitem-submission`
- 시나리오 ID: `07`
- Playwright 테스트 제목: `07 [backend-contract] 역할 기본값이 있으면 LLM 없이 roleBindings 를 반환한다`
- 분류: 백엔드 계약 전용 (스크린샷 의무 면제)
- 원본 명세:
  - `openspec/specs/completion_process-workitem-submission/spec.md`

## 목적
`POST /completion/role-binding` 이 정의에 `default` 가 있는 역할을 LLM 호출 없이 즉시 반환하는 백엔드 계약을 검증한다. 실제 프런트엔드 `ProcessGPTExecute.vue` 는 `hasDefaultRole === false` 분기에서만 `/role-binding` 을 호출하므로 (`ProcessGPTBackend.bindRole()`), 본 시나리오(`hasDefaultRole === true` 경로) 는 사용자 UI 에서 발화되지 않는다.

## 사전 조건
- `docker-compose.e2e.yml` 스택과 시드가 완료되어 있다.
- `wis_basic_process` 정의의 `requester` 역할에 `default='e2e-wis@uengine.org'` 가 설정되어 있다.

## 테스트 데이터 및 Stub
| 이름 | 유형 | 경로 또는 route | 목적 |
| --- | --- | --- | --- |
| `wis_basic_process` proc_def | seed | `e2e_seed.sql` | role default 보유 정의 |

## 절차
1. Playwright `request` 가 `POST /completion/role-binding` 에 `{ input: { proc_def_id: 'wis_basic_process', roles: [{ name: 'requester' }] } }` 를 전송한다.
2. 응답 본문 JSON 을 파싱하고 `roleBindings[0].userId` 를 검증한다.

## 기대 결과
- 응답 상태 코드는 `200`.
- 응답 본문의 `roleBindings` 배열이 비어있지 않으며 첫 매핑의 `userId` 가 `e2e-wis@uengine.org` 이다.

## 커버하는 요구사항
| 명세 | 요구사항 | 시나리오 |
| --- | --- | --- |
| `completion_process-workitem-submission` | 프로세스 역할 바인딩 | 역할 매핑 해소 성공 |

## 산출물
- 스크린샷 체크포인트: 없음 (백엔드 계약 전용).
- Trace/video: Playwright 실패 시 보존됩니다.
- 결과 JSON: `openspec/specs/completion_process-workitem-submission/e2e/results/results.json`
