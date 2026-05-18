# Operator Console Specification

## Purpose
최종 사용자와 운영자가 ProcessGPT의 인증·프로세스 정의·인스턴스·작업·캘린더·칸반·채팅·분석·외부 폼 같은 핵심 기능에 접근할 수 있는 단일 SPA를 제공한다. 인증은 Supabase 또는 Keycloak으로, 백엔드 호출은 게이트웨이 또는 개발 프록시를 통해 이루어진다.

## Requirements

### Requirement: 정적 SPA 배포
The system SHALL be deliverable as a Vite-built static bundle served by a lightweight HTTP server in a container image.

#### Scenario: 컨테이너 배포
- **GIVEN** Docker 이미지가 빌드되어 있다
- **WHEN** 운영자가 컨테이너를 실행한다
- **THEN** 정적 번들이 호스팅되고 사용자가 브라우저로 접근할 수 있다

#### Scenario: Kubernetes 매니페스트
- **WHEN** 운영자가 `kubernetes/` 매니페스트를 적용한다
- **THEN** Deployment, Service, Ingress 자원이 생성되어 외부에서 접근 가능해진다

### Requirement: 인증 흐름
The system SHALL provide login, registration, and password-reset screens, and SHALL require email verification at registration.

#### Scenario: 사용자 로그인
- **WHEN** 사용자가 `/auth/login` 화면에서 자격 증명을 입력하고 제출한다
- **THEN** 사용자는 보호된 화면에 접근할 수 있는 세션을 부여받는다

#### Scenario: 회원가입과 이메일 인증
- **WHEN** 사용자가 `/auth/register`에서 가입을 제출한다
- **THEN** 시스템은 가입을 접수하고 이메일 인증을 요구한다

#### Scenario: 비밀번호 재설정
- **WHEN** 사용자가 `/auth/reset-password`로 이동한다
- **THEN** 시스템은 비밀번호 재설정 흐름을 제공한다

### Requirement: 인증 백엔드 구성
The system SHALL authenticate users against Supabase by default and SHALL optionally support Keycloak when configured.

#### Scenario: Supabase 기본 인증
- **GIVEN** `VITE_SUPABASE_URL`과 `VITE_SUPABASE_KEY`가 설정되어 있다
- **WHEN** 사용자가 로그인한다
- **THEN** Supabase가 자격 증명을 검증한다

#### Scenario: Keycloak 사용
- **GIVEN** `VITE_KEYCLOAK_URL`, `VITE_KEYCLOAK_REALM`, `VITE_KEYCLOAK_CLIENT_ID`가 설정되어 있다
- **WHEN** 사용자가 로그인한다
- **THEN** 시스템은 Keycloak 인증을 수행한다

### Requirement: 보호된 라우트 가드
The system SHALL prevent unauthenticated access to screens marked as protected and SHALL allow public access to designated unauthenticated screens.

#### Scenario: 보호된 라우트 접근 제한
- **WHEN** 미인증 사용자가 `requiresAuth` 메타 플래그가 있는 라우트로 이동을 시도한다
- **THEN** 시스템은 인증 화면으로 라우팅한다

#### Scenario: 외부 폼 공개 접근
- **WHEN** 미인증 사용자가 `/external-forms/:formId`로 접근한다
- **THEN** 시스템은 인증 없이 폼을 표시한다

### Requirement: 핵심 사용자 화면 라우트
The system SHALL expose the following operator/user screens via URL routes: process definitions and instances, todolist, calendar, kanban, chat, analytics, markdown editor, slide editor, presentation, tenant management, and a landing page; a 404 screen SHALL handle unknown routes.

#### Scenario: 프로세스 정의/인스턴스 화면
- **WHEN** 사용자가 `/definitions/*`, `/instancelist`, `/instancelist/running`로 이동한다
- **THEN** 각 화면이 표시된다

#### Scenario: 작업 관리 화면
- **WHEN** 사용자가 `/todolist`, `/calendar`, `/kanban`으로 이동한다
- **THEN** 각 작업 보기가 표시된다

#### Scenario: 채팅과 분석
- **WHEN** 사용자가 `/chats`, `/chat`, `/analytics/*`로 이동한다
- **THEN** 각 화면이 표시된다

#### Scenario: 콘텐츠 에디터
- **WHEN** 사용자가 `/markdown-editor`, `/slide-editor`, `/present`로 이동한다
- **THEN** 마크다운 편집, 슬라이드 편집, 발표 모드가 각각 표시된다

#### Scenario: 알 수 없는 라우트
- **WHEN** 사용자가 정의되지 않은 경로로 이동한다
- **THEN** 시스템은 404 화면을 표시한다

### Requirement: 멀티테넌트 영역
The system SHALL provide a tenant area under `/tenant` for tenant-specific configuration.

#### Scenario: 테넌트 영역 접근
- **WHEN** 권한 있는 사용자가 `/tenant`로 이동한다
- **THEN** 테넌트 관리 화면이 표시된다

### Requirement: 백엔드 호출 라우팅
The system SHALL route XHR/fetch calls to backend services through documented host/path prefixes, configurable for development via the Vite proxy.

#### Scenario: 개발 프록시 동작
- **GIVEN** 개발 환경에서 Vite dev 서버가 실행 중이다
- **WHEN** UI가 `/query`, `/retrieve`, `/memento/`, `/complete`, `/vision-complete`, `/langchain-chat`, `/process-db-schema`, `/process-search`, `/agent/*`, `/agent-router/*`, `/process-gpt-deepagents/*` 같은 경로로 호출한다
- **THEN** 호출은 각각 Memento(8005), Completion(8000), Work Assistant(8008), Agent Router(8001), DeepAgents(8888) 같은 로컬 백엔드로 프록시된다

### Requirement: 환경 변수 계약
The system SHALL accept build- and runtime-time configuration via `VITE_SUPABASE_URL`, `VITE_SUPABASE_KEY`, `VITE_KEYCLOAK_URL`, `VITE_KEYCLOAK_REALM`, `VITE_KEYCLOAK_CLIENT_ID`.

#### Scenario: Supabase 자격 증명 누락
- **GIVEN** Supabase 변수가 설정되지 않았다
- **WHEN** 앱이 인증을 시도한다
- **THEN** 시스템은 인증 실패로 응답한다
