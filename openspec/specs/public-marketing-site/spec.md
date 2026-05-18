# Public Marketing Site Specification

## Purpose
ProcessGPT의 잠재 사용자가 제품 소개와 마켓플레이스 콘텐츠를 열람하고 연락처 폼을 통해 문의할 수 있는 정적 랜딩 사이트를 제공한다. 인증은 필요하지 않으며, 사이트는 GitHub Pages에서 호스팅된다.

## Requirements

### Requirement: 정적 사이트 배포
The system SHALL be deliverable as a static bundle suitable for GitHub Pages hosting at the configured custom domain.

#### Scenario: 빌드 산출물
- **WHEN** 운영자가 빌드 스크립트를 실행한다
- **THEN** `dist/` 정적 번들이 생성되고, 발행 단계에서 커스텀 도메인 CNAME이 포함되어 GitHub Pages로 배포된다

### Requirement: 핵심 페이지 라우트
The system SHALL expose at least two top-level pages: home (`/`) and marketplace (`/marketplace`).

#### Scenario: 홈 페이지
- **WHEN** 방문자가 `/`로 접근한다
- **THEN** 제품 소개를 위한 히어로, 피처, 케이스 스터디, 컨설팅, 기술 스택, 데모, CTA 섹션이 표시된다

#### Scenario: 마켓플레이스 페이지
- **WHEN** 방문자가 `/marketplace`로 접근한다
- **THEN** 인기 템플릿과 추천 템플릿 카드가 표시된다

### Requirement: 연락처 폼
The system SHALL provide a contact form modal that lets a visitor submit a message from the home page.

#### Scenario: 연락처 모달 노출
- **WHEN** 방문자가 홈 페이지의 연락처 CTA를 활성화한다
- **THEN** 시스템은 연락처 폼 모달을 표시한다

### Requirement: 다국어 표시
The system SHALL provide multilingual content with at least Korean and English locales.

#### Scenario: 언어 전환
- **WHEN** 방문자가 언어 선택을 변경한다
- **THEN** 페이지 텍스트가 선택된 언어로 표시된다

### Requirement: 인증 비요구
The system SHALL be fully public and SHALL NOT require authentication for any page in this scope.

#### Scenario: 비인증 접근
- **WHEN** 방문자가 어떤 페이지든 접근한다
- **THEN** 인증을 요구하지 않는다
