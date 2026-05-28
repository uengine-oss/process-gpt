# E2E 시나리오 03: 초대 받은 사용자가 초기 설정 화면에서 사용자명과 비밀번호를 저장한다

## 메타데이터
- 스위트 슬러그: `completion_tenant-user-administration`
- 원본 명세 ID: `completion_tenant-user-administration`
- 시나리오 ID: `03`
- Playwright 테스트 제목: `03 초대 받은 사용자가 초기 설정 화면에서 사용자명과 비밀번호를 저장한다`
- 원본 명세:
  - `openspec/specs/completion_tenant-user-administration/spec.md`

## 목적
실제 프론트엔드의 초기 설정 화면(`/auth/initial-setting`) 에서 사용자명·비밀번호·비밀번호 확인 입력 후 "초기 설정 완료" 버튼을 클릭하여 `POST /completion/set-initial-info` 가 호출되고 200 응답이 반환되는 경로를 검증한다.

## 사전 조건
- `docker-compose.e2e.yml` 의 `frontend`, `gateway`, `completion`, `auth`, `db` 가 실행 중.
- `InitialSettingForm.vue` 는 `localStorage.uid` 를 `user_id` 로 사용하므로, 로그인 상태에서 진입해야 한다. 본 시나리오는 어드민 로그인 후 동일 사용자의 비밀번호·사용자명을 재설정하는 흐름으로 검증한다.

## 테스트 데이터 및 Stub
| 이름 | 유형 | 경로 또는 route | 목적 |
| --- | --- | --- | --- |
| 어드민 시드 | seed | `openspec/specs/completion_agent-memory-chat/e2e/seed_files/e2e_seed.sql` | `localStorage.uid` 채우기 위한 사전 로그인 |
| 사용자명 | runtime | `E2E_<timestamp>` | 매 실행마다 unique 사용자명 |
| 신규 비밀번호 | runtime | `e2eNewPass1!` | InitialSettingForm 의 비밀번호 정책(>=8자) 충족 |

## 절차
1. `/auth/login` 으로 어드민 (`e2e@uengine.org`) 로그인하여 `localStorage.uid` 를 채운다.
2. `page.on('dialog')` 핸들러로 성공 alert 을 자동 수락하도록 등록한다.
3. `/auth/initial-setting` 로 이동하여 `InitialSettingForm` 을 연다.
4. 사용자명 입력칸(`v-text-field type=text`) 에 `E2E_<timestamp>` 를 입력한다.
5. 새 비밀번호 입력칸(`type=password`, 첫 번째) 에 `e2eNewPass1!` 를 입력한다.
6. 비밀번호 확인 입력칸(`type=password`, 두 번째) 에 동일한 값을 입력한다.
7. "초기 설정 완료" 버튼을 클릭한다.

## 기대 결과
- 클릭 후 `POST /completion/set-initial-info` 가 200 으로 응답한다.
- 응답 직후 form 의 성공 처리 로직(`alert` → `/auth/login` redirect) 이 트리거된다 (dialog 핸들러가 자동 수락하여 테스트는 진행).
- 백엔드는 GoTrue admin API 로 비밀번호와 user_metadata 를 업데이트하고 success 응답을 반환한다.

## 커버하는 요구사항
| 명세 | 요구사항 | 시나리오 |
| --- | --- | --- |
| `completion_tenant-user-administration` | 초기 정보 설정 | 초기 정보 설정 성공 |

## 산출물
- 스크린샷 체크포인트:
  | 체크포인트 | 캡처할 UI 상태 | 예상 파일 | 매뉴얼용 캡션 |
  | --- | --- | --- | --- |
  | `03-initial-setting-initial` | 초기 설정 화면 진입 상태 | `process-gpt-completion_tenant-user-administration-03-initial-setting-initial.png` | 초기 설정 화면 초기 상태 |
  | `03-initial-setting-input` | 사용자명·비밀번호·비밀번호 확인 입력 완료 | `process-gpt-completion_tenant-user-administration-03-initial-setting-input.png` | 초기 설정 정보 입력 화면 |
  | `03-initial-setting-response` | 초기 설정 저장 응답 직후 (redirect 직전) | `process-gpt-completion_tenant-user-administration-03-initial-setting-response.png` | 초기 설정 완료 결과 화면 |
- Trace/video: Playwright 실패 시 보존됩니다.
- 결과 JSON: `openspec/specs/completion_tenant-user-administration/e2e/results/results.json`
