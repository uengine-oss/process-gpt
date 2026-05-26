# 워크아이템 산출물 발행 명세

## Purpose
워크아이템의 폼 산출물을 문서로 생성해 Google Drive에 발행하고, 같은 산출물을 검색 인덱스에도 적재하는 능력을 보장한다.

## Requirements

### Requirement: 워크아이템 산출물 문서 생성과 발행
시스템은 `POST /process-output` 요청을 받으면 지정한 워크아이템의 폼 산출물을 DOCX 문서로 변환해 Google Drive의 프로세스별 폴더에 업로드하고, 업로드 메타 목록과 폴더 경로를 SHALL 반환한다.

#### Scenario: report/slide 산출물 발행
- **GIVEN** 워크아이템의 폼 정의에 `report` 또는 `slide` 타입 필드가 있고 그 값이 채워져 있다
- **WHEN** 클라이언트가 `workitem_id`로 `POST /process-output`을 호출한다
- **THEN** 시스템은 각 산출물을 DOCX로 변환해 Drive에 업로드하고 `uploaded` 목록과 `folder_path`를 반환한다

#### Scenario: report/slide 필드가 없는 경우
- **GIVEN** 워크아이템 폼 정의에 `report`/`slide` 타입 필드가 없다
- **WHEN** 클라이언트가 `POST /process-output`을 호출한다
- **THEN** 시스템은 폼 전체를 DOCX로 변환해 Drive에 업로드하고, 업로드 문서의 링크를 워크아이템의 `output_url`로 기록한다

#### Scenario: 존재하지 않는 워크아이템
- **GIVEN** 지정한 `workitem_id`에 해당하는 워크아이템이 없다
- **WHEN** 클라이언트가 `POST /process-output`을 호출한다
- **THEN** 시스템은 `404` 상태로 워크아이템을 찾을 수 없다는 오류를 반환한다

### Requirement: 발행 산출물의 검색 인덱스 적재
시스템은 발행한 산출물 문서를 청크로 변환해 검색 인덱스에 적재하고, 산출물 청크에 출처 식별 메타데이터를 SHALL 부여한다.

#### Scenario: 산출물 인덱싱
- **GIVEN** 산출물 DOCX가 Drive에 업로드되었다
- **WHEN** 시스템이 후속 인덱싱을 수행한다
- **THEN** 산출물 청크는 검색 인덱스에 적재되고 `source_type=process_output`, `workitem_id`, `activity_name` 메타데이터를 가진다
- **AND** 적재가 성공한 산출물은 처리 완료 파일로 기록된다
