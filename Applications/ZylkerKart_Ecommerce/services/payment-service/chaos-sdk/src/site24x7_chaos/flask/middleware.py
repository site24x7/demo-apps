"""Flask middleware that intercepts requests to inject HTTP faults.

Hooks into Flask via ``before_request`` to evaluate fault rules before the
application handler runs.  Different fault types produce different responses:

* ``http_exception`` — raises the mapped Python exception (Flask error handler
  will catch it).
* ``http_latency`` — sleeps, then continues to the normal handler.
* ``http_error_response`` — returns a plain-text error response directly.
* ``http_connection_reset`` — aborts the underlying socket.
* ``http_slow_body`` — returns a streaming response with inter-chunk delays.
"""

from __future__ import annotations

import logging
import time
from typing import TYPE_CHECKING, Optional

from flask import Response, request, stream_with_context

from ..fault.http import (
    ConnectionResetFault,
    ErrorResponseFault,
    ExceptionFault,
    HttpFaultInjector,
    LatencyFault,
    SlowBodyFault,
)

if TYPE_CHECKING:
    from flask import Flask

    from ..engine import ChaosEngine

logger = logging.getLogger("site24x7_chaos.flask.middleware")


class ChaosFlaskMiddleware:
    """Registers a ``before_request`` hook on the Flask *app* that evaluates
    inbound HTTP fault rules on every request.
    """

    def __init__(self, app: Flask, engine: ChaosEngine) -> None:
        self._app = app
        self._injector = HttpFaultInjector(engine)

        app.before_request(self._before_request)
        logger.info("ChaosFlaskMiddleware registered")

    # ------------------------------------------------------------------
    # Hook
    # ------------------------------------------------------------------

    def _before_request(self) -> Optional[Response]:
        """Evaluate fault rules; return a Response to short-circuit, or None
        to continue to the normal handler."""
        result = self._injector.evaluate(request.path)
        if result is None:
            return None

        # -- Exception: raise it (Flask error handlers will catch) ----------
        if isinstance(result, ExceptionFault):
            raise result.exception

        # -- Latency: already slept, continue normally ----------------------
        if isinstance(result, LatencyFault):
            return None

        # -- Error response: return static error ----------------------------
        if isinstance(result, ErrorResponseFault):
            return Response(
                result.body,
                status=result.status_code,
                content_type="text/plain",
            )

        # -- Connection reset: close the socket abruptly --------------------
        if isinstance(result, ConnectionResetFault):
            return self._abort_connection()

        # -- Slow body: streaming response with delays ----------------------
        if isinstance(result, SlowBodyFault):
            return self._slow_body_response(result)

        return None

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------

    @staticmethod
    def _abort_connection() -> Response:
        """Close the underlying socket to simulate a connection reset.

        We access the werkzeug socket from the WSGI environ dict and shut it
        down.  The client will see a ``ConnectionResetError``.
        """
        try:
            # werkzeug exposes the raw socket via environ
            environ = request.environ
            sock = environ.get("werkzeug.socket") or environ.get("gunicorn.socket")
            if sock is not None:
                import socket

                sock.shutdown(socket.SHUT_RDWR)
                sock.close()
                logger.debug("Connection reset: socket closed")
            else:
                # Fallback: return an empty 502 (not a true reset, but close)
                logger.debug(
                    "Connection reset: no raw socket available, returning 502"
                )
                return Response("", status=502)
        except Exception:
            logger.debug("Connection reset: error closing socket", exc_info=True)
        # Return an empty response — the socket is already dead
        return Response("", status=502)

    @staticmethod
    def _slow_body_response(fault: SlowBodyFault) -> Response:
        """Return a streaming response that writes chunks with delays."""
        chunk = b"." * fault.chunk_size
        delay_s = fault.delay_ms / 1000.0

        @stream_with_context
        def generate():
            for _ in range(fault.total_chunks):
                yield chunk
                time.sleep(delay_s)

        return Response(
            generate(),
            status=200,
            content_type="text/plain",
        )
