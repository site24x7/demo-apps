"""Inbound HTTP fault injector — 5 fault types.

This module evaluates HTTP fault rules against incoming requests and returns
fault results that the framework middleware (Flask / FastAPI) translates into
the appropriate HTTP response.

Fault types handled
-------------------
1. ``http_exception``       — Raise a mapped Python exception.
2. ``http_latency``         — Sleep before the request is handled.
3. ``http_error_response``  — Return a static error status + body.
4. ``http_connection_reset``— Abort the connection (close the socket).
5. ``http_slow_body``       — Stream a response body with inter-chunk delays.
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass
from typing import TYPE_CHECKING, Optional

from ..models import FaultRuleConfig, resolve_exception_class

if TYPE_CHECKING:
    from ..engine import ChaosEngine

logger = logging.getLogger("site24x7_chaos.fault.http")

# Prefix used to query the engine for inbound HTTP rules.
_FAULT_PREFIX = "http_"


# ------------------------------------------------------------------
# Result types — the middleware translates these into framework responses
# ------------------------------------------------------------------

@dataclass
class HttpFaultResult:
    """Base class for fault results returned to middleware."""

    rule_id: str


@dataclass
class ExceptionFault(HttpFaultResult):
    """Raise an exception."""

    exception: BaseException


@dataclass
class LatencyFault(HttpFaultResult):
    """Latency was already applied (sleep done). Continue request normally."""

    delay_ms: int


@dataclass
class ErrorResponseFault(HttpFaultResult):
    """Return a static error response."""

    status_code: int
    body: str


@dataclass
class ConnectionResetFault(HttpFaultResult):
    """Signal the middleware to abort the connection."""

    pass


@dataclass
class SlowBodyFault(HttpFaultResult):
    """Stream a response body slowly with inter-chunk delays."""

    delay_ms: int
    chunk_size: int
    total_chunks: int = 32


# ------------------------------------------------------------------
# Injector
# ------------------------------------------------------------------

class HttpFaultInjector:
    """Evaluates inbound HTTP fault rules for a request.

    The middleware calls :meth:`evaluate` before dispatching the request to the
    application.  If a fault fires, the appropriate :class:`HttpFaultResult` is
    returned; otherwise ``None``.
    """

    def __init__(self, engine: ChaosEngine) -> None:
        self._engine = engine

    def evaluate(self, request_url: str) -> Optional[HttpFaultResult]:
        """Check all ``http_*`` rules and return the first matching fault.

        For ``http_latency`` the sleep is applied immediately and a
        :class:`LatencyFault` is returned so the middleware knows latency was
        injected but should still continue the request.

        Returns ``None`` when no fault should be injected.
        """
        if not self._engine.enabled:
            return None

        rules = self._engine.find_matching_rules(_FAULT_PREFIX, request_url)

        for rule in rules:
            if not self._engine.should_fire(rule):
                continue

            try:
                fault_type = rule.fault_type
                if fault_type == "http_exception":
                    return self._apply_exception(rule)
                elif fault_type == "http_latency":
                    return self._apply_latency(rule)
                elif fault_type == "http_error_response":
                    return self._apply_error_response(rule)
                elif fault_type == "http_connection_reset":
                    return self._apply_connection_reset(rule)
                elif fault_type == "http_slow_body":
                    return self._apply_slow_body(rule)
                else:
                    logger.warning("Unknown HTTP fault type: %s", fault_type)
            except Exception as exc:
                # If the fault itself is an exception fault, re-raise
                if isinstance(exc, _InjectedFault):
                    raise exc.__cause__  # type: ignore[misc]
                logger.error(
                    "Failed to apply fault %s: %s", rule.id, exc, exc_info=True
                )

        return None

    # ------------------------------------------------------------------
    # Individual fault implementations
    # ------------------------------------------------------------------

    @staticmethod
    def _apply_exception(rule: FaultRuleConfig) -> ExceptionFault:
        java_class = rule.get_config_str("exception_class", "java.lang.RuntimeException")
        message = rule.get_config_str("message", "Injected fault")

        logger.debug("Injecting HTTP exception: %s - %s", java_class, message)

        exc_class = resolve_exception_class(java_class, default=RuntimeError)

        # Some exception classes (e.g. SQLAlchemy OperationalError) need
        # special construction.  Fall back to RuntimeError if instantiation
        # fails.
        try:
            exc = exc_class(message)
        except TypeError:
            exc = RuntimeError(message)

        return ExceptionFault(rule_id=rule.id, exception=exc)

    @staticmethod
    def _apply_latency(rule: FaultRuleConfig) -> LatencyFault:
        delay_ms = rule.get_config_int("delay_ms", 1000)

        logger.debug("Injecting HTTP latency: %dms", delay_ms)
        time.sleep(delay_ms / 1000.0)

        return LatencyFault(rule_id=rule.id, delay_ms=delay_ms)

    @staticmethod
    def _apply_error_response(rule: FaultRuleConfig) -> ErrorResponseFault:
        status_code = rule.get_config_int("status_code", 500)
        body = rule.get_config_str("body", "Internal Server Error")

        logger.debug("Injecting HTTP error response: %d - %s", status_code, body)

        return ErrorResponseFault(rule_id=rule.id, status_code=status_code, body=body)

    @staticmethod
    def _apply_connection_reset(rule: FaultRuleConfig) -> ConnectionResetFault:
        logger.debug("Injecting HTTP connection reset")
        return ConnectionResetFault(rule_id=rule.id)

    @staticmethod
    def _apply_slow_body(rule: FaultRuleConfig) -> SlowBodyFault:
        delay_ms = rule.get_config_int("delay_ms", 200)
        chunk_size = rule.get_config_int("chunk_size_bytes", 64)

        logger.debug(
            "Injecting HTTP slow body: %dms delay, %d byte chunks",
            delay_ms,
            chunk_size,
        )

        return SlowBodyFault(rule_id=rule.id, delay_ms=delay_ms, chunk_size=chunk_size)


class _InjectedFault(Exception):
    """Internal wrapper so we can distinguish injected exceptions from bugs."""

    pass
