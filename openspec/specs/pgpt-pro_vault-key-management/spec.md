# 보관함 키(KEK/DEK) 관리 명세

## Purpose
pgpt-pro 보관함의 마스터 키(KEK) 공급원과 버전, KEK·DEK 교체, 폐기 KEK 정리, 전수 검증, 이전 버전 데이터와의 호환을 운영자에게 보장한다. KEK 는 데이터베이스 밖에만 있고, 키 작업은 데이터 손실 없이 수행된다.

## Requirements
### Requirement: KEK 공급원과 식별
시스템은 KEK 를 환경 변수 `PRO_VAULT_KEK`(현재 키)와 `PRO_VAULT_KEK_RETIRED`(쉼표로 구분한 이전 키들), 또는 권한 0600 의 키링 파일(`PRO_VAULT_KEYRING`, 기본은 서버 폴더의 키링 파일) 중 하나에서 읽어야 한다(SHALL). 키링 파일이 없으면 첫 기동 때 만들어야 한다(SHALL). KEK 는 32바이트여야 하며 아니면 서버가 기동하지 않아야 한다(MUST NOT start). KEK 식별자는 KEK 의 SHA-256 앞 12자리여야 한다(SHALL). KEK 는 데이터베이스·로그·API 응답에 나타나지 않아야 한다(SHALL NOT).

#### Scenario: 보안 정보 조회
- **WHEN** 클라이언트가 `GET /api/config` 를 호출하면
- **THEN** `vault` 에 `kekId`, `provider`(`file` 또는 `env`), `keyVersions`, `algorithm` 이 담기고 키 값은 없다

### Requirement: 업그레이드 후 기존 데이터 유지
시스템은 단일 키 파일을 쓰던 이전 버전에서 업그레이드할 때 그 키를 키링의 첫 번째 키로 가져와야 하며(SHALL), 이전에 저장된 모든 DEK 와 항목을 그대로 복호화할 수 있어야 한다(SHALL).

#### Scenario: 단일 키 파일에서 키링으로
- **GIVEN** 이전 버전이 단일 키 파일로 저장한 로그인 2건과 OAuth 1건이 있다
- **WHEN** 새 버전이 처음 기동하고 운영자가 전수 검증을 실행하면
- **THEN** 키링의 현재 KEK 식별자는 이전과 같고, 3건 모두 열린다(`failed` 없음)

### Requirement: KEK 교체
운영자가 KEK 교체를 실행하면, 시스템은 새 KEK 를 만들어 현재 키로 지정하고 모든 사용자의 DEK 를 새 KEK 로 다시 감싸야 한다(SHALL). 항목 암호문은 바꾸지 않아야 한다(SHALL NOT). 이전 KEK 는 정리될 때까지 키링에 남아야 하고(SHALL), 이전 KEK 아래 남은 DEK 는 다음에 열릴 때 현재 KEK 로 다시 감싸야 한다(SHALL). KEK 공급원이 환경 변수이면 교체를 거절하고 운영 절차를 안내해야 한다(SHALL).

#### Scenario: 교체 후 항목은 그대로, DEK 만 다시 감쌈
- **GIVEN** 로그인 항목이 저장돼 있다
- **WHEN** 운영자가 KEK 를 교체하면
- **THEN** 그 사용자의 키 행은 새 KEK 식별자를 가리키고, 항목 암호문은 교체 전과 같다
- **AND** 새 KEK 로 DEK 를 풀어 항목을 열 수 있고, 이전 KEK 로는 DEK 를 풀 수 없다

#### Scenario: 환경 변수 공급원
- **GIVEN** KEK 를 `PRO_VAULT_KEK` 로 공급하고 있다
- **WHEN** 운영자가 KEK 교체를 실행하면
- **THEN** 교체는 수행되지 않고, 새 키를 `PRO_VAULT_KEK` 에, 이전 키를 `PRO_VAULT_KEK_RETIRED` 에 두고 재시작한 뒤 재래핑하라는 안내가 출력된다

### Requirement: 폐기된 KEK 정리
운영자가 정리를 실행하면, 시스템은 현재 키가 아니고 어떤 DEK 도 참조하지 않는 KEK 만 키링에서 지워야 한다(SHALL). 참조가 남은 KEK 는 지우지 않아야 한다(SHALL NOT).

#### Scenario: 교체 후 정리
- **GIVEN** KEK 교체로 모든 DEK 가 새 KEK 로 옮겨졌다
- **WHEN** 운영자가 정리를 실행하면
- **THEN** 이전 KEK 가 키링에서 사라지고, 모든 항목은 여전히 열린다

### Requirement: DEK 교체
운영자가 사용자(또는 전체)의 DEK 교체를 실행하면, 시스템은 새 DEK 를 만들어 그 사용자의 모든 항목을 한 트랜잭션 안에서 재암호화하고 DEK 버전을 1 올려야 한다(SHALL). 도중에 실패하면 아무것도 바뀌지 않아야 한다(SHALL NOT). 교체 후 이전 DEK 로는 새 암호문을 열 수 없어야 한다(MUST NOT). 감싼 DEK 의 AAD 에 버전을 포함해 이전 버전의 감싼 DEK 로 되돌려 놓는 것을 막아야 한다(SHALL).

#### Scenario: 로그인과 카드가 있는 사용자의 DEK 교체
- **WHEN** 운영자가 로그인 1건, 카드 1건을 가진 사용자의 DEK 를 교체하면
- **THEN** 결과는 2건 재암호화이고, 두 항목의 암호문이 모두 바뀌며 DEK 버전은 2 가 된다
- **AND** 브라우저 작업은 같은 비밀번호와 CVC 를 그대로 쓴다

### Requirement: 전수 검증
운영자가 전수 검증을 실행하면, 시스템은 모든 사용자의 모든 항목을 실제로 열어 보고 사용자 수, 항목 수, 성공 수, 실패 목록, KEK 식별자별 DEK 수를 출력해야 하며(SHALL), 비밀 값이나 키는 출력하지 않아야 한다(SHALL NOT). 이전 버전에서 저장돼 구분 지문이 없는 항목은 이때 채워야 한다(SHALL).

#### Scenario: 운영 데이터 검증
- **WHEN** 운영자가 전수 검증을 실행하면
- **THEN** `items` 와 `ok` 가 같고 `failed` 는 빈 목록이다

### Requirement: 메모리 안의 DEK 수명
시스템은 풀어 둔 DEK 를 메모리에 최대 10분만 두어야 하며(SHALL), 만료되거나 교체될 때 그 메모리를 0 으로 덮어써야 한다(SHALL).

#### Scenario: 오래된 DEK
- **WHEN** 사용자의 DEK 를 마지막으로 푼 지 10분이 지나면
- **THEN** 다음 사용 때 데이터베이스의 감싼 DEK 를 KEK 로 다시 푼다

### Requirement: 키 작업 기록
시스템은 KEK 교체(지연 재래핑 포함)와 DEK 교체를 사용자별 보관함 활동 기록에 `admin` 행위자로 남겨야 한다(SHALL).

#### Scenario: DEK 교체 기록
- **WHEN** 운영자가 사용자의 DEK 를 교체하면
- **THEN** 그 사용자의 활동 기록에 `rotate_dek` 이 재암호화한 항목 수와 함께 남는다

