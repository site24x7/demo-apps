"""Generic OpenAI-compatible endpoint (vLLM, LM Studio, custom gateways) via LiteLLM."""

from __future__ import annotations

from typing import Any

from app.llm._litellm import env, litellm_complete
from app.llm.base import ChatResult, LLMError


class CompatibleProvider:
    def __init__(self) -> None:
        self._model = env("LLM_MODEL", default="gpt-4o-mini")
        self._api_base = env("LLM_BASE_URL")
        self._api_key = env("LLM_API_KEY", default="unused")
        if not self._api_base:
            raise LLMError("LLM_BASE_URL is required for compatible provider")

    @property
    def name(self) -> str:
        return "compatible"

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
        # openai/-prefix with custom api_base talks to any OpenAI-compatible server
        model_id = self._model if self._model.startswith("openai/") else f"openai/{self._model}"
        return litellm_complete(
            model=model_id,
            messages=messages,
            tools=tools,
            temperature=temperature,
            tool_choice=tool_choice,
            api_base=self._api_base,
            api_key=self._api_key,
        )
