## ADDED Requirements

### Requirement: 서버 주소를 설정하는 Android 앱
Android 앱(`pgpt-pro/android`, Kotlin WebView 셸, minSdk 26)은 처음 실행 때 서버 주소와 선택적인 접근 암호를 SHALL 받아 한 번 연결을 확인한 뒤 저장하고, 그 서버의 pgpt pro 를 전체 화면으로 SHALL 연다. 서버 주소는 앱 아이콘 길게 누르기("서버 주소 바꾸기")와 연결 실패 화면에서 SHALL 바꿀 수 있다.

#### Scenario: 처음 실행
- **WHEN** 공개 주소와 접근 암호를 넣고 "연결" 을 누른다
- **THEN** 로그인 화면이 열리고, 이후 실행부터는 바로 그 서버가 열린다

### Requirement: 앱이 대신하는 일
앱은 서버의 기본 인증 요청에 저장된 암호로 SHALL 답하고, 파일 선택, 마이크·카메라 권한(페이지가 요청할 때만), 뒤로 가기(웹 기록), 맨 위에서 당겨 새로고침, 다른 사이트 링크의 외부 브라우저 열기를 SHALL 제공하며, `window.AndroidBridge`(`getAppVersion`, `getServerUrl`, `getFcmToken`, `openSettings`)를 SHALL 노출한다.

#### Scenario: 다른 사이트 링크
- **WHEN** 웹 앱에서 다른 도메인 링크(예: Google 로그인)를 연다
- **THEN** 앱 안이 아니라 외부 브라우저에서 열린다
