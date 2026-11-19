"""Structured (JSON-lines) logging with trace/correlation ids."""

from __future__ import annotations

import contextvars
import json
import logging
import sys
from datetime import datetime, timezone

# Request-scoped values populated by the HTTP middleware in app.main
correlation_id_var: contextvars.ContextVar[str | None] = contextvars.ContextVar(
    "correlation_id", default=None
)
traceparent_var: contextvars.ContextVar[str | None] = contextvars.ContextVar(
    "traceparent", default=None
)
tracestate_var: contextvars.ContextVar[str | None] = contextvars.ContextVar(
    "tracestate", default=None
)

_RESERVED = set(logging.LogRecord("", 0, "", 0, "", (), None).__dict__.keys()) | {
    "message",
    "asctime",
    "taskName",
}


def _current_trace_ids() -> tuple[str | None, str | None]:
    try:
        from opentelemetry import trace

        ctx = trace.get_current_span().get_span_context()
        if ctx and ctx.is_valid:
            return format(ctx.trace_id, "032x"), format(ctx.span_id, "016x")
    except Exception:  # pragma: no cover - otel optional
        pass
    return None, None


class JsonFormatter(logging.Formatter):
    def __init__(self, service: str) -> None:
        super().__init__()
        self.service = service

    def format(self, record: logging.LogRecord) -> str:
        payload: dict[str, object] = {
            "ts": datetime.fromtimestamp(record.created, tz=timezone.utc).isoformat(
                timespec="milliseconds"
            ),
            "level": record.levelname,
            "logger": record.name,
            "service": self.service,
            "message": record.getMessage(),
        }
        trace_id, span_id = _current_trace_ids()
        if trace_id:
            payload["trace_id"] = trace_id
            payload["span_id"] = span_id
        cid = correlation_id_var.get()
        if cid:
            payload["correlation_id"] = cid
        for key, value in record.__dict__.items():
            if key not in _RESERVED and not key.startswith("_"):
                try:
                    json.dumps(value)
                    payload[key] = value
                except TypeError:
                    payload[key] = str(value)
        if record.exc_info:
            payload["exc"] = self.formatException(record.exc_info)
        return json.dumps(payload, ensure_ascii=False)


def setup_logging(level: str = "INFO", fmt: str = "json", service: str = "ai-risk-service") -> None:
    handler = logging.StreamHandler(sys.stdout)
    if fmt == "json":
        handler.setFormatter(JsonFormatter(service))
    else:
        handler.setFormatter(
            logging.Formatter("%(asctime)s [%(levelname)s] %(name)s: %(message)s")
        )
    root = logging.getLogger()
    for h in list(root.handlers):
        root.removeHandler(h)
    root.addHandler(handler)
    root.setLevel(level)

    # uvicorn installs its own handlers; route them through ours
    for name in ("uvicorn", "uvicorn.error", "uvicorn.access"):
        lg = logging.getLogger(name)
        lg.handlers = []
        lg.propagate = True
    for noisy in ("httpx", "httpcore", "aiokafka", "LiteLLM", "litellm", "urllib3"):
        logging.getLogger(noisy).setLevel(logging.WARNING)
    # Simulated SMS/Email notifications must always be visible at INFO
    logging.getLogger("notifications").setLevel(logging.INFO)
