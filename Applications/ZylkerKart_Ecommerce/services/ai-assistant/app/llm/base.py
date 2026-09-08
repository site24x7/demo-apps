"""Abstract LLM provider contract used by the shopping assistant."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Protocol


class LLMError(Exception):
    """Raised when a provider call fails."""


@dataclass
class ToolCall:
    id: str
    name: str
    arguments: str


@dataclass
class ChatResult:
    content: str | None = None
    tool_calls: list[ToolCall] = field(default_factory=list)
    raw_model: str | None = None


class LLMProvider(Protocol):
    @property
    def name(self) -> str:
        """Provider registry key, e.g. ollama, openai."""

    @property
    def model(self) -> str:
        """Configured model / deployment id."""

    def complete(
        self,
        messages: list[dict[str, Any]],
        tools: list[dict[str, Any]] | None = None,
        *,
        temperature: float = 0.3,
        tool_choice: str | None = "auto",
    ) -> ChatResult:
        """Run one chat completion turn (optionally with tools)."""
