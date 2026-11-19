"""Reverse proxy implementation for routing traffic to backend microservices."""

import logging
from typing import AsyncIterator
import httpx
from fastapi import Request, Response
from fastapi.responses import JSONResponse, StreamingResponse

from app.config import get_settings

logger = logging.getLogger("proxy")

# Standard HTTP hop-by-hop headers to exclude from proxy forwarding
HOP_BY_HOP_HEADERS = {
    "connection",
    "keep-alive",
    "proxy-authenticate",
    "proxy-authorization",
    "te",
    "trailers",
    "transfer-encoding",
    "upgrade",
}

_client: httpx.AsyncClient | None = None


def get_http_client() -> httpx.AsyncClient:
    global _client
    if _client is None or _client.is_closed:
        _client = httpx.AsyncClient(
            timeout=httpx.Timeout(30.0, connect=5.0),
            follow_redirects=False,
            limits=httpx.Limits(max_keepalive_connections=50, max_connections=200),
        )
    return _client


async def close_http_client() -> None:
    global _client
    if _client and not _client.is_closed:
        await _client.aclose()
        _client = None


def resolve_target(path: str) -> tuple[str, str]:
    """Resolve backend service URL and service name based on request path."""
    settings = get_settings()

    # 1. Ledger Service (Go / Port 8081)
    if (
        path.startswith("/api/v1/ledger")
        or path.startswith("/api/v1/accounts")
        or path.startswith("/api/v1/auth")
        or path.startswith("/api/v1/users")
    ):
        return settings.ledger_url, "ledger-service"

    # 2. Financial Gateway (Node / Port 8082)
    if (
        path.startswith("/api/v1/transfers")
        or path.startswith("/api/v1/cards")
        or path.startswith("/api/v1/payment-requests")
    ):
        return settings.gateway_url, "financial-gateway"

    # 3. AI & Risk Service (Python / Port 8083)
    if (
        path.startswith("/api/v1/risk")
        or path.startswith("/api/v1/audit")
        or path.startswith("/api/v1/chat")
    ):
        return settings.ai_url, "ai-risk-service"

    # 4. Default: Banking Portal & BFF (Java / Port 8080)
    # Includes web UI pages (/, /dashboard, /account, /transactions), static assets, and BFF APIs
    return settings.portal_url, "banking-portal"


async def proxy_request(request: Request, path: str) -> Response:
    """Forward an incoming request to the target microservice and stream the response."""
    base_url, service_name = resolve_target("/" + path.lstrip("/"))
    target_url = f"{base_url}/{path.lstrip('/')}"
    if request.url.query:
        target_url = f"{target_url}?{request.url.query}"

    client = get_http_client()

    # Filter incoming headers
    headers = {}
    for key, val in request.headers.items():
        if key.lower() not in HOP_BY_HOP_HEADERS and key.lower() != "host":
            headers[key] = val

    # Forward or inject Correlation ID
    correlation_id = headers.get("x-correlation-id")
    if not correlation_id:
        import uuid
        correlation_id = str(uuid.uuid4())
        headers["x-correlation-id"] = correlation_id

    body = await request.body()

    try:
        req = client.build_request(
            method=request.method,
            url=target_url,
            headers=headers,
            content=body,
        )
        res = await client.send(req, stream=True)

        # Prepare response headers
        res_headers = {}
        for key, val in res.headers.items():
            if key.lower() not in HOP_BY_HOP_HEADERS and key.lower() != "content-length":
                res_headers[key] = val

        async def body_stream() -> AsyncIterator[bytes]:
            try:
                async for chunk in res.aiter_raw():
                    yield chunk
            finally:
                await res.aclose()

        return StreamingResponse(
            body_stream(),
            status_code=res.status_code,
            headers=res_headers,
            media_type=res.headers.get("content-type"),
        )

    except httpx.ConnectError as exc:
        logger.error("Failed to connect to %s (%s): %s", service_name, target_url, exc)
        return JSONResponse(
            status_code=502,
            content={
                "error": "BAD_GATEWAY",
                "message": f"Target service '{service_name}' is unreachable",
                "target": base_url,
            },
        )
    except httpx.TimeoutException as exc:
        logger.error("Gateway timeout connecting to %s (%s): %s", service_name, target_url, exc)
        return JSONResponse(
            status_code=504,
            content={
                "error": "GATEWAY_TIMEOUT",
                "message": f"Target service '{service_name}' timed out",
                "target": base_url,
            },
        )
    except Exception as exc:
        logger.exception("Unexpected proxy error forwarding to %s: %s", service_name, exc)
        return JSONResponse(
            status_code=500,
            content={
                "error": "INTERNAL_GATEWAY_ERROR",
                "message": f"Error proxying request to '{service_name}': {str(exc)}",
            },
        )
