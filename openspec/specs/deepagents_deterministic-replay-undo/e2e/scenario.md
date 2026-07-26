# E2E 시나리오

1. DeepAgents 워크아이템과 동일 키의 `mcp_python_code`를 준비한다.
2. 한국어 워크아이템에서 상품명·증가량·최종 재고·사유를 추출한다.
3. 활성 MCP 서버만 `MCP_CONFIG`로 전달한다.
4. 저장된 Python 코드를 별도 프로세스로 실행하고 `{ok, results}`를 검증한다.
5. 재작업에서는 이전 쓰기 이벤트가 undo 입력이 되고 undo→forward 순서를 검증한다.
6. 실행기는 DeepAgents 그래프 진입 전에 결정론적 결과 카드를 반환한다.

