# Documentation Portal Specification

## Purpose
ProcessGPT 사용자와 도입 평가자가 설치 가이드, 단계별 튜토리얼, 세부 기능 설명, 에이전트 디자인 패턴 문서를 다국어로 열람할 수 있는 정적 문서 사이트를 제공한다. 콘텐츠 소스는 마크다운 파일이며, 빌드 산출물은 GitHub Pages 또는 Netlify에서 호스팅된다.

## Requirements

### Requirement: 정적 사이트 빌드와 배포
The system SHALL produce a static `dist/` artifact suitable for GitHub Pages and Netlify hosting.

#### Scenario: 정적 빌드
- **WHEN** 운영자가 빌드 명령을 실행한다
- **THEN** `dist/`에 정적 HTML, 자산이 생성된다

#### Scenario: Netlify 배포
- **GIVEN** Netlify 설정이 존재한다
- **WHEN** Netlify가 빌드를 실행한다
- **THEN** 빌드 명령으로 `npm run build`가 호출되고 결과물이 `dist/`에서 공개된다

#### Scenario: GitHub Actions를 통한 자동 배포
- **GIVEN** GitHub Actions 워크플로우가 활성화되어 있다
- **WHEN** `main` 브랜치로 푸시가 발생한다
- **THEN** 빌드와 GitHub Pages 배포가 자동으로 수행된다

### Requirement: 마크다운 콘텐츠 소스
The system SHALL source page content from `content/**/*.md` files so that contributors can publish documentation by adding markdown files.

#### Scenario: 새 페이지 추가
- **WHEN** 기여자가 `content/`에 새 마크다운 파일을 추가하고 빌드한다
- **THEN** 결과 사이트에 해당 페이지가 라우팅되어 표시된다

### Requirement: 다국어 콘텐츠 경로
The system SHALL serve documentation under language prefixes including `/ko/` and `/en/`, with `/jp/` and `/zh/` reserved for future content.

#### Scenario: 한국어와 영어 문서 접근
- **WHEN** 방문자가 `/ko/...` 또는 `/en/...` 경로로 접근한다
- **THEN** 해당 언어의 문서가 표시된다

### Requirement: 콘텐츠 섹션 보장
The system SHALL cover the following sections in its information architecture: 시작하기, 튜토리얼(Level 1~5), 사용자/관리자 가이드, 프로세스 마켓플레이스, 시뮬레이션, 멀티에이전트, A2A 시스템, 음성 채팅, 브라우저 자동화, Claude 스킬, 피드백 시스템, 에이전틱 디자인 패턴(Prompt Chaining, Routing, 병렬화, Tool Use, MCP, Goal Setting, Planning 등).

#### Scenario: 섹션 도달
- **WHEN** 방문자가 메인 네비게이션에서 해당 섹션 링크를 클릭한다
- **THEN** 시스템은 해당 섹션의 첫 문서로 라우팅한다

### Requirement: 환경 변수와 분석 통합
The system SHALL accept `SITE_URL` for canonical URL composition and `GA_ID` for Google Analytics tracking, both via environment variables.

#### Scenario: 사이트 URL 설정
- **GIVEN** `SITE_URL`이 설정되어 있다
- **WHEN** 빌드가 수행된다
- **THEN** 산출된 메타 태그와 사이트맵이 해당 URL을 사용한다

#### Scenario: 분석 설정
- **GIVEN** `GA_ID`가 설정되어 있다
- **WHEN** 사이트가 방문자에게 제공된다
- **THEN** 추적 스크립트가 해당 ID로 로드된다

### Requirement: 인증 비요구
The system SHALL be fully public and SHALL NOT require authentication for any documentation page.

#### Scenario: 비인증 접근
- **WHEN** 방문자가 임의의 문서 페이지에 접근한다
- **THEN** 인증을 요구하지 않는다
