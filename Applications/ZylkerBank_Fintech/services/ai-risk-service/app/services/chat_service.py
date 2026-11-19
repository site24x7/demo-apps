"""Conversational banking assistant using LiteLLM with tool-calling and deterministic fallback."""

from __future__ import annotations

import asyncio
import json
import logging
import re
import uuid
from datetime import datetime, timezone
from typing import Any, AsyncIterator

import litellm

from app.auth import AuthenticatedUser
from app.config import Settings, get_settings
from app.db import Database, DatabaseUnavailable, get_db
from app.models.schemas import (
    ChatMessageItem,
    ChatRequest,
    ChatResponse,
    ConversationMessagesResponse,
    ToolCallSummary,
    UsageInfo,
)
from app.services.chat_tools import CHAT_TOOLS_SCHEMA, ChatToolExecutor

logger = logging.getLogger("chat_service")

SYSTEM_PROMPT = """You are the ZylkerBank AI Financial Assistant, an intelligent, secure, and professional copilot for banking customers.
You have access to tools to:
1. get_account_balance: Check the user's account balance and status.
2. get_recent_transactions: View statements and recent transaction history.
3. get_virtual_cards: List user's virtual cards and balances.
4. calculate_transfer_fee: Calculate fees for transfers, funding, and card withdrawals.

Always be polite, concise, and helpful. Always provide accurate monetary figures when returned by the tools.
"""

# In-memory store fallback when PostgreSQL is offline
_in_memory_conversations: dict[str, dict[str, Any]] = {}
_in_memory_messages: dict[str, list[dict[str, Any]]] = {}


def clear_in_memory_chat_state() -> None:
    _in_memory_conversations.clear()
    _in_memory_messages.clear()


