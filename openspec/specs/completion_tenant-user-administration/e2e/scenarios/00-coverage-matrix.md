# completion_tenant-user-administration E2E 커버리지 매트릭스

## 범위
- 스위트 슬러그: `completion_tenant-user-administration`
- 원본 명세 ID: `completion_tenant-user-administration`
- 원본 명세:
  - `openspec/specs/completion_tenant-user-administration/spec.md`
- 백엔드/제품 계약:
  - `services/completion` FastAPI 서비스의 사용자·테넌트 관리 라우트
  - API 라우트: `POST /create-user`, `POST /invite-user`, `POST /set-initial-info`, `POST /update-user`, `POST /set-tenant`
  - 영속성: Supabase `auth.users` 관리자 API, `public.users` 테이블 (테넌트 스코프)
  - 게이트웨이: 공유 nginx `gateway` (port 8088) 가 `/completion/*` 를 백엔드로 프록시
- E2E 루트: `openspec/specs/completion_tenant-user-administration/e2e/`
- Playwright 명세: `openspec/specs/completion_tenant-user-administration/e2e/tests/completion_tenant-user-administration.spec.mjs`
- 결과 디렉터리: `openspec/specs/completion_tenant-user-administration/e2e/results/`

## 재사용 산출물
- `docker-compose.e2e.yml` 의 `frontend`, `gateway`, `completion`, `kong`, `auth`, `rest`, `db`, `db-seed` 서비스를 그대로 사용한다.
- 공유 게이트웨이 nginx 설정 (`openspec/specs/completion_agent-memory-chat/e2e/docker/nginx.e2e.conf`) 의 `/completion/` 프록시 경로를 재사용한다.
- 기존 `db-seed` 가 만드는 `localhost` 테넌트와 어드민 사용자 `e2e@uengine.org` (`11111111-1111-1111-1111-111111111111`) 를 사전 조건 데이터로 재사용한다.
- 로그인 헬퍼는 `completion_agent-memory-chat` 의 `login(page)` 패턴(`.cp-id input`, `.cp-pwd input`, `.cp-login`) 을 동일하게 사용한다.

## 시나리오 목록
| ID | 시나리오 문서 | Playwright 테스트 제목 | 주요 동작 |
| --- | --- | --- | --- |
| 01 | `01-create-user.md` | (스코프 조정 필요 — 본 이터레이션에서 미구현) | OrganizationChartChat LLM 채팅 흐름으로 신규 사용자 생성 (후속 세션) |
| 02 | `02-invite-user.md` | `02 관리자가 사용자 관리 화면에서 신규 이메일을 초대한다` | `/account-settings` ManageAccess → 사용자 추가 다이얼로그 → 초대 |
| 03 | `03-set-initial-info.md` | `03 초대 받은 사용자가 초기 설정 화면에서 사용자명과 비밀번호를 저장한다` | `/auth/initial-setting` 폼 → 저장 |
| 04 | `04-update-user.md` | `04 로그인 사용자가 계정 설정 화면에서 본인 정보를 갱신한다` | `/account-settings` Account 탭 → 사용자명 변경 → 저장 |
| 05 | `05-set-tenant.md` | `05 사용자가 테넌트 관리 화면에서 테넌트를 선택해 적용한다` | `/tenant/manage` → `localhost` 카드 클릭 |

## 요구사항 커버리지
| 명세 | 요구사항 | 필수 수준 | 커버 시나리오 | 비고 |
| --- | --- | --- | --- | --- |
| `completion_tenant-user-administration` | 사용자 생성 | SHALL | 01 (보류) | OrganizationChartChat LLM 흐름 필요 — `미검증 및 보류 항목` 참조 |
| `completion_tenant-user-administration` | 사용자 초대 | SHALL | 02 | `POST /invite-user`, 실제 ManageAccess 다이얼로그 |
| `completion_tenant-user-administration` | 초기 정보 설정 | SHALL | 03 | `POST /set-initial-info`, 실제 InitialSettingForm |
| `completion_tenant-user-administration` | 사용자·테넌트 관리 정보 갱신 | SHALL | 04, 05 | `POST /update-user`, `POST /set-tenant` 두 라우트 모두 실제 UI 로 커버 |

