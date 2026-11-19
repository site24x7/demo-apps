"""Tests for audit logs endpoint."""

import pytest
from httpx import AsyncClient

from app.services.kafka_consumer import KafkaAuditConsumer


@pytest.mark.asyncio
async def test_get_audit_logs_empty(client: AsyncClient):
    resp = await client.get("/api/v1/audit/logs")
    assert resp.status_code == 200
    data = resp.json()
    assert "total" in data
    assert "items" in data
    assert isinstance(data["items"], list)


@pytest.mark.asyncio
async def test_get_audit_logs_filtering_and_pagination(client: AsyncClient):
    consumer = KafkaAuditConsumer()
    # Insert 3 events of different types
    await consumer._process_event(
        "bank.transfers.v1",
        {"event_id": "ev-1", "event_type": "TransferCompleted", "data": {}},
    )
    await consumer._process_event(
        "bank.cards.v1",
        {"event_id": "ev-2", "event_type": "CardFunded", "data": {}},
    )
    await consumer._process_event(
        "bank.transfers.v1",
        {"event_id": "ev-3", "event_type": "TransferCompleted", "data": {}},
    )

    # 1. Fetch all
    resp_all = await client.get("/api/v1/audit/logs")
    assert resp_all.status_code == 200
    assert resp_all.json()["total"] == 3

    # 2. Filter by event_type
    resp_filtered = await client.get(
        "/api/v1/audit/logs", params={"event_type": "TransferCompleted"}
    )
    assert resp_filtered.status_code == 200
    filtered_data = resp_filtered.json()
    assert filtered_data["total"] == 2
    for item in filtered_data["items"]:
        assert item["event_type"] == "TransferCompleted"

    # 3. Pagination: limit=1, offset=1
    resp_paged = await client.get(
        "/api/v1/audit/logs", params={"limit": 1, "offset": 1}
    )
    assert resp_paged.status_code == 200
    paged_data = resp_paged.json()
    assert paged_data["total"] == 3
    assert len(paged_data["items"]) == 1
