# 에이전트 문서 편집(이음오피스) 명세

## Purpose
pgpt-pro 채팅에서 에이전트가 만든 한글·워드·엑셀·파워포인트·PDF 문서를 다운로드 없이 process-gpt 의 이음오피스 편집기로 바로 열어 편집하고, 편집본이 채팅 카드에 이어지도록 보장한다.

## Requirements
### Requirement: 에이전트가 만든 문서는 그 자리에서 편집
pgpt-pro 채팅은 에이전트가 만든 문서(hwpx·hwp·docx·xlsx·csv·pptx·pdf)를 문서 카드로 SHALL 보여 주고, 카드를 누르면 다운로드가 아니라 process-gpt 의 이음오피스 편집기(office-host, 같은 출처의 `/office` 로 프록시)에서 원본 형식 그대로 SHALL 연다. 편집기 주소에는 로그인 토큰을 실어 편집기 서버가 사용자를 SHALL 확인한다.

#### Scenario: 한글 문서 요청
- **WHEN** 사용자가 "11월 고객 세미나 안내문을 한글 문서로 만들어줘" 라고 보낸다
- **THEN** 채팅에 "11월 고객 세미나 안내문.hwpx" 카드 하나가 생기고, 누르면 한글 편집기가 문서 AI 도우미와 함께 열린다

### Requirement: 문서를 저장소 URL 로 확보
pgpt-pro 는 office-mcp(`generate_hwpx`, `store_and_render_hwpx`) 결과의 `file_url` 을 그대로 SHALL 쓰고, 에이전트가 샌드박스에 직접 만든 문서(답에 적힌 경로, 대화 작업 폴더, 작업 공간 맨 위에서 이번 실행 동안 생긴 파일)는 `files` 버킷에 올려 공개 URL 을 SHALL 붙인다. 같은 문서는 카드 하나만 SHALL 만들고, office-mcp 가 바꾼 ASCII 이름 대신 답에 적힌 이름을 SHALL 보여 주며, 문서가 있으면 그것을 만든 스크립트 카드는 SHALL NOT 보여 준다.

#### Scenario: 스크립트로 만든 엑셀
- **GIVEN** 에이전트가 xlsx 스킬 스크립트로 `/workspace/11월 고객 세미나 비용 예산표.xlsx` 를 만들었다
- **WHEN** 답이 끝난다
- **THEN** "11월 고객 세미나 비용 예산표.xlsx" 카드가 공개 URL 과 함께 생기고 스크립트(.py) 카드는 없다

### Requirement: 편집본 저장
편집기 안에서 저장하면 편집기 서버가 원본 옆에 `edited-…` 사본을 올리고, pgpt-pro 는 그 URL 로 카드를 SHALL 바꾸며(`edited: true`, 이전 URL 은 `versions` 에 보관) 카드 설명을 "편집본 · 눌러서 이어 편집" 으로 SHALL 표시한다.

#### Scenario: 고치고 저장
- **WHEN** 사용자가 한글 편집기에서 문장을 고치고 ⌘S 를 누른다
- **THEN** "저장했어요" 알림이 뜨고, 카드를 다시 열면 편집본이 열린다