class ChatService:
    def __init__(
        self,
        db: Database | None = None,
        settings: Settings | None = None,
        tool_executor: ChatToolExecutor | None = None,
    ) -> None:
        self.settings = settings or get_settings()
        self.db = db or get_db(self.settings)
        self.tools = tool_executor or ChatToolExecutor(self.settings)

    async def _get_or_create_conversation(
        self,
        conversation_id: str | None,
        session_id: str | None,
        user: AuthenticatedUser | None,
    ) -> str:
        conv_id = conversation_id
        if conv_id:
            try:
                # Validate UUID format
                uuid.UUID(conv_id)
            except ValueError:
                conv_id = None

        if conv_id is None:
            conv_id = str(uuid.uuid4())

        s_id = session_id or conv_id
        u_id = user.user_id if user else None
        acc_no = user.account_number if user else None

        # Check DB or insert
        try:
            row = await self.db.fetchrow(
                "SELECT id FROM ai_conversations WHERE id = $1", uuid.UUID(conv_id)
            )
            if not row:
                await self.db.execute(
                    """
                    INSERT INTO ai_conversations (id, session_id, user_id, account_number, created_at)
                    VALUES ($1, $2, $3, $4, NOW())
                    ON CONFLICT (id) DO NOTHING
                    """,
                    uuid.UUID(conv_id),
                    s_id,
                    u_id,
                    acc_no,
                )
        except (DatabaseUnavailable, Exception) as exc:
            logger.debug("Database conversation lookup/insert failed: %s, using in-memory store", exc)
            if conv_id not in _in_memory_conversations:
                _in_memory_conversations[conv_id] = {
                    "id": conv_id,
                    "session_id": s_id,
                    "user_id": u_id,
                    "account_number": acc_no,
                    "created_at": datetime.now(timezone.utc),
                }

        return conv_id

    async def _load_history(self, conv_id: str) -> list[dict[str, Any]]:
        history: list[dict[str, Any]] = []
        try:
            rows = await self.db.fetch(
                """
                SELECT role, content, created_at
                FROM ai_messages
                WHERE conversation_id = $1
                ORDER BY id ASC
                LIMIT $2
                """,
                uuid.UUID(conv_id),
                self.settings.chat_history_limit,
            )
            for r in rows:
                history.append({"role": r["role"], "content": r["content"]})
            return history
        except (DatabaseUnavailable, Exception) as exc:
            logger.debug("Database load history failed: %s, using in-memory messages", exc)
            mem_msgs = _in_memory_messages.get(conv_id, [])
            return [
                {"role": m["role"], "content": m["content"]}
                for m in mem_msgs[-self.settings.chat_history_limit :]
            ]

    async def _save_message(
        self,
        conv_id: str,
        role: str,
        content: str,
        token_count: int = 0,
    ) -> None:
        now = datetime.now(timezone.utc)
        # Always store in memory for reliability
        if conv_id not in _in_memory_messages:
            _in_memory_messages[conv_id] = []
        _in_memory_messages[conv_id].append(
            {
                "conversation_id": conv_id,
                "role": role,
                "content": content,
                "token_count": token_count,
                "created_at": now,
            }
        )

        try:
            await self.db.execute(
                """
                INSERT INTO ai_messages (conversation_id, role, content, token_count, created_at)
                VALUES ($1, $2, $3, $4, $5)
                """,
                uuid.UUID(conv_id),
                role,
                content,
                token_count,
                now,
            )
        except (DatabaseUnavailable, Exception) as exc:
            logger.debug("Database save message failed: %s", exc)

    async def get_conversation_messages(
        self,
        conv_id: str,
    ) -> ConversationMessagesResponse:
        messages: list[ChatMessageItem] = []
        try:
            rows = await self.db.fetch(
                """
                SELECT role, content, created_at
                FROM ai_messages
                WHERE conversation_id = $1
                ORDER BY id ASC
                """,
                uuid.UUID(conv_id),
            )
            for r in rows:
                messages.append(
                    ChatMessageItem(
                        role=r["role"],
                        content=r["content"],
                        created_at=r["created_at"],
                    )
                )
            return ConversationMessagesResponse(messages=messages)
        except (DatabaseUnavailable, Exception) as exc:
            logger.debug("Database get_conversation_messages failed: %s, using in-memory", exc)
            mem_msgs = _in_memory_messages.get(conv_id, [])
            for m in mem_msgs:
                messages.append(
                    ChatMessageItem(
                        role=m["role"],
                        content=m["content"],
                        created_at=m["created_at"],
                    )
                )
            return ConversationMessagesResponse(messages=messages)

    async def _execute_deterministic_fallback(
        self,
        user_message: str,
        user: AuthenticatedUser | None,
    ) -> tuple[str, list[ToolCallSummary]]:
        text = user_message.lower()
        tool_summaries: list[ToolCallSummary] = []
        user_account = user.account_number if user else ""

        # 1. Balance intent
        if any(w in text for w in ("balance", "funds", "how much money", "savings", "checking", "account balance")):
            args = {"account_number": user_account}
            res = await self.tools.execute_tool("get_account_balance", args, user)
            tool_summaries.append(
                ToolCallSummary(
                    name="get_account_balance",
                    arguments=args,
                    result_summary=res,
                )
            )
            if "balance" in res:
                reply = (
                    f"Your account balance for {res.get('account_number', user_account)} is "
                    f"${res.get('balance')} {res.get('currency', 'USD')}. "
                    f"Account status: {res.get('account_status', 'ACTIVE')} (Tier {res.get('tier_level', 1)})."
                )
            else:
                reply = (
                    f"I attempted to check your balance, but the ledger service reported: "
                    f"{res.get('message', 'service unreachable')}. Please try again shortly."
                )
            return reply, tool_summaries

        # 2. Transaction intent
        if any(w in text for w in ("transaction", "transactions", "statement", "statements", "history", "transfers", "activity", "recent")):
            args = {"account_number": user_account, "limit": 5}
            res = await self.tools.execute_tool("get_recent_transactions", args, user)
            tool_summaries.append(
                ToolCallSummary(
                    name="get_recent_transactions",
                    arguments=args,
                    result_summary=res,
                )
            )
            items = res.get("items", [])
            if items:
                lines = [f"Here are your recent transactions for account {user_account}:"]
                for it in items[:5]:
                    ref = it.get("transaction_ref", "N/A")
                    amt = it.get("amount", "0.00")
                    tt = it.get("transaction_type", "TRANSFER")
                    entry = it.get("entry_type", "")
                    sign = "+" if entry == "CREDIT" else "-"
                    lines.append(f"• {tt}: {sign}${amt} ({ref})")
                reply = "\n".join(lines)
            elif "error" in res:
                reply = f"Could not retrieve transaction statements: {res.get('message')}."
            else:
                reply = f"No recent transactions found for account {user_account}."
            return reply, tool_summaries

        # 3. Fee calculation intent (evaluated before card listing so queries like 'fee to withdraw from card' match fee)
        if any(w in text for w in ("fee", "fees", "cost", "charge", "rate", "how much does it cost")):
            # Extract amount
            amount_match = re.search(r"\$?(\d+(?:\.\d{1,2})?)", text)
            amount = float(amount_match.group(1)) if amount_match else 100.0
            tx_type = "P2P_TRANSFER"
            if "withdraw" in text:
                tx_type = "CARD_WITHDRAWAL"
            elif "fund" in text or "deposit" in text:
                tx_type = "CARD_FUNDING"

            args = {"transaction_type": tx_type, "amount": amount}
            res = self.tools.calculate_transfer_fee(tx_type, amount)
            tool_summaries.append(
                ToolCallSummary(
                    name="calculate_transfer_fee",
                    arguments=args,
                    result_summary=res,
                )
            )
            reply = (
                f"Transfer Fee Calculation:\n"
                f"• Transaction Type: {res['transaction_type']}\n"
                f"• Amount: ${res['amount']}\n"
                f"• Fee: ${res['fee']} USD\n"
                f"• Total Deduction: ${res['total_deduction']} USD\n"
                f"Policy: {res['rule']}"
            )
            return reply, tool_summaries

        # 4. Virtual cards intent
        if any(w in text for w in ("card", "cards", "virtual", "debit card", "visa", "mastercard")):
            args: dict[str, Any] = {}
            res = await self.tools.execute_tool("get_virtual_cards", args, user)
            tool_summaries.append(
                ToolCallSummary(
                    name="get_virtual_cards",
                    arguments=args,
                    result_summary=res,
                )
            )
            cards = res.get("cards", [])
            if cards:
                lines = [f"You have {len(cards)} active virtual card(s):"]
                for c in cards:
                    masked = c.get("card_number_masked", "****")
                    ctype = c.get("card_type", "VISA")
                    bal = c.get("balance", "0.00")
                    lim = c.get("spending_limit", "1000.00")
                    status = "Frozen" if c.get("is_frozen") else "Active"
                    lines.append(f"• {ctype} {masked} | Balance: ${bal} | Daily Limit: ${lim} | Status: {status}")
                reply = "\n".join(lines)
            elif "error" in res:
                reply = f"Could not retrieve virtual cards: {res.get('message')}."
            else:
                reply = "You currently have no virtual cards provisioned."
            return reply, tool_summaries

        # 5. Default greeting & assistance menu
        reply = (
            "Hello! I am your ZylkerBank AI Banking Assistant. I can assist you with:\n"
            "• Checking your account balance and tier\n"
            "• Reviewing recent transactions and statements\n"
            "• Managing and viewing your virtual debit cards\n"
            "• Calculating transfer and card withdrawal fees\n\n"
            "How can I assist you today?"
        )
        return reply, tool_summaries

    async def chat(
        self,
        request: ChatRequest,
        user: AuthenticatedUser | None,
    ) -> ChatResponse:
        conv_id = await self._get_or_create_conversation(
            request.conversation_id, request.session_id, user
        )

        history = await self._load_history(conv_id)
        # Record user message
        await self._save_message(conv_id, "user", request.message)

        # Prepare messages for LiteLLM
        messages: list[dict[str, Any]] = [{"role": "system", "content": SYSTEM_PROMPT}]
        messages.extend(history)
        messages.append({"role": "user", "content": request.message})

        tool_summaries: list[ToolCallSummary] = []
        total_prompt_tokens = 0
        total_completion_tokens = 0
        model_name = self.settings.llm_model
        final_reply: str | None = None

        # Attempt LiteLLM acompletion with tool loop
        try:
            for _ in range(self.settings.llm_max_iterations):
                kwargs: dict[str, Any] = {
                    "model": self.settings.llm_model,
                    "messages": messages,
                    "tools": CHAT_TOOLS_SCHEMA,
                    "tool_choice": "auto",
                    "temperature": self.settings.llm_temperature,
                    "timeout": self.settings.llm_timeout,
                }
                if self.settings.llm_api_base:
                    kwargs["api_base"] = self.settings.llm_api_base
                if self.settings.llm_api_key:
                    kwargs["api_key"] = self.settings.llm_api_key

                response = await litellm.acompletion(**kwargs)
                choice = response.choices[0]
                msg = choice.message

                usage = getattr(response, "usage", None)
                if usage:
                    total_prompt_tokens += getattr(usage, "prompt_tokens", 0)
                    total_completion_tokens += getattr(usage, "completion_tokens", 0)

                # Check if tool calls were returned
                tool_calls = getattr(msg, "tool_calls", None)
                if tool_calls:
                    # Append assistant message with tool calls
                    messages.append(
                        {
                            "role": "assistant",
                            "content": msg.content or "",
                            "tool_calls": [
                                {
                                    "id": tc.id,
                                    "type": "function",
                                    "function": {
                                        "name": tc.function.name,
                                        "arguments": tc.function.arguments,
                                    },
                                }
                                for tc in tool_calls
                            ],
                        }
                    )
                    for tc in tool_calls:
                        fn_name = tc.function.name
                        try:
                            fn_args = json.loads(tc.function.arguments or "{}")
                        except Exception:
                            fn_args = {}

                        tool_res = await self.tools.execute_tool(fn_name, fn_args, user)
                        tool_summaries.append(
                            ToolCallSummary(
                                name=fn_name,
                                arguments=fn_args,
                                result_summary=tool_res,
                            )
                        )
                        messages.append(
                            {
                                "role": "tool",
                                "tool_call_id": tc.id,
                                "name": fn_name,
                                "content": json.dumps(tool_res),
                            }
                        )
                    continue

                # No tool calls; final assistant response
                final_reply = msg.content or ""
                break

        except Exception as exc:
            logger.warning("LiteLLM completion failed (%s). Checking fallback...", exc)
            if not self.settings.llm_fallback_enabled:
                raise

            model_name = "deterministic-fallback"
            final_reply, fallback_tools = await self._execute_deterministic_fallback(
                request.message, user
            )
            tool_summaries.extend(fallback_tools)

        if final_reply is None:
            final_reply = "I was unable to formulate a response. Please try again."

        # Save assistant reply to memory
        await self._save_message(
            conv_id, "assistant", final_reply, token_count=total_completion_tokens
        )

        return ChatResponse(
            conversation_id=conv_id,
            reply=final_reply,
            tool_calls=tool_summaries,
            model=model_name,
            usage=UsageInfo(
                prompt_tokens=total_prompt_tokens,
                completion_tokens=total_completion_tokens,
            ),
        )

    async def stream_chat(
        self,
        request: ChatRequest,
        user: AuthenticatedUser | None,
    ) -> AsyncIterator[str]:
        """Stream SSE chunks (event: tool, event: token, event: done)."""
        chat_resp = await self.chat(request, user)

        # 1. Emit tool calls if any
        for tc in chat_resp.tool_calls:
            payload = json.dumps({"name": tc.name, "arguments": tc.arguments})
            yield f"event: tool\ndata: {payload}\n\n"
            await asyncio.sleep(0.01)

        # 2. Emit reply tokens (chunked words or characters)
        words = chat_resp.reply.split(" ")
        for i, word in enumerate(words):
            token = word + (" " if i < len(words) - 1 else "")
            payload = json.dumps({"token": token})
            yield f"event: token\ndata: {payload}\n\n"
            await asyncio.sleep(0.01)

        # 3. Emit done event
        done_payload = json.dumps(
            {
                "conversation_id": chat_resp.conversation_id,
                "reply": chat_resp.reply,
                "tool_calls": [tc.model_dump() for tc in chat_resp.tool_calls],
                "model": chat_resp.model,
                "usage": chat_resp.usage.model_dump(),
            }
        )
        yield f"event: done\ndata: {done_payload}\n\n"
