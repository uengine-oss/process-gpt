"""E2E-only sitecustomize that fixes a sanitize_mcp_tools bug for
completion_automated-task-execution.

The polling worker's services/completion/polling_service/mcp_processor.py
defines sanitize_mcp_tools(tools) with an explicit `if/else` branch:

    if isinstance(tool.args_schema, dict):
        ...
        if not has_properties and not has_required:
            patched = StructuredTool.from_function(...)   # response_format=content
            sanitized.append(patched)
            continue
        # ELSE branch missing - tools with non-empty dict schema are silently dropped
    else:
        sanitized.append(tool)

That dropping path means the E2E mock MCP tool (which advertises a real
``properties``/``additionalProperties`` schema so the agent loop runs
with the original ``response_format='content_and_artifact'`` tool
instance) never reaches the LangGraph react agent, so no tool call is
made and handle_service_workitem records empty results.

This sitecustomize keeps the production behavior for the "empty schema"
patching path and ONLY adds the missing append for tools whose
args_schema is a dict with real properties/required — i.e., what
langchain-mcp-adapters 0.1.0 actually produces from a normal MCP tool.
It mounts via PYTHONPATH so Python imports it on startup, before main.py
runs.

This file is E2E-specific; production deployments do not see it.
"""
from __future__ import annotations

import sys


def _install() -> None:
    try:
        import mcp_processor  # type: ignore
    except Exception:
        return

    original = getattr(mcp_processor, "sanitize_mcp_tools", None)
    if not callable(original):
        return

    def patched(tools):
        sanitized = []
        for tool in tools:
            schema = getattr(tool, "args_schema", None)
            if isinstance(schema, dict):
                if schema.get("properties") or schema.get("required"):
                    # Production code drops these silently. Keep the original
                    # MCP-backed tool object (response_format='content_and_artifact').
                    sanitized.append(tool)
                    continue
            # Delegate to the original (handles empty-schema patching and
            # non-dict args_schema branches identically to production).
            sanitized.extend(original([tool]))
        return sanitized

    mcp_processor.sanitize_mcp_tools = patched
    sys.stderr.write("[e2e-sitecustomize] sanitize_mcp_tools patched for dict-with-properties\n")
    sys.stderr.flush()


_install()
