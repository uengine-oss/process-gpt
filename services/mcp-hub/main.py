#!/usr/bin/env python3
"""MCP Hub 진입점."""
import uvicorn

from src.mcp_hub.config import PORT

if __name__ == "__main__":
    uvicorn.run("src.mcp_hub.api:app", host="0.0.0.0", port=PORT, log_level="info")
