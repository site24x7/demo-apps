"""ZylkerKart AI shopping assistant — FastAPI entrypoint."""

from __future__ import annotations

import logging
from typing import Any

from fastapi import FastAPI
from pydantic import BaseModel, Field

from app.instrumentation import init_tracing

# Initialize Site24x7 / Traceloop BEFORE importing OpenAI-backed agent
init_tracing()

from app.agent import run_shopping_assistant  # noqa: E402

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")
logger = logging.getLogger("ai-assistant")

app = FastAPI(title="ZylkerKart AI Assistant", version="1.0.0")


class ChatRequest(BaseModel):
    message: str = Field(..., min_length=1, max_length=4000)
    session_id: str | None = None
    user_id: str | int | None = None
    page_context: str | None = None


class ChatResponse(BaseModel):
    reply: str
    cards: list[dict[str, Any]] = []
    tools_used: list[str] = []
    model: str | None = None


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok", "service": "ai-assistant"}


@app.post("/chat", response_model=ChatResponse)
def chat(req: ChatRequest) -> ChatResponse:
    logger.info(
        "chat message_len=%s session=%s user=%s",
        len(req.message),
        bool(req.session_id),
        req.user_id,
    )
    result = run_shopping_assistant(
        message=req.message,
        session_id=req.session_id or "",
        user_id=req.user_id,
        page_context=req.page_context,
    )
    return ChatResponse(**result)