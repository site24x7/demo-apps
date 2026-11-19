"""Pydantic v2 schemas for requests and responses."""

from __future__ import annotations

from datetime import datetime
from decimal import Decimal
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field


class ErrorResponse(BaseModel):
    error: str
    message: str


# ── Risk Models ─────────────────────────────────────────────────────────────
class RiskEvaluationRequest(BaseModel):
    model_config = ConfigDict(extra="ignore")

    from_account: str = Field(..., min_length=1, max_length=20, description="Source account number")
    to_account: str = Field(..., min_length=1, max_length=20, description="Destination account number")
    amount: Decimal = Field(..., gt=0, description="Transfer amount in USD")
    timestamp: datetime | None = Field(default=None, description="Optional ISO8601 evaluation timestamp")
    correlation_id: str | None = Field(default=None, description="Correlation ID for tracing")


class RiskReason(BaseModel):
    rule: str
    points: int
    detail: str


class RiskEvaluationResponse(BaseModel):
    risk_score: int = Field(..., ge=0, le=100, description="Additive risk score (0-100)")
    decision: Literal["APPROVED", "FLAGGED_FOR_REVIEW", "BLOCKED"]
    reasons: list[RiskReason] = Field(default_factory=list)
    evaluated_at: datetime


# ── Chat Models ─────────────────────────────────────────────────────────────
class ChatRequest(BaseModel):
    model_config = ConfigDict(extra="ignore")

    message: str = Field(..., min_length=1, max_length=4000, description="User's query/prompt")
    conversation_id: str | None = Field(default=None, description="Existing conversation UUID")
    session_id: str | None = Field(default=None, description="Client session ID")


class ToolCallSummary(BaseModel):
    name: str
    arguments: dict[str, Any] = Field(default_factory=dict)
    result_summary: Any = None


class UsageInfo(BaseModel):
    prompt_tokens: int = 0
    completion_tokens: int = 0


class ChatResponse(BaseModel):
    conversation_id: str
    reply: str
    tool_calls: list[ToolCallSummary] = Field(default_factory=list)
    model: str
    usage: UsageInfo = Field(default_factory=UsageInfo)


class ChatMessageItem(BaseModel):
    role: str
    content: str
    created_at: datetime


class ConversationMessagesResponse(BaseModel):
    messages: list[ChatMessageItem] = Field(default_factory=list)


# ── Audit Models ────────────────────────────────────────────────────────────
class AuditEventItem(BaseModel):
    id: int
    event_id: str | None = None
    event_type: str
    topic: str | None = None
    payload: dict[str, Any] = Field(default_factory=dict)
    correlation_id: str | None = None
    created_at: datetime


class AuditLogsResponse(BaseModel):
    total: int
    items: list[AuditEventItem] = Field(default_factory=list)


# ── Health Models ───────────────────────────────────────────────────────────
class HealthResponse(BaseModel):
    status: Literal["UP", "DEGRADED"]
    service: str = "ai-risk-service"
    database: dict[str, Any] = Field(default_factory=dict)
    kafka: dict[str, Any] = Field(default_factory=dict)
    llm: dict[str, Any] = Field(default_factory=dict)
