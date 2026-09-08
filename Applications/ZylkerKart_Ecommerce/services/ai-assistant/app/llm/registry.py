"""Provider registry — select LLM backend from LLM_PROVIDER."""

from __future__ import annotations

import logging
import os
from typing import Callable

from app.llm.anthropic import AnthropicProvider
from app.llm.azure import AzureProvider
from app.llm.base import LLMError, LLMProvider
from app.llm.compatible import CompatibleProvider
from app.llm.groq import GroqProvider
from app.llm.ollama import OllamaProvider
from app.llm.openai_provider import OpenAIProvider

logger = logging.getLogger(__name__)

_PROVIDERS: dict[str, Callable[[], LLMProvider]] = {
    "ollama": OllamaProvider,
    "openai": OpenAIProvider,
    "anthropic": AnthropicProvider,
    "azure": AzureProvider,
    "groq": GroqProvider,
    "compatible": CompatibleProvider,
}

_cached: LLMProvider | None = None


def available_providers() -> list[str]:
    return sorted(_PROVIDERS.keys())


def get_provider(name: str | None = None, *, force_reload: bool = False) -> LLMProvider:
    global _cached
    if _cached is not None and not force_reload and name is None:
        return _cached

    key = (name or os.environ.get("LLM_PROVIDER") or "ollama").strip().lower()
    factory = _PROVIDERS.get(key)
    if factory is None:
        raise LLMError(
            f"Unknown LLM_PROVIDER={key!r}. Supported: {', '.join(available_providers())}"
        )
    provider = factory()
    logger.info("LLM provider ready name=%s model=%s", provider.name, provider.model)
    if name is None:
        _cached = provider
    return provider
