# E2E 시나리오 01: 신규 사용자 계정을 관리자가 생성한다 (스코프 조정 필요)

## 메타데이터
- 스위트 슬러그: `completion_tenant-user-administration`
- 원본 명세 ID: `completion_tenant-user-administration`
- 시나리오 ID: `01`
- Playwright 테스트 제목: (본 이터레이션에서는 미구현)
- 원본 명세:
  - `openspec/specs/completion_tenant-user-administration/spec.md`

## 목적
관리자가 신규 사용자 계정을 생성하여 `POST /completion/create-user` 가 호출되고, 백엔드가 Supabase `auth.users` + `public.users` 에 사용자를 영속화하는 경로를 검증한다.

## 현재 상태 — Real-Frontend Rule Gate Failure
2026-05-27 트레이스 결과, `services/frontend` 에서 `/completion/create-user` 를 호출하는 사용자-facing 경로는 다음 단 한 곳이다.

- `/organization` 라우트 → `OrganizationChartChat.vue` → 채팅 메시지 → LLM 응답의 `modifications[].action==='add'` 처리 → `createNewUser(user)` → `backend.createUser` → `POST /completion/create-user`.
- 직접 클릭 가능한 "사용자 추가" 다이얼로그(`OrganizationAddDialog.vue`) 는 `isNewUser` 가 하드코딩된 `false` 이고 UI 토글이 없어 신규 사용자 입력 폼이 렌더되지 않는다 (line 54, 160 참조).

따라서 결정성 있는 E2E 로 본 시나리오를 구동하려면 다음 인프라가 추가로 필요하다 (사용자 선택: "Mock-LLM 채팅 흐름").

1. 스위트 전용 `mock-llm-tua` 컨테이너: OpenAI 호환 응답으로 `modifications[].action==='add'` JSON 을 반환 (조직도 수정 프롬프트 식별 후).
2. 스위트 전용 `completion-tua` 컨테이너 또는 `LLM_PROXY_URL` 분기 (기존 `completion` 은 agent-memory-chat 의 `mock-llm` 에 결속되어 있어 공유 불가).
3. 스위트 전용 `gateway-tua` nginx (별도 포트, `/completion/*` → `completion-tua` 프록시).
4. 스위트 전용 시드 `e2e_seed.sql`: tenant=`localhost` 의 `configuration.key='organization'` 에 최소 1개 팀 노드를 포함한 차트 + 가입 사용자 목록 보장.
5. Playwright: `/organization` 진입 → 채팅 입력창에 "신규 사용자 X 를 Y팀에 추가" 메시지 전송 → 스트리밍 응답 완료 대기 → `/completion/create-user` 응답 검증 → 차트 노드 추가 + 스크린샷.

## 후속 조치 (사용자 결정 사항)
사용자가 옵션 (1) "Mock-LLM 채팅 흐름" 을 선택했다. 본 이터레이션에서는 다음 충돌을 안전하게 풀 시간이 필요하여 본 시나리오 구현을 후속 세션으로 분리한다.

- 기존 `mock-llm` 컨테이너는 `completion_agent-memory-chat` 의 답변 계약에 결속되어 있어 동일 컨테이너에 조직도 수정 응답을 추가하면 다른 스위트의 결정성을 깨뜨릴 위험이 있다.
- `completion` 서비스의 `LLM_PROXY_URL` 환경변수는 단일 값이므로 별도 `completion-tua` + `mock-llm-tua` + `gateway-tua` 인프라 추가가 필요하다.
- 본 이터레이션의 핵심 요청(`tua-tester.html` 제거 및 실제 UI 재작성) 을 안전하게 완료하기 위해 본 시나리오는 별도 세션의 작업으로 분리한다.

`00-coverage-matrix.md` 의 `미검증 및 보류 항목` 에 동일 내용이 기록되어 있다.

## 사전 조건 (후속 구현 시)
- `docker-compose.e2e.yml` 에 `mock-llm-tua`, `completion-tua`, `gateway-tua`, `db-seed-tua` 추가.
- `localhost` 테넌트의 조직도 configuration 시드.
- 어드민 로그인 (`e2e@uengine.org` / `e2epassword`).

## 테스트 데이터 및 Stub
| 이름 | 유형 | 경로 또는 route | 목적 |
| --- | --- | --- | --- |
| 보류 | — | — | 본 시나리오는 본 이터레이션에서 보류되어 실제 stub/seed 가 정의되어 있지 않다. 후속 구현 시 `mock-llm-tua`, `gateway-tua`, 조직도 seed 등을 본 표에 기록한다. |

## 절차 (후속 구현 시 예정)
1. 어드민으로 `/auth/login` 로그인.
2. `/organization` 진입, 시드된 팀 노드가 렌더링될 때까지 대기.
3. 채팅 입력창에 "신규 사용자 (이메일 X) 를 (시드 팀명) 에 추가" 메시지 전송.
4. 스트리밍 응답 완료 후 `POST /completion/create-user` 200 응답 검증.
5. 조직도 트리에 새 사용자 노드가 추가된 화면을 검증.

## 기대 결과 (후속 구현 시)
- `/completion/create-user` 가 200 으로 응답하고 `result.user.id` 가 반환된다.
- `public.users` 에 신규 사용자 행이 생성된다 (테넌트 `localhost`).
- 조직도 화면이 새 사용자 노드를 포함하여 다시 그려진다.

## 커버하는 요구사항
| 명세 | 요구사항 | 시나리오 |
| --- | --- | --- |
| `completion_tenant-user-administration` | 사용자 생성 | 사용자 생성 성공 (보류) |

## 산출물
- 스크린샷 체크포인트: 본 이터레이션에서는 정의되지 않음 (후속 세션에서 정의 + 캡처).
- 결과 JSON: `openspec/specs/completion_tenant-user-administration/e2e/results/results.json` (본 시나리오 항목 미포함).
