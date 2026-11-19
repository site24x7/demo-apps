"""Pytest configuration and shared fixtures."""

import os
import sys
from pathlib import Path
from typing import AsyncIterator

# Ensure service root is in sys.path
SERVICE_ROOT = Path(__file__).resolve().parent.parent
if str(SERVICE_ROOT) not in sys.path:
    sys.path.insert(0, str(SERVICE_ROOT))

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient

# Configure test environment prior to importing application
os.environ["CHAOS_SDK_ENABLED"] = "false"
os.environ["TRACELOOP_ENABLED"] = "false"
os.environ["KAFKA_ENABLED"] = "false"
os.environ["JWT_SECRET"] = "test-secret-key-for-zylkerbank-unit-tests-12345"
os.environ["INTERNAL_TOKEN"] = "test-internal-token-zylkerbank"
os.environ["REQUIRE_INTERNAL_TOKEN"] = "false"
os.environ["LLM_FALLBACK_ENABLED"] = "true"
os.environ["LLM_MODEL"] = "ollama/llama3"

from app.auth import create_access_token
from app.config import get_settings
from app.main import app
from app.services.chat_service import clear_in_memory_chat_state
from app.services.kafka_consumer import clear_in_memory_audit_logs
from app.services.risk_engine import clear_in_memory_risk_state


@pytest.fixture(autouse=True)
def clean_state():
    """Reset in-memory singletons and state between tests."""
    get_settings.cache_clear()
    clear_in_memory_risk_state()
    clear_in_memory_chat_state()
    clear_in_memory_audit_logs()
    yield


@pytest.fixture
def alice_token() -> str:
    return create_access_token(
        user_id="11111111-1111-1111-1111-111111111111",
        email="alice@zylkerbank.com",
        name="Alice Johnson",
        account_number="2170000001",
    )


@pytest.fixture
def bob_token() -> str:
    return create_access_token(
        user_id="22222222-2222-2222-2222-222222222222",
        email="bob@zylkerbank.com",
        name="Bob Smith",
        account_number="2170000002",
    )


@pytest_asyncio.fixture
async def client() -> AsyncIterator[AsyncClient]:
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://testserver") as ac:
        yield ac