## 명세 시나리오 커버리지
| 명세 | 요구사항 | 명세 시나리오 | 커버 시나리오 | 사용자 검증 표면 |
| --- | --- | --- | --- | --- |
| `completion_tenant-user-administration` | 사용자 생성 | 사용자 생성 성공 | 01 (보류) | OrganizationChartChat 채팅 + 차트 노드 |
| `completion_tenant-user-administration` | 사용자 초대 | 사용자 초대 성공 | 02 | ManageAccess 다이얼로그 / 초대 결과 영역 |
| `completion_tenant-user-administration` | 초기 정보 설정 | 초기 정보 설정 성공 | 03 | InitialSettingForm / alert 결과 |
| `completion_tenant-user-administration` | 사용자·테넌트 관리 정보 갱신 | 관리 정보 갱신 성공 | 04, 05 | AccountTab 저장 / 테넌트 카드 클릭 |

## 스펙 관련 코드 표면
### 백엔드
| 파일 | 함수/클래스/라우트 | 관련 요구사항 | 커버리지 기준 | 선정 근거 |
| --- | --- | --- | --- | --- |
| `services/completion/process_db_manager.py` | `combine_input_with_new_user_info`, `combine_input_with_invite_user_info`, `combine_input_with_set_initial_info`, `combine_input_with_user_info`, `combine_input_with_tenant_id`, `add_routes_to_app` | 사용자 생성, 초대, 초기 정보, 갱신 | line/function >= 80% (생성 라우트는 시나리오 01 보류로 제외) | 5개 라우트의 FastAPI 등록·요청 디스패처 직접 구현 |
| `services/completion/database.py` | `invite_user`, `set_initial_info`, `update_user_admin` | 사용자 초대, 초기 정보, 갱신 | 함수별 line >= 70% | Supabase 어드민 호출과 `public.users` 영속화 본체 (`create_user` 는 시나리오 01 보류로 제외) |

### 프론트엔드
| 파일 | 컴포넌트/함수/API 호출 | 관련 요구사항 | 커버리지 기준 | 선정 근거 |
| --- | --- | --- | --- | --- |
| `services/frontend/src/components/tenant/inviteUserCard.vue` | `inviteUsers` 메서드, `backend.inviteUser` 호출 | 사용자 초대 | V8 bundle 보조 지표 | `/account-settings` ManageAccess 다이얼로그에서 실제로 트리거되는 컴포넌트 |
| `services/frontend/src/components/pages/account-settings/ManageAccessTab.vue` | `openInviteUserCard`, `closeInviteUserCard` | 사용자 초대 | V8 bundle 보조 지표 | 초대 다이얼로그 컨테이너 |
| `services/frontend/src/components/auth/InitialSettingForm.vue` | `setInitialSettings` | 초기 정보 설정 | V8 bundle 보조 지표 | `/auth/initial-setting` 실제 화면의 `/completion/set-initial-info` 호출부 |
| `services/frontend/src/components/pages/account-settings/AccountTab.vue` | `updateUser` 저장 핸들러 | 사용자 갱신 | V8 bundle 보조 지표 | 본인 정보 저장 시 `/completion/update-user` 호출 트리거 |
| `services/frontend/src/components/tenant/TenantManagePage.vue` | `toSelectedTenantPage`, `backend.setTenant` 호출 | 테넌트 갱신 | V8 bundle 보조 지표 | `/tenant/manage` 카드 클릭 → `/completion/set-tenant` 호출 |
| `services/frontend/src/components/api/ProcessGPTBackend.ts` | `inviteUser`, `updateUser`, `updateUserInfo`, `setTenant` | 모든 요구사항 (생성 제외) | V8 bundle 보조 지표 | 실제 호출 경로의 axios 어댑터 |

