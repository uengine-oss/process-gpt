## Why

pgpt-pro 는 SNS 트렌드 데일리 대응처럼 여러 사람이 오가는 프로세스를 돌리지만, 사람의 결정이 필요한 순간이 **맞는 사람에게** 가지 않았다.

- 담당자가 비어 있는 역할을 모두 시작한 사람에게 묶었다. 그래서 "제품 책임자 결정" 도 "마케터 승인" 도 예약을 건 한 사람에게만 갔다.
- process-gpt 에는 이미 알림 장치가 있다. 담당자가 정해진 작업 항목이 진행되면 todolist 트리거가 `notifications` 에 행을 만들고, 알림 종과 모바일 푸시가 그것을 읽는다. pgpt-pro 는 이 알림을 읽지 않았다.
  - 대신 서버 메모리의 감시자가 시작한 사람의 채팅에만 메시지를 올렸다.
  - 이 감시자는 30분 뒤 멈추고, 서버를 다시 시작하면 사라졌다.
- 팀원 목록이 없어 "이건 김민지님께 봐 달라고 해" 같은 요청을 할 수 없었다.
- SNS 조사에서 우리 제품과 무관한 화제도 끝까지 흘러가, 사람에게 알릴 가치가 있는지 거르는 단계가 없었다.

hark 의 홈 패널처럼 "내가 지금 조치할 것" 이 버튼과 함께 뜨고, 누르면 바로 처리되는 경험이 필요하다. 다만 pgpt-pro 는 혼자 쓰는 비서가 아니라 역할별로 일이 오가는 팀용이다.

## What Changes

- **역할 기반 배정**: 설정 → 팀·역할에서 팀원과 역할 담당자를 지정한다(테넌트 기본, 프로세스별 지정 우선). 프로세스를 시작할 때 역할을 담당자에게 묶고, 담당자가 없는 역할만 시작한 사람이 맡는다.
- **알림은 process-gpt 그대로**: `notifications` 테이블을 읽고 쓴다. 작업 항목 알림은 기존 todolist 트리거가 만든다. pgpt-pro 가 추가로 만드는 알림은 팀원 요청 `mention` 과 예약 스킬 결과 `mission` 이다.
- **홈 "조치 필요" 카드**: 단계 이름, 직전 단계의 요지 한 줄, 그리고 그 단계 선택지를 버튼으로 보여 준다. 버튼을 누르면 바로 제출된다. 새 알림은 몇 초 안에 뜬다.
- **대화 중 팀원·역할 지목**: "김민지님께 알려줘", "제품 책임자한테 확인해 달라고 해" 로 요청하면 직전 대화 발췌를 담아 알림을 보낸다.
- **스킬과 프로세스의 경계**: 한 사람의 일(예약 스킬)은 건 사람에게만 알리고, 사람·역할 사이를 오가거나 분기하거나 여러 에이전트를 잇는 일은 프로세스로 돌려 단계마다 역할 담당자에게 알린다.
- **SNS 트렌드 프로세스**:
  - 신호 분류에 "Process GPT 접목 여부·접목 방안" 을 넣는다. 무관하면 알림 없이 끝낸다.
  - 반영만 누른 결정도 구현 단계가 접목 방안에서 범위를 골라 Claude Code worktree 구현으로 이어진다.
- **견고성**: 서버 재시작 때 끊긴 브라우저 단계를 다시 잡는다. 프로필 이름을 process-gpt `users.username` 에 반영한다.

## Capabilities

### New Capabilities

- `pgpt-pro_role-based-notifications`: 역할 담당자 배정, process-gpt notifications 재사용, 홈 조치 카드와 바로 결정, 대화 중 팀원·역할 요청, 팀·역할 설정, 스킬/프로세스 알림 범위.
- `pgpt-pro_sns-trend-response`: 접목할 건만 알림, 반영 뒤 Claude Code worktree 구현과 시연 영상, 마지막 승인 경로, 재시작 뒤 브라우저 단계 재개.

### Modified Capabilities

없음.

## Impact

- **데이터**: `pro_team_members`, `pro_role_assignments` (`pgpt-pro/server/sql/006_team_notify.sql`). process-gpt 테이블 스키마는 그대로 두고, `notifications` 행만 추가로 쓴다.
- **pgpt-pro**:
  - 서버: `lib/team.js`, `lib/notify.js`, `lib/engine.js`(역할 배정), `lib/agent.js`(`notify_member` 도구, 스킬/프로세스 기준), `lib/missions.js`, `lib/browserWorker.js`, `index.js`(API).
  - 화면: `NotificationCard.vue`, `HomeDock.vue`, `TeamRoles.vue`, 설정 탭.
  - 프로세스 정의: `sql/seed-sns-process.mjs`.
- **process-gpt**: 코드 변경 없음. 알림 종(NotificationDD)과 FCM 이 같은 알림을 받는다.
