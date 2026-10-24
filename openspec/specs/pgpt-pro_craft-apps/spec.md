# ArtCraft 앱 연동(CADCraft) 명세

## Purpose
ArtCraft 의 오픈소스 제작 앱(CADCraft 먼저, 이어서 PhotoCraft·VectorCraft·SoundCraft·FilmCraft)을 이음오피스처럼 pgpt-pro 채팅에 붙인다. 에이전트는 각 앱의 MCP 서버로 파일을 만들고, 사람은 채팅 카드에서 같은 출처로 띄운 웹(WebAssembly) 판으로 바로 고친다.

## Requirements
### Requirement: 같은 출처의 웹 앱
pgpt-pro 서버는 자체 호스팅한 웹 빌드를 `/craft/<app>/` 에서 SHALL 제공하고(.wasm 은 `application/wasm`, 해시 파일은 immutable 캐시, index.html 은 no-cache), 개발 서버는 `/craft` 를 pgpt-pro 서버로 SHALL 프록시한다. 앱의 부모 페이지 연동은 같은 출처에서만 응답하므로 다른 도메인에 두지 SHALL NOT 는다.

#### Scenario: 웹 앱 불러오기
- **WHEN** 브라우저가 `/craft/photocraft/` 를 연다
- **THEN** index.html 은 no-cache, 해시 붙은 wasm·js 는 immutable 캐시로 같은 출처에서 내려온다

### Requirement: 도면 카드는 CADCraft 로 연다
채팅의 `.dxf`·`.dwg` 카드(배지 CAD)는 누르면 `/craft/cadcraft/?host=parent` 를 iframe 으로 SHALL 열고, `cadcraft:ready` 를 받으면 카드 URL 의 바이트를 `cadcraft:open {name, bytes}` 로 SHALL 보낸다. 앱 안의 SAVE/QSAVE 는 `cadcraft:save` 로 돌아오며, 도면 형식이면 첨부 저장소에 올려 카드가 편집본을 SHALL 가리키게 하고(`edited: true`, 이전 URL 은 `versions`), PNG·PDF·SVG 내보내기는 올린 뒤 링크로 SHALL 알린다. 저장 안 된 변경(`cadcraft:dirty`)이 있으면 표시하고 페이지를 떠날 때 SHALL 묻는다.

#### Scenario: 에이전트 도면을 고쳐 저장
- **GIVEN** 채팅에 "원룸 평면도.dxf" 카드가 있다
- **WHEN** 사용자가 카드를 열어 명령줄에 `circle 4,3 0.3` 을 넣고 `qsave` 한다
- **THEN** 카드가 편집본 URL 로 바뀌고 "편집본 · 눌러서 이어 편집" 으로 표시된다

### Requirement: 에이전트는 CADCraft MCP 로 그린다
pgpt-pro 는 `cadcraft-cli mcp`(stdio) 를 `/mcp/cadcraft`(streamable HTTP, 사용자 JWT) 뒤에 SHALL 두고, 도구와 스키마는 그대로 SHALL 전달한다. deepagents 는 도구 호출마다 MCP 세션을 새로 열기 때문에 사용자마다 cadcraft-cli 프로세스 하나(열린 도면 하나)를 20분 유휴까지 SHALL 유지한다. `open`·`save`·`render` 의 `/workspace/…` 경로는 이 호스트의 deepagents 작업 공간으로 SHALL 바꾸고(작업 공간 밖은 거부), 결과 글의 호스트 경로는 `/workspace` 로 SHALL 되돌린다. mcp-hub 에는 `pgpt-cadcraft` 로 등록되고 계정 연결이 필요 없으므로 모든 사용자에게 SHALL 바인딩되며, 시스템 레지스트리에는 "CADCraft(설계·도면)" 로 SHALL 오른다.

#### Scenario: 평면도 그려줘
- **WHEN** 사용자가 "원룸 평면도를 CAD 도면으로 그려줘 … 파일 이름은 원룸 평면도.dxf" 라고 보낸다
- **THEN** 에이전트가 execute·inspect_drawing·render·save 를 호출해 `/workspace/원룸 평면도.dxf` 를 만들고, 채팅에 그 카드가 생긴다

