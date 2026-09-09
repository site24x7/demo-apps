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
_cached_failed: str | None = None


def available_providers() -> list[str]:
    return sorted(_PROVIDERS.keys())


def clear_provider_cache() -> None:
    global _cached, _cached_failed
    _cached = None
    _cached_failed = None


def get_provider(name: str | None = None, *, force_reload: bool = False) -> LLMProvider:
    """Return the configured provider.

    Failed constructions are not cached permanently — the next request retries so
    late-starting Ollama (or other backends) can recover without a container restart.
    """
    global _cached, _cached_failed
    if force_reload:
        clear_provider_cache()

    if _cached is not None and name is None:
        return _cached

    key = (name or os.environ.get("LLM_PROVIDER") or "ollama").strip().lower()
    factory = _PROVIDERS.get(key)
    if factory is None:
        raise LLMError(
            f"Unknown LLM_PROVIDER={key!r}. Supported: {', '.join(available_providers())}"
        )

    try:
        provider = factory()
    except Exception as e:
        _cached_failed = str(e)
        logger.warning("LLM provider init failed name=%s err=%s — will retry next request", key, e)
        raise LLMError(f"Failed to initialize LLM provider {key!r}: {e}") from e

    logger.info("LLM provider ready name=%s model=%s", provider.name, provider.model)
    if name is None:
        _cached = provider
        _cached_failed = None
    return provider
