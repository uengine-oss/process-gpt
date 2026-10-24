## Why
- process-gpt 의 스킬은 만들자마자 테넌트 전체에 보인다(`tenant_skills`). 혼자 다듬는 중인 스킬도 남의 에이전트가 쓰게 된다. "내 스킬" 과 "전사 공유" 의 구분이 없다.
- 스킬을 고치는 길(브랜치·병합 요청·병합 전 검증)은 git 공급자(`tenant_git_config`)가 연결된 테넌트에만 있다. 공급자가 없으면 이력도, 제안도, 검토도 없다.
- 병합 권한은 화면에서만 확인한다(병합 경로에는 테넌트 확인뿐). 스킬을 쓰는 에이전트를 책임지는 사람(에이전트 보스)은 그 스킬의 변경을 받아들일 수 없다.

## What Changes
- **스킬 = 공유 폴더의 한 종류**: 폴더 화면에 "스킬" 탭을 두고, 스킬 파일이 그 폴더의 기준본(main)이 된다. 고칠 점은 변형(브랜치)으로 만들고, "반영 요청" 은 process-gpt 의 `resource_pull_requests` 행이다. 비교·미리보기는 공유 폴더 화면을 그대로 쓴다.
- **공개 범위**: 새 스킬은 "내 스킬"(작성자와 작성자의 실행만 씀)로 시작한다. 저장 직후와 첫 성공 사용 뒤 "이 스킬을 전사에 공유하시겠어요?" 를 묻는다. 공유하면 누구나 쓰고 변형으로 제안할 수 있다.
- **병합 권한**: 작성자(`tenant_skills.owner_id`)와 그 스킬을 쓰는 에이전트의 보스만 병합한다. 서버(pgpt-pro)가 병합 전에 확인한다. 에이전트 보스는 pgpt-pro 가 관리한다.
- **병합 전 검증**: 같은 시나리오를 main 과 변형으로 돌려 채점하고 결과를 나란히 보여 준다. git 공급자가 있으면 process-gpt 의 검증 경로를 쓴다.
- **채팅 흐름**: "○○ 스킬 이렇게 고쳐줘" → 에이전트가 그 스킬의 변형에서 일한다 → 반영 권한이 없으면 반영 요청이 자동으로 간다 → 작성자·보스에게 알림(Home 카드) → 검토·검증 → 병합 → `skill_contributions` 에 기여자가 남는다.
- **버전 고정**: 이번에는 하지 않는다(에이전트는 늘 main 을 쓴다). 남은 일로 둔다.

## Capabilities
### New Capabilities
- `pgpt-pro_skill-sharing`: 스킬의 공개 범위(내 스킬/전사 공유), 스킬 변형·반영 요청·병합 권한, 병합 전 검증, 기여 기록, 에이전트 보스

### Modified Capabilities
없음. `pgpt-pro_shared-folders` 의 폴더·변형·반영 계약 위에 스킬 종류를 얹는다.

## Impact
- **pgpt-pro DB**: `pro_skill_visibility`, `pro_agent_owners`, `pro_skill_verifications`, `pro_folders.kind` 에 `skill` 추가(`server/sql/008_skill_sharing.sql`).
- **pgpt-pro 서버**: 스킬 폴더·공개 범위·반영 요청·병합 권한·검증, 스킬 초안 저장(비공개로 시작), 예약 실행과 채팅에서 비공개 스킬 사용.
- **pgpt-pro 화면**: 폴더 목록의 "스킬" 탭, 스킬 폴더(공유 질문·스킬 정보·에이전트 담당자·기여 기록), 변형의 반영 요청·검증 결과, 채팅의 공유 질문 카드, Home 알림의 "검토하기".
- **process-gpt**: 서비스 코드는 바꾸지 않는다. 쓰는 것: deepagents `/skills/upload`(공유 시 설치), `resource_pull_requests`·`resource_pr_reviews`·`skill_contributions`·`notifications` 행. 권고: deepagents 병합 경로(`/skills/{n}/pull-requests/{n}/merge`)에도 같은 권한 확인을 넣을 것.
