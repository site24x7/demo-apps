"""Shared LiteLLM completion helper used by all provider adapters."""

from __future__ import annotations

import logging
import os
from typing import Any

from app.llm.base import ChatResult, LLMError, ToolCall

logger = logging.getLogger(__name__)


def litellm_complete(
    *,
    model: str,
    messages: list[dict[str, Any]],
    tools: list[dict[str, Any]] | None = None,
    temperature: float = 0.3,
    tool_choice: str | None = "auto",
    api_base: str | None = None,
    api_key: str | None = None,
    api_version: str | None = None,
    extra: dict[str, Any] | None = None,
) -> ChatResult:
    try:
        import litellm
    except ImportError as e:
        raise LLMError("litellm is not installed") from e

    # Avoid noisy success logs in demos; keep failures via our logger
    litellm.suppress_debug_info = True

    kwargs: dict[str, Any] = {
        "model": model,
        "messages": messages,
        "temperature": temperature,
    }
    if tools:
        kwargs["tools"] = tools
        if tool_choice is not None:
            kwargs["tool_choice"] = tool_choice
    if api_base:
        kwargs["api_base"] = api_base
    if api_key is not None:
        kwargs["api_key"] = api_key
    if api_version:
        kwargs["api_version"] = api_version
    if extra:
        kwargs.update(extra)

    try:
        response = litellm.completion(**kwargs)
    except Exception as e:
        logger.exception("LiteLLM completion failed model=%s", model)
        raise LLMError(str(e)) from e

    choice = response.choices[0]
    message = choice.message
    content = getattr(message, "content", None) or None
    tool_calls: list[ToolCall] = []
    raw_calls = getattr(message, "tool_calls", None) or []
    for tc in raw_calls:
        fn = getattr(tc, "function", None)
        tool_calls.append(
            ToolCall(
                id=getattr(tc, "id", "") or "",
                name=getattr(fn, "name", "") if fn else "",
                arguments=(getattr(fn, "arguments", None) or "{}") if fn else "{}",
            )
        )

    raw_model = getattr(response, "model", None) or model
    return ChatResult(content=content, tool_calls=tool_calls, raw_model=raw_model)


def env(*names: str, default: str = "") -> str:
    for name in names:
        val = os.environ.get(name)
        if val is not None and str(val).strip():
            return str(val).strip()
    return default
