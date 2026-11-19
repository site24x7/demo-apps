"""Conversational banking assistant router with SSE streaming."""

from __future__ import annotations

import logging

from fastapi import APIRouter, Depends
from fastapi.responses import StreamingResponse

from app.auth import AuthenticatedUser, get_current_user
from app.models.schemas import (
    ChatRequest,
    ChatResponse,
    ConversationMessagesResponse,
)
from app.services.chat_service import ChatService

logger = logging.getLogger("chat_router")
router = APIRouter(prefix="/api/v1/chat", tags=["Chat"])


@router.post(
    "",
    response_model=ChatResponse,
    summary="Send message to AI assistant with tool-calling and deterministic fallback",
)
async def chat_endpoint(
    request: ChatRequest,
    current_user: AuthenticatedUser = Depends(get_current_user),
) -> ChatResponse:
    chat_svc = ChatService()
    return await chat_svc.chat(request, current_user)


@router.post(
    "/stream",
    summary="Server-Sent Events (SSE) streaming chat endpoint",
)
async def chat_stream_endpoint(
    request: ChatRequest,
    current_user: AuthenticatedUser = Depends(get_current_user),
) -> StreamingResponse:
    chat_svc = ChatService()
    return StreamingResponse(
        chat_svc.stream_chat(request, current_user),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
        },
    )


@router.get(
    "/conversations/{conversation_id}/messages",
    response_model=ConversationMessagesResponse,
    summary="Fetch chat message history for a conversation",
)
async def get_messages(
    conversation_id: str,
    _current_user: AuthenticatedUser = Depends(get_current_user),
) -> ConversationMessagesResponse:
    chat_svc = ChatService()
    return await chat_svc.get_conversation_messages(conversation_id)
