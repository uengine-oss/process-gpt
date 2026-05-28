# E2E 시나리오 02: 관리자가 사용자 관리 화면에서 신규 이메일을 초대한다

## 메타데이터
- 스위트 슬러그: `completion_tenant-user-administration`
- 원본 명세 ID: `completion_tenant-user-administration`
- 시나리오 ID: `02`
- Playwright 테스트 제목: `02 관리자가 사용자 관리 화면에서 신규 이메일을 초대한다`
- 원본 명세:
  - `openspec/specs/completion_tenant-user-administration/spec.md`

## 목적
실제 프론트엔드 어드민 화면(`/account-settings` → ManageAccess 탭 → 사용자 추가 다이얼로그) 에서 이메일을 입력하고 초대 버튼을 클릭하여 `POST /completion/invite-user` 가 호출되고 200 응답이 반환되는 경로를 검증한다.

## 사전 조건
- `docker-compose.e2e.yml` 의 `frontend`, `gateway`, `completion`, `auth`, `kong`, `rest`, `db` 가 모두 실행 중.
- `db-seed` 가 어드민 사용자 `e2e@uengine.org` / 비밀번호 `e2epassword` 를 `localhost` 테넌트에 `is_admin=true` 로 생성.
- 가입되지 않은 신규 이메일을 매 실행마다 생성하여 초대 충돌을 피한다.

## 테스트 데이터 및 Stub
| 이름 | 유형 | 경로 또는 route | 목적 |
| --- | --- | --- | --- |
| 어드민 시드 | seed | `openspec/specs/completion_agent-memory-chat/e2e/seed_files/e2e_seed.sql` | `e2e@uengine.org` 어드민 로그인 / 테넌트 `localhost` |
| 초대 대상 이메일 | runtime | `e2e-invite-<timestamp>@uengine.org` | 매 실행마다 unique 이메일로 충돌 회피 |
| LLM/SMTP | stub | — | invite-user 백엔드는 SMTP 미설정 시에도 graceful 성공 경로 반환 (이메일 발송 자체는 검증하지 않음) |

## 절차
1. `/auth/login` 으로 진입하여 `e2e@uengine.org` / `e2epassword` 로 로그인한다.
2. 로그인 직후 `/account-settings` 로 이동하여 계정 설정 화면을 연다.
3. 상단 탭에서 "ManageAccess" (사용자 관리) 탭을 클릭한다.
4. 사용자 목록 상단의 "사용자 추가" 버튼을 클릭하여 초대 다이얼로그를 연다.
5. `InviteUserCard` 다이얼로그의 이메일 입력칸에 `e2e-invite-<timestamp>@uengine.org` 를 입력한다.
6. "초대" (Send Invitation) 버튼을 클릭한다.

## 기대 결과
- 클릭 후 `POST /completion/invite-user` 가 200 으로 응답한다.
- 응답 본문에 `success`/`user`/`invited`/`message` 중 하나 이상의 키가 포함된다.
- 다이얼로그 UI 가 초대 결과 상태로 변경된다 (성공 알림 또는 사용자 행 추가).

## 커버하는 요구사항
| 명세 | 요구사항 | 시나리오 |
| --- | --- | --- |
| `completion_tenant-user-administration` | 사용자 초대 | 사용자 초대 성공 |

## 산출물
- 스크린샷 체크포인트:
  | 체크포인트 | 캡처할 UI 상태 | 예상 파일 | 매뉴얼용 캡션 |
  | --- | --- | --- | --- |
  | `02-account-settings-initial` | 어드민 로그인 직후 `/account-settings` 초기 화면 | `process-gpt-completion_tenant-user-administration-02-account-settings-initial.png` | 계정 설정 화면 진입 상태 |
  | `02-invite-input` | 사용자 추가 다이얼로그에 초대 이메일 입력 완료 | `process-gpt-completion_tenant-user-administration-02-invite-input.png` | 사용자 초대 정보 입력 화면 |
  | `02-invite-response` | 초대 버튼 클릭 후 응답 처리 완료 | `process-gpt-completion_tenant-user-administration-02-invite-response.png` | 사용자 초대 완료 결과 화면 |
- Trace/video: Playwright 실패 시 보존됩니다.
- 결과 JSON: `openspec/specs/completion_tenant-user-administration/e2e/results/results.json`
