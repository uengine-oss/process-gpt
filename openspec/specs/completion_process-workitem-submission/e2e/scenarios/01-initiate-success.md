# E2E 시나리오 01: 신규 프로세스 인스턴스 시작 성공 (백엔드 계약)

## 메타데이터
- 스위트 슬러그: `completion_process-workitem-submission`
- 원본 명세 ID: `completion_process-workitem-submission`
- 시나리오 ID: `01`
- Playwright 테스트 제목: `01 [backend-contract] 신규 프로세스 인스턴스 시작이 TODO 워크아이템을 반환한다`
- 분류: 백엔드 계약 전용 (스크린샷 의무 면제)
- 원본 명세:
  - `openspec/specs/completion_process-workitem-submission/spec.md`

## 목적
정상 정의(`wis_basic_process`) 에 대해 `POST /completion/initiate` 가 초기 활동을 자동 탐색하고 `status=TODO` 워크아이템을 반환하는 백엔드 계약을 검증한다. `POST /completion/initiate` 는 `services/frontend/src/**` 어디에서도 호출되지 않으며 (`grep` 결과 0건), 인스턴스 생성은 백엔드/스케줄러/외부 트리거가 수행하는 비-사용자 경로이다. 따라서 본 시나리오는 사용자 UI 트리거 경로가 없으므로 Real-Frontend Rule 의 스코프 재조정 규정에 따라 백엔드 계약 전용으로 분류한다.

## 사전 조건
- `docker-compose.e2e.yml` 스택과 `db-seed-workitem-submission` 시드가 완료되어 있다.
- 시드로 생성된 `wis_basic_process` 정의(`localhost` 테넌트, `submit_request` 초기 활동, role default `e2e-wis@uengine.org`) 가 존재한다.
- 게이트웨이 `gateway-wis`(포트 8090) 가 `/completion/*` → completion 으로 라우팅한다.

## 테스트 데이터 및 Stub
| 이름 | 유형 | 경로 또는 route | 목적 |
| --- | --- | --- | --- |
| `wis_basic_process` proc_def | seed | `openspec/specs/completion_process-workitem-submission/e2e/seed_files/e2e_seed.sql` | 초기 활동/role default 정상 정의 |
| Playwright `request` | runtime | `POST /completion/initiate` via `gateway-wis:8090` | 백엔드 계약 직접 호출 (UI 트리거 경로 없음) |

## 절차
1. Playwright `request` 가 `POST /completion/initiate` 에 `{ input: { process_definition_id: 'wis_basic_process' } }` 를 전송한다.
2. 응답 본문을 JSON 으로 파싱한다.
3. 반환된 `status`, `proc_def_id`, `activity_id`, `proc_inst_id` 를 검증한다.

## 기대 결과
- 응답 상태 코드는 `200`.
- 본문에 `status=TODO`, `proc_def_id='wis_basic_process'`, `activity_id='submit_request'`, 비어있지 않은 `proc_inst_id` 가 포함된다.

## 커버하는 요구사항
| 명세 | 요구사항 | 시나리오 |
| --- | --- | --- |
| `completion_process-workitem-submission` | 프로세스 인스턴스 시작 | 신규 인스턴스 시작 성공 |
| `completion_process-workitem-submission` | 프로세스 정의 버전 해소 | 버전 미지정 시 운영 버전 적용 (proc_def.definition 폴백) |

## 산출물
- 스크린샷 체크포인트: 없음 (백엔드 계약 전용, Real-Frontend Rule 스코프 재조정에 따라 면제).
- Trace/video: Playwright 실패 시 보존됩니다.
- 결과 JSON: `openspec/specs/completion_process-workitem-submission/e2e/results/results.json`
