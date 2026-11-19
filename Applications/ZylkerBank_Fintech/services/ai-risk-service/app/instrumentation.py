"""Site24x7 LLM observability via Traceloop (OpenLLMetry) → OTLP."""

from __future__ import annotations

import logging
import os

from app.config import get_settings

logger = logging.getLogger(__name__)


def init_tracing(service_name: str | None = None) -> None:
    settings = get_settings()
    if not settings.traceloop_enabled:
        logger.info("Traceloop tracing is disabled via TRACELOOP_ENABLED=false")
        return

    svc_name = service_name or settings.service_name
    otlp_endpoint = settings.otlp_endpoint.rstrip("/")
    api_key = os.environ.get("TRACELOOP_API_KEY") or None

    raw_headers = os.environ.get("OTEL_EXPORTER_OTLP_HEADERS", "")
    headers: dict[str, str] = {}
    if raw_headers:
        for pair in raw_headers.split(","):
            if "=" in pair:
                k, v = pair.split("=", 1)
                headers[k.strip()] = v.strip()

    os.environ.setdefault("OTEL_EXPORTER_OTLP_TIMEOUT", "30000")
    os.environ.setdefault("OTEL_EXPORTER_OTLP_PROTOCOL", "http/protobuf")

    try:
        from traceloop.sdk import Traceloop

        Traceloop.init(
            app_name=svc_name,
            api_endpoint=otlp_endpoint,
            api_key=api_key,
            headers=headers if headers else None,
            disable_batch=True,
        )
        logger.info(
            "Traceloop initialized service=%s endpoint=%s",
            svc_name,
            otlp_endpoint,
        )
    except Exception as exc:
        logger.warning("Failed to initialize Traceloop tracing (continuing without LLM tracing): %s", exc)
