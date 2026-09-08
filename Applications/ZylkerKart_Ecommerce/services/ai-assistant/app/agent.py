"""Shopping assistant agent: Ollama (OpenAI-compatible) + tools."""

from __future__ import annotations

import json
import logging
import os
from typing import Any

from openai import OpenAI
from traceloop.sdk.decorators import workflow

from app.tools import TOOL_DEFINITIONS, build_cards, execute_tool

logger = logging.getLogger(__name__)

OLLAMA_BASE = os.environ.get("OLLAMA_BASE_URL", "http://host.docker.internal:11434").rstrip("/")
OLLAMA_MODEL = os.environ.get("OLLAMA_MODEL", "gemma4:latest")
MAX_TOOL_ROUNDS = int(os.environ.get("AI_MAX_TOOL_ROUNDS", "4"))

SYSTEM_PROMPT = """You are ZylkerKart's shopping assistant.
- Answer helpfully and concisely about products, cart, orders, and trends.
- ALWAYS use tools for live catalog, cart, order, or trending data. Never invent prices, stock, or order status.
- When listing products, mention title, price, and productId.
- If the user is not logged in and asks about orders, say they need to sign in.
- For cart questions, use the provided session_id via get_cart.
- Keep replies under 180 words unless the user asks for detail.
"""


def _client() -> OpenAI:
    return OpenAI(base_url=f"{OLLAMA_BASE}/v1", api_key="ollama")


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

    client = _client()
    tools_used: list[str] = []
    cards: list[dict[str, Any]] = []
    reply = ""

    for _ in range(MAX_TOOL_ROUNDS):
        try:
            completion = client.chat.completions.create(
                model=OLLAMA_MODEL,
                messages=messages,
                tools=TOOL_DEFINITIONS,
                tool_choice="auto",
                temperature=0.3,
            )
        except Exception as e:
            logger.exception("Ollama chat failed")
            return {
                "reply": f"Sorry, the local AI model is unavailable right now ({e}).",
                "cards": cards,
                "tools_used": tools_used,
            }

        choice = completion.choices[0]
        assistant_msg = choice.message
        tool_calls = assistant_msg.tool_calls or []

        if not tool_calls:
            reply = (assistant_msg.content or "").strip()
            break

        messages.append(
            {
                "role": "assistant",
                "content": assistant_msg.content or "",
                "tool_calls": [
                    {
                        "id": tc.id,
                        "type": "function",
                        "function": {
                            "name": tc.function.name,
                            "arguments": tc.function.arguments or "{}",
                        },
                    }
                    for tc in tool_calls
                ],
            }
        )

        for tc in tool_calls:
            name = tc.function.name
            try:
                args = json.loads(tc.function.arguments or "{}")
            except json.JSONDecodeError:
                args = {}
            tools_used.append(name)
            result = execute_tool(name, args, context)
            cards.extend(build_cards(name, result))
            messages.append(
                {
                    "role": "tool",
                    "tool_call_id": tc.id,
                    "content": json.dumps(result, default=str)[:12000],
                }
            )
    else:
        # Exhausted tool rounds — ask model for a final answer without tools
        try:
            completion = client.chat.completions.create(
                model=OLLAMA_MODEL,
                messages=messages
                + [
                    {
                        "role": "user",
                        "content": "Please give a final helpful answer based on the tool results.",
                    }
                ],
                temperature=0.3,
            )
            reply = (completion.choices[0].message.content or "").strip()
        except Exception:
            reply = "I gathered some data but could not finish the answer. Please try again."

    if not reply:
        reply = "I looked that up — see the results below." if cards else "I could not find an answer."

    # Dedupe cards by type+id
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
        "model": OLLAMA_MODEL,
    }