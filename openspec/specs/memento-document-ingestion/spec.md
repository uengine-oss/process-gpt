# 문서 인제스트 명세

## Purpose
업로드된 파일, 스토리지에 있는 파일, 데이터베이스 레코드를 검색 가능한 청크로 변환해 원문 저장소와 검색 인덱스에 적재하는 능력을 보장한다. 클라이언트는 다양한 소스의 콘텐츠를 인제스트하고 처리 결과를 확인할 수 있다.

## Requirements

### Requirement: 파일 업로드 인제스트
시스템은 `POST /save-to-storage` 멀티파트 요청을 받으면 파일을 스토리지에 업로드하고, 콘텐츠를 추출·청킹·임베딩해 검색 인덱스에 적재한 뒤, 처리 성공 여부를 담은 결과를 SHALL 반환한다.

#### Scenario: 지원 형식 파일 업로드 성공
- **GIVEN** 클라이언트가 텍스트를 추출할 수 있는 문서 파일과 `tenant_id`를 제공한다
- **WHEN** 클라이언트가 `POST /save-to-storage`로 파일을 업로드한다
- **THEN** 시스템은 `file_path`, `file_name`, `public_url`과 `processed=true`를 반환한다
- **AND** 추출된 청크가 검색 인덱스에 적재되고 해당 파일이 처리 완료 목록에 기록된다

#### Scenario: 콘텐츠를 추출할 수 없는 파일
- **GIVEN** 클라이언트가 콘텐츠를 추출할 수 없는 파일을 제공한다
- **WHEN** 클라이언트가 `POST /save-to-storage`로 파일을 업로드한다
- **THEN** 시스템은 파일을 스토리지에 업로드한 결과와 `processed=false`를 반환한다

#### Scenario: 검색 인덱스 적재 실패
- **GIVEN** 파일은 스토리지에 업로드되었으나 검색 인덱스 적재가 실패한다
- **WHEN** 클라이언트가 `POST /save-to-storage`로 파일을 업로드한다
- **THEN** 시스템은 업로드는 성공했고 처리는 실패했음을 알리는 `processed=false` 결과를 반환한다

### Requirement: 지식 범위 메타데이터 부여
시스템은 인제스트 시 클라이언트가 제공한 `proc_inst_id` 또는 `room_id` 옵션에 따라 청크에 `knowledge_scope`(`room` 또는 `global`)와 관련 식별자를 SHALL 부여한다.

#### Scenario: 방 범위 업로드
- **GIVEN** 클라이언트가 `room_id`를 옵션으로 제공한다
- **WHEN** 클라이언트가 파일을 인제스트한다
- **THEN** 적재된 청크는 `knowledge_scope=room`과 해당 `room_id`를 메타데이터로 가진다

#### Scenario: 전역 범위 업로드
- **GIVEN** 클라이언트가 `room_id`를 제공하지 않는다
- **WHEN** 클라이언트가 파일을 인제스트한다
- **THEN** 적재된 청크는 `knowledge_scope=global`을 메타데이터로 가진다

### Requirement: 다양한 소스의 문서 처리
시스템은 `POST /process`(`storage_type=local` 또는 `storage`)와 `POST /process/database` 요청을 받으면 각각 파일 시스템 경로의 문서, 스토리지의 파일, 데이터베이스 레코드를 청크로 변환해 검색 인덱스에 SHALL 적재한다.

#### Scenario: 스토리지 파일 처리
- **GIVEN** 클라이언트가 스토리지에 있는 파일 경로를 지정한다
- **WHEN** 클라이언트가 `storage_type=storage`와 `file_path`로 `POST /process`를 호출한다
- **THEN** 시스템은 해당 파일을 추출·적재하고 성공 메시지를 반환한다

#### Scenario: 스토리지 처리 시 파일 경로 누락
- **GIVEN** 클라이언트가 `file_path`를 제공하지 않는다
- **WHEN** 클라이언트가 `storage_type=storage`로 `POST /process`를 호출한다
- **THEN** 시스템은 `400` 상태로 `file_path`가 필요하다는 오류를 반환한다

#### Scenario: 존재하지 않는 로컬 디렉토리
- **GIVEN** 지정한 입력 디렉토리가 존재하지 않는다
- **WHEN** 클라이언트가 `storage_type=local`로 `POST /process`를 호출한다
- **THEN** 시스템은 `404` 상태로 디렉토리가 없다는 오류를 반환한다

#### Scenario: 데이터베이스 레코드 처리
- **GIVEN** 클라이언트가 조회 옵션을 제공하고 해당 조건의 레코드가 존재한다
- **WHEN** 클라이언트가 `POST /process/database`를 호출한다
- **THEN** 시스템은 각 레코드의 산출물을 문서로 변환해 검색 인덱스에 적재하고 성공 메시지를 반환한다

### Requirement: 문서 내 이미지 분석 병합
시스템은 PDF/DOCX/PPTX 문서에서 추출한 이미지를 Vision 분석하고, 해당 이미지가 위치한 구간의 청크에 분석 텍스트를 SHALL 병합한다. 단, Vision을 지원하지 않는 LLM 제공자 설정에서는 이미지 분석을 건너뛴다.

#### Scenario: 이미지 포함 문서 인제스트
- **GIVEN** Vision 분석이 가능한 설정에서 이미지가 포함된 문서를 인제스트한다
- **WHEN** 시스템이 문서를 처리한다
- **THEN** 각 이미지는 한 번만 분석되고, 분석 텍스트가 해당 이미지 구간의 청크 콘텐츠에 포함된다

#### Scenario: 단일 이미지 파일 인제스트
- **GIVEN** 클라이언트가 단일 이미지 파일(JPG/PNG/GIF/BMP/WEBP)을 인제스트한다
- **WHEN** 시스템이 파일을 처리한다
- **THEN** 시스템은 이미지를 하나의 이미지 문서로 만들고, Vision 분석 텍스트를 콘텐츠로 적재한다
