## ADDED Requirements

### Requirement: 사용자 토큰으로 여는 문서 도구 서버

문서 도구는 `POST /office/mcp`의 MCP(Streamable HTTP, 상태 없음)로 제공해야 한다(SHALL). 요청은 `Authorization: Bearer <사용자 토큰>`이 확인될 때만 처리해야 하며(SHALL), 확인되지 않으면 401로 거절해야 한다(SHALL). 도구가 저장소에 올리는 객체는 그 사용자의 권한(또는 설정된 서비스 키)으로 올려야 한다(SHALL).

#### Scenario: 토큰 없는 호출
- **WHEN** 에이전트가 토큰 없이 도구 목록을 요청한다
- **THEN** 401과 함께 거절된다

#### Scenario: 테넌트 등록
- **GIVEN** 테넌트 MCP 설정에 `process-gpt-office`가 `Authorization: Bearer {{user_jwt}}` 헤더로 등록되어 있다
- **WHEN** 사용자가 채팅에서 문서를 고쳐 달라고 한다
- **THEN** 채팅 에이전트가 이 서버의 도구를 쓰고, 채팅 화면의 컨텍스트에 커넥터 `process-gpt-office`가 표시된다

### Requirement: 문서 생성은 제공하지 않기

이 서버는 새 문서를 만드는 도구를 제공하지 않아야 한다(SHALL). 문서 생성은 office-mcp가 맡는다. 도구는 사용자 토큰이 있어야 동작하므로, 사용자 토큰이 없는 백그라운드 업무 실행에서는 에이전트에게 이 서버의 도구가 주어지지 않아야 한다(SHALL).

#### Scenario: 도구 목록
- **WHEN** 에이전트가 도구 목록을 받는다
- **THEN** 목록은 `office_guide`, `office_read_document`, `office_apply_ops`, `office_convert`와 실시간 도구(`office_live_*`)이며, 새 문서를 만드는 도구는 없다

#### Scenario: 백그라운드 업무 실행
- **GIVEN** 에이전트 단계가 사용자 없이(작업 목록 폴링으로) 실행된다
- **WHEN** 에이전트가 도구를 받는다
- **THEN** 이 서버의 도구는 없고, 문서 생성은 office-mcp 경로로 이루어진다

### Requirement: 저장소의 문서 읽기

`office_read_document`는 저장소 문서 주소(`file_url`)를 받아 워드·엑셀·파워포인트·PDF·한글 문서의 내용을 돌려줘야 한다(SHALL). 워드는 블록 번호가 붙은 목록으로 돌려주고 `range`로 범위를 줄일 수 있어야 한다(SHALL). 허락된 출처(`IEUM_ALLOWED_SOURCES`)가 아닌 주소는 거절해야 한다(SHALL).

#### Scenario: 워드 보고서 읽기
- **WHEN** 에이전트가 워드 보고서 주소로 읽기를 부른다
- **THEN** 블록 수와 블록마다 번호·종류(제목·문단·목록)·글이 온다

### Requirement: 연산으로 고쳐 편집본으로 올리기

`office_apply_ops`는 문서 주소와 연산 목록(`ops`)을 받아 문서를 고쳐야 한다(SHALL). `ops`는 연산 객체의 배열이며, 같은 배열을 담은 JSON 문자열도 받아야 한다(SHALL). 비어 있거나 배열이 아니면 오류로 돌려줘야 한다(SHALL). 결과 문서는 원본을 두고 원본 옆에 편집본으로 올려야 하며(SHALL), 결과에는 `file_url`, `file_name`, `content_type`, `editor_url`, 거절된 연산의 번호와 이유가 있어야 한다(SHALL). 워드 결과에는 채팅 문서 패널이 여는 `html_url`이 있어야 한다(SHALL).

#### Scenario: 제목 바꾸기
- **WHEN** 에이전트가 워드 보고서에 `[{"op":"findReplace","find":"출장 결과 보고서","replace":"부산 신항 출장 결과 보고서"}]`를 적용한다
- **THEN** 원본은 그대로이고, 원본 옆에 제목이 바뀐 편집본이 올라가며 그 주소가 돌아온다

#### Scenario: 연산을 문자열로 보냄
- **WHEN** 에이전트가 같은 연산 배열을 JSON 문자열로 보낸다
- **THEN** 배열로 보냈을 때와 같은 결과가 돌아온다

#### Scenario: 채팅 문서 패널
- **WHEN** 채팅 에이전트가 워드 문서를 연산으로 고친다
- **THEN** 채팅 옆 문서 패널에 그 편집본이 원본 형식 편집기로 열린다

### Requirement: 다른 형식으로 바꾸기

`office_convert`는 문서 주소와 대상 형식을 받아 바꾼 문서를 저장소에 올리고 그 주소를 돌려줘야 한다(SHALL). 서버에서 할 수 있는 변환(워드→마크다운·ODT, 마크다운→워드·HTML·ODT, PDF→워드·파워포인트·엑셀·마크다운·EPUB, 엑셀→CSV 등)만 받아야 하며(SHALL), 그 밖의 변환(예: PDF로 내보내기)은 기다리지 않고 바로 되는 변환 목록과 함께 거절해야 한다(SHALL).

#### Scenario: 워드를 ODT로
- **WHEN** 에이전트가 워드 문서를 ODT로 바꾼다
- **THEN** ODT 문서가 올라가고 그 주소와 파일 이름이 돌아온다

#### Scenario: 서버에서 하지 않는 변환
- **WHEN** 에이전트가 워드 문서를 PDF로 바꾸려 한다
- **THEN** 바로 오류가 돌아오고, 오류에 되는 변환 목록이 있다
