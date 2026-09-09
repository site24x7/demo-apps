"""Site24x7 LLM observability via Traceloop (OpenLLMetry) → OTLP."""

from __future__ import annotations

import logging
import os

logger = logging.getLogger(__name__)


def init_tracing(service_name: str | None = None) -> None:
    otlp_endpoint = os.environ.get(
        "OTEL_EXPORTER_OTLP_ENDPOINT", "https://otel.site24x7rum.com"
    ).rstrip("/")
    svc_name = service_name or os.environ.get(
        "OTEL_SERVICE_NAME", "zylkerkart-ai-assistant"
    )
    api_key = os.environ.get("TRACELOOP_API_KEY") or None

    raw_headers = os.environ.get("OTEL_EXPORTER_OTLP_HEADERS", "")
    headers: dict[str, str] = {}
    if raw_headers:
        for pair in raw_headers.split(","):
            if "=" in pair:
                k, v = pair.split("=", 1)
                headers[k.strip()] = v.strip()

    # Ensure exporter timeout is generous behind corporate proxies
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
            "Traceloop initialized service=%s endpoint=%s headers=%s",
            svc_name,
            otlp_endpoint,
            list(headers.keys()),
        )
    except Exception:
        logger.exception("Failed to initialize Traceloop — continuing without LLM tracing")
