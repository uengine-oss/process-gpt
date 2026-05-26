# 내부 지식공간 파일 관리 명세

## Purpose
테넌트가 설정 화면에서 내부 지식공간의 파일과 폴더를 직접 관리하는 능력을 보장한다. 사용자/관리자는 파일을 업로드·조회·삭제하고, 폴더를 만들고 이름을 바꾸며, 중복 업로드를 사전에 확인할 수 있다.

## Requirements

### Requirement: 지식공간 파일 직접 업로드
시스템은 `POST /knowledge/files/upload` 멀티파트 요청을 받으면 파일을 스토리지에 저장하고, 파일 메타를 등록한 뒤 RAG 인덱싱을 수행하고, 인덱싱 성공 여부를 담은 결과를 SHALL 반환한다.

#### Scenario: 파일 업로드 및 인덱싱 성공
- **GIVEN** 사용자가 텍스트를 추출할 수 있는 파일과 `tenant_id`를 제공한다
- **WHEN** 사용자가 `POST /knowledge/files/upload`로 파일을 업로드한다
- **THEN** 시스템은 `source_type=upload`, `source_ref`, `file_name`, `indexed=true`를 반환한다
- **AND** 해당 파일은 테넌트 파일 목록에서 조회되고 인덱싱 상태가 `indexed`로 표시된다

#### Scenario: 인덱싱 실패
- **GIVEN** 파일은 업로드되었으나 콘텐츠 추출 또는 인덱싱이 실패한다
- **WHEN** 사용자가 `POST /knowledge/files/upload`로 파일을 업로드한다
- **THEN** 시스템은 `indexed=false`와 실패 사유(`error`)를 반환하고 파일 인덱싱 상태를 `failed`로 표시한다

### Requirement: 중복 파일 사전 확인
시스템은 `GET /knowledge/files/check-hash` 요청을 받으면 동일 테넌트 내에 같은 SHA-256 해시를 가진 파일이 있는지 확인해 결과를 SHALL 반환한다. 업로드 시에는 클라이언트가 보낸 해시를 신뢰하지 않고 서버에서 재계산해 저장한다.

#### Scenario: 동일 해시 파일 존재
- **GIVEN** 동일 테넌트에 같은 해시의 파일이 이미 등록되어 있다
- **WHEN** 클라이언트가 그 파일 해시로 `GET /knowledge/files/check-hash`를 호출한다
- **THEN** 시스템은 `exists=true`와 기존 파일 메타(`existing`)를 반환한다

#### Scenario: 중복 없음
- **GIVEN** 동일 해시의 파일이 등록되어 있지 않다
- **WHEN** 클라이언트가 `GET /knowledge/files/check-hash`를 호출한다
- **THEN** 시스템은 `exists=false`를 반환한다

### Requirement: 테넌트 파일 목록 조회
시스템은 `GET /documents/list` 요청을 받으면 해당 테넌트의 지식공간 파일 목록을 파일명 배열과 확장 메타(`file_details`), 총 개수와 함께 SHALL 반환한다.

#### Scenario: 파일 목록 조회
- **GIVEN** 테넌트에 등록된 지식공간 파일이 존재한다
- **WHEN** 클라이언트가 `tenant_id`로 `GET /documents/list`를 호출한다
- **THEN** 시스템은 `files`, `file_details`(소스 타입·인덱싱 상태·업로더 등 포함), `total`을 반환한다

#### Scenario: 이미지 파일 기본 제외
- **GIVEN** 테넌트 파일 목록에 이미지 파일이 포함되어 있다
- **WHEN** 클라이언트가 `include_images` 없이 `GET /documents/list`를 호출한다
- **THEN** 시스템은 이미지 파일을 제외한 목록을 반환한다

### Requirement: 파일 보기/다운로드 URL 발급
시스템은 `GET /knowledge/files/url` 요청을 받으면 소스 타입에 따라 Drive 뷰어 URL 또는 스토리지 다운로드 URL을 SHALL 반환한다.

