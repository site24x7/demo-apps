"""Tests for Kafka audit consumer and simulated notification dispatcher."""

import logging
import pytest

from app.services.kafka_consumer import KafkaAuditConsumer, get_in_memory_audit_logs


@pytest.mark.asyncio
async def test_kafka_process_transfer_completed(caplog):
    consumer = KafkaAuditConsumer()
    event_payload = {
        "event_id": "test-event-uuid-12345",
        "event_type": "TransferCompleted",
        "correlation_id": "corr-9999",
        "occurred_at": "2026-11-18T14:30:00Z",
        "data": {
            "transaction_ref": "TX-10001",
            "journal_id": 42,
            "from_account": "2170000001",
            "to_account": "2170000002",
            "from_name": "Alice Johnson",
            "to_name": "Bob Smith",
            "amount": "300.00",
            "currency": "USD",
            "description": "Dinner split",
            "risk_score": 15,
            "risk_decision": "APPROVED",
        },
    }

    with caplog.at_level(logging.INFO, logger="notifications"):
        await consumer._process_event("bank.transfers.v1", event_payload)

    # Check notification logs
    logs = caplog.text
    assert "[SMS ALERT]" in logs
    assert "DEBITED $300.00 USD" in logs
    assert "CREDITED $300.00 USD" in logs
    assert "[EMAIL NOTIFICATION]" in logs
    assert "TX-10001" in logs

    # Check in-memory audit log
    mem_logs = get_in_memory_audit_logs()
    assert any(l["event_id"] == "test-event-uuid-12345" for l in mem_logs)


@pytest.mark.asyncio
async def test_kafka_process_card_event(caplog):
    consumer = KafkaAuditConsumer()
    event_payload = {
        "event_id": "test-card-event-67890",
        "event_type": "CardFunded",
        "correlation_id": "corr-card-1",
        "data": {
            "card_id": "c1",
            "account_number": "2170000001",
            "card_type": "VISA",
            "masked": "4111 **** **** 1111",
            "amount": "150.00",
        },
    }

    with caplog.at_level(logging.INFO, logger="notifications"):
        await consumer._process_event("bank.cards.v1", event_payload)

    logs = caplog.text
    assert "[SMS ALERT]" in logs
    assert "CardFunded" in logs
    assert "2170000001" in logs


def test_kafka_status_info():
    consumer = KafkaAuditConsumer()
    info = consumer.status_info
    assert "brokers" in info
    assert "topics" in info
    assert "consumer_running" in info
