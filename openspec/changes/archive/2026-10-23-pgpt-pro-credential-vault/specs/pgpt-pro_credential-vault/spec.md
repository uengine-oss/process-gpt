## ADDED Requirements

### Requirement: 봉투 암호화 저장
시스템은 보관함 항목(로그인, 결제 카드, API 키, OAuth 토큰)의 비밀 값을 사용자별 데이터 키(DEK)로 AES-256-GCM 암호화해 저장해야 한다(SHALL). DEK 는 마스터 키(KEK)로 감싼 형태로만 저장해야 하며(SHALL), KEK 는 데이터베이스에 저장하지 않아야 한다(SHALL NOT). 암호문은 (사용자, 항목 종류, 사이트)에 묶여 있어 다른 사용자·종류·사이트의 맥락에서는 복호화되지 않아야 한다(MUST NOT).

#### Scenario: 로그인 저장 후 데이터베이스에는 암호문만 남음
- **WHEN** 사용자가 사이트 `shop.test` 의 아이디와 비밀번호를 보관함에 저장하면
- **THEN** 데이터베이스의 항목 행과 키 행 어디에도 비밀번호가 평문이나 base64 로 나타나지 않는다
- **AND** 감싼 DEK 를 KEK 로 풀고 그 DEK 로 항목을 풀면 사용자가 입력한 아이디와 비밀번호가 그대로 복원된다
- **AND** 항목 암호문은 KEK 로 직접 풀리지 않는다

#### Scenario: 암호문을 다른 사이트로 옮기면 사용할 수 없음
- **GIVEN** `bank.test` 로그인이 저장돼 있다
- **WHEN** 누군가 데이터베이스에서 그 행의 사이트를 `attacker.test` 로 바꾼 뒤 브라우저 작업이 그 항목을 쓰려 하면
- **THEN** 복호화 인증이 실패해 값이 사용되지 않는다

### Requirement: 항목 종류와 입력 검증
시스템은 항목 종류로 `login`, `card`, `apikey`, `oauth` 만 받아야 한다(SHALL). `login` 은 사이트와 비밀번호가, `apikey` 는 키가 있어야 하며, `card` 는 번호가 13~19자리이고 Luhn 검사를 통과하며 만료일이 `MM/YY` 형식으로 지나지 않았고 CVC 가 3~4자리여야 한다(MUST). 조건을 어기면 저장하지 않고 `400` 과 한국어 `error` 메시지로 응답해야 한다(SHALL).

#### Scenario: 잘못된 카드 번호
- **WHEN** 클라이언트가 Luhn 검사를 통과하지 못하는 번호로 `POST /api/vault` 를 호출하면
- **THEN** 응답은 `400` 이고 `error` 는 "카드 번호를 확인해 주세요." 이며 아무것도 저장되지 않는다

#### Scenario: 만료된 카드
- **WHEN** 만료일이 이미 지난 카드를 저장하려 하면
- **THEN** 응답은 `400` 이고 `error` 에 만료 사실이 담기며 저장되지 않는다

### Requirement: 비밀 값을 돌려주지 않는 조회와 응답
시스템은 보관함 조회 `GET /api/vault` 와 저장·수정 응답에서 `id`, `kind`, `site`, `label`, `status`, `meta`, `last_used_at`, `use_count`, `created_at`, `updated_at` 만 돌려줘야 하며(SHALL), 비밀번호·카드 번호·CVC·API 키·토큰을 어떤 응답에도 포함하지 않아야 한다(SHALL NOT). 카드의 `label` 은 "브랜드 •••• 끝 네 자리" 형식이고 `meta` 에는 `brand`, `last4` 만 담아야 한다(SHALL).

#### Scenario: 카드와 로그인이 있는 보관함 조회
- **GIVEN** 로그인 하나와 카드 `4242 4242 4242 4242` 가 저장돼 있다
- **WHEN** 사용자가 `GET /api/vault` 를 호출하면
- **THEN** 카드 항목의 `label` 은 `Visa •••• 4242`, `meta` 는 `{brand: "Visa", last4: "4242"}` 이다
- **AND** 응답 전체에 카드 번호, CVC, 비밀번호 문자열이 나타나지 않는다

### Requirement: 사이트별 여러 계정과 여러 장의 카드
시스템은 같은 사이트에 서로 다른 아이디의 로그인을 각각의 항목으로 보관하고, 같은 아이디(대소문자 무시)로 다시 저장하면 기존 항목을 갱신해야 한다(SHALL). 카드는 카드 번호로 구분해 여러 장을 보관해야 한다(SHALL). 이 구분을 위해 아이디나 카드 번호를 평문으로 저장하지 않아야 한다(SHALL NOT).

#### Scenario: 같은 사이트의 두 계정
- **WHEN** 사용자가 `mail.test` 에 `work@corp.test` 와 `me@home.test` 를 차례로 저장하고, 다시 `Work@corp.test` 로 새 비밀번호를 저장하면
- **THEN** `mail.test` 항목은 두 개이고, 첫 번째 항목의 비밀번호만 새 값으로 바뀐다

