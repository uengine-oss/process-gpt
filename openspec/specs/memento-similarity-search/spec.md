# 유사도 검색 및 청크 조회 명세

## Purpose
적재된 문서 청크를 질의로 검색하거나 파일/인덱스 기준으로 직접 조회하는 능력을 보장한다. 클라이언트는 테넌트 격리된 검색 결과와 컨텍스트 청크를 확보할 수 있다.

## Requirements

### Requirement: 엄격한 top_k 벡터 검색
시스템은 `GET /search` 요청을 받으면 테넌트 범위 내에서 질의와 가장 유사한 청크를 정확히 `top_k`개까지 SHALL 반환하며, 작은 문서 통째 반환·용어집 병합 같은 암묵적 동작 없이 단일 검색만 수행한다.

#### Scenario: 질의 검색
- **GIVEN** 테넌트에 적재된 청크가 존재한다
- **WHEN** 클라이언트가 `query`, `tenant_id`, `top_k`로 `GET /search`를 호출한다
- **THEN** 시스템은 유사도 상위 청크를 `top_k` 이하로 `{response: [...]}` 형태로 반환한다

#### Scenario: 파일 범위 좁힘과 청크 제외
- **GIVEN** 클라이언트가 `file_ids`와 `exclude_chunk_ids`를 함께 지정한다
- **WHEN** 클라이언트가 `GET /search`를 호출한다
- **THEN** 시스템은 지정한 파일들 안에서만 검색하고, 제외된 청크를 빼고 `top_k`를 채운다

#### Scenario: 필수 파라미터 누락
- **GIVEN** 클라이언트가 `query` 또는 `tenant_id`를 제공하지 않는다
- **WHEN** 클라이언트가 `GET /search`를 호출한다
- **THEN** 시스템은 `400` 상태로 필수 파라미터 오류를 반환한다

### Requirement: 범위 분기 검색
시스템은 `GET /retrieve` 요청을 받으면 지정된 `file_ids`, `room_id`, `proc_inst_id` 등에 따라 검색 범위를 분기하고, 외부 용어집 결과를 병합해 청크를 SHALL 반환한다.

#### Scenario: 선택한 파일 기준 검색
- **GIVEN** 클라이언트가 하나 이상의 `file_ids`를 지정한다
- **WHEN** 클라이언트가 `GET /retrieve`를 호출한다
- **THEN** 시스템은 작은 문서는 전체 청크를, 큰 문서는 질의 기반 상위 청크를 반환한다

#### Scenario: 방 범위 검색 시 전역 지식 병합
- **GIVEN** 클라이언트가 `room_id`를 지정한다
- **WHEN** 클라이언트가 `GET /retrieve`를 호출한다
- **THEN** 시스템은 방 범위 청크와 전역 범위 청크를 함께 반환하고, 전역 지식을 우선 병합한다

#### Scenario: 용어집 병합
- **GIVEN** 질의에 해당하는 외부 용어집 항목이 존재한다
- **WHEN** 클라이언트가 `GET /retrieve`를 호출한다
- **THEN** 시스템은 검색 청크와 용어집 항목을 중복 제거해 병합한 결과를 반환한다
- **AND** 용어집 조회가 실패하면 검색 청크만으로 결과를 반환한다

### Requirement: 이미지 전용 검색
시스템은 `GET /retrieve-images` 요청을 받으면 이미지 분석 캡션을 기준으로 검색해 이미지 식별자·URL·캡션을 담은 결과를 SHALL 반환한다.

#### Scenario: 이미지 검색
- **GIVEN** 테넌트에 Vision 분석된 이미지가 적재되어 있다
- **WHEN** 클라이언트가 `query`, `tenant_id`로 `GET /retrieve-images`를 호출한다
- **THEN** 시스템은 `image_id`, `image_url`, `caption`, `file_name`을 담은 `{images: [...]}`를 반환한다

### Requirement: 청크 직접 조회
시스템은 파일명·파일 경로·청크 인덱스를 기준으로 청크 본문과 메타데이터를 직접 조회할 수 있도록 `POST /retrieve-by-indices`와 `GET /documents/chunks-metadata`, `/documents/chunks-by-file-path`, `/documents/chunks-by-file-name`, `/documents/chunks-with-embeddings`를 SHALL 제공하며, 이미지 분석 청크는 일반 청크 조회 결과에서 제외한다.

#### Scenario: 청크 인덱스로 조회
- **GIVEN** 클라이언트가 `tenant_id`, `file_name`, `chunk_indices`를 제공한다
- **WHEN** 클라이언트가 `POST /retrieve-by-indices`를 호출한다
- **THEN** 시스템은 지정한 인덱스의 청크 본문과 메타데이터를 반환한다

#### Scenario: 파일별 청크 메타 조회
- **GIVEN** 특정 문서가 청크로 적재되어 있다
- **WHEN** 클라이언트가 `tenant_id`, `file_name`으로 `GET /documents/chunks-metadata`를 호출한다
- **THEN** 시스템은 청크 인덱스 순서로 정렬된 청크 메타데이터와 총 개수를 반환한다

#### Scenario: 청크와 임베딩 동시 조회
- **GIVEN** 다운스트림 에이전트가 특정 파일의 청크와 임베딩이 필요하다
- **WHEN** 클라이언트가 `file_path` 또는 `file_name`으로 `GET /documents/chunks-with-embeddings`를 호출한다
- **THEN** 시스템은 청크 본문·메타데이터와 임베딩 벡터를 함께 반환한다

#### Scenario: 식별자 미지정
- **GIVEN** 클라이언트가 `file_path`와 `file_name`을 모두 제공하지 않는다
- **WHEN** 클라이언트가 `GET /documents/chunks-with-embeddings`를 호출한다
- **THEN** 시스템은 `400` 상태로 둘 중 하나가 필요하다는 오류를 반환한다
