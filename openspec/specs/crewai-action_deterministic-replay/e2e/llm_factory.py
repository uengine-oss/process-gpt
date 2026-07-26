"""llm_factory shim for DeterministicCodeTool.

The deployed crewai-action image provides a `llm_factory.create_llm` module
on its PYTHONPATH (see services/crewai-action `llm.py`, which is the same
factory "without the external llm_factory dependency"). The tool under test
(`processgpt_agent_utils.tools.deterministic_code_tool`) imports
`from llm_factory import create_llm`, so this file reproduces that factory
1:1 for the E2E run — a plain ChatOpenAI constructor, no mocking.
"""
from __future__ import annotations

import os
from typing import Optional, Tuple, Union

TimeoutType = Union[float, Tuple[float, float]]


def create_llm(
    model: Optional[str] = None,
    streaming: bool = False,
    temperature: float = 0.0,
    timeout: Optional[TimeoutType] = (10.0, 120.0),
    max_retries: int = 6,
):
    from langchain_openai import ChatOpenAI

    base_url = os.getenv("LLM_PROXY_URL", "https://api.openai.com/v1")
    api_key = os.getenv("LLM_PROXY_API_KEY") or os.getenv("OPENAI_API_KEY", "")
    resolved_model = (
        model
        or (os.getenv("LLM_MODEL") or os.getenv("OPENAI_MODEL") or "").strip()
        or "gpt-4o"
    )
    _ = streaming
    return ChatOpenAI(
        base_url=base_url,
        api_key=api_key,
        model=resolved_model,
        temperature=temperature,
        streaming=False,
        disable_streaming=True,
        timeout=timeout,
        max_retries=max_retries,
    )
