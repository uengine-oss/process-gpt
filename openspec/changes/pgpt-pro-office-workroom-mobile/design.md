## 결정
- **이음오피스 이식**: process-gpt-vue3 `feat/office-editor-ieumoffice` 의 `OfficeEditorFrame.vue`·`officeEditor.js` 를 Vuetify·supabase-js 없이 옮겼다. 메시지 규약(`ieum-office` ↔ `process-gpt`)과 편집본 처리는 그대로다. 편집기 서버는 같은 출처의 `/office` 로 프록시해 iframe·웹소켓·문서 바이트가 한 출처에서 온다.
- **생성 경로**: 한글은 office-mcp 를 우선 쓰고(`generate_hwpx` 템플릿, 없으면 샌드박스에서 만든 hwpx 를 executor 가 `store_and_render_hwpx` 로 올림), 다른 형식은 deepagents 의 docx/pptx/xlsx/pdf 스킬 결과를 pgpt-pro 가 찾아 올린다. 스크립트가 만든 파일은 `file_artifact` 이벤트가 없으므로 답의 경로와 폴더를 찾아본다.
- **작업실 = agent-share 의 터미널 모델**: PTY + xterm.js, JSON 웹소켓(input/resize ↔ session/output/exit), 스크롤백 재생, 여러 명 동시 보기. Claude Code 는 비대화형으로 돌기 때문에 실행 중에는 입력할 수 없다. 대신 끝난 뒤(또는 멈춘 뒤) 같은 세션을 대화형으로 이어 연다. deepagents 는 SDK 의 `/chat/steer` 로 실행 중에 지시한다.
- **공개 접속 보호**:
  - 셸은 이 컴퓨터 사용자 권한으로 돈다. 그래서 공개 주소 접근 암호 + 로그인 + 터미널 열쇠의 세 겹으로 막는다.
  - 개발용 데모 로그인(코드 000000)은 접근 암호 뒤에 있다.
  - 기본 인증과 API 의 Bearer 가 같은 헤더를 쓰므로, 한 번 통과하면 httpOnly 쿠키로 대신한다.
- **Cloudflare 임시 터널 선택**: ngrok 무료 터널이 느려 바꿨다. 임시 터널은 SSE 를 통과시키지 않으므로 롱폴링으로 내려간다. 이름 있는 터널(계정)로 바꾸면 SSE 가 그대로 동작한다.
- **Android**: TWA(고정 도메인·검증 필요)나 Capacitor(빌드 때 주소 고정) 대신 WebView 셸을 택했다. 주소를 앱에서 바꿀 수 있어야 하기 때문이다.

## 남은 일
- **Google 로그인(Android)**: WebView 에서는 Google 이 막으므로 외부 브라우저로 열린다. 앱으로 돌아오려면 Custom Tabs + 딥 링크가 필요하다.
- **채팅 응답 스트림**: Cloudflare 임시 터널에서는 채팅 응답의 글자 단위 스트림이 보이지 않고 완성된 답이 한 번에 온다. 이름 있는 터널을 쓰면 해결된다.
- **작업실 범위**: 지금은 다른 사람의 실행 폴더도 열 수 있다. 실행 소유자·참여자로 제한하는 권한 확인이 필요하다.
- **office-host 업로드 권한**: 로컬에서는 버킷 정책을 열어 두었다. 운영에서는 office-host 가 사용자 토큰으로 올리도록 맞추는 편이 낫다.
- **FCM 푸시**: `AndroidBridge.getFcmToken()` 은 빈 값이다. FCM 을 연결해야 한다.