### Requirement: 한글 표시
웹 빌드는 한글 글꼴을 기본으로 싣지 않으므로, pgpt-pro 용 빌드는 OFL 글꼴(NanumGothic)을 `CRAFT_FONTS_DIR` 로 SHALL 싣는다(웹 필터 두 줄 패치: `artcraft/patches/cadcraft-web-korean-font.patch`). 탭 이름·레이어 이름·도면 글자의 한글이 네모로 SHALL NOT 보인다.

#### Scenario: 한글 레이어 이름
- **WHEN** 한글 이름의 레이어가 있는 PSD 를 연다
- **THEN** 레이어 패널과 탭에 한글이 네모 없이 보인다

### Requirement: 열린 앱을 에이전트와 함께 고친다(라이브)
PhotoCraft·VectorCraft·FilmCraft 카드를 열어 파일이 열리면 페이지는 일회용 티켓(1분, 한 번 사용)과 같은 출처 검사를 거친 웹소켓 `/api/craft/live` 로 `{app, file}` 을 SHALL 알린다. 서버는 그 (사용자, 앱)에 127.0.0.1 임의 포트를 열고 줄 단위 JSON 제어 요청을 페이지로 넘겨 `window.<app>.request` 결과를 SHALL 돌려준다. 그동안 `/mcp/<app>` 는 headless 대신 `<app>-cli mcp --bridge/--connect` 로 그 화면을 SHALL 조작하고, 페이지가 닫히면 headless 로 SHALL 돌아간다.

#### Scenario: 대화창에 적은 수정안이 열린 PhotoCraft 에 바로 반영
- **GIVEN** 사용자가 "세미나 썸네일.psd" 카드를 옆 시트로 열었다
- **WHEN** 채팅에 "제목 글자를 노란색으로 바꾸고 오른쪽 아래에 '선착순 50명' 문구를 넣어줘" 를 보낸다
- **THEN** 상태 알약이 "이미지 편집하는 중" 을 보이는 동안 열린 PhotoCraft 의 제목이 노랗게 바뀌고 문구 레이어가 생기며, 저장은 사용자가 ⌘S 로 한다

### Requirement: 라이브 제어 포트는 그 사용자의 CLI 만
제어 포트는 127.0.0.1 에만, 세션마다 새로 SHALL 열린다. 접속한 소켓의 상대편이 서버가 그 세션용으로 띄운 CLI 프로세스의 것인지(pid, lsof) SHALL 확인해 아니면 끊는다. PhotoCraft·FilmCraft 는 세션마다 새 256비트 토큰을 CLI 환경 변수로만(명령줄에 SHALL NOT) 넘기고, PhotoCraft 는 첫 줄 auth, FilmCraft 는 줄에 token 이 오면 상수 시간으로 비교한다(filmcraft-cli 0.12 는 보내지 않아 pid 확인만). `/workspace` 밖 경로 거부 규칙은 라이브에서도 SHALL 그대로다.

#### Scenario: 다른 프로세스의 접속
- **WHEN** 같은 호스트의 다른 프로세스가 라이브 포트에 붙어 틀린 토큰으로 auth 를 보낸다
- **THEN** 서버는 응답 없이 연결을 끊고 "not its CLI" 를 로그에 남긴다

### Requirement: 열린 앱이 에이전트 맥락이 된다
라이브 앱이 열린 동안 보낸 메시지는 라우터 대신 deepagents 로 SHALL 가고, 그 앱의 도구를 켜며 "사용자가 지금 <앱> 에서 '<파일>' 을 열어 두었어요 … 저장은 사용자가 해요" 힌트를 SHALL 붙인다. 편집기 띠는 "대화와 연결됨"/"AI가 고치는 중" 을 SHALL 보이고, 요청이 오는 동안 앱 테두리를 빛내며 편집이 오면 "저장 안 됨" 으로 SHALL 표시한다.

#### Scenario: 앱이 열린 동안 보낸 메시지
- **GIVEN** VectorCraft 에 "세미나 배너.svg" 가 열려 있다
- **WHEN** 사용자가 "제목을 노랗게" 라고만 보낸다
- **THEN** 에이전트는 새 파일을 만들지 않고 열린 배너를 vectorcraft_ 도구로 고친다

