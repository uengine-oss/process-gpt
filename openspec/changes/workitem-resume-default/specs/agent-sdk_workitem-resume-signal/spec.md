## ADDED Requirements

### Requirement: RS-1 실행기는 워크아이템이 왜 다시 실행되는지 알 수 있다
SDK는 워크아이템을 실행기에 넘길 때 재개 정보를 함께 넘겨야 한다(SHALL). 재개 정보는 실행 문맥의 부가 데이터(`extras`)와 표준 메타데이터 양쪽에서 `resume` 키로 읽을 수 있어야 하며, 다음 필드를 가진다.

- `kind`: `fresh` | `reclaim` | `human_answer` | `revision` 중 하나
- `attempt`: 이번 점유가 몇 번째 점유인가(1 이상의 정수)
- `key`: 재개 키. 워크아이템(todo) id
- `answer_raw`: 사람이 남긴 마지막 입력의 원문. 요약·가공하지 않은 값이어야 한다(MUST). 해당 없으면 빈 문자열

재개 정보는 직렬화 가능한 단순 값(문자열·정수)만 담아야 한다(MUST).

#### Scenario: RS-1.1 처음 집힌 작업
- **WHEN** 한 번도 점유된 적 없는 신규 작업(`claim_count`=1, feedback 없음)이 실행기에 넘어간다
- **THEN** `resume.kind`는 `fresh`, `resume.attempt`는 1, `resume.key`는 todo id, `resume.answer_raw`는 빈 문자열이다

#### Scenario: RS-1.2 재개 정보는 직렬화할 수 있다
- **WHEN** 실행기가 받은 `resume` 값을 JSON으로 직렬화한다
- **THEN** 오류 없이 직렬화되고, 다시 읽으면 같은 네 필드가 나온다

### Requirement: RS-2 크래시 재점유를 재개 사유로 알린다
점유가 만료된 작업을 다른 워커가 다시 집었으면(점유 RPC가 돌려준 `claim_count`가 1보다 크다) SDK는 `kind`를 `reclaim`으로, `attempt`를 그 `claim_count`로 넘겨야 한다(SHALL). 재점유 판정은 feedback 내용보다 우선한다(MUST).

#### Scenario: RS-2.1 두 번째 점유
- **WHEN** 첫 워커가 lease를 연장하지 못하고 사라진 뒤 다른 워커가 같은 작업을 `claim_count`=2로 집는다
- **THEN** `resume.kind`는 `reclaim`, `resume.attempt`는 2이다

#### Scenario: RS-2.2 사람 답변을 처리하던 중 죽은 작업의 재점유
- **WHEN** 사람 답변으로 다시 집힌 작업을 수행하던 워커가 죽어, 마지막 feedback이 `human_answer`인 채로 `claim_count`=2로 다시 집힌다
- **THEN** `resume.kind`는 `reclaim`이다

#### Scenario: RS-2.3 종료 신호로 실행이 끊긴 작업도 재점유된다
- **WHEN** 워커가 작업을 수행하던 중 종료 신호(파드 종료, 롤링 배포, 스케일 다운)를 받아 실행이 끊긴다
- **THEN** 그 작업의 점유는 비워지지 않고 남아, lease 가 만료된 뒤 다른 워커가 `claim_count`=2 로 집고 `resume.kind` 는 `reclaim` 이다
- **AND** 종료 신호를 받은 그 워커는 더 이상 작업을 집지 않는다(자기 작업을 lease 만료 뒤 다시 집지 않는다)
- **AND** 사용자가 화면에서 취소한 작업은 이와 달리 점유를 바로 해제하고, 워커는 다음 작업을 계속 집는다

### Requirement: RS-3 사람 답변 재개와 반려 재작업을 구분한다
점유가 재점유가 아닐 때 SDK는 feedback 배열의 마지막 항목으로 사유를 정해야 한다(SHALL).

- 마지막 항목의 `kind`가 `human_answer`면 `kind`=`human_answer`
- 마지막 항목의 `kind`가 `revision`이거나 `kind`가 없으면(구분 표시 이전에 저장된 항목) `kind`=`revision`
- feedback이 없거나 비었거나 해석할 수 없으면 `kind`=`fresh`

`human_answer`와 `revision`일 때 `answer_raw`는 마지막 항목의 `content` 원문이어야 한다(MUST). feedback은 배열 또는 배열을 담은 JSON 문자열 어느 쪽으로 와도 같은 결과여야 한다(MUST).

