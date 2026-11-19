"""Audit logs router for compliance and monitoring."""

from __future__ import annotations

import logging
from typing import Any

from fastapi import APIRouter, Depends, Query

from app.auth import get_optional_user
from app.config import get_settings
from app.db import DatabaseUnavailable, get_db
from app.models.schemas import AuditEventItem, AuditLogsResponse
from app.services.kafka_consumer import get_in_memory_audit_logs

logger = logging.getLogger("audit_router")
router = APIRouter(prefix="/api/v1/audit", tags=["Audit"])


@router.get(
    "/logs",
    response_model=AuditLogsResponse,
    summary="Query audit events with optional event_type filtering and pagination",
)
async def get_audit_logs(
    event_type: str | None = Query(default=None, description="Filter by event type"),
    limit: int = Query(default=50, ge=1, le=200, description="Page size"),
    offset: int = Query(default=0, ge=0, description="Offset index"),
    _user: Any = Depends(get_optional_user),
) -> AuditLogsResponse:
    settings = get_settings()
    db = get_db(settings)

    try:
        if event_type:
            total_val = await db.fetchval(
                "SELECT COUNT(*) FROM audit_events WHERE event_type = $1",
                event_type,
            )
            rows = await db.fetch(
                """
                SELECT id, event_id, event_type, topic, payload, correlation_id, created_at
                FROM audit_events
                WHERE event_type = $1
                ORDER BY id DESC
                LIMIT $2 OFFSET $3
                """,
                event_type,
                limit,
                offset,
            )
        else:
            total_val = await db.fetchval("SELECT COUNT(*) FROM audit_events")
            rows = await db.fetch(
                """
                SELECT id, event_id, event_type, topic, payload, correlation_id, created_at
                FROM audit_events
                ORDER BY id DESC
                LIMIT $1 OFFSET $2
                """,
                limit,
                offset,
            )

        items = [
            AuditEventItem(
                id=r["id"],
                event_id=r["event_id"],
                event_type=r["event_type"],
                topic=r["topic"],
                payload=r["payload"] if isinstance(r["payload"], dict) else {},
                correlation_id=r["correlation_id"],
                created_at=r["created_at"],
            )
            for r in rows
        ]
        return AuditLogsResponse(total=int(total_val or 0), items=items)

    except (DatabaseUnavailable, Exception) as exc:
        logger.debug("Database audit logs query failed: %s, falling back to memory", exc)
        mem_logs = get_in_memory_audit_logs()
        if event_type:
            mem_logs = [l for l in mem_logs if l.get("event_type") == event_type]
        total = len(mem_logs)
        sliced = mem_logs[offset : offset + limit]
        items = [
            AuditEventItem(
                id=l["id"],
                event_id=l.get("event_id"),
                event_type=l.get("event_type", "Unknown"),
                topic=l.get("topic"),
                payload=l.get("payload", {}),
                correlation_id=l.get("correlation_id"),
                created_at=l["created_at"],
            )
            for l in sliced
        ]
        return AuditLogsResponse(total=total, items=items)
