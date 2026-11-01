## Why

팀 맥락 공유(`2026-11-01-pgpt-pro-team-context`)를 내보낸 뒤 두 가지가 비었다.

- 민감 맥락을 지키는 규칙(민감이면 자동 허용 금지, 인사·급여 같은 주제 찾기)이 맥락 기능 안의 코드였다. 회사의 다른 가드레일(메일·결제·출시)은 Agentic BPM 정책 엔진이 판단하고 결정 원장에 남기는데, 팀원 맥락 참고만 그 밖에 있어 관리자가 보지도 고치지도 못했다. 민감 제안도 주인이 설정을 열 때만 돌았다.
- 나나 팀원이 이미 한 요청을 또 하면 에이전트가 처음부터 다시 만든다. 팀원이 만든 결과는 「요청하면 볼 수 있는 맥락」으로 답 뒤에야 보였다.

## What Changes

- **회사 정책으로**: 참고 요청을 행위 `context.access` 로 정책 엔진에 묻는다. 카탈로그에 「민감 맥락은 주인이 직접 허락」·「민감할 수 있는 주제는 자동 허용하지 않음」(주제 목록을 정책이 가짐)·「팀원 맥락 참고는 기록」을 넣는다. 정책이 먼저, 주인 규칙은 그 안에서. 요청 하나가 결정 원장의 한 줄이 되어 허락·거절·만료·회수를 따라간다. 민감할 수 있는 맥락은 원장에서 제목을 가린다. 원장의 승인 단추는 보관된 행위가 있는 결정에만.
- **요약 때 민감 제안**: 맥락 요약을 다시 만들 때 같은 주제 목록으로 보고, 새로 제안하면 주인의 홈에 「민감 표시 제안」 카드.
- **같은 요청 알아보기**: 메인 채팅의 요청이 에이전트로 가기 전에 이미 한 요청을 찾고, 있으면 「이미 한 요청」 카드(그 답 보기·요청하기·그래도 새로 하기).

## Capabilities

### New Capabilities
- `pgpt-pro_context-repeat-request`

### Modified Capabilities
- `pgpt-pro_context-access-request`: 참고 요청의 결정은 회사 정책이 먼저, 결정 원장
- `pgpt-pro_context-visibility`: 민감 제안의 기준은 정책의 주제 목록, 요약 때도
- `pgpt-pro_agentic-guardrails`: 정책의 주제 목록, 주인이 정하는 결정은 원장에서 승인하지 않음

## Impact

- process-gpt-lite `feat/team-context`: `server/lib/context/{sensitive,repeat}.js`, `access.js`·`grade.js`·`digest.js`·`agent.js`(알아보기), `lib/policy/{catalog,dsl}.js`, `routes/agentic.js`, `server/sql/029_team_context.sql`(`pro_access_requests.policy_decision`, `pro_context_repeats`), 화면 `PolicyCenter`·`SharingCenter`·`AccessDecide`·`RepeatCard`.
