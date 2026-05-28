---
name: polling-mcp-processor-quirks
description: completion polling worker 의 mcp_processor.sanitize_mcp_tools 가 dict-with-properties 도구를 silently 드롭하며, 전역 MCPProcessor 가 동시 호출 시 dict 변경 race 를 일으킴. E2E 에서 sitecustomize.py 패치 + 워크아이템 직렬화 reservation 으로 우회.
applies-to:
  - completion-polling
  - mcp_processor
  - langchain-mcp-adapters
  - service-task
last-verified: 2026-05-27
metadata:
  type: pitfall
---

# completion polling MCP processor: silent tool drop + concurrency race

`services/completion/polling_service/mcp_processor.py` 의 `sanitize_mcp_tools(tools)`
는 다음과 같은 분기 구조이며 dict-with-properties 도구가 silently 사라지는 버그가 있음:

```python
for tool in tools:
    if isinstance(tool.args_schema, dict):
        if not has_properties and not has_required:
            # patch (response_format 손실 버그도 함께 발생)
            sanitized.append(patched_tool); continue
        # ← ELSE branch 없음: dict-with-properties 도구는 sanitized 에 추가되지 않음
    else:
        sanitized.append(tool)
```

`langchain-mcp-adapters` 0.1.0 은 MCP 도구를 `StructuredTool(args_schema=tool.inputSchema)`
형태로 만들어 args_schema 가 항상 dict 임. 정상적인 MCP 도구(`properties` 필드가 채워진
JSON schema 를 advertise) 는 sanitize 후 빈 리스트가 되고, `create_react_agent(llm, [])`
가 tool 호출 없이 즉시 final answer 를 생성하므로 ToolMessage 가 만들어지지 않음. 그 결과
`handle_service_workitem` 의 `extract_tool_results_from_agent_messages` 가 빈 dict 를
돌려주고 워크아이템은 `log="모든 MCP 도구 실행 완료: "` 로 DONE 처리되어 보임 (실제로는
도구가 한 번도 실행되지 않음).

또한 모듈 하단의 `mcp_processor = MCPProcessor()` 가 전역 singleton 이라 동시
SUBMITTED 워크아이템 2건이 asyncio.gather 로 병렬 처리되면 `self.mcp_configs` /
`self.mcp_tools` 에서 `dictionary changed size during iteration` 가 발생.

## What works

1. **sitecustomize.py 로 sanitize 패치 (E2E 한정)**:

   ```python
   # PYTHONPATH 에 /mocks 추가, /mocks/sitecustomize.py 가 자동 로드됨
   import mcp_processor
   _original = mcp_processor.sanitize_mcp_tools
   def patched(tools):
       sanitized = []
       for tool in tools:
           s = getattr(tool, 'args_schema', None)
           if isinstance(s, dict) and (s.get('properties') or s.get('required')):
               sanitized.append(tool)  # 원본 보존 (response_format='content_and_artifact')
               continue
           sanitized.extend(_original([tool]))
       return sanitized
   mcp_processor.sanitize_mcp_tools = patched
   ```

   compose env: `PYTHONPATH: "/mocks:/usr/src/app"`.

2. **워크아이템 reservation 으로 동시 처리 회피**:
   두 번째 워크아이템을 `consumer='hold-test-02'` 로 시드 → `fetch_workitem_with_submitted_status`
   는 `consumer is null` 만 가져오므로 직렬화 됨. 첫 시나리오 완료 후 SQL 로 `consumer=null`
   해제 → 다음 폴링 사이클에 픽업.

3. **mock MCP 서버 inputSchema 에 dummy property 1개라도 넣기**:
   비어 있는 schema 면 sanitize 의 patch 경로로 진입해 `response_format='content_and_artifact'`
   가 손실되고 ToolMessage.content 가 list-shaped string 으로 들어와 다른 버그 발생.

## Why

- `sanitize_mcp_tools` 의 if/else 가 누락 — production 코드 버그
- `MCPProcessor` 가 global singleton — concurrent 사용 가정 없음
- StructuredTool.from_function 의 기본 `response_format='content'` 가 원본의
  `'content_and_artifact'` 와 달라 (str, artifact) 튜플을 통째로 stringify

## How to apply

- Triggered when:
  - completion polling worker 가 도구를 호출했다고 로그를 남기는데 ToolMessage 가 비어 있을 때
  - `dictionary changed size during iteration` 또는 `MultiServerMCPClient' object has no attribute 'close'` 가 동시 처리에서 발생할 때
- Skip if:
  - production 측에서 위 두 버그가 수정된 이후

Related: [[coverage-py-usr2-flush]], [[mem0-vecs-table-reinit]]