## 미검증 및 보류 항목
| 항목 | 사유 | 후속 조치 |
| --- | --- | --- |
| 시나리오 01 (사용자 생성) — 실제 UI 구동 | 프론트엔드에서 `/completion/create-user` 를 호출하는 유일한 경로는 `/organization` 의 OrganizationChartChat LLM 채팅 흐름이며, OrganizationAddDialog 에는 신규 사용자 입력 UI 토글이 없다. 결정성 있는 구동에는 별도 `mock-llm-tua` + `completion-tua` + `gateway-tua` + 조직도 시드 인프라가 필요하다. | 사용자 결정: "Mock-LLM 채팅 흐름". 별도 세션에서 신규 mock-llm-tua / completion-tua / gateway-tua / db-seed-tua 를 추가한 뒤 본 시나리오를 활성화한다. |
| 신규 이메일 GoTrue `invite_user_by_email` 실 메일 전송 | E2E 환경에 SMTP 가 없어 메일 전송 자체는 nondeterministic | 백엔드 graceful 성공 경로(200 + success 응답) 만 검증 |
| 신규 사용자(invite 후) 의 set-initial-info 실 흐름 | invite 후 토큰 발급/메일 링크 클릭 단계가 SMTP 의존 | 시나리오 03 은 어드민 본인의 비밀번호 재설정 경로로 set-initial-info 계약 자체를 검증 |
| 프론트엔드 source-mapped coverage | 현재 `frontend` 컨테이너는 ghcr.io 의 prebuilt 미니파이 이미지 (`ghcr.io/uengine-oss/process-gpt:e343845`) | V8 raw JSON 을 번들 보조 지표로 사용. 후속 작업에서 `Dockerfile.coverage-prebuilt` 기반 source-built 이미지로 전환 가능 |

## 체크리스트
- [ ] 모든 Requirement가 하나 이상의 E2E 시나리오에 매핑되어 있습니다. (요구사항 1 "사용자 생성"이 보류 상태이므로 게이트 실패로 보고됩니다.)
- [x] 중요한 OpenSpec Scenario가 E2E 시나리오에 매핑되어 있거나 미검증 및 보류 항목에 기록되어 있습니다.
- [x] 사람이 읽는 요구사항명, 명세 시나리오명, 목적, 절차, 기대 결과는 한국어로 작성되어 있습니다.
- [x] 원본 OpenSpec에 영어 설명이 있더라도 E2E 문서에는 한국어 의미로 변환되어 있으며, API 경로·필드명·이벤트명 같은 계약 식별자만 원문으로 유지합니다.
- [x] 원본 명세가 하나의 백엔드 연계 피쳐 또는 응집된 사용자 workflow 범위이며, 마이크로서비스 전체 요약이나 프론트엔드 단독 명세가 아닙니다.
- [x] 원본 명세의 서비스 접두어 또는 도메인 구분자가 `frontend`, `ui`, `react`, `page`, `component` 같은 구현 레이어가 아닙니다.
- [x] E2E가 실행할 소유 백엔드 서비스/API/데이터 계약이 명확합니다.
- [x] 서비스 접두형 명세 ID를 사용하는 경우 스위트 슬러그가 동일한 값을 유지합니다.
- [x] E2E 시나리오, 테스트 스크립트, seed/stub, 실행 결과, 스크린샷은 `openspec/specs/completion_tenant-user-administration/e2e/` 아래에 응집되어 있습니다.
- [x] 사용자-facing 시나리오 02/03/04/05 는 실제 services/frontend Vue UI 의 클릭/입력/제출 동작으로 검증합니다 (페이지.route() 합성 페이지 주입 금지 원칙 준수).
- [x] 시나리오별 스크린샷 체크포인트가 매뉴얼에 재사용할 수 있는 UI 상태를 설명합니다.
- [x] 스펙 관련 백엔드/프론트엔드 파일과 함수가 코드 표면 표에 기록되어 있습니다.
- [x] 커버리지 기준이 전체 저장소가 아니라 스펙 관련 파일/함수 중심으로 정의되어 있습니다.
- [x] 결과 경로가 `OUTPUT_CONTRACT.md`와 일치합니다.
