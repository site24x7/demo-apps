import os
import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.routers import payment
from app.config.database import get_pool

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup: initialize DB pool
    logger.info("Payment Service starting up...")
    get_pool()
    yield
    # Shutdown
    logger.info("Payment Service shutting down...")


app = FastAPI(
    title="ZylkerKart Payment Service",
    description="Mock payment processing with fraud scoring",
    version="1.0.0",
    lifespan=lifespan,
)

# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Site24x7 Labs Chaos SDK
try:
    from site24x7_chaos.fastapi import init_chaos

    init_chaos(
        app,
        app_name=os.getenv("CHAOS_SDK_APP_NAME", "payment-service"),
        config_dir=os.getenv("CHAOS_SDK_CONFIG_DIR", "/var/site24x7-labs/faults"),
        enabled=os.getenv("CHAOS_SDK_ENABLED", "true").lower() != "false",
    )
except Exception as e:
    logger.warning("Failed to initialize Chaos SDK: %s", e)


# Routes
app.include_router(payment.router)


@app.get("/health")
async def health():
    db_status = "UP"
    try:
        conn = get_pool().get_connection()
        conn.ping(reconnect=True)
        conn.close()
    except Exception as e:
        db_status = f"DOWN: {e}"

    status = "UP" if db_status == "UP" else "DEGRADED"
    return {
        "service": "payment-service",
        "status": status,
        "checks": {"mysql": {"status": db_status}},
    }


if __name__ == "__main__":
    import uvicorn

    port = int(os.getenv("PORT", "8084"))
    logger.info(f"💳 Payment Service running on port {port}")
    uvicorn.run(app, host="0.0.0.0", port=port)
