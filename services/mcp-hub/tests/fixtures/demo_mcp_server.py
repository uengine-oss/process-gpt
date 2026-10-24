#!/usr/bin/env python3
"""Demo and test MCP server (streamable-http).

Also serves as a worked example of the integration standard: snake_case verb_noun
tool names, a description on every field, annotation hints, and errorType classes.

Tool descriptions here are imported verbatim into the MCP hub catalogue, so they are
written in English: a Korean docstring would overwrite the hub's catalogue text the
next time someone hits "Refresh tools".
"""
import os

try:  # mcp 2.x
    from mcp.server.mcpserver import MCPServer as _Server
except ImportError:  # mcp 1.x
    from mcp.server.fastmcp import FastMCP as _Server

# Bind address is left open so the validator container can reach this server too.
mcp = _Server(
    "demo-inventory",
    host=os.getenv("HOST", "127.0.0.1"),
    port=int(os.getenv("PORT", "8790")),
)


@mcp.tool()
def check_stock(sku: str) -> dict:
    """Look up the current stock quantity for a SKU.

    Args:
        sku: Item code to look up (for example SKU-1001)
    """
    table = {"SKU-1001": 42, "SKU-1002": 0, "SKU-1003": 128}
    if sku not in table:
        raise ValueError(f"VALIDATION: Unknown item code: {sku}")
    return {"sku": sku, "quantity": table[sku], "location": "A-03"}


@mcp.tool()
def list_low_stock(threshold: int = 10) -> list:
    """Return every item at or below a stock threshold.

    Args:
        threshold: Only items at or below this quantity are returned
    """
    table = {"SKU-1001": 42, "SKU-1002": 0, "SKU-1003": 128}
    return [{"sku": k, "quantity": v} for k, v in table.items() if v <= threshold]


@mcp.tool()
def create_stock_adjustment(sku: str, delta: int, reason: str) -> dict:
    """Adjust stock on hand. This is a write and cannot be undone.

    Args:
        sku: Item code to adjust
        delta: Quantity change (negative subtracts)
        reason: Why the adjustment was made
    """
    return {"sku": sku, "delta": delta, "reason": reason, "applied": True}


if __name__ == "__main__":
    mcp.run(transport="streamable-http")
