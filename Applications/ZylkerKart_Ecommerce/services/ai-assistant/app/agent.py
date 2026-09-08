"""Shopping assistant agent: provider-agnostic tool loop via LiteLLM adapters."""

from __future__ import annotations

import json
import logging
import os
from typing import Any

from traceloop.sdk.decorators import workflow

from app.llm import LLMError, get_provider
from app.tools import TOOL_DEFINITIONS, build_cards, execute_tool

logger = logging.getLogger(__name__)

MAX_TOOL_ROUNDS = int(os.environ.get("AI_MAX_TOOL_ROUNDS", "4"))

SYSTEM_PROMPT = """You are ZylkerKart's shopping assistant.
- Answer helpfully and concisely about products, cart, orders, and trends.
- ALWAYS use tools for live catalog, cart, order, or trending data. Never invent prices, stock, or order status.
- When listing products, mention title, price, and productId.
- Cart and orders tools automatically use the current shopper session. Never ask for or invent user ids or session ids.
- If the user is not logged in and asks about orders, say they need to sign in.
- Keep replies under 180 words unless the user asks for detail.
"""


@workflow(name="shopping_assistant")
def run_shopping_assistant(
    message: str,
    session_id: str = "",
    user_id: str | int | None = None,
    page_context: str | None = None,
) -> dict[str, Any]:
    context = {"session_id": session_id or "", "user_id": user_id}
    user_blob = message
    if page_context:
        user_blob += f"\n\n[Page context: {page_context}]"
    if session_id:
        user_blob += f"\n[session_id={session_id}]"
    if user_id:
        user_blob += f"\n[user_id={user_id}]"
    else:
        user_blob += "\n[user not logged in]"

    messages: list[dict[str, Any]] = [
        {"role": "system", "content": SYSTEM_PROMPT},
        {"role": "user", "content": user_blob},
    ]

    try:
        provider = get_provider()
    except LLMError as e:
        return {
            "reply": f"Sorry, the AI provider is not configured ({e}).",
            "cards": [],
            "tools_used": [],
            "model": None,
            "provider": None,
        }

    tools_used: list[str] = []
    cards: list[dict[str, Any]] = []
    reply = ""

    for _ in range(MAX_TOOL_ROUNDS):
        try:
            result = provider.complete(
                messages,
                tools=TOOL_DEFINITIONS,
                temperature=0.3,
                tool_choice="auto",
            )
        except LLMError as e:
            logger.exception("LLM chat failed provider=%s", provider.name)
            return {
                "reply": f"Sorry, the AI model is unavailable right now ({e}).",
                "cards": cards,
                "tools_used": tools_used,
                "model": provider.model,
                "provider": provider.name,
            }

        if not result.tool_calls:
            reply = (result.content or "").strip()
            break

        messages.append(
            {
                "role": "assistant",
                "content": result.content or "",
                "tool_calls": [
                    {
                        "id": tc.id,
                        "type": "function",
                        "function": {
                            "name": tc.name,
                            "arguments": tc.arguments or "{}",
                        },
                    }
                    for tc in result.tool_calls
                ],
            }
        )

        for tc in result.tool_calls:
            try:
                args = json.loads(tc.arguments or "{}")
            except json.JSONDecodeError:
                args = {}
            tools_used.append(tc.name)
            tool_result = execute_tool(tc.name, args, context)
            cards.extend(build_cards(tc.name, tool_result))
            messages.append(
                {
                    "role": "tool",
                    "tool_call_id": tc.id,
                    "content": json.dumps(tool_result, default=str)[:12000],
                }
            )
    else:
        try:
            result = provider.complete(
                messages
                + [
                    {
                        "role": "user",
                        "content": "Please give a final helpful answer based on the tool results.",
                    }
                ],
                tools=None,
                temperature=0.3,
                tool_choice=None,
            )
            reply = (result.content or "").strip()
        except LLMError:
            reply = "I gathered some data but could not finish the answer. Please try again."

    if not reply:
        reply = "I looked that up — see the results below." if cards else "I could not find an answer."

    seen: set[str] = set()
    unique_cards: list[dict[str, Any]] = []
    for c in cards:
        key = f"{c.get('type')}:{c.get('productId') or c.get('orderId') or c.get('query') or c.get('url')}"
        if key in seen:
            continue
        seen.add(key)
        unique_cards.append(c)

    return {
        "reply": reply,
        "cards": unique_cards[:12],
        "tools_used": tools_used,
        "model": provider.model,
        "provider": provider.name,
    }
