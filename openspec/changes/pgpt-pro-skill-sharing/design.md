# 스킬 공유 설계 — 스킬을 공유 폴더로

## 1. 지금 있는 것 (확인 결과)
- 스킬: `tenant_skills(tenant_id, skill_name, owner_id)` — 소유자는 사람 한 명. 에이전트 배정은 `agent_skills(user_id=에이전트, skill_name)`. 설치된 스킬 파일은 `services/deepagents/skills/<tenant>/local/<스킬>/`. 테넌트 안에서는 모두에게 보인다.
- 채팅 실행은 테넌트의 설치된 스킬 전체를 본다. 줄이는 길은 프로세스 활동 지정(`activity_skills`)과 대화 프로필뿐이고, 요청마다 "이 스킬은 빼라" 를 넘기는 길은 없다.
- git 공급자가 있으면(`tenant_git_config`) deepagents 의 `/skills/{n}/branches·commits·commit·pull-requests·merge·verification` 이 스킬마다 저장소 하나로 브랜치·병합 요청을 다룬다. 병합 요청 행은 `resource_pull_requests`(상태 `OPEN/CHANGES_REQUESTED/APPROVED/MERGED/CLOSED`, `reviewer_id`=소유자), 검토는 `resource_pr_reviews`, 기여는 `skill_contributions(CREATED/MODIFIED/PROPOSAL_APPROVED)`.
- 로컬 확인: `tenant_git_config` 0건(공급자 없음), 검증용 `resource_eval_*` 테이블 없음, 병합 요청 알림 트리거(`20260716_feedback_proposal_notifications.sql`)는 로컬 DB 에 적용돼 있지 않다.
- 병합 경로는 `@tenant_guard` 만 있다 — 소유자 확인은 프런트에서만 한다.

## 2. 결정 (사용자 승인)
1. **병합 권한** = 작성자 + 그 스킬을 쓰는 에이전트의 보스. 보스는 pgpt-pro `pro_agent_owners`(에이전트 → 담당자). 서버(pgpt-pro)가 병합 전에 확인한다. process-gpt 병합 경로에도 같은 확인을 넣도록 권고한다(이번에 고치지 않음).
2. **공개 범위**: 새 스킬은 비공개로 시작. 저장 직후, 그리고 첫 성공 사용 뒤 "전사에 공유하시겠어요?" 를 묻는다. 공유하면 누구나 쓰고 변형으로 제안, 병합은 작성자·보스만.
3. **버전 고정**: 하지 않는다(에이전트는 main). 남은 일.

## 3. 비공개를 어떻게 지키나 — 선택과 이유
| 길 | 내용 | 판단 |
| --- | --- | --- |
| (가) 설치하지 않기 | 비공개 스킬은 테넌트 스킬로 설치하지 않는다. 작성자의 실행에만 사본(`/workspace/.pro-skills/<uid>/<스킬>/`)을 두고 그 경로를 따르게 지시한다. 공유할 때 설치한다 | **채택**. process-gpt 를 고치지 않고, 어떤 클라이언트(process-gpt 화면 포함)에서도 남의 실행이 이 스킬을 목록·자동 로드로 볼 수 없다 |
| (나) deepagents 요청별 제외 | 설치는 하되 요청 메타에 "숨길 스킬" 을 넘겨 `FilteredSkillsMiddleware` 로 거른다 | deepagents 수정 필요, pgpt-pro 를 거치지 않는 요청에는 효과 없음 |
| (다) deepagents 가 pgpt-pro 공개 범위를 조회 | 실행마다 공개 범위를 물어 거른다 | 서비스 간 의존이 새로 생김 |
- (가) 의 한계: 사본은 테넌트 작업공간 안이라 샌드박스 셸로는 읽을 수 있다(공유 폴더와 같은 테넌트 수준 격리). 작성자의 에이전트가 **프로세스 단계**에서 비공개 스킬을 쓰는 경로는 아직 없다(채팅·예약 실행만). 남은 일로 둔다.
- 이미 설치된 스킬은 공개(`tenant`)로 본다 — 지금도 그렇게 동작하기 때문이다.

