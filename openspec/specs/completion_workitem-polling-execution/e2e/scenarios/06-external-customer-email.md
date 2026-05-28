# E2E 시나리오 06: 외부 고객 안내 이메일 발송

## 메타데이터
- 스위트 슬러그: `completion_workitem-polling-execution`
- 원본 명세 ID: `completion_workitem-polling-execution`
- 시나리오 ID: `06`
- Playwright 테스트 제목: `다음 활동 담당자가 external_customer 인 경우 외부 폼 링크 안내 이메일이 발송된다`
- 원본 명세:
  - `openspec/specs/completion_workitem-polling-execution/spec.md`
- 상태: **보류** (SMTP capture 인프라 필요)

## 목적
폴링 워커가 다음 활동을 진행할 때 담당 역할 endpoint 가 `external_customer` 이고 완료된 데이터에서 고객 이메일을 확인할 수 있으면, `smtp_handler` 모듈을 통해 외부 폼 링크가 포함된 안내 이메일을 고객에게 발송한다. 직접 구현체는 `services/completion/polling_service/smtp_handler.py` 의 발송 함수이며, 호출 지점은 `workitem_processor.py` 의 `execute_next_activity` 내부 external_customer 분기이다.

## 사전 조건
- `docker-compose.e2e.yml` 에 SMTP capture 컨테이너(예: `mock-smtp`, aiosmtpd 기반)가 추가되어 있어야 합니다.
- `completion-polling` 의 환경변수가 SMTP host 를 `mock-smtp` 로 가리키도록 override 되어야 합니다.
- 본 스위트 고유 시드:
  - `proc_def` 에 두 개의 활동: `act_form` (userTask, 사용자 입력) → `act_external` (userTask, role endpoint=`external_customer`).
  - `bpm_proc_inst.role_bindings` 에 `[{"name":"external_customer","endpoint":["external_customer"]}]` + 고객 이메일을 담은 `variables_data`.
  - SUBMITTED `act_form` 워크아이템.
- mock-llm-ate 가 `prompt_completed` / `prompt_next_activity` 응답에 외부 고객 분기를 포함해야 합니다.

## 테스트 데이터 및 Stub
| 이름 | 유형 | 경로 또는 route | 목적 |
| --- | --- | --- | --- |
| `mock-smtp` | container | `openspec/specs/completion_workitem-polling-execution/e2e/scripts/mock_smtp.py` (작성 필요) | 발송된 메일을 `/captures/smtp-messages.jsonl` 로 기록 |
| `e2e_seed.sql` | seed | `openspec/specs/completion_workitem-polling-execution/e2e/seed_files/e2e_seed.sql` | external_customer role binding + 고객 이메일 변수 시드 |
| `mock_llm.py` (확장) | stub | `openspec/specs/completion_automated-task-execution/e2e/scripts/mock_llm.py` | external_customer 활동 진행 분기 |

## 절차
1. 사용자가 로그인 후 `/todolist` 에서 `act_form` 카드를 입력 후 제출합니다.
2. 폴링 워커가 `act_form` 을 DONE 처리하고 `act_external` 활동을 진행합니다.
3. 사용자가 `/todolist` 새로고침 후 `act_external` 카드가 별도의 처리자 상태로 표시되는지 확인합니다 (UI 표면 셀렉터는 본 스위트 활성화 시 확정).
4. 테스트는 `mock-smtp` 의 capture 파일을 검사해 메일 발송을 검증합니다.

## 기대 결과
- `mock-smtp` capture 파일에 1건의 메일이 기록됩니다. 메일에는 외부 폼 링크 URL 과 고객 이메일 수신자가 포함되어 있어야 합니다.
- `act_external` 워크아이템이 `user_id='external_customer'` 또는 등가의 외부 처리자 식별자로 생성됩니다.

## 커버하는 요구사항
| 명세 | 요구사항 | 시나리오 |
| --- | --- | --- |
| `completion_workitem-polling-execution` | 외부 고객 대상 이메일 안내 | 외부 고객 안내 이메일 발송 |

## 산출물
- 스크린샷 체크포인트:
  | 체크포인트 | 캡처할 UI 상태 | 예상 파일 | 매뉴얼용 캡션 |
  | --- | --- | --- | --- |
  | `06-form-submitted` | act_form 제출 직후 화면 | `process-gpt-completion_workitem-polling-execution-06-form-submitted.png` | 사용자 활동 제출 직후 |
  | `06-external-activity` | act_external 카드가 외부 처리자 상태로 노출 | `process-gpt-completion_workitem-polling-execution-06-external-activity.png` | 외부 고객 처리 대기 상태 |
- Trace/video: Playwright 실패 시 보존됩니다.
- 결과 JSON: `openspec/specs/completion_workitem-polling-execution/e2e/results/results.json`.
- SMTP capture: `openspec/specs/completion_workitem-polling-execution/e2e/results/artifacts/smtp-captures/smtp-messages.jsonl`.

## 보류 사유
SMTP 는 기존 E2E 인프라에 없는 새 boundary 이다. (a) aiosmtpd 기반 `mock-smtp` 컨테이너 추가, (b) `smtp_handler` 환경변수(또는 monkey-patch) 로 SMTP host 주입, (c) capture 디렉터리 마운트, (d) `external_customer` role_binding 시드 등 4건의 인프라 변경이 필요하다. fcm-service capture 패턴([[notifications-updated-at-missing]] 인근의 firebase_patch.py 와 유사) 을 SMTP 에 동일하게 적용할 수 있으나, 별도 작업으로 분리하는 것이 권장된다.