#### Scenario: 업로드 파일 다운로드 URL
- **GIVEN** `source_type=upload`인 파일이 존재한다
- **WHEN** 클라이언트가 `GET /knowledge/files/url`을 호출한다
- **THEN** 시스템은 원본 파일명으로 내려받을 수 있는 다운로드 URL을 반환한다

#### Scenario: 잘못된 소스 타입
- **GIVEN** 클라이언트가 `drive`/`upload`가 아닌 `source_type`을 지정한다
- **WHEN** 클라이언트가 `GET /knowledge/files/url`을 호출한다
- **THEN** 시스템은 `400` 상태로 잘못된 소스 타입 오류를 반환한다

### Requirement: 권한 기반 파일 삭제
시스템은 `DELETE /knowledge/files` 요청을 받으면 파일을 검색 인덱스, 스토리지, 파일 메타에서 완전히 제거하되, 관리자가 아닌 사용자는 본인이 업로드한 `upload` 파일만 삭제할 수 있도록 SHALL 제한한다.

#### Scenario: 관리자 파일 삭제
- **GIVEN** 요청자가 관리자(`is_admin=true`)이다
- **WHEN** 관리자가 `DELETE /knowledge/files`로 파일을 삭제한다
- **THEN** 시스템은 해당 파일의 청크, 스토리지 객체, 파일 메타를 제거하고 `ok=true`를 반환한다

#### Scenario: 일반 사용자가 타인 파일 삭제 시도
- **GIVEN** 요청자가 관리자가 아니고 대상 파일의 업로더가 아니다
- **WHEN** 요청자가 `DELETE /knowledge/files`를 호출한다
- **THEN** 시스템은 `403` 상태로 본인 파일만 삭제할 수 있다는 오류를 반환한다

#### Scenario: 일반 사용자가 Drive 항목 삭제 시도
- **GIVEN** 요청자가 관리자가 아니고 대상이 `drive` 소스 항목이다
- **WHEN** 요청자가 `DELETE /knowledge/files`를 호출한다
- **THEN** 시스템은 `403` 상태로 관리자만 제거할 수 있다는 오류를 반환한다

### Requirement: 지식공간 폴더 관리
시스템은 `GET/POST /knowledge/folders`, `POST /knowledge/folders/rename`, `DELETE /knowledge/folders` 요청으로 빈 폴더 생성, 폴더 목록 조회, 폴더 이름 변경, 폴더 삭제를 SHALL 지원하며, 이름 변경과 삭제는 관리자만 수행할 수 있다.

#### Scenario: 빈 폴더 생성
- **GIVEN** 클라이언트가 유효한 `folder_path`를 제공한다
- **WHEN** 클라이언트가 `POST /knowledge/folders`를 호출한다
- **THEN** 시스템은 폴더를 등록하고 이후 폴더 목록 조회에서 그 폴더가 반환된다

#### Scenario: 폴더 이름 변경 시 하위 경로 일괄 갱신
- **GIVEN** 관리자가 기존 폴더와 새 폴더 경로를 제공한다
- **WHEN** 관리자가 `POST /knowledge/folders/rename`을 호출한다
- **THEN** 시스템은 해당 폴더와 하위 폴더의 파일 경로를 새 경로로 갱신하고 영향받은 개수를 반환한다

#### Scenario: 일반 사용자의 폴더 변경 시도
- **GIVEN** 요청자가 관리자가 아니다(`is_admin=false`)
- **WHEN** 요청자가 폴더 이름 변경 또는 삭제를 호출한다
- **THEN** 시스템은 `403` 상태로 관리자만 가능하다는 오류를 반환한다

#### Scenario: 폴더 삭제 시 하위 파일 제거
- **GIVEN** 관리자가 파일이 들어 있는 폴더를 삭제한다
- **WHEN** 관리자가 `DELETE /knowledge/folders`를 호출한다
- **THEN** 시스템은 폴더 하위 모든 파일을 검색 인덱스·스토리지·메타에서 제거하고 삭제/실패 개수를 반환한다