#### Scenario: 두 장의 카드
- **WHEN** 사용자가 Visa 카드와 Mastercard 카드를 차례로 저장하면
- **THEN** 지갑에는 `Visa •••• 4242` 와 `Mastercard •••• 4444` 두 장이 있다

### Requirement: 값을 보여주지 않는 항목 수정과 삭제
시스템은 `PATCH /api/vault/:id` 로 일부 필드만 새 값으로 바꿀 수 있게 해야 하며(SHALL), 이때 기존 값을 클라이언트에 보여주지 않아야 한다(SHALL NOT). 수정에 성공하면 항목의 `status` 를 비워야 한다(SHALL). 수정 결과가 같은 사이트의 다른 항목과 같은 계정이 되면 `409` 로 거절해야 한다(SHALL). `DELETE /api/vault/:id` 는 항목을 지워야 한다(SHALL). 다른 사용자의 항목에 대한 요청은 `404` 로 응답해야 한다(SHALL).

#### Scenario: 거부된 비밀번호만 바꾸기
- **GIVEN** 상태가 `rejected` 인 로그인 항목이 있다
- **WHEN** 사용자가 `PATCH /api/vault/:id` 에 `{data: {password: "새 비밀번호"}}` 를 보내면
- **THEN** 아이디는 그대로이고 비밀번호만 바뀌며, 항목의 `status` 는 `null` 이 된다

#### Scenario: 다른 사용자의 항목
- **WHEN** 사용자가 다른 사용자의 항목 id 로 `DELETE /api/vault/:id` 를 호출하면
- **THEN** 응답은 `404` 이고 항목은 남아 있다

### Requirement: 감지된 항목의 확인과 폐기
시스템은 상태가 `captured` 인 항목(브라우저에서 사용자가 직접 입력한 것을 감지해 보관한 항목)을 브라우저 작업에 자동으로 쓰지 않아야 한다(SHALL NOT). `POST /api/vault/:id/confirm` 은 그 항목을 활성으로 바꾸고, 같은 계정의 기존 항목이 있으면 대체해야 한다(SHALL). `POST /api/vault/:id/discard` 는 그 항목을 지워야 한다(SHALL).

#### Scenario: 새 비밀번호 감지 후 확인
- **GIVEN** `shop.test` 에 `choi` 계정이 저장돼 있고, 같은 계정의 다른 비밀번호가 `captured` 로 감지돼 있다
- **WHEN** 사용자가 감지 항목을 확인하면
- **THEN** `shop.test` 의 `choi` 항목은 하나만 남고, 그 비밀번호는 감지된 새 값이다

#### Scenario: 확인 전에는 쓰이지 않음
- **GIVEN** 감지 항목이 아직 확인되지 않았다
- **WHEN** 브라우저 작업이 `shop.test` 로그인을 찾으면
- **THEN** 기존에 확인된 항목만 후보로 나온다

### Requirement: 보관함 활동 기록
시스템은 항목의 생성·변경·삭제·감지·확인·폐기, 사이트의 비밀번호 거부, 브라우저 작업의 값 입력(입력한 필드 이름 포함), 일회용 값 전달, 키 교체를 행위자(`user`, `browser-agent`, `mail`, `connector`, `admin`)와 함께 기록해야 한다(SHALL). 기록에는 비밀 값을 넣지 않아야 한다(SHALL NOT). `GET /api/vault/audit` 는 본인의 기록을 최신순으로, `limit` 최대 200건까지 돌려줘야 한다(SHALL).

#### Scenario: 브라우저 작업이 로그인을 입력한 기록
- **WHEN** 브라우저 에이전트가 저장된 로그인의 아이디와 비밀번호를 페이지에 입력하면
- **THEN** 활동 기록에 `fill` 두 건이 `browser-agent` 행위자, `username` 과 `password` 필드로 남는다
- **AND** 기록 어디에도 비밀번호 값은 없다

### Requirement: 값을 보여주지 않는 암호화 검증
시스템은 `GET /api/vault/proof` 로 본인의 보관함이 봉투 암호화로 저장돼 있음을 값 노출 없이 확인할 수 있게 해야 한다(SHALL). 응답에는 KEK 식별자·공급원·키링 포함 여부와 `stored_in_database: false`, DEK 버전·감싼 크기·해시, 항목별 암호문 크기·해시·IV·AAD·필드 이름, 그리고 다음 검사 결과가 불리언으로 담겨야 한다(SHALL): 사용자 DEK 로 복호화됨, 다른 사이트 AAD 거부, 다른 사용자 AAD 거부, 1비트 변조 거부, KEK 로 직접 복호화 거부, 행에 비밀 필드 평문·base64 없음. 응답에 비밀 값이 포함되지 않아야 한다(SHALL NOT).

#### Scenario: 검증 통과
- **GIVEN** 로그인 하나와 카드 하나가 저장돼 있다
- **WHEN** 사용자가 `GET /api/vault/proof` 를 호출하면
- **THEN** `ok` 는 `true` 이고 각 항목의 검사 여섯 개가 모두 `true` 이다
- **AND** 카드 항목의 필드 이름은 `name`, `number`, `exp`, `cvv` 이지만 값은 나타나지 않는다