## 4. 저장소 — git 공급자 유무
- **공급자 없음(로컬, 지금 환경)**: 스킬 폴더 = 공유 폴더(안 2)의 git 저장소. 처음 열 때 설치된(또는 비공개) 스킬 파일로 만든다. 변형·비교·일괄 반영·충돌은 공유 폴더 기능 그대로. 병합되면 main 을 설치 위치(공유) 또는 작성자 사본(비공개)에 그대로 맞춘다.
- **공급자 있음**: 브랜치·병합 요청·검증은 process-gpt 의 스킬 저장소 경로가 맡아야 한다. 이번 구현은 모드를 알아보고(스킬 정보에 표시), 검증만 process-gpt 경로로 넘긴다. 변형을 공급자 브랜치로 미는 일과 병합 위임은 남은 일(로컬에 공급자가 없어 검증할 수 없음).

## 5. 흐름
- **만들기**: 스킬 만들기 초안의 "스킬로 저장" → 비공개 스킬 폴더 + 작성자 사본 + `pro_skill_visibility(private)`. 카드가 바로 공유를 묻는다.
- **쓰기(작성자)**: 채팅에서 `/이름` 또는 "이름 스킬…" → 그 실행에 사본 경로를 알린다. 첫 성공 뒤 공유를 한 번 더 묻는다(`asked_at`). 예약 실행도 같은 사본을 쓴다.
- **공유**: deepagents `/skills/upload` 로 설치(소유자 = 작성자, `tenant_skills` 행) → `visibility=tenant`.
- **제안(동료)**: "○○ 스킬 이렇게 고쳐줘" → 스킬 폴더의 새 변형에서 에이전트가 일하고 서버가 커밋 → 병합 권한이 없으면 `resource_pull_requests` 행(`OPEN`, 요청자, 검토자=작성자)과 알림(`merge_request`, 작성자·보스; process-gpt 트리거가 있으면 작성자 알림은 트리거에 맡김) → 채팅 카드 "반영 요청을 보냈어요".
- **검토(작성자·보스)**: Home "검토하기" → 변형 화면(차이·미리보기·바뀐 점) → "병합 전 검증": 시나리오 2개(저장된 시나리오가 있으면 그것, 없으면 변형의 SKILL.md 로 생성)를 main 과 변형으로 각각 deepagents 에서 돌려 채점, 변경 전/후를 나란히 → "이 변형 반영"(권한 없는 사람은 서버가 403).
- **반영 뒤**: 설치 위치를 main 에 맞추고, 병합 요청 `MERGED`, 검토 `APPROVED`, 기여 기록(요청자가 작성자가 아니면 `PROPOSAL_APPROVED`, 아니면 `MODIFIED`).
- **에이전트 보스**: 스킬 화면에서 그 스킬을 쓰는 에이전트와 담당자를 보여 준다. 담당자가 없는 에이전트는 누구나 맡을 수 있고, 담당자는 넘길 수 있다(지금 담당자만). 기본값 "에이전트를 만든 사람" 은 process-gpt 에 만든 사람 기록이 없어 쓸 수 없다 — pgpt-pro 에서 에이전트를 만들 때 기록하도록 남은 일.

## 6. 구현 위치(검토 대상)
- `server/lib/folders/skills.js`(공개 범위·폴더·공유·반영 요청·병합 뒤 처리·검증·보스), `service.js`(스킬 폴더 권한), `merge.js`(병합 뒤 처리), `work.js`(채팅의 스킬 변형·자동 반영 요청), `routes/folders.js`(스킬 경로·병합 권한), `lib/agent.js`(비공개 스킬 사용·공유 재질문), `lib/missions.js`(예약 실행의 비공개 스킬), `index.js`(초안 저장 = 비공개).
- 화면: `FolderList.vue`(스킬 탭), `FolderDetail.vue`(공유 질문·스킬 정보), `VariationView.vue`(반영 요청·검증), `SkillShareCard.vue`, `SkillDraftCard.vue`, `Message.vue`, `NotificationCard.vue`.

## 7. 남은 일
- 버전 고정(에이전트가 특정 버전을 쓰기).
- git 공급자 모드의 브랜치 동기화·병합 위임, process-gpt 병합 경로의 권한 확인.
- 작성자의 에이전트가 프로세스 단계에서 비공개 스킬을 쓰는 길.
- 에이전트 보스 기본값(만든 사람) 기록.
