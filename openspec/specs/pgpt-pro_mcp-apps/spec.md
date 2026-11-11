# Lite 앱 규약 v2 — MCP Apps

## Purpose

Process GPT Lite는 화면이 있는 확장(검토 보드·볼트 보드·산출물 보기 같은 앱, 홈 패널, ArtCraft·이음오피스 편집기)을 MCP의 공식 확장인 MCP Apps(2026-01-26) 규약으로 연결한다. 앱 하나는 MCP 서버 하나다. 도구와 화면(`ui://` 리소스)을 제공한다. 화면은 격리된 iframe에서 표준 postMessage JSON-RPC로만 Lite와 통신한다. 같은 앱을 Claude·ChatGPT·VS Code 같은 다른 MCP Apps 호스트에도 띄울 수 있다. 이미 MCP로 구현된 백엔드와 같은 규약을 쓴다. 앱은 Lite의 기능(AI-DLC 기록·사람·세션·결정·알림)을 직접 가져다 쓰지 않고 `lite-host` MCP 서버의 도구로만 쓴다. 실시간 갱신처럼 표준에 아직 없는 것은 Lite 확장(`io.uengine.lite`)으로 둔다. 이 규약은 `pgpt-pro_aidlc-review`의 앱 규약 v1을 대신한다.

## Requirements

### Requirement: 앱 하나는 MCP 서버 하나다

시스템은 앱마다 MCP 서버를 `/api/apps/<id>/mcp`(Streamable HTTP, 상태 없음)에 두어야 한다(SHALL). 매니페스트에 이름을 명시한 입구 도구는 `_meta.ui.resourceUri`로 그 앱의 `ui://<id>/…` 화면을 가리킨다. 화면 리소스는 `text/html;profile=mcp-app`으로 읽힌다. 앱의 다른 도구도 모두 그 앱의 화면에 딸린다. Lite의 감시기만 부르는 훅(`lite_wait_accepts`·`lite_wait_notify`)은 모델에게 보이지 않는다(`visibility: ["app"]`).

#### Scenario: 입구 도구와 화면

- **WHEN** 호스트가 앱의 MCP 서버에서 도구 목록을 받고, 입구 도구가 가리키는 `ui://` 리소스를 읽는다
- **THEN** 입구 도구의 화면 주소는 `ui://<그 앱 id>/`로 시작하고, 리소스의 형식은 `text/html;profile=mcp-app`이며 모듈 스크립트를 포함한다

#### Scenario: 감시기 훅은 모델에게 숨는다

- **WHEN** 검토 보드 앱의 도구 목록을 본다
- **THEN** `lite_wait_accepts`·`lite_wait_notify`의 공개 범위는 `["app"]`뿐이다

### Requirement: 앱은 로그인한 사람의 권한으로만 돈다

시스템은 앱의 MCP 요청마다 그 사람의 토큰을 확인하고, 앱의 도구는 그 사람의 권한으로 실행되어야 한다(SHALL). 토큰이 없는 요청은 401이다. 서버는 세션을 두지 않으므로 GET·DELETE는 405이다. 폴더 구성원이 아닌 사람이 그 폴더의 앱 도구를 부르면 403이다. `lite-host`를 사람의 토큰으로 부르면 그 사람이 볼 수 있는 것만 반환되며, 남에게 홈 카드를 보내는 도구(`notify_user`)는 403이다.

#### Scenario: 토큰 없이

- **WHEN** 토큰 없이 검토 보드의 입구 도구를 부른다
- **THEN** 401로 거절된다

#### Scenario: 구성원이 아니다

- **WHEN** 폴더 구성원이 아닌 사람이 그 폴더의 산출물 목록이나 세션 화면 도구를 부른다
- **THEN** 도구는 오류를 돌려주고 상태는 403이다

#### Scenario: 남의 이름으로 카드

- **WHEN** 사람이 자기 토큰으로 `/api/apps/_host/mcp`의 `notify_user`를 호출해 다른 사람에게 카드를 보내려 한다
- **THEN** 오류가 돌아오고 상태는 403이며, 카드는 전송되지 않는다

### Requirement: 앱은 Lite를 lite-host 도구로만 쓴다

시스템은 앱 서버 코드가 Lite의 모듈을 가져다 쓰지 못하게 하고, 앱에 `lite-host` MCP 서버의 클라이언트만 넘겨야 한다(SHALL). 같은 프로세스의 앱은 메모리 내부 연결로, 따로 실행되는 앱은 `/api/apps/_host/mcp`로 같은 도구를 부른다. 앱 화면은 자기 파일과 Lite 런타임(표준 `App` 위의 얇은 어댑터)만 불러온다.

