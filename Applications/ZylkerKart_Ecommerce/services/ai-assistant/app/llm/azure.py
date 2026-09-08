"""Azure OpenAI provider via LiteLLM."""

from __future__ import annotations

from typing import Any

from app.llm._litellm import env, litellm_complete
from app.llm.base import ChatResult, LLMError


class AzureProvider:
    def __init__(self) -> None:
        self._model = env("LLM_MODEL", "AZURE_OPENAI_DEPLOYMENT", default="")
        self._api_key = env("LLM_API_KEY", "AZURE_API_KEY", "AZURE_OPENAI_API_KEY")
        self._api_base = env("LLM_BASE_URL", "AZURE_API_BASE", "AZURE_OPENAI_ENDPOINT")
        self._api_version = env("LLM_API_VERSION", "AZURE_API_VERSION", default="2024-08-01-preview")
        if not self._model:
            raise LLMError("LLM_MODEL (Azure deployment name) is required for azure provider")
        if not self._api_key:
            raise LLMError("AZURE_API_KEY or LLM_API_KEY is required for azure provider")
        if not self._api_base:
            raise LLMError("AZURE_API_BASE / LLM_BASE_URL is required for azure provider")

    @property
    def name(self) -> str:
        return "azure"

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
        model_id = self._model if self._model.startswith("azure/") else f"azure/{self._model}"
        return litellm_complete(
            model=model_id,
            messages=messages,
            tools=tools,
            temperature=temperature,
            tool_choice=tool_choice,
            api_base=self._api_base,
            api_key=self._api_key,
            api_version=self._api_version,
        )
