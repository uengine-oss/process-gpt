# E2E 시나리오 04: 로그인 사용자가 계정 설정 화면에서 본인 정보를 갱신한다

## 메타데이터
- 스위트 슬러그: `completion_tenant-user-administration`
- 원본 명세 ID: `completion_tenant-user-administration`
- 시나리오 ID: `04`
- Playwright 테스트 제목: `04 로그인 사용자가 계정 설정 화면에서 본인 정보를 갱신한다`
- 원본 명세:
  - `openspec/specs/completion_tenant-user-administration/spec.md`

## 목적
실제 프론트엔드의 계정 설정 화면(`/account-settings` → Account 탭) 에서 본인 이름(`username`) 을 수정하고 "저장" 버튼을 눌러 `AccountTab.updateUser` → `ProcessGPTBackend.updateUserInfo` → `ProcessGPTBackend.updateUser` → `POST /completion/update-user` 흐름을 트리거하고 200 응답을 검증한다.

## 사전 조건
- `docker-compose.e2e.yml` 의 `frontend`, `gateway`, `completion`, `auth`, `kong`, `rest`, `db` 가 실행 중.
- `e2e@uengine.org` 어드민 사용자가 `localhost` 테넌트에 시드되어 있어야 한다 (본인 계정 갱신을 위해).

## 테스트 데이터 및 Stub
| 이름 | 유형 | 경로 또는 route | 목적 |
| --- | --- | --- | --- |
| 어드민 시드 | seed | `openspec/specs/completion_agent-memory-chat/e2e/seed_files/e2e_seed.sql` | 본인 갱신 흐름의 로그인 사용자 |
| 새 사용자명 | runtime | `E2E_갱신_<timestamp%1000000>` | 매 실행마다 unique 이름으로 변경 검증 |

## 절차
1. `/auth/login` 으로 `e2e@uengine.org` / `e2epassword` 로그인.
2. `/account-settings` 로 이동, Account 탭이 기본으로 활성화된 상태에서 `formFields` (name, email) 가 fetch 되어 채워질 때까지 대기.
3. 사용자명 입력칸(첫 번째 `v-text-field type=text`) 의 값을 `E2E_갱신_<timestamp>` 로 변경한다.
4. 화면 하단의 "저장" (`accountTab.save`) 버튼을 클릭한다.

## 기대 결과
- 클릭 후 `POST /completion/update-user` 가 200 으로 응답한다.
- 응답 직후 `window.$app_.snackbar` 가 success 상태로 표시되고, 1초 후 페이지가 reload 된다 (테스트는 reload 직전 상태를 캡처).
- 백엔드는 `auth.users` 의 `user_metadata.name` 을 새 사용자명으로 갱신한다.

## 커버하는 요구사항
| 명세 | 요구사항 | 시나리오 |
| --- | --- | --- |
| `completion_tenant-user-administration` | 사용자·테넌트 관리 정보 갱신 | 관리 정보 갱신 성공 (사용자 갱신 경로) |

## 산출물
- 스크린샷 체크포인트:
  | 체크포인트 | 캡처할 UI 상태 | 예상 파일 | 매뉴얼용 캡션 |
  | --- | --- | --- | --- |
  | `04-account-tab-initial` | Account 탭 진입 상태 (기존 사용자 정보 로드 완료) | `process-gpt-completion_tenant-user-administration-04-account-tab-initial.png` | 계정 설정 Account 탭 초기 상태 |
  | `04-account-tab-input` | 사용자명 입력칸을 새 값으로 변경한 상태 | `process-gpt-completion_tenant-user-administration-04-account-tab-input.png` | 사용자 정보 갱신 입력 화면 |
  | `04-account-tab-response` | 저장 응답 직후 (snackbar success / reload 직전) | `process-gpt-completion_tenant-user-administration-04-account-tab-response.png` | 사용자 정보 갱신 결과 화면 |
- Trace/video: Playwright 실패 시 보존됩니다.
- 결과 JSON: `openspec/specs/completion_tenant-user-administration/e2e/results/results.json`
