# 시나리오 8 — Undo(실행 취소): 고착화 2편 (별도 데모)

시나리오 7(실행 경로 고착화)에 이어지는 **별도 데모**. LLM 에이전트 실행이
DB에 남긴 부수효과를, 이벤트 로그로부터 자동 생성된 역연산(undo) 코드로
되돌리고(원복 + 감사 로그 삭제 + 다른 실행 결과 보존), 정정된 값으로 고착화
경로를 재실행(redo)한다.

- 스펙: `openspec/specs/crewai-action_deterministic-undo/spec.md` (별도 스펙)
- 구현: undo 코드 생성 = `services/completion/compensation_handler.py`
  (`generate_deterministic_compensation_code`, `mcp_python_code.compensation` 보존),
  실행 = 결정론적 실행 경로(재작업 시 undo 우선 → 순방향 재실행)
- 완성 영상: `docs/demo/deterministic-undo-demo.mp4` (~2분 10초, TTS 내레이션 + 자막)

## 전제 — 시나리오 7이 먼저

undo는 1차 실행의 이벤트 로그와 순방향 고착화 코드가 있어야 성립한다:
```bash
cd openspec/specs/crewai-action_deterministic-replay/e2e
<detdemo-venv>/bin/python run_e2e.py     # 21/21 — 1차 실행 + 고착화 + 재실행
cd ../../crewai-action_deterministic-undo/e2e
<detdemo-venv>/bin/python run_e2e.py     # 19/19 — undo 코드 생성/실행/redo/표시
<detdemo-venv>/bin/python record_demo.py # 9/9  — demo.html 렌더 검증
```
영상 재생성은 `demo-recordings/deterministic-undo-demo/`의
`record_undo_demo.py` + `assemble_narrated_video.py` (scenario 7 문서의 4단계와 동일 패턴).

## 반드시 알아야 할 전제 — 가역적 연산

이벤트 로그에는 도구 **호출 인자만** 남는다(SELECT 결과 없음). 따라서
`SET stock = 80` 같은 절대값 대입은 로그만으로 역연산이 불가능하다.
시나리오 7의 1차 실행 에이전트는 그래서 **상대 연산**(`stock = stock + N`)을
지시받는다. 데모를 변형할 때 이 형태를 유지할 것.

## 시연 포인트

1. undo 코드는 completion의 배포 로직이 이벤트 로그에서 생성한 것 — 값 하드코딩 없음.
2. undo 실행은 LLM 0회 — 로그를 파싱해 UPDATE는 반대 연산, INSERT는 DELETE로.
3. 정밀함: 같은 테이블의 다른 실행(Galaxy) 결과는 건드리지 않는다.
4. 워크아이템 화면의 "다시 수행하기" 버튼이 프로덕션 재작업(undo→redo) 진입점.
5. 비즈니스 메시지: "실행할 용기는 되돌릴 수 있음에서" — AI 자동화의 안전망.

## 알려진 함정 (업스트림 이슈 — e2e에 워크어라운드 문서화됨)

- undo 프롬프트의 SQL 예시가 MySQL식 큰따옴표 → PostgreSQL에서 조용히 실패.
  e2e는 query 컨텍스트에 "PostgreSQL — 작은따옴표" 힌트를 추가해 해결.
- `DeterministicCodeTool._run`의 재작업 분기는 문자열에 `.get()`을 호출하는
  타입 오류로 배포 코드에서 동작 불가 — e2e는 `_execute_code`를 직접 사용.
- undo 코드 입력 계약은 `{"event_logs": [...]}`인데 executor는 워크아이템
  파라미터를 넘김 — e2e는 올바른 계약으로 실행.
자세한 내용: `openspec/specs/crewai-action_deterministic-undo/e2e/results.md`