#### Scenario: import 경계

- **WHEN** 앱 폴더의 서버 파일과 화면 파일이 무엇을 import 하는지 확인한다
- **THEN** 서버 파일은 자기 파일·node 모듈·서버가 선언한 패키지만, 화면 파일은 자기 화면 폴더와 `../../_runtime/lite.js`만 불러오고, 런타임은 MCP Apps SDK(`ext-apps.js`)만 불러온다

#### Scenario: 따로 도는 앱

- **WHEN** 앱이 사람의 토큰으로 `/api/apps/_host/mcp`의 `aidlc_work`를 그 사람이 구성원인 폴더를 대상으로 호출한다
- **THEN** 그 폴더의 AI-DLC 작업(폴더·역할·현재 단계)이 반환된다

### Requirement: 화면은 출처 없는 격리 틀에서 돈다

시스템은 앱 화면을 `sandbox="allow-scripts …"`의 출처 없는 iframe에 띄우고, 화면과는 표준 MCP Apps 연결로만 통신해야 한다(SHALL). 화면의 도구 호출은 그 앱의 서버로 그대로 전달된다. 화면이 여는 링크는 정해진 Lite 화면(작업실·결정 화면·앱·폴더)이나 바깥 http(s) 주소뿐이다. 실시간 갱신(그 폴더에 앱이 알린 변경, 감시기의 「작업이 움직였다」)은 Lite 확장 알림 `notifications/io.uengine.lite/event`로 화면에 전달된다. 화면이 보내는 정보(상태 등)도 같은 알림으로 호스트에 전달된다. 화면 파일과 런타임은 CORS로 제공하고, 따로 열면 CSP sandbox를 적용한다.

#### Scenario: 정해지지 않은 화면으로 옮기기

- **WHEN** 화면이 `/settings/admin`, `//evil`, `javascript:` 주소, 앱의 MCP 주소로 옮기려 한다
- **THEN** 호스트가 거절한다

#### Scenario: 다른 사람의 이의가 바로 보인다

- **WHEN** 두 사람이 같은 폴더의 검토 보드를 보고 있고 한 사람이 카드에 이의를 단다
- **THEN** 다른 사람의 화면에서 다시 불러오지 않아도 그 카드가 「논의 필요」로 바뀐다

### Requirement: 자기 출처가 필요한 화면은 샌드박스 프록시 뒤에서 돈다

시스템은 매니페스트가 `origin: true`로 선언한 앱의 화면(ArtCraft·이음오피스 편집기)만 MCP Apps의 샌드박스 프록시(이중 iframe) 뒤에서 실행해야 한다(SHALL). 바깥 틀 `/api/apps/_sandbox`는 설정한 샌드박스 출처(`PRO_APPS_SANDBOX_ORIGIN`, Lite 화면과 다른 호스트나 포트)에서 뜬다. 바깥 틀은 Lite 화면만 담을 수 있고(`frame-ancestors`), 허락된 부모에게만 답한다. 받은 화면 HTML을 그 출처의 안쪽 틀에서 선언된 CSP를 적용해 실행한다. 샌드박스 출처를 정하지 않으면 바깥 틀은 Lite 출처에서 뜬다. 모델이 작성한 홈 패널과 다른 앱 화면은 출처 없는 틀을 그대로 쓴다.

#### Scenario: 편집기는 샌드박스 출처에서

- **WHEN** 샌드박스 출처를 정한 설치에서 SVG 카드나 엑셀 카드를 연다
- **THEN** VectorCraft·이음오피스 편집기의 틀은 Lite 화면이 아닌 샌드박스 출처에 있고, 편집기는 그 출처의 저장소와 글꼴을 쓴다

#### Scenario: 프록시를 남이 담는다

- **WHEN** 허락되지 않은 페이지가 `/api/apps/_sandbox`를 틀에 담거나 그 틀에 화면 HTML을 보낸다
- **THEN** 브라우저가 담기를 막고(`frame-ancestors`), 프록시는 그 부모에게 답하지 않는다

#### Scenario: 출처가 필요한 앱만

- **WHEN** 로드된 앱 중 `origin: true`인 것을 센다
- **THEN** ArtCraft(`craft`)와 이음오피스(`office`)뿐이다

### Requirement: 홈 패널은 내장 패널 앱이다

