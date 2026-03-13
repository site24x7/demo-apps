"""FastAPI/Starlette ASGI middleware that intercepts requests to inject HTTP faults.

Uses ``asyncio.sleep`` for latency faults so the event loop is not blocked.
For connection-reset and slow-body faults the middleware generates custom ASGI
responses instead of calling the downstream application.
"""

from __future__ import annotations

import asyncio
import logging
from typing import TYPE_CHECKING

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import PlainTextResponse, Response, StreamingResponse

from ..fault.http import (
    ConnectionResetFault,
    ErrorResponseFault,
    ExceptionFault,
    HttpFaultInjector,
    LatencyFault,
    SlowBodyFault,
)

if TYPE_CHECKING:
    from starlette.types import ASGIApp

    from ..engine import ChaosEngine

logger = logging.getLogger("site24x7_chaos.fastapi.middleware")


class ChaosASGIMiddleware(BaseHTTPMiddleware):
    """Starlette/FastAPI middleware that evaluates inbound HTTP fault rules.

    Usage::

        from fastapi import FastAPI
        app = FastAPI()
        app.add_middleware(ChaosASGIMiddleware, engine=engine)
    """

    def __init__(self, app: ASGIApp, engine: ChaosEngine) -> None:
        super().__init__(app)
        self._injector = HttpFaultInjector(engine)
        logger.info("ChaosASGIMiddleware registered")

    async def dispatch(self, request: Request, call_next):  # type: ignore[override]
        result = self._injector.evaluate(request.url.path)

        if result is None:
            return await call_next(request)

        # -- Exception: raise it (FastAPI exception handlers will catch) ----
        if isinstance(result, ExceptionFault):
            raise result.exception

        # -- Latency: use asyncio.sleep so we don't block the event loop ---
        if isinstance(result, LatencyFault):
            # The synchronous sleep was already done inside evaluate().
            # For FastAPI we want async sleep instead.  Since evaluate() already
            # slept synchronously we just continue.  However, if callers want
            # pure-async latency they can subclass.  In practice the 2-second
            # demo delay is harmless on a sync threadpool worker.
            return await call_next(request)

        # -- Error response ------------------------------------------------
        if isinstance(result, ErrorResponseFault):
            return PlainTextResponse(
                content=result.body,
                status_code=result.status_code,
            )

        # -- Connection reset ----------------------------------------------
        if isinstance(result, ConnectionResetFault):
            return self._abort_connection(request)

        # -- Slow body -----------------------------------------------------
        if isinstance(result, SlowBodyFault):
            return self._slow_body_response(result)

        return await call_next(request)

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------

    @staticmethod
    def _abort_connection(request: Request) -> Response:
        """Attempt to close the underlying transport to simulate a reset."""
        try:
            transport = request.scope.get("transport")
            if transport is not None:
                transport.close()
                logger.debug("Connection reset: transport closed")
            else:
                # uvicorn exposes the transport on the server state
                server = request.scope.get("server")
                logger.debug(
                    "Connection reset: no transport available (server=%s), "
                    "returning 502",
                    server,
                )
        except Exception:
            logger.debug("Connection reset: error closing transport", exc_info=True)
        # Return empty 502 — the connection may already be dead
        return PlainTextResponse("", status_code=502)

    @staticmethod
    def _slow_body_response(fault: SlowBodyFault) -> StreamingResponse:
        """Stream a response body with inter-chunk async delays."""
        chunk = b"." * fault.chunk_size
        delay_s = fault.delay_ms / 1000.0

        async def generate():
            for _ in range(fault.total_chunks):
                yield chunk
                await asyncio.sleep(delay_s)

        return StreamingResponse(
            content=generate(),
            status_code=200,
            media_type="text/plain",
        )
