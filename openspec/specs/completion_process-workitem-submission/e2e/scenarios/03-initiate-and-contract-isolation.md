# E2E 시나리오 03: 인스턴스 시작과 누락·오류 계약 및 테넌트 격리를 검증한다

## 메타데이터
- 스위트 슬러그: `completion_process-workitem-submission`
- 원본 명세 ID: `completion_process-workitem-submission`
- 시나리오 ID: `03`
- Playwright 테스트 제목: `인스턴스 시작과 누락·오류 계약 및 테넌트 격리를 검증한다`
- 원본 명세:
  - `openspec/specs/completion_process-workitem-submission/spec.md`

## 목적
이 시나리오는 사용자-facing 흐름이 아닌 비-UI 프로토콜 검증이다. `POST /initiate`는 저장소 프론트엔드에 운영용 호출 경로가 없는 외부 API 계약이므로 브라우저 시나리오로 표현할 수 없다. 따라서 `POST /initiate`의 인스턴스 시작 성공 계약, 초기 활동·기본 사용자 누락 시 `400` 오류 계약, `POST /complete`의 식별자 누락 `400` 계약, 명시 버전 적용, 그리고 요청 subdomain 기반 테넌트 격리를 게이트웨이 경유 HTTP 요청으로 검증한다.

## 사전 조건
- Docker Compose 스택(`docker-compose.e2e.yml`)이 기동되어 있고 `gateway`(nginx `:8088`)와 `completion`, `db`, `kong` 컨테이너가 정상이다.
- 본 스위트 seed로 다음 프로세스 정의가 등록되어 있다.
  - `e2e_pws_leave` (`localhost`): 시작 이벤트·초기 활동·역할 기본 담당자를 갖춘 정상 정의. `proc_def_version`에 명시 버전(`version_tag` `major`, `version` `2`) 행도 함께 시드된다.
  - `e2e_pws_no_initial` (`localhost`): 시작 이벤트로 이어지는 초기 활동이 없는 정의(`No initial activity found` 검증용).
  - `e2e_pws_no_user` (`localhost`): 초기 활동의 역할에 기본 사용자가 없는 정의(`No default user email found` 검증용).
  - `e2e_pws_tenant_b` (`tenant-b`): 타 테넌트 전용 정의(격리 검증용).
- 모든 요청은 게이트웨이(`/completion/*`)를 경유하며, `X-Forwarded-Host` 헤더로 요청 테넌트 subdomain을 지정한다.

## 테스트 데이터 및 Stub
| 이름 | 유형 | 경로 또는 route | 목적 |
| --- | --- | --- | --- |
| `e2e_seed.sql` | seed | `openspec/specs/completion_process-workitem-submission/e2e/seed_files/e2e_seed.sql` | 정상·오류·격리 검증용 프로세스 정의를 결정적으로 준비 |
| `POST /completion/initiate` | route | 게이트웨이 → `completion:8000/initiate` | 인스턴스 시작 및 오류 계약 검증 |
| `POST /completion/complete` | route | 게이트웨이 → `completion:8000/complete` | 식별자 누락 `400` 계약 검증 |
| `X-Forwarded-Host` 헤더 | 요청 헤더 | `localhost` / `tenant-b.example.com` | 테넌트 subdomain 분리 검증 |

## 절차
1. 게이트웨이로 `POST /completion/initiate`에 정상 정의 `e2e_pws_leave`와 `email`을 담아 요청한다.
2. 초기 활동이 없는 정의 `e2e_pws_no_initial`로 `POST /completion/initiate`를 요청한다.
3. `email`이 없고 역할 기본값도 없는 정의 `e2e_pws_no_user`로 `POST /completion/initiate`를 요청한다.
4. `process_instance_id` 없이 `POST /completion/complete`를 요청한다.
5. `version_tag` `major`, `version` `2`를 명시해 `POST /completion/initiate`를 요청한다.
6. `X-Forwarded-Host`를 `tenant-b.example.com`으로 지정해 `tenant-b` 전용 정의로 요청하고, 같은 정의를 `localhost`로 요청해 결과를 비교한다.

## 기대 결과
- 1번 요청: 응답 `200`이며 본문에 `proc_inst_id`, `proc_def_id`, `activity_id`, `status`가 `TODO`인 워크아이템 정보가 포함된다.
- 2번 요청: 응답 `400`이며 메시지에 `No initial activity found`가 포함된다.
- 3번 요청: 응답 `400`이며 메시지에 `No default user email found`가 포함된다.
- 4번 요청: 응답 `400`이며 메시지에 `Process instance id is required`가 포함된다.
- 5번 요청: 응답 `200`이며 명시한 버전(`version` `2`)의 정의가 적용되어 인스턴스가 시작된다.
- 6번 요청: `tenant-b` subdomain 요청은 `tenant-b` 정의만 처리할 수 있고, `localhost` subdomain으로 같은 `tenant-b` 정의를 시작하려는 요청은 정의를 찾지 못해 실패한다(테넌트 간 정의가 분리됨).

## 커버하는 요구사항
| 명세 | 요구사항 | 시나리오 |
| --- | --- | --- |
| `completion_process-workitem-submission` | 프로세스 인스턴스 시작 | 신규 인스턴스 시작 성공 / 초기 활동을 찾을 수 없음 / 담당 사용자 이메일을 해소할 수 없음 |
| `completion_process-workitem-submission` | 워크아이템 제출 | 프로세스 인스턴스 식별자 누락 |
| `completion_process-workitem-submission` | 프로세스 정의 버전 해소 | 명시한 버전으로 처리 |
| `completion_process-workitem-submission` | 테넌트 격리 | 테넌트별 데이터 분리 |

## 산출물
- 스크린샷 체크포인트:
  | 체크포인트 | 캡처할 UI 상태 | 예상 파일 | 매뉴얼용 캡션 |
  | --- | --- | --- | --- |
  | 해당 없음 | 비-UI 프로토콜 검증 시나리오로 사용자 화면 전이가 없어 스크린샷 체크포인트를 두지 않는다 | - | - |
- Trace/video: Playwright 실패 시 보존됩니다.
- 결과 JSON: `openspec/specs/completion_process-workitem-submission/e2e/results/results.json`
