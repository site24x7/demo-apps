"""Tests for conversational chat assistant, fallback responder, and streaming."""

import pytest
from httpx import AsyncClient

from app.auth import create_access_token


@pytest.mark.asyncio
async def test_chat_unauthorized(client: AsyncClient):
    resp = await client.post("/api/v1/chat", json={"message": "What is my balance?"})
    assert resp.status_code == 401


@pytest.mark.asyncio
async def test_chat_balance_fallback(client: AsyncClient, alice_token: str):
    headers = {"Authorization": f"Bearer {alice_token}"}
    resp = await client.post(
        "/api/v1/chat",
        json={"message": "Can you check my account balance?"},
        headers=headers,
    )
    assert resp.status_code == 200
    data = resp.json()
    assert "conversation_id" in data
    assert "reply" in data
    assert len(data["tool_calls"]) > 0
    assert data["tool_calls"][0]["name"] == "get_account_balance"
    assert data["model"] == "deterministic-fallback"


@pytest.mark.asyncio
async def test_chat_fee_fallback(client: AsyncClient, alice_token: str):
    headers = {"Authorization": f"Bearer {alice_token}"}
    resp = await client.post(
        "/api/v1/chat",
        json={"message": "What is the fee to withdraw 500 dollars from my card?"},
        headers=headers,
    )
    assert resp.status_code == 200
    data = resp.json()
    assert "fee" in data["reply"].lower()
    tool_names = [tc["name"] for tc in data["tool_calls"]]
    assert "calculate_transfer_fee" in tool_names


@pytest.mark.asyncio
async def test_chat_greeting_fallback(client: AsyncClient, alice_token: str):
    headers = {"Authorization": f"Bearer {alice_token}"}
    resp = await client.post(
        "/api/v1/chat",
        json={"message": "Hello there!"},
        headers=headers,
    )
    assert resp.status_code == 200
    data = resp.json()
    assert "ZylkerBank" in data["reply"]


@pytest.mark.asyncio
async def test_chat_stream_endpoint(client: AsyncClient, alice_token: str):
    headers = {"Authorization": f"Bearer {alice_token}"}
    resp = await client.post(
        "/api/v1/chat/stream",
        json={"message": "Hi assistant"},
        headers=headers,
    )
    assert resp.status_code == 200
    assert "text/event-stream" in resp.headers.get("content-type", "")
    content = resp.text
    assert "event: token" in content
    assert "event: done" in content


@pytest.mark.asyncio
async def test_get_conversation_messages(client: AsyncClient, alice_token: str):
    headers = {"Authorization": f"Bearer {alice_token}"}
    # First send a message to establish conversation
    post_resp = await client.post(
        "/api/v1/chat",
        json={"message": "Hello ZylkerBank"},
        headers=headers,
    )
    conv_id = post_resp.json()["conversation_id"]

    # Now get conversation messages
    get_resp = await client.get(
        f"/api/v1/chat/conversations/{conv_id}/messages",
        headers=headers,
    )
    assert get_resp.status_code == 200
    msgs = get_resp.json()["messages"]
    assert len(msgs) >= 2
    roles = [m["role"] for m in msgs]
    assert "user" in roles
    assert "assistant" in roles
