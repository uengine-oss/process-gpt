# E2E 시나리오 03: 존재하지 않는 인스턴스로 후보 조회시 400을 반환한다

## 메타데이터
- 스위트 슬러그: `completion_process-activity-rework`
- 원본 명세 ID: `completion_process-activity-rework`
- 시나리오 ID: `03`
- Playwright 테스트 제목: `존재하지 않는 인스턴스로 후보 조회시 400을 반환한다`
- 원본 명세:
  - `openspec/specs/completion_process-activity-rework/spec.md`

## 목적
재작업 후보 조회 시 존재하지 않는 워크아이템을 지정하면 백엔드가 `400` 상태와 `No workitem found` 메시지를 반환해야 한다는 계약을 검증한다. 이 시나리오는 사용자가 직접 트리거하지 않는 백엔드 보호 경로이므로 게이트웨이를 통한 HTTP 호출(`request.post`)로 검증하며, 사용자-facing 흐름이 아니다.

## 사전 조건
- completion 서비스가 healthy 상태이고 nginx 게이트웨이(`:8088`)가 `/completion/*` 경로를 백엔드로 라우팅 중

## 테스트 데이터 및 Stub
| 이름 | 유형 | 경로 또는 route | 목적 |
| --- | --- | --- | --- |
| 미존재 인스턴스 ID | 입력 | `instanceId='__nonexistent__'`, `activityId='__nonexistent__'` | 워크아이템 미발견 분기 트리거 |

## 절차
1. Playwright `request` 픽스처로 `POST http://localhost:8088/completion/get-rework-activities` 에 `{ instanceId, activityId }` 전송
2. 응답 상태 코드와 본문을 확인

## 기대 결과
- 상태 코드는 `400`이다.
- 응답 본문의 `detail`은 `"No workitem found"`이다.

## 커버하는 요구사항
| 명세 | 요구사항 | 시나리오 |
| --- | --- | --- |
| `completion_process-activity-rework` | 재작업 가능 활동 조회 | 워크아이템을 찾을 수 없음 |

## 산출물
- 스크린샷 체크포인트: 본 시나리오는 사용자 UI를 동반하지 않는 백엔드 계약 검증이므로 스크린샷을 생성하지 않습니다.
- Trace/video: Playwright 실패 시 보존됩니다.
- 결과 JSON: `openspec/specs/completion_process-activity-rework/e2e/results/results.json`
