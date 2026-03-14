"""Outbound HTTP fault injector — monkey-patches ``requests`` and ``httpx``.

Fault types handled
-------------------
1. ``http_client_latency``            — Sleep before the outbound call proceeds.
2. ``http_client_exception``          — Raise a mapped Python exception instead of
   making the call.
3. ``http_client_error_response``     — Return a fake error response without
   hitting the remote server.
4. ``http_client_partial_response``   — Return a truncated response body
   (simulates TCP reset mid-transfer).

Monkey-patching approach
------------------------
We wrap ``requests.Session.send`` and ``httpx.Client.send`` /
``httpx.AsyncClient.send`` at the lowest transport level so that *all*
outbound HTTP calls made via those libraries are intercepted — regardless of
whether the caller uses ``requests.get()`` or a custom ``Session``.
"""

from __future__ import annotations

import logging
import time
from typing import TYPE_CHECKING, Any, Optional

from ..models import FaultRuleConfig, resolve_exception_class

if TYPE_CHECKING:
    from ..engine import ChaosEngine

logger = logging.getLogger("site24x7_chaos.fault.http_client")

_FAULT_PREFIX = "http_client_"

# Sentinel to track whether we've already patched
_patched_requests = False
_patched_httpx = False


class HttpClientFaultInjector:
    """Evaluates ``http_client_*`` fault rules and monkey-patches outbound
    HTTP libraries to inject faults.

    Call :meth:`install` once after the engine is started.
    """

    def __init__(self, engine: ChaosEngine) -> None:
        self._engine = engine

    def install(self) -> None:
        """Monkey-patch ``requests`` and ``httpx`` (if available)."""
        self._patch_requests()
        self._patch_httpx()

    # ------------------------------------------------------------------
    # requests monkey-patch
    # ------------------------------------------------------------------

    def _patch_requests(self) -> None:
        global _patched_requests
        if _patched_requests:
            return
        try:
            import requests  # noqa: F811
        except ImportError:
            return

        original_send = requests.Session.send
        engine = self._engine

        def patched_send(session_self: Any, request: Any, **kwargs: Any) -> Any:
            url = str(request.url)
            result = _evaluate(engine, url)

            if result is not None:
                fault_type = result[0]
                if fault_type == "exception":
                    raise result[1]
                elif fault_type == "error_response":
                    return _fake_requests_response(result[1], result[2], request)
                elif fault_type == "partial_response":
                    return _fake_requests_response(result[1], result[2], request)
                # latency: already slept, fall through to real call

            return original_send(session_self, request, **kwargs)

        requests.Session.send = patched_send  # type: ignore[assignment]
        _patched_requests = True
        logger.info("Monkey-patched requests.Session.send")

    # ------------------------------------------------------------------
    # httpx monkey-patch
    # ------------------------------------------------------------------

    def _patch_httpx(self) -> None:
        global _patched_httpx
        if _patched_httpx:
            return
        try:
            import httpx  # noqa: F811
        except ImportError:
            return

        engine = self._engine

        # --- Sync client ---
        original_sync_send = httpx.Client.send

        def patched_sync_send(client_self: Any, request: Any, **kwargs: Any) -> Any:
            url = str(request.url)
            result = _evaluate(engine, url)

            if result is not None:
                fault_type = result[0]
                if fault_type == "exception":
                    raise result[1]
                elif fault_type == "error_response":
                    return _fake_httpx_response(result[1], result[2], request)
                elif fault_type == "partial_response":
                    return _fake_httpx_response(result[1], result[2], request)

            return original_sync_send(client_self, request, **kwargs)

        httpx.Client.send = patched_sync_send  # type: ignore[assignment]

        # --- Async client ---
        original_async_send = httpx.AsyncClient.send

        async def patched_async_send(
            client_self: Any, request: Any, **kwargs: Any
        ) -> Any:
            url = str(request.url)
            result = _evaluate(engine, url)

            if result is not None:
                fault_type = result[0]
                if fault_type == "exception":
                    raise result[1]
                elif fault_type == "error_response":
                    return _fake_httpx_response(result[1], result[2], request)
                elif fault_type == "partial_response":
                    return _fake_httpx_response(result[1], result[2], request)

            return await original_async_send(client_self, request, **kwargs)

        httpx.AsyncClient.send = patched_async_send  # type: ignore[assignment]

        _patched_httpx = True
        logger.info("Monkey-patched httpx.Client.send and httpx.AsyncClient.send")


