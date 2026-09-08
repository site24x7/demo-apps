"""Anthropic (Claude) provider via LiteLLM."""

from __future__ import annotations

from typing import Any

from app.llm._litellm import env, litellm_complete
from app.llm.base import ChatResult, LLMError


class AnthropicProvider:
    def __init__(self) -> None:
        self._model = env("LLM_MODEL", default="claude-sonnet-4-20250514")
        self._api_key = env("LLM_API_KEY", "ANTHROPIC_API_KEY")
        self._api_base = env("LLM_BASE_URL", "ANTHROPIC_BASE_URL") or None
        if not self._api_key:
            raise LLMError("ANTHROPIC_API_KEY or LLM_API_KEY is required for anthropic provider")

    @property
    def name(self) -> str:
        return "anthropic"

    @property
    def model(self) -> str:
        return self._model

    def complete(
        self,
        messages: list[dict[str, Any]],
        tools: list[dict[str, Any]] | None = None,
        *,
        temperature: float = 0.3,
        tool_choice: str | None = "auto",
    ) -> ChatResult:
        model_id = self._model if self._model.startswith("anthropic/") else f"anthropic/{self._model}"
        return litellm_complete(
            model=model_id,
            messages=messages,
            tools=tools,
            temperature=temperature,
            tool_choice=tool_choice,
            api_base=self._api_base,
            api_key=self._api_key,
        )