### Requirement: 옆 시트와 최대화 다이얼
앱 시트(최대화 아님)는 오른쪽에 SHALL 놓이고, 채팅 열과 입력창은 왼쪽에서 그대로 SHALL 쓸 수 있다(바깥 클릭으로 닫지 않고 채팅은 살짝 어둡게만). 최대화하면 오른쪽 아래에 둥근 다이얼 버튼이 SHALL 나오고, 누르면 앱 아래쪽을 흐리게(backdrop-filter) 하며 같은 모양의 입력창과 상태 알약이 SHALL 펼쳐진다. 보내거나 Esc 로 SHALL 접히고, 일하는 동안 알약은 다이얼 옆에 SHALL 남는다.

#### Scenario: 최대화한 앱에서 다이얼로 수정
- **GIVEN** PhotoCraft 를 최대화했다
- **WHEN** 다이얼을 눌러 "부제를 더 크게" 를 보낸다
- **THEN** 입력창이 접히고 다이얼 옆 알약이 작업 단계를 보이는 동안 화면의 부제가 커진다

### Requirement: PhotoCraft 웹 페이지 API
PhotoCraft 웹 빌드는 `window.photocraft.request(method, params)` 를 SHALL 둔다(로컬 패치 `artcraft/patches/photocraft-web-page-api.patch`: ControlRequest 채널을 with_control 로 연결, 마감 없음, 매 프레임 응답). 웹에서는 창 캡처가 되지 않으므로 `ui.screenshot` 은 열린 문서를 PNG 로 렌더해 `{base64, mime, width, height}` 로 SHALL 답한다.

#### Scenario: 미리보기 요청
- **WHEN** 라이브 중 에이전트가 `photocraft_doc_render_preview` 를 부른다
- **THEN** 열린 문서의 PNG 이미지가 도구 결과로 돌아온다

## 시연 영상
- https://youtu.be/QyfrjwhBSsw (일부 공개, 95초) · 로컬 `pgpt-pro/docs/demo/pgpt-pro-cadcraft-demo.mp4`
- VectorCraft https://youtu.be/Wu4qx_VWY2A · PhotoCraft https://youtu.be/qVRwjYTMISI · SoundCraft https://youtu.be/HizUJkrQowk · FilmCraft https://youtu.be/rjLw7C5ZN5k (모두 일부 공개, 로컬 `pgpt-pro/docs/demo/pgpt-pro-<app>-demo.mp4`)

## 나머지 앱 (VectorCraft · PhotoCraft · SoundCraft · FilmCraft)
- 열기: VectorCraft 는 `window.vectorcraft.openFile`, FilmCraft 는 `window.filmcraft.importFiles` 뒤 `file.newSequenceFromClip`, PhotoCraft·SoundCraft 는 캔버스에 합성 드롭(SoundCraft 는 `?empty`, FilmCraft 는 `?empty&fresh`).
- 저장: 같은 출처 iframe 안에서 다운로드 링크의 blob 을 가로채 올린다(앱 형식이면 편집본, 아니면 링크). FilmCraft 의 겹친 확장자(`a.mp4.mp4`)는 정리한다.
- MCP 도구는 `<app>_<tool>` 로 이름을 붙여 앱끼리 겹치지 않게 하고, 화면 조작용(ui_*·screenshot·jobs_*)은 뺀다. 에이전트 도구 한도(110) 때문에 사용자의 메시지가 그 앱 작업을 요청할 때만 30분 동안 전체 도구를 보이고, 그 밖에는 `<app>_start` 하나만 보인다. `/workspace` 밖 절대 경로는 거부한다.
- 한글: VectorCraft 는 web 내장 글꼴 필터·UI 대체 글꼴 패치, PhotoCraft·SoundCraft·FilmCraft 는 `set_fonts` 앞에 웹 전용 한글 대체 글꼴(NanumGothic) 추가 패치(`artcraft/patches/*`, `artcraft/build-ko.sh`).
