## 기존 알림 장치 조사 (process-gpt)

| 무엇 | 어디 | 받는 사람 |
|---|---|---|
| 작업 항목 알림 | DB 트리거 `handle_todolist_change` (`docker-infra/volumes/db/init.sql:1052`) — 상태가 `IN_PROGRESS` 가 될 때 `notifications` 에 `workitem_bpm`, url `/todolist/<id>` | `todolist.user_id` 그대로 |
| 채팅 알림 | `handle_chat_insert` (init.sql:1124) | 채팅방 참가자(보낸 사람·방에 있는 사람 제외) |
| 변경 요청 | `insert_feedback_resource_notification` (frontend migrations 20260716) | 스킬·프로세스 소유자 |
| 인계 | 프론트 `createChatHandover` | 지목한 사람 |
| 표시 | `NotificationDD.vue`(realtime 구독, 50건, `user_id IN (email, uuid)`) | — |
| 푸시 | `completion/fcm_service`(15초 폴링, `consumer` 로 선점) | `user_devices.user_email = notifications.user_id` |

**역할 → 사람**: `bpm_proc_inst.role_bindings` 의 `endpoint` 를 polling 서비스가 `todolist.user_id` 로 옮긴다(`_resolve_next_user_email`, `upsert_next_workitems`). 그래서 **역할을 누구에게 묶느냐가 곧 누구에게 알림이 가느냐**다. pgpt-pro 가 고칠 곳은 알림 장치가 아니라 배정이었다.

## 결정

### 1. 알림 저장소를 새로 만들지 않는다
pgpt-pro 전용 알림 테이블을 두면 process-gpt 화면·푸시와 어긋난다. 작업 항목 알림은 트리거가 이미 만들고, pgpt-pro 가 더하는 종류(`mention`, `mission`)도 같은 테이블에 넣는다. 확인 처리는 process-gpt 와 같이 url 단위로 한다. 서버 메모리 감시자는 화면 갱신용으로만 남는다.

### 2. 배정 규칙: 지정 → 시작한 사람
- 프로세스별 지정 > 테넌트 기본(`*`) > 시작한 사람(예약이면 건 사람). 첫 단계 역할은 지정이 없으면 시작한 사람이다.
- 에이전트 역할(`origin=used`, endpoint 있음)은 건드리지 않는다.
- "설정한 사람이 기본 담당자" 라는 원칙과 "팀원을 지목할 수 있다" 를 함께 만족한다.

### 3. 홈 카드의 버튼 = 단계 양식의 첫 선택형 필드
- 결정·승인 단계는 대개 라디오·셀렉트 하나로 갈린다. 그 선택지를 버튼으로 두면 hark 의 Release/Remind 처럼 홈에서 바로 처리된다.
- 나머지 필드(개선 범위 등)는 비어 있을 수 있으므로, 그 값을 쓰는 다음 단계가 비었을 때의 기본 동작을 갖는다. 예를 들어 구현 단계는 접목 방안에서 범위를 고른다.
- 카드의 요지 한 줄은 직전 완료 단계들의 출력에서 `fit_reason`·`summary`·`rationale` 류 필드를 먼저 고른다. 보고서·URL 필드는 제외한다.

### 4. 대화 중 지목은 라우터 도구 하나
- 라우터에 `notify_member(member, title, message)` 를 둔다. 시스템 메시지에 팀원과 역할 담당을 알려 주므로, "제품 책임자" 같은 역할 이름도 사람으로 풀린다.
- 받는 사람은 대화를 보지 못했으므로 직전 발췌(최대 3개)를 붙인다. 이전 "알려줘" 요청과 그 응답, 현재 요청의 확인 문장은 뺀다.

### 5. 실시간 갱신
- `notifications` 를 4초마다 테넌트 단위로 한 번 조회한다. 새 행의 `user_id`(email 또는 uuid)를 사용자로 풀어 SSE `notifications` 이벤트를 보낸다.
- Supabase realtime 을 BFF 에 붙이는 것보다 단순하고, 사용자 수와 무관하게 쿼리 한 번이다.

### 6. 스킬 vs 프로세스
| 경우 | 실행 단위 | 알림 |
|---|---|---|
| 한 사람의 일, 한 에이전트·스킬 | 예약 스킬(미션) | 건 사람에게만, 변동 있을 때 |
| 사람·역할 사이를 오감(검토·승인·결정), 분기, 여러 에이전트·스킬, 사용자가 프로세스를 명시 | 프로세스 정의(저장·관리) | 단계마다 역할 담당자 |

라우터의 `schedule_task` 설명에 이 기준을 넣어 고르게 한다.

## 함께 발견한 process-gpt 쪽 문제 (이번 변경에서 고치지 않음)
- **FCM 선점 오류 가능성**: FCM 선점 쿼리가 `notifications.updated_at` 을 쓰는데, DDL 에 그 열이 없다(`fcm_service/database.py:225-261`). 선점 자체가 실패할 수 있다.
- **uuid 담당자의 푸시 누락**: FCM 이 기기 토큰을 `user_devices.user_email = notifications.user_id` 로 찾는다. 그래서 uuid 로 배정된 사람(pgpt-pro 의 담당자)은 푸시를 받지 못한다. 알림 종은 uuid 도 맞춰 본다.
- **여러 담당자 알림의 수신자 없음**: 담당자가 여럿이거나 에이전트+사람이면 `todolist.user_id` 가 쉼표로 이어진다. 트리거가 그 문자열을 그대로 쓰므로 그 알림은 아무에게도 보이지 않는다.
- process-gpt 프론트의 `@멘션` 은 에이전트 지목에만 쓰이고 알림을 만들지 않는다. 사람 지목 알림은 인계(`handover`) 하나뿐이다.

## 남은 일
- 프로세스별 역할 지정 화면(지금 화면은 테넌트 기본만, API 는 프로세스별 지원)
- 알림을 다른 팀원에게 넘기기(위임), 기한·리마인드
- 위 process-gpt 문제 수정은 별도 변경
