"""Redis-backed short conversation history for multi-turn chat."""

from __future__ import annotations

import json
import logging
import os
from typing import Any

logger = logging.getLogger(__name__)

MAX_TURNS = int(os.environ.get("AI_HISTORY_TURNS", "8"))
TTL_SEC = int(os.environ.get("AI_HISTORY_TTL_SEC", "3600"))

_redis = None
_redis_tried = False


def _client():
    global _redis, _redis_tried
    if _redis_tried:
        return _redis
    _redis_tried = True
    host = os.environ.get("REDIS_HOST", "").strip()
    if not host:
        return None
    try:
        import redis

        port = int(os.environ.get("REDIS_PORT", "6379"))
        _redis = redis.Redis(host=host, port=port, db=0, decode_responses=True, socket_timeout=2)
        _redis.ping()
        logger.info("Conversation history Redis connected host=%s port=%s", host, port)
    except Exception as e:
        logger.warning("Conversation history Redis unavailable: %s", e)
        _redis = None
    return _redis


def _key(session_id: str) -> str:
    return f"zk:ai:history:{session_id}"


def load_history(session_id: str) -> list[dict[str, Any]]:
    if not session_id:
        return []
    r = _client()
    if r is None:
        return []
    try:
        raw = r.get(_key(session_id))
        if not raw:
            return []
        data = json.loads(raw)
        return data if isinstance(data, list) else []
    except Exception:
        logger.exception("Failed to load chat history")
        return []


def append_turn(session_id: str, user_message: str, assistant_reply: str) -> None:
    if not session_id or not user_message:
        return
    r = _client()
    if r is None:
        return
    try:
        history = load_history(session_id)
        history.append({"role": "user", "content": user_message})
        history.append({"role": "assistant", "content": assistant_reply or ""})
        # Keep last N *turns* (user+assistant pairs)
        max_msgs = max(2, MAX_TURNS * 2)
        history = history[-max_msgs:]
        r.setex(_key(session_id), TTL_SEC, json.dumps(history))
    except Exception:
        logger.exception("Failed to save chat history")
