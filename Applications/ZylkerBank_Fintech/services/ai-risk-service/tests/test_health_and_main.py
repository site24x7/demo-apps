"""Tests for health endpoint, middleware, and error handlers."""

import pytest
from httpx import AsyncClient


@pytest.mark.asyncio
async def test_health_endpoint(client: AsyncClient):
    resp = await client.get("/health")
    assert resp.status_code == 200
    data = resp.json()
    assert data["service"] == "ai-risk-service"
    assert data["status"] in ("UP", "DEGRADED")
    assert "database" in data
    assert "kafka" in data
    assert "llm" in data


@pytest.mark.asyncio
async def test_correlation_id_middleware(client: AsyncClient):
    custom_cid = "custom-test-correlation-id-987"
    resp = await client.get("/health", headers={"X-Correlation-Id": custom_cid})
    assert resp.status_code == 200
    assert resp.headers.get("x-correlation-id") == custom_cid


@pytest.mark.asyncio
async def test_validation_error_handler(client: AsyncClient):
    # Invalid amount (negative or not a number)
    resp = await client.post(
        "/api/v1/risk/evaluate",
        json={"from_account": "123", "to_account": "456", "amount": -10},
    )
    assert resp.status_code == 422
    data = resp.json()
    assert data["error"] == "VALIDATION_ERROR"
    assert "message" in data
