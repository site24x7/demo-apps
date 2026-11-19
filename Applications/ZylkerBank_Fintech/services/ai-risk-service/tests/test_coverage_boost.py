"""Additional comprehensive tests for LiteLLM loop, DB pool, instrumentation, logging, and edge cases."""

import asyncio
import json
import logging
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi import HTTPException
from httpx import AsyncClient

from app.auth import get_optional_user, verify_internal_token
from app.config import Settings, get_settings
from app.db import Database, DatabaseUnavailable, get_db, set_db
from app.instrumentation import init_tracing
from app.logging_config import JsonFormatter, correlation_id_var, setup_logging
from app.models.schemas import ChatRequest
from app.services.chat_service import ChatService
from app.services.chat_tools import ChatToolExecutor
from app.services.kafka_consumer import KafkaAuditConsumer


@pytest.mark.asyncio
async def test_litellm_tool_loop_mock(alice_token: str):
    """Test LiteLLM multi-iteration tool calling loop."""
    chat_svc = ChatService()
    from app.auth import get_current_user

    user = await get_current_user(f"Bearer {alice_token}")

    # Mock tool call response from LiteLLM
    tool_call_mock = MagicMock()
    tool_call_mock.id = "call_abc123"
    tool_call_mock.function.name = "calculate_transfer_fee"
    tool_call_mock.function.arguments = json.dumps(
        {"transaction_type": "P2P_TRANSFER", "amount": 200.0}
    )

    first_msg = MagicMock()
    first_msg.content = None
    first_msg.tool_calls = [tool_call_mock]

    first_resp = MagicMock()
    first_resp.choices = [MagicMock(message=first_msg)]
    first_resp.usage.prompt_tokens = 15
    first_resp.usage.completion_tokens = 10

    # Second response with final answer
    second_msg = MagicMock()
    second_msg.content = "A transfer of $200.00 has zero fees."
    second_msg.tool_calls = None

    second_resp = MagicMock()
    second_resp.choices = [MagicMock(message=second_msg)]
    second_resp.usage.prompt_tokens = 25
    second_resp.usage.completion_tokens = 12

    with patch("litellm.acompletion", side_effect=[first_resp, second_resp]):
        req = ChatRequest(message="What is the fee for 200?")
        res = await chat_svc.chat(req, user)

        assert res.reply == "A transfer of $200.00 has zero fees."
        assert len(res.tool_calls) == 1
        assert res.tool_calls[0].name == "calculate_transfer_fee"
        assert res.usage.prompt_tokens == 40
        assert res.usage.completion_tokens == 22


@pytest.mark.asyncio
async def test_db_pool_mock_operations():
    """Test Database query execution and error translations."""
    settings = get_settings()
    db = Database(settings)

    mock_pool = MagicMock()
    mock_pool.fetchval = AsyncMock(return_value=42)
    mock_pool.fetchrow = AsyncMock(return_value={"id": 1, "name": "test"})
    mock_pool.fetch = AsyncMock(return_value=[{"id": 1}, {"id": 2}])
    mock_pool.execute = AsyncMock(return_value="INSERT 0 1")
    mock_pool.close = AsyncMock()

    db.pool = mock_pool

    assert await db.ping() is True
    assert await db.fetchval("SELECT 42") == 42
    assert (await db.fetchrow("SELECT * FROM test"))["name"] == "test"
    assert len(await db.fetch("SELECT * FROM test")) == 2
    assert await db.execute("INSERT INTO test VALUES (1)") == "INSERT 0 1"

    await db.close()
    assert db.pool is None


@pytest.mark.asyncio
async def test_db_unavailable_handling():
    settings = get_settings()
    db = Database(settings)

    with patch.object(db, "try_connect", AsyncMock(return_value=False)):
        db.last_error = "Connection refused"
        with pytest.raises(DatabaseUnavailable):
            await db.fetch("SELECT 1")


def test_json_formatter_logging():
    formatter = JsonFormatter("ai-risk-service")
    correlation_id_var.set("test-cid-123")
    record = logging.LogRecord(
        name="test_logger",
        level=logging.INFO,
        pathname="test.py",
        lineno=10,
        msg="Test log message",
        args=(),
        exc_info=None,
    )
    formatted = formatter.format(record)
    parsed = json.loads(formatted)
    assert parsed["service"] == "ai-risk-service"
    assert parsed["level"] == "INFO"
    assert parsed["message"] == "Test log message"
    assert parsed["correlation_id"] == "test-cid-123"


def test_setup_logging_text_and_json():
    setup_logging(level="DEBUG", fmt="text", service="test-service")
    setup_logging(level="INFO", fmt="json", service="test-service")


def test_init_tracing_disabled():
    with patch("app.config.get_settings") as mock_get_settings:
        mock_settings = MagicMock()
        mock_settings.traceloop_enabled = False
        mock_get_settings.return_value = mock_settings
        # Should return without exception
        init_tracing()


def test_init_tracing_enabled(monkeypatch):
    monkeypatch.setenv("TRACELOOP_ENABLED", "true")
    with patch("traceloop.sdk.Traceloop.init") as mock_traceloop_init:
        init_tracing()
        mock_traceloop_init.assert_called_once()


@pytest.mark.asyncio
async def test_get_optional_user_helper(alice_token: str):
    user = await get_optional_user(f"Bearer {alice_token}")
    assert user is not None
    assert user.account_number == "2170000001"

    none_user = await get_optional_user(None)
    assert none_user is None


@pytest.mark.asyncio
async def test_verify_internal_token_required_mode(monkeypatch):
    monkeypatch.setenv("REQUIRE_INTERNAL_TOKEN", "true")
    get_settings.cache_clear()

    # Valid internal token
    valid = await verify_internal_token("test-internal-token-zylkerbank")
    assert valid == "test-internal-token-zylkerbank"

    # Missing internal token when required
    with pytest.raises(HTTPException) as exc_info:
        await verify_internal_token(None)
    assert exc_info.value.status_code == 401


@pytest.mark.asyncio
async def test_chat_tool_unknown_executor():
    executor = ChatToolExecutor()
    res = await executor.execute_tool("unknown_tool_name", {}, None)
    assert res["error"] == "UNKNOWN_TOOL"


@pytest.mark.asyncio
async def test_kafka_consumer_start_stop():
    consumer = KafkaAuditConsumer()
    consumer.start()
    await consumer.stop()
    assert consumer.running is False


@pytest.mark.asyncio
async def test_unhandled_exception_endpoint(monkeypatch):
    from httpx import ASGITransport
    from app.main import app
    from app.services.risk_engine import RiskEngine

    async def raise_runtime_error(*args, **kwargs):
        raise RuntimeError("Unexpected failure in engine")

    monkeypatch.setattr(RiskEngine, "evaluate", raise_runtime_error)
    transport = ASGITransport(app=app, raise_app_exceptions=False)
    async with AsyncClient(transport=transport, base_url="http://testserver") as test_client:
        resp = await test_client.post(
            "/api/v1/risk/evaluate",
            json={"from_account": "111", "to_account": "222", "amount": 100},
        )
        assert resp.status_code == 500
        data = resp.json()
        assert data["error"] == "INTERNAL_SERVER_ERROR"
        assert "Unexpected failure" in data["message"]
