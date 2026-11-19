"""FastAPI entrypoint for ZylkerBank AI & Risk Intelligence Service."""

from __future__ import annotations

import asyncio
import logging
import uuid
from contextlib import asynccontextmanager
from typing import AsyncIterator

from fastapi import FastAPI, HTTPException, Request, Response, status
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app.config import get_settings
from app.db import get_db
from app.instrumentation import init_tracing
from app.logging_config import (
    correlation_id_var,
    setup_logging,
    traceparent_var,
    tracestate_var,
)
from app.routers import audit, chat, health, risk
from app.services.kafka_consumer import get_kafka_consumer

logger = logging.getLogger("main")


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    settings = get_settings()
    setup_logging(
        level=settings.log_level,
        fmt=settings.log_format,
        service=settings.service_name,
    )
    logger.info("Starting %s on port %d...", settings.service_name, settings.port)

    # 1. Initialize Traceloop OTLP tracing
    init_tracing()

    # 2. Database connection background task
    db = get_db(settings)
    db_stop_event = asyncio.Event()
    db_task = asyncio.create_task(db.connect_with_retry(stop=db_stop_event))

    # 3. Kafka consumer background task
    kafka = get_kafka_consumer(settings)
    kafka.start()

    logger.info("%s initialized successfully", settings.service_name)
    try:
        yield
    finally:
        logger.info("Shutting down %s...", settings.service_name)
        db_stop_event.set()
        db_task.cancel()
        try:
            await asyncio.wait_for(db_task, timeout=2.0)
        except (asyncio.TimeoutError, asyncio.CancelledError):
            pass

        await kafka.stop()
        await db.close()
        logger.info("%s shutdown complete", settings.service_name)


app = FastAPI(
    title="ZylkerBank AI & Risk Service",
    description="Conversational Banking Assistant & Pre-Transaction Fraud Risk Engine",
    version="1.0.0",
    lifespan=lifespan,
)

settings = get_settings()

# ── Site24x7 Chaos SDK ──────────────────────────────────────────────────────
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

# ── CORS Middleware ─────────────────────────────────────────────────────────
app.add_middleware(
    CORSMiddleware,
    allow_origins=list(settings.cors_origins),
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ── Correlation & W3C Traceparent Middleware ─────────────────────────────────
@app.middleware("http")
async def context_propagation_middleware(request: Request, call_next: Any) -> Response:
    # Correlation ID
    cid = request.headers.get("x-correlation-id") or str(uuid.uuid4())
    correlation_id_var.set(cid)

    # W3C Trace Context
    tp = request.headers.get("traceparent")
    if tp:
        traceparent_var.set(tp)
    ts = request.headers.get("tracestate")
    if ts:
        tracestate_var.set(ts)

    response: Response = await call_next(request)
    response.headers["X-Correlation-Id"] = cid
    return response


# ── Exception Handlers (Consistent Error Envelope) ───────────────────────────
@app.exception_handler(HTTPException)
async def http_exception_handler(_request: Request, exc: HTTPException) -> JSONResponse:
    if isinstance(exc.detail, dict) and "error" in exc.detail:
        payload = exc.detail
    else:
        payload = {
            "error": "HTTP_ERROR",
            "message": str(exc.detail),
        }
    return JSONResponse(status_code=exc.status_code, content=payload)


@app.exception_handler(RequestValidationError)
async def validation_exception_handler(_request: Request, exc: RequestValidationError) -> JSONResponse:
    error_msg = "; ".join(
        f"{'.'.join(str(l) for l in err.get('loc', []))}: {err.get('msg')}"
        for err in exc.errors()
    )
    return JSONResponse(
        status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
        content={"error": "VALIDATION_ERROR", "message": error_msg},
    )


@app.exception_handler(Exception)
async def unhandled_exception_handler(_request: Request, exc: Exception) -> JSONResponse:
    logger.exception("Unhandled server error: %s", exc)
    return JSONResponse(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        content={"error": "INTERNAL_SERVER_ERROR", "message": str(exc)},
    )


# ── Include Routers ─────────────────────────────────────────────────────────
app.include_router(health.router)
app.include_router(risk.router)
app.include_router(chat.router)
app.include_router(audit.router)


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        "app.main:app",
        host="0.0.0.0",
        port=settings.port,
        reload=False,
    )
