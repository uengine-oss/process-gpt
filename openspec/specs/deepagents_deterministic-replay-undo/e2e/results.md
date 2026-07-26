# 실행 결과

- 구현: `services/deepagents/core/deterministic/replay.py`
- 실행기 연결: `services/deepagents/executor.py`
- 테스트: `services/deepagents/tests/test_deterministic_replay.py`
- 명령: `uv run pytest -q tests/test_deterministic_replay.py`
- 결과: **3 passed**
- 확인 계약:
  - 한국어 새 입력의 업무 파라미터 추출
  - 비활성 MCP 서버 제외
  - LLM 없는 Python 서브프로세스 실행 및 `{ok, results}` 반환

## 실제 UI 데모

- 실측 실행: `run_live_demo.py`
  - DeepAgents replay 결과: Galaxy 재고 `35 → 250`
  - DeepAgents undo/redo 결과: iPhone 이전 변경 undo 후 최종 재고 `60`
  - 실제 UI용 이벤트: LLM 실행·Replay·Undo 총 10건
- 녹화: `record_live_ui.py`
  - 실제 `http://localhost:5199` 로그인 화면
  - 실제 업무 목록의 `DeepAgents 재고 반영` 3건
  - 실제 워크아이템 `에이전트에 맡기기` 탭의 LLM 도구 이력
  - 실제 `DeepAgents 결정론적 코드 실행 결과` 카드
  - 실제 `DeepAgents Undo 후 재실행 결과` 카드
- 최종 영상:
  `demo-recordings/deepagents-deterministic-live-demo.mp4`
- 목업/설명 HTML은 최종 영상에 포함하지 않음
