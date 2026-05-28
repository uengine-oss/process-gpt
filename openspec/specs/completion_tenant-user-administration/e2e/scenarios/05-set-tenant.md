# E2E 시나리오 05: 사용자가 로그인하면 자동으로 테넌트가 적용되고 테넌트 관리 화면이 열린다

## 메타데이터
- 스위트 슬러그: `completion_tenant-user-administration`
- 원본 명세 ID: `completion_tenant-user-administration`
- 시나리오 ID: `05`
- Playwright 테스트 제목: `05 사용자가 로그인하면 자동으로 테넌트가 적용되고 테넌트 관리 화면이 열린다`
- 원본 명세:
  - `openspec/specs/completion_tenant-user-administration/spec.md`

## 목적
실제 프론트엔드의 로그인 화면(`/auth/login`) 에서 어드민이 로그인 버튼을 클릭하면 `stores/auth.ts` 의 `signIn` 흐름이 자동으로 `backend.setTenant(window.$tenantName)` 를 호출하여 `POST /completion/set-tenant` 가 트리거된다. 본 시나리오는 (a) 로그인 사용자 동작으로 set-tenant 가 호출되어 200 응답을 반환하는지, (b) 후속 `/tenant/manage` 진입이 정상적으로 처리되는지 검증한다.

## 사전 조건
- `docker-compose.e2e.yml` 의 `frontend`, `gateway`, `completion`, `auth`, `kong`, `rest`, `db` 가 실행 중.
- `db-seed` 가 `localhost` 테넌트와 `e2e@uengine.org` 어드민 사용자를 생성한 상태.

## 테스트 데이터 및 Stub
| 이름 | 유형 | 경로 또는 route | 목적 |
| --- | --- | --- | --- |
| `localhost` 테넌트 | seed | `openspec/specs/completion_agent-memory-chat/e2e/seed_files/e2e_seed.sql` | `window.$tenantName` 가 `localhost` 로 resolve 되도록 보장 |
| 어드민 시드 | seed | (동일) | 로그인 가능한 어드민 |

## 절차
1. `/auth/login` 으로 진입한다.
2. 이메일 입력칸에 `e2e@uengine.org` 를 입력한다.
3. 비밀번호 입력칸에 `e2epassword` 를 입력한다.
4. "Remember me" 체크박스를 체크한다 (LoginForm 의 required 룰).
5. 로그인 버튼(`.cp-login`) 을 클릭한다.
6. 로그인 직후 자동으로 `POST /completion/set-tenant` 가 트리거된다 (stores/auth.ts:57).
7. 로그인이 성공하여 `/auth/login` 이외의 URL로 이동한 뒤, `/tenant/manage` 로 명시적으로 이동하여 테넌트 관리 화면을 확인한다.

## 기대 결과
- 로그인 버튼 클릭 직후 `POST /completion/set-tenant` 가 200 으로 응답한다.
- 백엔드는 `auth.users.app_metadata.tenant_id` 를 갱신한다.
- 페이지가 `/auth/login` 을 벗어나 `/definition-map` 또는 `/tenant/manage` 로 이동한다.
- 후속 `/tenant/manage` 진입 시 테넌트 관리 화면이 렌더링된다 (소유 테넌트 카드가 비어 있더라도 페이지 자체는 정상 로드).

## 커버하는 요구사항
| 명세 | 요구사항 | 시나리오 |
| --- | --- | --- |
| `completion_tenant-user-administration` | 사용자·테넌트 관리 정보 갱신 | 관리 정보 갱신 성공 (테넌트 갱신 경로) |

## 산출물
- 스크린샷 체크포인트:
  | 체크포인트 | 캡처할 UI 상태 | 예상 파일 | 매뉴얼용 캡션 |
  | --- | --- | --- | --- |
  | `05-login-input` | 어드민 이메일·비밀번호·체크박스 입력 완료 상태 | `process-gpt-completion_tenant-user-administration-05-login-input.png` | 로그인 화면 입력 완료 상태 |
  | `05-tenant-manage-response` | 로그인 → set-tenant 200 → /tenant/manage 진입 후 화면 | `process-gpt-completion_tenant-user-administration-05-tenant-manage-response.png` | 테넌트 적용 후 테넌트 관리 화면 |
- Trace/video: Playwright 실패 시 보존됩니다.
- 결과 JSON: `openspec/specs/completion_tenant-user-administration/e2e/results/results.json`