시스템은 홈 패널을 내장 `panels` 앱으로 띄우고, 패널의 코드와 데이터는 입구 도구 `panel_view`가 패널 주인에게만 주어야 한다(SHALL). 패널의 저장·외부 JSON·짧은 답·AI-DLC 읽기는 그 앱의 도구이며, 언제나 패널 주인의 권한으로 실행된다. 남의 패널은 404다. AI-DLC 읽기는 다섯 가지 대시보드 읽기 요청만 받고 `..`·인코딩된 점·슬래시를 거절한다. 틀의 높이는 화면이 알린 크기를 따른다.

#### Scenario: 패널 저장

- **WHEN** 패널 주인이 패널 안의 단추로 값을 저장하고 화면을 다시 연다
- **THEN** 저장한 값이 그대로 보이고, 다른 사람이 같은 패널을 저장하려 하면 404다

#### Scenario: 패널이 기록 밖을 읽는다

- **WHEN** 패널 스크립트가 `../panels`, 인코딩된 `..`, 대시보드가 아닌 경로를 AI-DLC 읽기로 부른다
- **THEN** 읽기는 거절된다

### Requirement: ArtCraft 편집기는 화면 안에서 파일을 받고 저장을 넘긴다

시스템은 ArtCraft 웹 앱(CADCraft·VectorCraft·PhotoCraft·SoundCraft·FilmCraft)을 내장 `craft` 앱 화면 안의 같은 출처 틀에 띄워야 한다(SHALL). 파일은 페이지가 화면 도구(`craft_file`)로 넘긴다. 앱의 저장·내보내기는 화면이 `ui/download-file`로 페이지에 넘긴다. 페이지는 앱 자체 형식이면 카드의 편집본으로, 아니면 내보낸 파일 링크로 올린다. 대화와 연결된 동안 에이전트의 요청은 화면 도구(`craft_request`)로 열린 앱에서 실행된다. 이 설치에 없는 앱은 404다.

#### Scenario: 카드를 열면 연결된다

- **WHEN** 사람이 도면·그림·소리·영상 카드를 연다
- **THEN** 그 앱이 파일을 연 상태로 뜨고 머리줄에 「대화와 연결됨」이 보이며, 그동안 앱의 MCP 도구가 열린 화면을 읽는다

#### Scenario: 앱에서 저장

- **WHEN** 사람이 앱에서 저장한다
- **THEN** 편집본이 원본 옆에 올라가고 채팅 카드가 편집본을 가리킨다

### Requirement: 이음오피스 편집기는 화면이 메시지를 중계한다

시스템은 이음오피스 편집기를 내장 `office` 앱 화면 안의 같은 출처 틀에 띄우고, 편집기와 Lite의 기존 메시지 규약(ready·saved·agent·mention·reply …)을 화면이 그대로 중계해야 한다(SHALL). 편집기 주소(그 사람의 토큰 포함)는 페이지가 화면 도구로 넘긴다. 화면은 자기 출처의 `/office/…`만 연다. 리본 접기·한글 도구 상자·미리보기의 AI 칸 숨기기는 화면 도구다. 그림을 주고받을 때 바이트는 base64로 오간다.

#### Scenario: 누르면 멘션

- **WHEN** 「@ 가리키기」를 켜고 편집기에서 셀 범위나 그림을 누른다
- **THEN** 대화 입력창에 그 범위·그림의 멘션 칩이 생긴다

#### Scenario: 한글 그림 왕복

- **WHEN** 한글 문서의 그림을 가리키고 고치라고 한 뒤 「한글 문서에 넣기」를 누른다
- **THEN** 그림이 포토크래프트로 열렸다가 같은 자리에 돌아가고, 검수 기록이 남는다

### Requirement: 한 앱이 깨져도 나머지는 올라온다

시스템은 앱을 올릴 때 매니페스트(규약 2, 이름의 한국어·영어, 입구 도구 이름, 알려진 연결 위치·기다림)를 검사하고 입구 도구가 실제로 등록되는지 확인해야 한다(SHALL). 규약에 맞지 않는 앱은 오류 내용을 기록하고 제외하며, 다른 앱과 Lite는 그대로 올라온다.

#### Scenario: 깨진 앱 둘

- **WHEN** 앱 폴더에 서버 코드가 예외를 던지는 앱과 입구 도구를 등록하지 않는 앱이 있다
- **THEN** 두 앱은 제외되고 나머지 앱과 내장 앱은 올라오며, 제외된 앱의 도구를 부르면 404다
