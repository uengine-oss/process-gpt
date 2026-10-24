## ADDED Requirements

### Requirement: 새 페이지의 상태를 빠른 판단으로 확인
pgpt-pro 브라우저 에이전트는 판단 게이트가 켜져 있을 때(`PRO_BROWSER_GATES`, 기본 켬, 라우터 주소 `PRO_CONTEXT_ROUTER_URL` 필요) 새 http(s) 페이지에 처음 도착할 때마다 큰 모델의 턴을 쓰기 전에 context-router 의 `POST /decide` 로 페이지 상태(`loading` | `login_wall` | `captcha` | `content`)를 SHALL 판단한다. 판단에 넘기는 페이지 글은 보관함에서 채운 값을 가린 뒤의 글이어야 한다(SHALL). 결과는 측정된 확신도(`calibrated: true`)가 0.85 이상일 때만 SHALL 따른다.

#### Scenario: 아직 뜨지 않은 페이지
- **GIVEN** 페이지 본문이 늦게 그려진다
- **WHEN** 판단이 `loading` 을 확신한다
- **THEN** 에이전트는 큰 모델을 부르지 않고 1.5초 기다린 뒤 페이지를 다시 읽으며, 최대 두 번까지 반복한다

#### Scenario: 아무도 없는 실행에서 만난 로그인 벽
- **GIVEN** 프로세스 단계처럼 사람이 지켜보지 않는 작업이다
- **WHEN** 판단이 `login_wall` 또는 `captcha` 를 확신한다
- **THEN** 큰 모델에게 보내는 페이지 정보에 "통과할 수 없으니 시도하지 말고 목표의 대체 경로를 쓰라"는 안내가 붙는다

#### Scenario: 라우터가 없을 때
- **GIVEN** 라우터 주소가 설정되지 않았거나 판단이 응답하지 않는다
- **WHEN** 새 페이지에 도착한다
- **THEN** 게이트 없이 기존 루프대로 진행한다

### Requirement: 목표 달성의 빠른 확인과 조기 종료
에이전트는 사실을 기록(`note`)할 때마다 목표와 지금까지 기록한 사실로 "목표가 요구한 정보가 모두 기록됐는가"(`done` | `more`)를 SHALL 판단하고, `done` 을 측정된 확신도 0.9 이상으로 판단하면 더 탐색하지 않고 `finish` 를 강제한 한 번의 호출로 요약을 받아 작업을 SHALL 끝낸다.

#### Scenario: 필요한 사실을 다 모은 뒤
- **GIVEN** 목표가 "Travel 카테고리 처음 세 권의 제목과 가격"이다
- **WHEN** 에이전트가 세 권의 제목과 가격을 기록했다
- **THEN** 판단이 `done` 이면 다음 탐색 턴 없이 요약으로 끝난다

### Requirement: 게이트 효과의 측정 기록
에이전트는 작업 결과에 턴 수, 큰 모델 호출 수, 게이트 판단 수와 시간, 기다림 횟수, 안내 횟수, 조기 종료 여부, 판단 목록(질문·선택·확신도·전략)을 SHALL 남긴다.

#### Scenario: 측정 스크립트
- **WHEN** `node scripts/bench-browser-gates.mjs` 를 실행한다
- **THEN** 같은 고정 과제를 게이트를 끈 채와 켠 채로 돌려 과제별 정답 여부와 위 수치를 JSON 으로 출력한다
