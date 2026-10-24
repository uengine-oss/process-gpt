## ADDED Requirements


### Requirement: 메시지의 맥락 판단
시스템은 `POST /route` 와 `POST /chat/stream` 요청에서 사용자의 최근 맥락(이전에 라우팅된 대화들)과 클라이언트가 함께 보낸 맥락(`metadata.contexts`: `conversation_id`, `title`, `summary`, `kind`, `active`)을 후보로, 새 메시지가 어느 후보의 후속인지 또는 새 주제인지 판단 전략으로 SHALL 결정한다. 결과는 대화 식별자와 행동(`continue` | `new` | `stay`), 고른 맥락, 판단 근거(전략·확신도·모델)를 SHALL 포함한다.

#### Scenario: 이어지는 요청
- **GIVEN** 사용자에게 "경제사냥꾼 유튜브"와 "부산 출장" 대화가 있다
- **WHEN** 사용자가 "숙소는 바다 보이는 곳이면 좋겠어"라고 보낸다
- **THEN** 행동은 `continue` 이고 대화 식별자는 "부산 출장" 대화의 식별자다

#### Scenario: 새 주제
- **GIVEN** 사용자에게 유튜브 대화만 있다
- **WHEN** 사용자가 무관한 출장 숙소 추천을 요청한다
- **THEN** 행동은 `new` 이고 새 대화 식별자가 발급된다

#### Scenario: 맥락이 하나도 없을 때
- **WHEN** 사용자의 첫 메시지가 들어온다
- **THEN** 판단 모델을 호출하지 않고 새 대화(또는 요청에 있던 대화)로 시작한다

### Requirement: 확신이 없을 때는 옮기지 않음
시스템은 판단의 확신도가 기준(`ROUTER_THRESHOLD`, 기본 0.55)보다 낮으면 사용자가 이미 있던 대화(요청의 `conversation_id`)에 SHALL 머물고 행동을 `stay` 로 SHALL 표시한다. 자기 보고 확신도(`calibrated: false`)에는 더 높은 기준을 SHALL 적용한다.

#### Scenario: 애매한 지시
- **GIVEN** 판단 확신도가 0.45 다
- **WHEN** 사용자가 "그거 다시"라고 보낸다
- **THEN** 대화는 바뀌지 않고 행동은 `stay` 다

### Requirement: 라우팅은 요청별 선택
시스템은 요청의 `metadata.auto_route` 가 참일 때만 대화를 SHALL 바꾼다(기본값은 `ROUTER_AUTO_ROUTE_DEFAULT`, 기본 거짓). 대화방이 이미 하나의 대화로 고정된 클라이언트의 요청은 대화를 바꾸지 않고 그대로 SHALL 전달한다.

#### Scenario: 라우팅을 요청하지 않은 채팅
- **WHEN** `metadata.auto_route` 없이 `/chat/stream` 을 호출한다
- **THEN** 요청의 `conversation_id` 가 그대로 에이전트에 전달된다

### Requirement: 에이전트 앞 투명 프록시
시스템은 라우팅한 채팅 요청을 대상 에이전트(`metadata.agent` 또는 기본 대상)의 `/chat/stream` 으로 전달하고, 에이전트의 SSE 응답을 바꾸지 않고 SHALL 흘려보내되, 맨 앞에 정해진 대화 식별자와 라우팅 결과를 담은 `metadata` 이벤트 하나를 SHALL 덧붙인다. 그 밖의 모든 경로(재접속, 스킬, 파일 등)는 기본 에이전트로 그대로 SHALL 전달하여, 게이트웨이의 에이전트 경로를 라우터로 바꾸는 것만으로 앞단에 둘 수 있어야 한다.

#### Scenario: 라우팅 메타데이터 이벤트
- **WHEN** 라우팅이 켜진 채팅 요청을 보낸다
- **THEN** 첫 SSE 이벤트는 `metadata` 이고 `conversation_id` 와 `routing`(행동, 맥락, 판단)을 포함하며, 이후 이벤트는 에이전트가 보낸 그대로다

#### Scenario: 그 밖의 경로
- **WHEN** 라우터의 `/health` 나 `/skills` 경로를 호출한다
- **THEN** 기본 에이전트의 같은 경로 응답이 그대로 돌아온다

### Requirement: 맥락 기억
시스템은 라우팅한 대화마다 사용자별 맥락(제목, 최근 요청과 답의 요약, 종류, 갱신 시각)을 SHALL 저장하고, 다음 메시지의 후보로 최근 순으로 SHALL 사용한다. 클라이언트가 장식한 프롬프트가 아니라 사용자가 실제로 한 말(`metadata.route_text`)이 있으면 그것으로 SHALL 판단한다.

#### Scenario: 답 이후 요약 갱신
- **WHEN** 라우팅된 대화의 응답 스트림이 끝난다
- **THEN** 그 맥락의 요약이 이번 요청과 답으로 갱신되고 갱신 시각이 바뀐다
