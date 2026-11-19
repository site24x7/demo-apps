"""External & local tools for the conversational banking assistant."""

from __future__ import annotations

import logging
from decimal import Decimal
from typing import Any

import httpx

from app.auth import AuthenticatedUser
from app.config import Settings, get_settings
from app.logging_config import correlation_id_var, traceparent_var, tracestate_var

logger = logging.getLogger("chat_tools")

# OpenAI/LiteLLM tool definitions
CHAT_TOOLS_SCHEMA: list[dict[str, Any]] = [
    {
        "type": "function",
        "function": {
            "name": "get_account_balance",
            "description": "Fetch current account balance, status, currency, and tier for a ZylkerBank account.",
            "parameters": {
                "type": "object",
                "properties": {
                    "account_number": {
                        "type": "string",
                        "description": "The 10-digit account number (e.g. '2170000001'). If omitted, defaults to the authenticated user's account.",
                    }
                },
                "required": [],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "get_recent_transactions",
            "description": "Fetch recent ledger transactions and statement items for a ZylkerBank account.",
            "parameters": {
                "type": "object",
                "properties": {
                    "account_number": {
                        "type": "string",
                        "description": "The 10-digit account number. If omitted, defaults to the authenticated user's account.",
                    },
                    "limit": {
                        "type": "integer",
                        "description": "Maximum number of transactions to return (default 5, max 20).",
                        "default": 5,
                    },
                },
                "required": [],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "get_virtual_cards",
            "description": "List all virtual debit cards provisioned for the current authenticated user, including masked card numbers, spending limits, balances, and frozen status.",
            "parameters": {
                "type": "object",
                "properties": {},
                "required": [],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "calculate_transfer_fee",
            "description": "Calculate the fee for a transaction (P2P transfer, card funding, or card withdrawal).",
            "parameters": {
                "type": "object",
                "properties": {
                    "transaction_type": {
                        "type": "string",
                        "description": "The type of transaction: 'P2P_TRANSFER', 'CARD_FUNDING', or 'CARD_WITHDRAWAL'",
                        "enum": ["P2P_TRANSFER", "CARD_FUNDING", "CARD_WITHDRAWAL"],
                    },
                    "amount": {
                        "type": "number",
                        "description": "The amount to transfer or withdraw in USD.",
                    },
                },
                "required": ["transaction_type", "amount"],
            },
        },
    },
]


def _build_outbound_headers(user: AuthenticatedUser | None) -> dict[str, str]:
    headers: dict[str, str] = {
        "Accept": "application/json",
    }
    if user and user.raw_token:
        headers["Authorization"] = f"Bearer {user.raw_token}"

    tp = traceparent_var.get()
    if tp:
        headers["traceparent"] = tp
    ts = tracestate_var.get()
    if ts:
        headers["tracestate"] = ts
    cid = correlation_id_var.get()
    if cid:
        headers["X-Correlation-Id"] = cid

    try:
        from opentelemetry.trace.propagation.tracecontext import TraceContextTextMapPropagator

        TraceContextTextMapPropagator().inject(headers)
    except Exception:
        pass

    return headers


class ChatToolExecutor:
    def __init__(self, settings: Settings | None = None) -> None:
        self.settings = settings or get_settings()

    async def get_account_balance(
        self,
        user: AuthenticatedUser | None,
        account_number: str | None = None,
    ) -> dict[str, Any]:
        acc_num = (account_number or "").strip()
        if not acc_num and user:
            acc_num = user.account_number.strip()
        if not acc_num:
            return {"error": "ACCOUNT_REQUIRED", "message": "No account number specified"}

        url = f"{self.settings.ledger_url}/api/v1/accounts/{acc_num}"
        headers = _build_outbound_headers(user)
        try:
            async with httpx.AsyncClient(timeout=self.settings.http_timeout) as client:
                resp = await client.get(url, headers=headers)
                if resp.status_code == 200:
                    data = resp.json()
                    return {
                        "account_number": data.get("account_number", acc_num),
                        "owner_name": data.get("owner_name", user.name if user else ""),
                        "balance": str(data.get("balance", "0.00")),
                        "currency": data.get("currency", "USD"),
                        "account_status": data.get("account_status", "ACTIVE"),
                        "tier_level": data.get("tier_level", 1),
                        "daily_limit": str(data.get("daily_limit", "1000.00")),
                    }
                return {
                    "error": "LEDGER_ERROR",
                    "status_code": resp.status_code,
                    "message": f"Ledger service responded with {resp.status_code}: {resp.text}",
                }
        except Exception as exc:
            logger.warning("Failed to reach Ledger service at %s: %s", url, exc)
            return {
                "error": "LEDGER_UNREACHABLE",
                "message": f"Unable to reach ledger service at {self.settings.ledger_url}: {exc}",
                "account_number": acc_num,
            }

    async def get_recent_transactions(
        self,
        user: AuthenticatedUser | None,
        account_number: str | None = None,
        limit: int = 5,
    ) -> dict[str, Any]:
        acc_num = (account_number or "").strip()
        if not acc_num and user:
            acc_num = user.account_number.strip()
        if not acc_num:
            return {"error": "ACCOUNT_REQUIRED", "message": "No account number specified"}

        safe_limit = max(1, min(limit or 5, 20))
        url = f"{self.settings.ledger_url}/api/v1/ledger/statements/{acc_num}?page=1&page_size={safe_limit}"
        headers = _build_outbound_headers(user)
        try:
            async with httpx.AsyncClient(timeout=self.settings.http_timeout) as client:
                resp = await client.get(url, headers=headers)
                if resp.status_code == 200:
                    data = resp.json()
                    return {
                        "account_number": acc_num,
                        "total": data.get("total", 0),
                        "items": data.get("items", []),
                    }
                return {
                    "error": "LEDGER_ERROR",
                    "status_code": resp.status_code,
                    "message": f"Ledger service responded with {resp.status_code}: {resp.text}",
                }
        except Exception as exc:
            logger.warning("Failed to reach Ledger statements at %s: %s", url, exc)
            return {
                "error": "LEDGER_UNREACHABLE",
                "message": f"Unable to reach ledger service at {self.settings.ledger_url}: {exc}",
                "account_number": acc_num,
                "items": [],
            }

    async def get_virtual_cards(self, user: AuthenticatedUser | None) -> dict[str, Any]:
        url = f"{self.settings.gateway_url}/api/v1/cards"
        headers = _build_outbound_headers(user)
        try:
            async with httpx.AsyncClient(timeout=self.settings.http_timeout) as client:
                resp = await client.get(url, headers=headers)
                if resp.status_code == 200:
                    data = resp.json()
                    cards = data.get("cards", []) if isinstance(data, dict) else data
                    return {"cards": cards, "total": len(cards)}
                return {
                    "error": "GATEWAY_ERROR",
                    "status_code": resp.status_code,
                    "message": f"Financial gateway responded with {resp.status_code}: {resp.text}",
                }
        except Exception as exc:
            logger.warning("Failed to reach Financial Gateway at %s: %s", url, exc)
            return {
                "error": "GATEWAY_UNREACHABLE",
                "message": f"Unable to reach financial gateway at {self.settings.gateway_url}: {exc}",
                "cards": [],
            }

    def calculate_transfer_fee(
        self,
        transaction_type: str,
        amount: float | int | Decimal | str,
    ) -> dict[str, Any]:
        # Normalize transaction type
        tt = str(transaction_type or "").upper().strip()
        if "WITHDRAW" in tt:
            canonical_type = "CARD_WITHDRAWAL"
        elif "FUND" in tt or "DEPOSIT" in tt:
            canonical_type = "CARD_FUNDING"
        else:
            canonical_type = "P2P_TRANSFER"

        try:
            amt = float(amount)
        except (ValueError, TypeError):
            amt = 0.0

        if canonical_type == "CARD_WITHDRAWAL":
            # 0.5% capped at $5.00
            fee = round(min(5.00, amt * 0.005), 2)
            rule_desc = "Card withdrawal fee is 0.5% of amount, capped at $5.00"
        elif canonical_type == "CARD_FUNDING":
            fee = 0.00
            rule_desc = "Card funding is free of charge ($0.00)"
        else:
            fee = 0.00
            rule_desc = "Peer-to-peer bank transfers are free of charge ($0.00)"

        return {
            "transaction_type": canonical_type,
            "amount": f"{amt:.2f}",
            "fee": f"{fee:.2f}",
            "total_deduction": f"{(amt + fee):.2f}",
            "currency": "USD",
            "rule": rule_desc,
        }

    async def execute_tool(
        self,
        tool_name: str,
        arguments: dict[str, Any],
        user: AuthenticatedUser | None,
    ) -> Any:
        logger.info("Executing chat tool %s with args %s", tool_name, arguments)
        if tool_name == "get_account_balance":
            return await self.get_account_balance(
                user=user,
                account_number=arguments.get("account_number"),
            )
        elif tool_name == "get_recent_transactions":
            return await self.get_recent_transactions(
                user=user,
                account_number=arguments.get("account_number"),
                limit=arguments.get("limit", 5),
            )
        elif tool_name == "get_virtual_cards":
            return await self.get_virtual_cards(user=user)
        elif tool_name == "calculate_transfer_fee":
            return self.calculate_transfer_fee(
                transaction_type=arguments.get("transaction_type", "P2P_TRANSFER"),
                amount=arguments.get("amount", 0.0),
            )
        else:
            return {"error": "UNKNOWN_TOOL", "message": f"Tool '{tool_name}' is not recognized"}
