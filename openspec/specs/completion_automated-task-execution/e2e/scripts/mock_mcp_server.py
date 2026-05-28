"""Deterministic stdio-based MCP server used by polling worker E2E.

The langchain-mcp-adapters MultiServerMCPClient spawns this script as a
subprocess (transport='stdio') and discovers its tools via the MCP
protocol. Two tools are exposed:

  * success_tool  -> always returns a status=success payload
  * failure_tool  -> always returns a status=error payload

handle_service_workitem in services/completion/polling_service classifies
tool results by the embedded ``status`` field; this lets the E2E suite
drive both the "all tools succeeded" and "all tools failed" log branches
deterministically without exercising any external MCP server.

The script depends only on the `mcp` package (already a transitive dep
of langchain-mcp-adapters>=0.1.0).
"""
from __future__ import annotations

import asyncio
import json
import os
import sys

from mcp.server import Server
from mcp.server.stdio import stdio_server
from mcp.types import TextContent, Tool


SUCCESS_PAYLOAD = {
    "status": "success",
    "connection_type": "stdio",
    "data": {
        "executed_by": "mock-mcp",
        "note": "deterministic E2E stub success",
    },
}

FAILURE_PAYLOAD = {
    "status": "error",
    "connection_type": "stdio",
    "error": "simulated tool failure",
}


def _build_server() -> Server:
    server: Server = Server("mock-mcp")
    mode = os.environ.get("MCP_MODE", "success").lower()

    @server.list_tools()
    async def _list_tools() -> list[Tool]:  # type: ignore[override]
        tools: list[Tool] = []
        if mode in ("success", "both"):
            tools.append(
                Tool(
                    name="success_tool",
                    description="Deterministic success tool for completion_automated-task-execution E2E.",
                    inputSchema={
                        "type": "object",
                        "properties": {"reason": {"type": "string", "description": "Optional"}},
                        "additionalProperties": True,
                    },
                )
            )
        if mode in ("failure", "both"):
            tools.append(
                Tool(
                    name="failure_tool",
                    description="Deterministic failure tool for completion_automated-task-execution E2E.",
                    inputSchema={
                        "type": "object",
                        "properties": {"reason": {"type": "string", "description": "Optional"}},
                        "additionalProperties": True,
                    },
                )
            )
        return tools

    @server.call_tool()
    async def _call_tool(name: str, arguments: dict | None):  # type: ignore[override]
        if name == "success_tool":
            payload = SUCCESS_PAYLOAD
        elif name == "failure_tool":
            payload = FAILURE_PAYLOAD
        else:
            payload = {"status": "error", "connection_type": "stdio", "error": f"unknown tool {name}"}
        return [TextContent(type="text", text=json.dumps(payload, ensure_ascii=False))]

    return server


async def _amain() -> None:
    server = _build_server()
    async with stdio_server() as (read_stream, write_stream):
        await server.run(read_stream, write_stream, server.create_initialization_options())


def main() -> None:
    # mcp's stdio_server uses anyio internally; asyncio.run is the
    # documented entrypoint for FastMCP-style stdio servers.
    sys.stderr.write(f"[mock-mcp] starting (pid={os.getpid()})\n")
    sys.stderr.flush()
    asyncio.run(_amain())


if __name__ == "__main__":
    main()