#### Scenario: RS-3.1 질문 카드에 답한 뒤 다시 집힘
- **WHEN** 에이전트가 사람에게 묻고(`HUMAN_ASKED`) 화면이 답 "승인합니다. 단 C사는 제외하세요"를 `kind`=`human_answer`로 붙여 `FB_REQUESTED`로 돌린 작업이 집힌다
- **THEN** `resume.kind`는 `human_answer`, `resume.answer_raw`는 "승인합니다. 단 C사는 제외하세요"이다

#### Scenario: RS-3.2 초안 반려 뒤 다시 집힘
- **WHEN** 초안을 본 사용자가 "표 형식으로 다시"를 `kind`=`revision`으로 남겨 `FB_REQUESTED`로 돌린 작업이 집힌다
- **THEN** `resume.kind`는 `revision`, `resume.answer_raw`는 "표 형식으로 다시"이다

#### Scenario: RS-3.3 구분 표시가 없는 과거 feedback
- **WHEN** `kind` 없이 저장된 feedback 항목만 있는 작업이 집힌다
- **THEN** `resume.kind`는 `revision`이다

#### Scenario: RS-3.4 문자열로 저장된 feedback
- **WHEN** feedback이 `[{"content":"답","kind":"human_answer"}]` 같은 JSON 문자열로 온다
- **THEN** 배열로 온 경우와 같은 `resume`이 나온다

#### Scenario: RS-3.5 깨진 feedback
- **WHEN** feedback이 JSON으로 해석되지 않는 문자열이다
- **THEN** 실행은 실패하지 않고 `resume.kind`는 `fresh`이다

### Requirement: RS-4 재개 정보는 하위 호환으로 추가된다
재개 정보 추가는 기존 실행 문맥의 어떤 필드도 바꾸거나 없애지 않아야 한다(MUST). 기존 요약 피드백(`summarized_feedback`)은 그대로 제공된다. 재개 정보를 읽지 않는 실행기는 이전 버전과 같은 입력을 받는다.

#### Scenario: RS-4.1 기존 필드 유지
- **WHEN** feedback이 있는 작업이 실행기에 넘어간다
- **THEN** `summarized_feedback`과 원래 행(`row`)이 이전과 같이 제공되고, `resume`만 추가된다

#### Scenario: RS-4.2 재개 정보가 없는 실행 문맥
- **WHEN** 재개 정보가 없는 실행 문맥(구버전 SDK 또는 채팅 요청)에서 재개 정보 해석 기능을 쓴다
- **THEN** 행이 있으면 행으로부터 같은 규칙으로 판정하고, 행도 없으면 `fresh`를 돌려준다

### Requirement: RS-5 SDK는 표준 "이어서" 지시 문구를 제공한다
SDK는 대화 기록이 남아 있는 에이전트를 재개할 때 쓸 표준 지시 문구를 제공해야 한다(SHALL). 문구는 "직전 실행이 중단되었다", "이미 완료한 단계는 다시 하지 말 것", "완료되지 않은 단계부터 이어서 할 것"을 모두 담아야 한다(MUST). 원래 작업 지시를 함께 넘기면 문구 뒤에 참고용으로 붙인다.

#### Scenario: RS-5.1 이어서 지시
- **WHEN** 서비스가 원래 지시 "보고서를 작성하라"와 함께 이어서 지시를 요청한다
- **THEN** 돌려받은 문구에 중단 사실, 완료 단계 반복 금지, 이어서 수행 지시, 그리고 원래 지시 원문이 들어 있다

### Requirement: RS-6 화면은 답을 저장할 때 구분 표시를 남긴다
화면은 작업을 다시 진행시키려고 feedback에 항목을 덧붙일 때, 그 항목이 사람 질문에 대한 답인지 결과에 대한 반려·피드백인지 `kind`로 남겨야 한다(SHALL). 기존 필드(`time`, `content`, `user_id`)는 그대로 둔다.

#### Scenario: RS-6.1 질문 카드 답변
- **WHEN** 사용자가 `HUMAN_ASKED` 작업의 질문 카드에 답한다
- **THEN** 새 feedback 항목에 `kind`=`human_answer`와 답 원문이 들어가고 `draft_status`는 `FB_REQUESTED`가 된다

#### Scenario: RS-6.2 결과 피드백·반려
- **WHEN** 사용자가 에이전트 결과 화면에서 피드백을 보내 작업을 다시 진행시킨다
- **THEN** 새 feedback 항목에 `kind`=`revision`이 들어간다
