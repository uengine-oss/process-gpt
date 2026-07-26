# E2E 결과 — 결정론적 Undo(실행 취소) — 2026-07-23

## 요약
- `run_e2e.py`: **19/19 PASS** (실 Supabase + 실 MCP 서버 + completion 배포 코드, mock 없음)
- `record_demo.py`(Playwright): **9/9 PASS** (demo.html 실측 렌더 검증)
- 데모 영상(별도 2편): `docs/demo/deterministic-undo-demo.mp4`
  (= `demo-recordings/deterministic-undo-demo-narrated.mp4`, 130.5s, 1280x720,
  OpenAI TTS 내레이션(marin) + 자막, 실제 UI 1장면 — 재작업 워크아이템의
  Undo 실행 카드 — 포함, `assemble_narrated_video.py` 검증 PASS)

## 검증 흐름 (실측)
| 단계 | 내용 | 결과 |
|---|---|---|
| undo 코드 생성 | 1차 실행 이벤트 로그 3건 → 역연산 Python (completion 로직, LLM 1회 ~10s) | 생성·`mcp_python_code.compensation` 보존 |
| undo 실행 | 이벤트 로그 입력, 서브프로세스, **LLM 0회**, 1.8s | iPhone 80→**20 원복**, 감사 로그 **삭제** |
| 정밀성 | 같은 테이블의 다른 실행 결과 | Galaxy=250·로그 **보존** |
| redo | 재작업 지시(정정 입고 40) → 순방향 고착화 코드 | iPhone=**60** + 재작업 로그 |
| 표시 | `Undo(실행 취소) 후 재실행 결과` 카드(crew_type result) | 워크아이템 화면에 표시, 도구 추론 이벤트 0건 |

## 핵심 발견 — undo 가능성은 "가역적 연산 형태"에 달려 있다
이벤트 로그에는 도구 **호출 인자만** 남고 SELECT **결과는 남지 않는다**. 따라서
`SET stock = 80` 같은 절대값 대입은 로그만으로 이전 값을 알 수 없어 역연산이
불가능하다(초기 시도에서 실제로 실패 — 생성된 undo 코드가 SELECT *쿼리 문자열*에서
이전 값을 찾으려다 실패). 1차 실행 에이전트에게 **상대 연산**(`stock = stock + N`)을
지시하자 undo가 결정론적으로 성립했다. 운영 가이드: 에이전트의 쓰기 작업은
로그만으로 역연산 가능한(가역적) 형태를 권장.

## 업스트림 이슈 (이번 검증에서 추가 발견, 워크어라운드 적용·문서화)
1. **undo 프롬프트의 SQL 예시가 MySQL식 큰따옴표 문자열** —
   `compensation_handler.generate_deterministic_compensation_code`의 프롬프트 예시
   (`WHERE product_name = "노트북"`)를 따라 생성된 역연산 SQL이 PostgreSQL에서
   식별자로 해석돼 조용히 실패(0행 매칭). e2e는 워크아이템 query 컨텍스트에
   "PostgreSQL — 작은따옴표" 힌트를 덧붙여 해결. 프롬프트 예시를 표준 SQL
   작은따옴표로 고치는 업스트림 수정 권장.
2. **재작업 실행 분기의 타입 오류** — `DeterministicCodeTool._run`의
   `use_compensation` 분기가 `_execute_code`의 **문자열** 반환값에 `.get()`을 호출
   (`compensation_result.get("results", [])`) → 항상 예외. 미수정 시 재작업 경로는
   배포 코드에서 동작 불가.
3. **undo 코드 입력 계약 불일치** — completion이 생성하는 undo 코드는
   `{"event_logs": [...]}` 입력을 기대하지만, `_execute_code`는 워크아이템에서
   추출한 파라미터를 전달. e2e는 올바른 계약(이벤트 로그)으로 직접 실행했다.
4. (재확인) 생성 결과의 ```python 코드펜스가 검증(`"async def run(" in code`)을
   통과하므로 실행 전 펜스 제거 필요.

replay 쪽 업스트림 이슈 목록은 `crewai-action_deterministic-replay/e2e/results.md` 참조.
