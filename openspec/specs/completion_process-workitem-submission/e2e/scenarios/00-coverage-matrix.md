# 프로세스 워크아이템 생성·제출 E2E 커버리지 매트릭스

## 범위
- 스위트 슬러그: `completion_process-workitem-submission`
- 원본 명세 ID: `completion_process-workitem-submission`
- 원본 명세:
  - `openspec/specs/completion_process-workitem-submission/spec.md`
- 백엔드/제품 계약:
  - 소유 백엔드: `services/completion` FastAPI 서비스 (`process_engine.py`)
  - API 경로(게이트웨이 `/completion/*` → `completion:8000/*`, 접두어 제거):
    - `POST /initiate` — 프로세스 인스턴스 시작, 초기 워크아이템을 `status` `TODO`로 생성
    - `POST /complete`, `POST /vision-complete` — 워크아이템을 `status` `SUBMITTED`로 생성·갱신
    - `POST /role-binding` — 프로세스 역할을 사용자 계정에 연결
  - 영속 계약: Supabase Postgres `proc_def`, `proc_def_version`, `bpm_proc_inst`, `todolist`, `users`
  - 테넌트 격리: 요청 `X-Forwarded-Host` subdomain → `DBConfigMiddleware` → tenant 범위 한정
  - 게이트웨이: nginx 리버스 프록시(`:8088`)가 브라우저 단일 진입점
- E2E 루트: `openspec/specs/completion_process-workitem-submission/e2e/`
- Playwright 명세: `openspec/specs/completion_process-workitem-submission/e2e/tests/completion_process-workitem-submission.spec.mjs`
- 결과 디렉터리: `openspec/specs/completion_process-workitem-submission/e2e/results/`

## 시나리오 목록
| ID | 시나리오 문서 | Playwright 테스트 제목 | 주요 동작 |
| --- | --- | --- | --- |
| 01 | `01-execute-process-submit-workitem.md` | `프로세스 정의를 실행하여 워크아이템을 제출한다` | 정의 맵에서 프로세스를 실행하고 역할 바인딩 후 폼을 제출 |
| 02 | `02-resubmit-existing-workitem.md` | `할 일 목록의 기존 워크아이템을 제출한다` | 할 일 목록의 기존 `TODO` 작업을 열어 폼을 제출 |
| 03 | `03-initiate-and-contract-isolation.md` | `인스턴스 시작과 누락·오류 계약 및 테넌트 격리를 검증한다` | `/initiate` 시작 계약, 400 오류 계약, 명시 버전, 테넌트 격리 검증 |

## 요구사항 커버리지
| 명세 | 요구사항 | 필수 수준 | 커버 시나리오 | 비고 |
| --- | --- | --- | --- | --- |
| `completion_process-workitem-submission` | 프로세스 인스턴스 시작 | SHALL | 03 | `/initiate`는 UI 진입점이 없어 프로토콜로 검증 |
| `completion_process-workitem-submission` | 워크아이템 제출 | SHALL | 01, 02 | 신규 제출(01)과 기존 워크아이템 갱신 제출(02) |
| `completion_process-workitem-submission` | 프로세스 역할 바인딩 | SHALL | 01 | 실행 다이얼로그 진입 시 `/role-binding` 호출 |
| `completion_process-workitem-submission` | 프로세스 정의 버전 해소 | SHALL | 01, 03 | 버전 미지정 운영 버전(01), 명시 버전(03) |
| `completion_process-workitem-submission` | 테넌트 격리 | SHALL | 01, 03 | 자사 테넌트 처리(01), 타 테넌트 분리(03) |

