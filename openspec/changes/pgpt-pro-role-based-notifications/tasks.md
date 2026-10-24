## 1. 역할 기반 배정과 팀

- [x] 1.1 `pro_team_members`, `pro_role_assignments` (`server/sql/006_team_notify.sql` 적용)와 `lib/team.js`(팀원 추가·빼기, 역할 지정, 역할 카탈로그, 이름·이메일·역할 → 팀원).
- [x] 1.2 프로세스 시작 시 역할 담당자 배정(프로세스별 > 테넌트 기본 > 시작한 사람, 에이전트 역할 유지). 완료 기준: 인스턴스 `role_bindings` 에 제품 책임자 → 김민지, 마케팅 담당자 → 장진영(`e2e/db-evidence.log`).
- [x] 1.3 설정 → 팀·역할 화면(`TeamRoles.vue`), 프로필 이름 → `users.username`.

## 2. 알림

- [x] 2.1 process-gpt `notifications` 읽기·확인·실시간 갱신(`lib/notify.js`, 4초 테넌트 조회 → SSE).
- [x] 2.2 홈 "조치 필요" 카드(`NotificationCard.vue`): 요지 한 줄, 선택지 버튼으로 바로 제출, 끝난 단계 숨김.
- [x] 2.3 대화 중 팀원·역할 요청(`notify_member` 라우터 도구, 대화 발췌). 완료 기준: "제품 책임자한테 확인해 달라고 알려줘" → 김민지에게 요청 카드.
- [x] 2.4 예약 스킬 결과는 건 사람에게만(`mission`), 스킬/프로세스 선택 기준을 라우터에.

## 3. SNS 트렌드 프로세스

- [x] 3.1 신호 분류의 접목 여부·접목 방안, `gw_fit` → 무관이면 알림 없이 종료.
- [x] 3.2 반영만 누른 결정에서도 구현 단계가 범위를 골라 Claude Code worktree 구현 → 시연 영상(`ce7bdf2`, 102초 영상).
- [x] 3.3 재시작 뒤 브라우저 단계 재개(`browserWorker` 시작 시 이전 소비자 해제).

## 4. 검증

- [x] 4.1 두 사용자 e2e(배정·알림·요청·홈 결정·승인·완료) → `specs/pgpt-pro_role-based-notifications/e2e/`
- [x] 4.2 프로세스 실행 기록 → `specs/pgpt-pro_sns-trend-response/e2e/`
- [x] 4.3 시연 영상 → `specs/pgpt-pro_role-based-notifications/docs/role-notifications-demo.mp4`
- [ ] 4.4 프로세스별 역할 지정 화면, 알림 위임·기한
- [ ] 4.5 앞 단계 산출물 전문을 구현 작업 항목에 넘기기
- [ ] 4.6 process-gpt FCM 문제(선점 쿼리의 `updated_at`, uuid 담당자 푸시, 쉼표 결합 `user_id`) — 별도 변경
