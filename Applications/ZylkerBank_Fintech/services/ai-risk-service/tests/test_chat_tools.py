"""Tests for chat tools execution and fee calculations."""

import pytest
import httpx

from app.auth import AuthenticatedUser
from app.services.chat_tools import ChatToolExecutor, _build_outbound_headers


def test_calculate_transfer_fee_p2p():
    executor = ChatToolExecutor()
    res = executor.calculate_transfer_fee("P2P_TRANSFER", 500.0)
    assert res["transaction_type"] == "P2P_TRANSFER"
    assert res["fee"] == "0.00"
    assert res["total_deduction"] == "500.00"


def test_calculate_transfer_fee_card_funding():
    executor = ChatToolExecutor()
    res = executor.calculate_transfer_fee("CARD_FUNDING", 250.0)
    assert res["transaction_type"] == "CARD_FUNDING"
    assert res["fee"] == "0.00"
    assert res["total_deduction"] == "250.00"


def test_calculate_transfer_fee_card_withdrawal():
    executor = ChatToolExecutor()

    # Small amount: 0.5% of $100 = $0.50
    res1 = executor.calculate_transfer_fee("CARD_WITHDRAWAL", 100.0)
    assert res1["transaction_type"] == "CARD_WITHDRAWAL"
    assert res1["fee"] == "0.50"
    assert res1["total_deduction"] == "100.50"

    # Exact cap: 0.5% of $1000 = $5.00
    res2 = executor.calculate_transfer_fee("CARD_WITHDRAWAL", 1000.0)
    assert res2["fee"] == "5.00"
    assert res2["total_deduction"] == "1005.00"

    # Exceeding cap: 0.5% of $5000 = $25 -> capped at $5.00
    res3 = executor.calculate_transfer_fee("CARD_WITHDRAWAL", 5000.0)
    assert res3["fee"] == "5.00"
    assert res3["total_deduction"] == "5005.00"


def test_build_outbound_headers():
    user = AuthenticatedUser(
        user_id="1111",
        account_number="2170000001",
        raw_token="fake-jwt-token",
    )
    headers = _build_outbound_headers(user)
    assert headers["Authorization"] == "Bearer fake-jwt-token"
    assert headers["Accept"] == "application/json"


@pytest.mark.asyncio
async def test_get_account_balance_mock(monkeypatch):
    executor = ChatToolExecutor()
    user = AuthenticatedUser(
        user_id="1111",
        account_number="2170000001",
        name="Alice Johnson",
        raw_token="token",
    )

    class MockResponse:
        status_code = 200

        def json(self):
            return {
                "account_number": "2170000001",
                "owner_name": "Alice Johnson",
                "balance": "8500.00",
                "currency": "USD",
                "account_status": "ACTIVE",
                "tier_level": 2,
            }

    async def mock_get(self, url, headers=None):
        return MockResponse()

    monkeypatch.setattr(httpx.AsyncClient, "get", mock_get)

    res = await executor.get_account_balance(user)
    assert res["balance"] == "8500.00"
    assert res["account_status"] == "ACTIVE"
    assert res["tier_level"] == 2


@pytest.mark.asyncio
async def test_get_virtual_cards_mock(monkeypatch):
    executor = ChatToolExecutor()
    user = AuthenticatedUser(
        user_id="1111",
        account_number="2170000001",
        raw_token="token",
    )

    class MockResponse:
        status_code = 200

        def json(self):
            return {
                "cards": [
                    {
                        "card_id": "c1",
                        "card_number_masked": "4111 **** **** 1111",
                        "card_type": "VISA",
                        "balance": "250.00",
                        "is_frozen": False,
                    }
                ]
            }

    async def mock_get(self, url, headers=None):
        return MockResponse()

    monkeypatch.setattr(httpx.AsyncClient, "get", mock_get)

    res = await executor.get_virtual_cards(user)
    assert res["total"] == 1
    assert res["cards"][0]["card_type"] == "VISA"
