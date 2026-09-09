"""Ollama (local) provider via LiteLLM.

Uses Ollama's OpenAI-compatible /v1 chat API for reliable tool calling.
"""

from __future__ import annotations

from typing import Any

from app.llm._litellm import env, litellm_complete
from app.llm.base import ChatResult


class OllamaProvider:
    def __init__(self) -> None:
        self._model = env("LLM_MODEL", "OLLAMA_MODEL", default="gemma4:latest")
        base = env(
            "LLM_BASE_URL",
            "OLLAMA_BASE_URL",
            default="http://host.docker.internal:11434",
        ).rstrip("/")
        # Prefer OpenAI-compatible chat endpoint for tool calls
        if not base.endswith("/v1"):
            base = f"{base}/v1"
        self._api_base = base
        self._api_key = env("LLM_API_KEY", default="ollama")

    @property
    def name(self) -> str:
        return "ollama"

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
        # Route through openai/ + Ollama /v1 for structured tool_calls
        bare = self._model
        for prefix in ("ollama/", "ollama_chat/", "openai/"):
            if bare.startswith(prefix):
                bare = bare[len(prefix) :]
                break
        model_id = f"openai/{bare}"
        return litellm_complete(
            model=model_id,
            messages=messages,
            tools=tools,
            temperature=temperature,
            tool_choice=tool_choice,
            api_base=self._api_base,
            api_key=self._api_key,
        )