## 명세 시나리오 커버리지
| 명세 | 요구사항 | 명세 시나리오 | 커버 시나리오 | 사용자 검증 표면 |
| --- | --- | --- | --- | --- |
| `completion_process-workitem-submission` | 프로세스 인스턴스 시작 | 신규 인스턴스 시작 성공 | 03 | 프로토콜 검증(UI 없음): `POST /initiate` 200 + `TODO` 워크아이템 |
| `completion_process-workitem-submission` | 프로세스 인스턴스 시작 | 초기 활동을 찾을 수 없음 | 03 | 프로토콜 검증: `400` + `No initial activity found` |
| `completion_process-workitem-submission` | 프로세스 인스턴스 시작 | 담당 사용자 이메일을 해소할 수 없음 | 03 | 프로토콜 검증: `400` + `No default user email found` |
| `completion_process-workitem-submission` | 워크아이템 제출 | 폼 값을 담은 워크아이템 제출 성공 | 01 | 실행 폼 입력/제출 완료 버튼/인스턴스 목록 결과 화면 |
| `completion_process-workitem-submission` | 워크아이템 제출 | 기존 워크아이템 갱신 제출 | 02 | 할 일 목록 작업 열기/폼 입력/제출 완료 버튼 |
| `completion_process-workitem-submission` | 워크아이템 제출 | 프로세스 인스턴스 식별자 누락 | 03 | 프로토콜 검증: `400` + `Process instance id is required` |
| `completion_process-workitem-submission` | 프로세스 역할 바인딩 | 역할 매핑 해소 성공 | 01 | 실행 다이얼로그 역할 자동 바인딩 표시 |
| `completion_process-workitem-submission` | 프로세스 정의 버전 해소 | 명시한 버전으로 처리 | 03 | 프로토콜 검증: `version_tag`+`version` 지정 호출 |
| `completion_process-workitem-submission` | 프로세스 정의 버전 해소 | 버전 미지정 시 운영 버전 적용 | 01 | 실행 시 `version` 미지정으로 운영 정의 적용 |
| `completion_process-workitem-submission` | 테넌트 격리 | 테넌트별 데이터 분리 | 03 | 프로토콜 검증: 타 테넌트 subdomain 호출 시 분리 |

## 미검증 및 보류 항목
| 항목 | 사유 | 후속 조치 |
| --- | --- | --- |
| `POST /initiate`의 브라우저 UI 검증 | 저장소 프론트엔드(`services/frontend`)에 운영용 `/completion/initiate` 호출 경로가 없음(실 UI는 `/complete`로 인스턴스를 생성). `/initiate`는 외부 API 계약이라 시나리오 03 프로토콜로 검증 | 프론트엔드에 `/initiate` UI가 추가되면 브라우저 시나리오로 승격 |
| `POST /vision-complete` | `/complete`와 동일 핸들러(`handle_submit`)이며 이미지 첨부 시에만 분기. 결정적 이미지 입력 UI 흐름이 별도로 없음 | `/complete` 검증으로 핸들러 계약을 대표 검증 |

## 체크리스트
- [x] 모든 Requirement가 하나 이상의 E2E 시나리오에 매핑되어 있습니다.
- [x] 중요한 OpenSpec Scenario가 E2E 시나리오에 매핑되어 있거나 미검증 및 보류 항목에 기록되어 있습니다.
- [x] 사람이 읽는 요구사항명, 명세 시나리오명, 목적, 절차, 기대 결과는 한국어로 작성되어 있습니다.
- [x] 원본 OpenSpec에 영어 설명이 있더라도 E2E 문서에는 한국어 의미로 변환되어 있으며, API 경로·필드명·이벤트명 같은 계약 식별자만 원문으로 유지합니다.
- [x] 원본 명세가 하나의 백엔드 연계 피쳐 또는 응집된 사용자 workflow 범위이며, 마이크로서비스 전체 요약이나 프론트엔드 단독 명세가 아닙니다.
- [x] 원본 명세의 서비스 접두어 또는 도메인 구분자가 `frontend`, `ui`, `react`, `page`, `component` 같은 구현 레이어가 아닙니다.
- [x] E2E가 실행할 소유 백엔드 서비스/API/데이터 계약이 명확합니다.
- [x] 서비스 접두형 명세 ID를 사용하는 경우 스위트 슬러그가 동일한 값을 유지합니다.
- [x] E2E 시나리오, 테스트 스크립트, seed/stub, 실행 결과, 스크린샷은 `openspec/specs/completion_process-workitem-submission/e2e/` 아래에 응집되어 있습니다.
- [x] 사용자-facing 시나리오는 직접 API 요청이 아니라 브라우저 UI 상호작용으로 검증합니다.
- [x] 시나리오별 스크린샷 체크포인트가 매뉴얼에 재사용할 수 있는 UI 상태를 설명합니다.
- [x] 결과 경로가 `OUTPUT_CONTRACT.md`와 일치합니다.
