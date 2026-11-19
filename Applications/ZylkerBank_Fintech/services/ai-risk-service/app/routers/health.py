"""Health and dependency status endpoint."""

from __future__ import annotations

import logging
from typing import Any

import httpx
from fastapi import APIRouter

from app.config import get_settings
from app.db import get_db
from app.models.schemas import HealthResponse
from app.services.kafka_consumer import get_kafka_consumer

logger = logging.getLogger("health")
router = APIRouter(tags=["Health"])


async def _probe_llm() -> dict[str, Any]:
    settings = get_settings()
    info: dict[str, Any] = {
        "model": settings.llm_model,
        "api_base": settings.llm_api_base,
        "fallback_enabled": settings.llm_fallback_enabled,
    }

    # If Ollama or local API base is provided, probe tags endpoint
    base = settings.llm_api_base.rstrip("/")
    probe_url = f"{base}/api/tags" if "11434" in base or "ollama" in settings.llm_model.lower() else base
    try:
        async with httpx.AsyncClient(timeout=1.5) as client:
            resp = await client.get(probe_url)
            if resp.status_code in (200, 404, 401):
                info["status"] = "available"
                info["reachable"] = True
                return info
    except Exception as exc:
        info["last_error"] = str(exc)

    if settings.llm_fallback_enabled:
        info["status"] = "fallback_active"
        info["reachable"] = False
    else:
        info["status"] = "unreachable"
        info["reachable"] = False
    return info


@router.get("/health", response_model=HealthResponse)
async def health_check() -> HealthResponse:
    settings = get_settings()
    db = get_db()
    kafka = get_kafka_consumer()

    # 1. Database state
    db_ok = await db.ping()
    db_state: dict[str, Any] = {
        "status": "connected" if db_ok else "disconnected",
        "host": settings.db_host,
        "port": settings.db_port,
        "database": settings.db_name,
        "error": db.last_error if not db_ok else None,
    }

    # 2. Kafka state
    kafka_state = kafka.status_info

    # 3. LLM state
    llm_state = await _probe_llm()

    # System status: UP if process is alive and primary DB is up, DEGRADED otherwise
    # Per contract: health must return 200 even when optional deps such as Kafka/LLM/DB are degraded
    system_status = "UP" if (db_ok and kafka_state.get("status") == "connected") else "DEGRADED"

    return HealthResponse(
        status=system_status,
        service=settings.service_name,
        database=db_state,
        kafka=kafka_state,
        llm=llm_state,
    )