# ------------------------------------------------------------------
# Shared evaluation logic
# ------------------------------------------------------------------


def _evaluate(
    engine: ChaosEngine, url: str
) -> Optional[tuple]:
    """Evaluate ``http_client_*`` rules and return a result tuple or None.

    Result tuples:
    * ``("latency", delay_ms)``  — sleep already done
    * ``("exception", exc)``
    * ``("error_response", status_code, body)``
    * ``("partial_response", status_code, body)`` — body already truncated
    """
    if not engine.enabled:
        return None

    rules = engine.find_matching_rules(_FAULT_PREFIX, url)

    for rule in rules:
        if not engine.should_fire(rule):
            continue

        fault_type = rule.fault_type
        if fault_type == "http_client_latency":
            delay_ms = rule.get_config_int("delay_ms", 3000)
            logger.debug("Injecting HTTP client latency: %dms on %s", delay_ms, url)
            time.sleep(delay_ms / 1000.0)
            return ("latency", delay_ms)

        elif fault_type == "http_client_exception":
            java_class = rule.get_config_str(
                "exception_class",
                "org.springframework.web.client.ResourceAccessException",
            )
            message = rule.get_config_str("message", "Injected outbound fault")
            logger.debug(
                "Injecting HTTP client exception: %s - %s on %s",
                java_class,
                message,
                url,
            )
            exc_class = resolve_exception_class(java_class, default=ConnectionError)
            try:
                exc = exc_class(message)
            except TypeError:
                exc = ConnectionError(message)
            return ("exception", exc)

        elif fault_type == "http_client_error_response":
            status_code = rule.get_config_int("status_code", 503)
            body = rule.get_config_str("body", "Service Unavailable")
            logger.debug(
                "Injecting HTTP client error response: %d on %s",
                status_code,
                url,
            )
            return ("error_response", status_code, body)

        elif fault_type == "http_client_partial_response":
            status_code = rule.get_config_int("status_code", 200)
            body = rule.get_config_str(
                "body", '{"data":[{"id":1,"name":"item"'
            )
            truncate_pct = min(90, max(10, rule.get_config_int("truncate_percentage", 50)))
            trunc_len = max(1, len(body) * truncate_pct // 100)
            truncated_body = body[:trunc_len]
            logger.debug(
                "Injecting HTTP client partial response: %d%% of body on %s",
                truncate_pct,
                url,
            )
            return ("partial_response", status_code, truncated_body)

        else:
            logger.warning("Unknown HTTP client fault type: %s", fault_type)

    return None


# ------------------------------------------------------------------
# Fake response builders
# ------------------------------------------------------------------


def _fake_requests_response(
    status_code: int, body: str, request: Any
) -> Any:
    """Build a ``requests.Response`` without making a real HTTP call."""
    import requests

    resp = requests.Response()
    resp.status_code = status_code
    resp._content = body.encode("utf-8")
    resp.headers["Content-Type"] = "text/plain"
    resp.encoding = "utf-8"
    resp.request = request
    resp.url = str(request.url)
    return resp


def _fake_httpx_response(
    status_code: int, body: str, request: Any
) -> Any:
    """Build an ``httpx.Response`` without making a real HTTP call."""
    import httpx

    return httpx.Response(
        status_code=status_code,
        content=body.encode("utf-8"),
        headers={"Content-Type": "text/plain"},
        request=request,
    )
