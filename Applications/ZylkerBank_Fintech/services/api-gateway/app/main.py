"""FastAPI entrypoint for ZylkerBank API Gateway."""

import logging
from contextlib import asynccontextmanager
from typing import AsyncIterator
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware

from app.config import get_settings
from app.health import router as health_router
from app.proxy import close_http_client, proxy_request

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] [%(name)s] %(message)s",
)
logger = logging.getLogger("api-gateway")


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    settings = get_settings()
    logger.info("Starting ZylkerBank API Gateway on port %d...", settings.port)
    yield
    # Cleanup connections
    await close_http_client()
    logger.info("API Gateway stopped.")


app = FastAPI(
    title="ZylkerBank API Gateway",
    description="Edge Reverse Proxy, Route Multiplexer & Resilience Fault Hub for ZylkerBank",
    version="1.0.0",
    lifespan=lifespan,
)

settings = get_settings()

# 1. Initialize Site24x7 Chaos SDK (before middleware freezing)
if settings.chaos_enabled:
    try:
        from site24x7_chaos.fastapi import init_chaos

        init_chaos(
            app,
            app_name=settings.chaos_app_name,
            config_dir=settings.chaos_config_dir,
            enabled=True,
        )
        logger.info(
            "Site24x7 Chaos SDK initialized app_name=%s config_dir=%s",
            settings.chaos_app_name,
            settings.chaos_config_dir,
        )
    except Exception as exc:
        logger.warning("Chaos SDK could not be initialized (continuing): %s", exc)

# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Health & introspection routes
app.include_router(health_router)


# Catch-all reverse proxy route for all API and web traffic
@app.api_route(
    "/{path:path}",
    methods=["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"],
    include_in_schema=False,
)
async def catch_all_proxy(request: Request, path: str):
    return await proxy_request(request, path)
