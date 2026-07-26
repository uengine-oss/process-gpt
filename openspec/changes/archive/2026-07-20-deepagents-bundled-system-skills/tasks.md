## 1. 번들 스킬 디렉토리 및 로컬 시딩

- [x] 1.1 deepagents 저장소에 이미지 빌드 대상 번들 디렉토리
      `system-skills/process-gpt-system/`을 추가 — 스킬 루트(볼륨 마운트
      대상)와 경로를 분리해 배포 시 볼륨 마운트에 가려지지 않게 한다
- [x] 1.2 번들 디렉토리를 스킬 루트의 `process-gpt-system` 컬렉션으로
      동기화하는 로컬 시딩 함수 작성 — 네트워크 호출 없이 파일 복사만 사용,
      실패해도 예외를 삼켜 서비스 기동/채팅 실행을 막지 않음

## 2. 전역 컬렉션 인식 확장

- [x] 2.1 스킬 소스 스캔 로직에서 `process-gpt-system`을 `SKILL_REPO_URLS`
      설정 여부와 무관하게 항상 전역 컬렉션으로 인식하도록 확장
- [x] 2.2 기존 Git 기반 전역 컬렉션(`anthropics-skills`) 인식 경로는
      변경하지 않고 그대로 유지(순수 추가)

## 3. 기동/실행 경로 연결

- [x] 3.1 서버 기동 시점에 로컬 시딩을 1회 실행해 스킬 관리 API/화면에서
      재기동 직후에도 즉시 조회 가능하게 함
- [x] 3.2 매 채팅 실행(턴) 시작 시에도 로컬 시딩을 실행해 컨테이너 재시작
      없이도 번들 갱신이 반영되게 함

## 4. 첫 시스템 스킬 등재: bsc-strategy-interview

- [x] 4.1 균형성과표(BSC) Socratic 전략 인터뷰 스킬(`bsc-strategy-interview`)을
      번들 디렉토리에 등록
- [x] 4.2 스킬 내 질문 도구 안내를 실행 환경 무관 표현으로 정리(Claude Code
      `AskUserQuestion` / process-gpt 채팅 `request_human_input` 매핑) —
      런타임에 존재하지 않는 도구명을 지시문에 하드코딩하지 않음

## 5. 검증

- [x] 5.1 deepagents 서비스 재빌드·재기동 후 기동 로그에서 로컬 시딩 실행
      확인
- [x] 5.2 한 번도 스킬을 업로드한 적 없는 임의 테넌트로 스킬 목록 API를
      조회해 `bsc-strategy-interview`가 `process-gpt-system` 컬렉션으로
      자동 노출됨을 확인
- [x] 5.3 Playwright(headed)로 실제 채팅 UI에서 로그인 → 스킬 목록 화면 →
      해당 스킬이 별도 업로드 없이 표시됨을 확인
- [x] 5.4 Playwright로 실제 대화창(deepagents 오케스트레이션)에서 스킬이
      트리거되어 BSC 인터뷰가 진행됨을 확인
