"""Background Kafka consumer for audit events and simulated notifications."""

from __future__ import annotations

import asyncio
import json
import logging
from collections import deque
from datetime import datetime, timezone
from typing import Any

from aiokafka import AIOKafkaConsumer

from app.config import Settings, get_settings
from app.db import Database, DatabaseUnavailable, get_db
from app.services.risk_engine import record_completed_transfer_in_memory

logger = logging.getLogger("kafka_consumer")
notifications_logger = logging.getLogger("notifications")

# In-memory audit buffer for fallback & standalone testing
_in_memory_audit_logs: deque[dict[str, Any]] = deque(maxlen=500)


def get_in_memory_audit_logs() -> list[dict[str, Any]]:
    return list(_in_memory_audit_logs)


def clear_in_memory_audit_logs() -> None:
    _in_memory_audit_logs.clear()


class KafkaAuditConsumer:
    def __init__(self, settings: Settings | None = None, db: Database | None = None) -> None:
        self.settings = settings or get_settings()
        self.db = db or get_db(self.settings)
        self.consumer: AIOKafkaConsumer | None = None
        self.running: bool = False
        self.processed_count: int = 0
        self.last_error: str | None = None
        self._task: asyncio.Task[None] | None = None
        self._stop_event = asyncio.Event()

    @property
    def status_info(self) -> dict[str, Any]:
        if not self.settings.kafka_enabled:
            return {
                "status": "disabled",
                "brokers": self.settings.kafka_brokers,
                "topics": list(self.settings.kafka_topics),
                "consumer_running": False,
            }
        return {
            "status": "connected" if (self.running and not self.last_error) else "degraded",
            "brokers": self.settings.kafka_brokers,
            "topics": list(self.settings.kafka_topics),
            "consumer_running": self.running,
            "processed_count": self.processed_count,
            "last_error": self.last_error,
        }

    async def _process_event(self, topic: str, raw_value: Any) -> None:
        if isinstance(raw_value, (bytes, bytearray)):
            try:
                payload = json.loads(raw_value.decode("utf-8"))
            except Exception:
                payload = {"raw": raw_value.decode("utf-8", errors="replace")}
        elif isinstance(raw_value, dict):
            payload = raw_value
        else:
            payload = {"raw": str(raw_value)}

        event_id = payload.get("event_id")
        event_type = payload.get("event_type", "UnknownEvent")
        correlation_id = payload.get("correlation_id")
        data = payload.get("data", {})
        now = datetime.now(timezone.utc)

        # Store in in-memory buffer
        mem_entry = {
            "id": len(_in_memory_audit_logs) + 1,
            "event_id": event_id,
            "event_type": event_type,
            "topic": topic,
            "payload": payload,
            "correlation_id": correlation_id,
            "created_at": now,
        }
        _in_memory_audit_logs.appendleft(mem_entry)
        self.processed_count += 1

        # Track completed transfer for risk engine
        if event_type == "TransferCompleted":
            from_acc = str(data.get("from_account", ""))
            to_acc = str(data.get("to_account", ""))
            if from_acc and to_acc:
                record_completed_transfer_in_memory(from_acc, to_acc)

        # Persist to PostgreSQL audit_events (dedupe on event_id)
        try:
            await self.db.execute(
                """
                INSERT INTO audit_events (event_id, event_type, topic, payload, correlation_id, created_at)
                VALUES ($1, $2, $3, $4, $5, $6)
                ON CONFLICT (event_id) DO NOTHING
                """,
                event_id,
                event_type,
                topic,
                payload,
                correlation_id,
                now,
            )
        except (DatabaseUnavailable, Exception) as exc:
            logger.debug("Database audit event insert failed (%s), recorded in memory", exc)

        # Simulated SMS and Email notifications (dedicated 'notifications' logger at INFO)
        self._dispatch_notifications(event_type, data)

    def _dispatch_notifications(self, event_type: str, data: dict[str, Any]) -> None:
        if event_type == "TransferCompleted":
            from_acc = data.get("from_account", "N/A")
            to_acc = data.get("to_account", "N/A")
            from_name = data.get("from_name", "Sender")
            to_name = data.get("to_name", "Beneficiary")
            amount = data.get("amount", "0.00")
            currency = data.get("currency", "USD")
            tx_ref = data.get("transaction_ref", "N/A")

            # 1. Debit SMS to sender
            notifications_logger.info(
                "[SMS ALERT] To %s (%s): Your account has been DEBITED $%s %s for transfer to %s (%s). Ref: %s",
                from_name,
                from_acc,
                amount,
                currency,
                to_name,
                to_acc,
                tx_ref,
            )

            # 2. Credit SMS to receiver
            notifications_logger.info(
                "[SMS ALERT] To %s (%s): Your account has been CREDITED $%s %s from %s (%s). Ref: %s",
                to_name,
                to_acc,
                amount,
                currency,
                from_name,
                from_acc,
                tx_ref,
            )

            # 3. Email notification
            notifications_logger.info(
                "[EMAIL NOTIFICATION] Receipt: $%s %s transfer COMPLETED from %s (%s) to %s (%s). Transaction Ref: %s.",
                amount,
                currency,
                from_name,
                from_acc,
                to_name,
                to_acc,
                tx_ref,
            )

        elif event_type in ("CardCreated", "CardFunded", "CardWithdrawn", "CardStatusChanged"):
            acc_num = data.get("account_number", "N/A")
            masked = data.get("masked", "****")
            card_type = data.get("card_type", "CARD")
            amount = data.get("amount")
            notifications_logger.info(
                "[SMS ALERT] Virtual Card Event '%s' for account %s: Card %s (%s) %s",
                event_type,
                acc_num,
                masked,
                card_type,
                f"Amount: ${amount}" if amount else "",
            )

    async def _run_consumer_loop(self) -> None:
        backoff = 2.0
        while not self._stop_event.is_set():
            try:
                logger.info(
                    "Connecting to Kafka brokers %s for topics %s",
                    self.settings.kafka_brokers,
                    self.settings.kafka_topics,
                )
                self.consumer = AIOKafkaConsumer(
                    *self.settings.kafka_topics,
                    bootstrap_servers=self.settings.kafka_brokers,
                    group_id=self.settings.kafka_group_id,
                    auto_offset_reset="earliest",
                    enable_auto_commit=True,
                )
                await self.consumer.start()
                self.running = True
                self.last_error = None
                backoff = 2.0
                logger.info("Kafka consumer started successfully on %s", self.settings.kafka_topics)

                async for msg in self.consumer:
                    if self._stop_event.is_set():
                        break
                    try:
                        await self._process_event(msg.topic, msg.value)
                    except Exception as err:
                        logger.error("Error processing Kafka message on topic %s: %s", msg.topic, err)

            except asyncio.CancelledError:
                break
            except Exception as exc:
                self.last_error = f"{type(exc).__name__}: {exc}"
                self.running = False
                logger.warning(
                    "Kafka consumer disconnected (%s). Retrying in %.1fs...",
                    self.last_error,
                    backoff,
                )
                if self.consumer:
                    try:
                        await self.consumer.stop()
                    except Exception:
                        pass
                    self.consumer = None
                try:
                    await asyncio.wait_for(self._stop_event.wait(), timeout=backoff)
                except asyncio.TimeoutError:
                    pass
                backoff = min(backoff * 2, 30.0)

        if self.consumer:
            try:
                await self.consumer.stop()
            except Exception:
                pass
        self.running = False

    def start(self) -> None:
        if not self.settings.kafka_enabled:
            logger.info("Kafka consumer is disabled via KAFKA_ENABLED=false")
            return
        if self._task is None or self._task.done():
            self._stop_event.clear()
            self._task = asyncio.create_task(self._run_consumer_loop())

    async def stop(self) -> None:
        self._stop_event.set()
        if self._task:
            self._task.cancel()
            try:
                await asyncio.wait_for(self._task, timeout=5.0)
            except (asyncio.TimeoutError, asyncio.CancelledError):
                pass
            self._task = None
        if self.consumer:
            try:
                await self.consumer.stop()
            except Exception:
                pass
            self.consumer = None
        self.running = False


_consumer_instance: KafkaAuditConsumer | None = None


def get_kafka_consumer(settings: Settings | None = None) -> KafkaAuditConsumer:
    global _consumer_instance
    if _consumer_instance is None:
        _consumer_instance = KafkaAuditConsumer(settings)
    return _consumer_instance
