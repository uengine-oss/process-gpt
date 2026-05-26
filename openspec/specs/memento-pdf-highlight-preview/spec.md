# PDF 하이라이트 미리보기 명세

## Purpose
PDF 파일의 특정 페이지에서 지정한 영역을 하이라이트한 미리보기 이미지를 제공하는 능력을 보장한다. 클라이언트는 검색 결과의 출처 위치를 시각적으로 확인할 수 있다.

## Requirements

### Requirement: PDF 페이지 영역 하이라이트 렌더링
시스템은 `GET /preview/pdf-highlight` 요청을 받으면 지정한 PDF 파일의 페이지에서 `bbox` 영역을 하이라이트한 PNG 이미지를 렌더링하고, 그 이미지의 공개 URL을 SHALL 반환한다.

#### Scenario: 하이라이트 렌더링 성공
- **GIVEN** 스토리지에 지정한 `file_id`의 PDF가 존재하고 `page`와 `bbox`가 유효하다
- **WHEN** 클라이언트가 `tenant_id`, `file_id`, `page`, `bbox`로 `GET /preview/pdf-highlight`를 호출한다
- **THEN** 시스템은 하이라이트된 PNG의 `url`, `cache_key`, `page`, `width`, `height`와 `cached=false`를 반환한다

#### Scenario: 잘못된 bbox 형식
- **GIVEN** 클라이언트가 `x0,y0,x1,y1` 형식이 아닌 `bbox`를 제공한다
- **WHEN** 클라이언트가 `GET /preview/pdf-highlight`를 호출한다
- **THEN** 시스템은 `400` 상태로 잘못된 `bbox` 오류를 반환한다

#### Scenario: 페이지 범위 초과
- **GIVEN** 지정한 `page`가 PDF의 페이지 범위를 벗어난다
- **WHEN** 클라이언트가 `GET /preview/pdf-highlight`를 호출한다
- **THEN** 시스템은 `400` 상태로 페이지 범위 초과 오류를 반환한다

#### Scenario: PDF 미존재
- **GIVEN** 지정한 `file_id`의 PDF가 스토리지에 없다
- **WHEN** 클라이언트가 `GET /preview/pdf-highlight`를 호출한다
- **THEN** 시스템은 `404` 상태로 PDF를 찾을 수 없다는 오류를 반환한다

### Requirement: 렌더링 결과 캐시 재사용
시스템은 파일·페이지·`bbox`·`dpi` 조합으로 결정되는 캐시 키에 따라 이미 렌더링된 이미지를 재사용하고, 캐시 적중 시 재렌더링 없이 캐시된 URL을 SHALL 반환한다.

#### Scenario: 동일 요청 캐시 적중
- **GIVEN** 이전에 동일한 파일·페이지·`bbox`·`dpi`로 하이라이트가 렌더링되었다
- **WHEN** 클라이언트가 같은 파라미터로 다시 `GET /preview/pdf-highlight`를 호출한다
- **THEN** 시스템은 재렌더링 없이 캐시된 `url`과 `cached=true`를 반환한다
