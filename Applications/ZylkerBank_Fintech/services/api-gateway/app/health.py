"""Health check and service status endpoints for API Gateway."""

import asyncio
from datetime import datetime, timezone
import httpx
from fastapi import APIRouter
from fastapi.responses import JSONResponse

from app.config import get_settings

router = APIRouter()


async def check_service(client: httpx.AsyncClient, name: str, base_url: str) -> dict:
    url = f"{base_url}/health"
    try:
        res = await client.get(url, timeout=3.0)
        return {
            "status": "UP" if res.status_code == 200 else "DEGRADED",
            "status_code": res.status_code,
            "url": url,
        }
    except Exception as exc:
        return {
            "status": "DOWN",
            "error": str(exc),
            "url": url,
        }


@router.get("/health")
async def health_check():
    settings = get_settings()
    async with httpx.AsyncClient() as client:
        results = await asyncio.gather(
            check_service(client, "banking-portal", settings.portal_url),
            check_service(client, "ledger-service", settings.ledger_url),
            check_service(client, "financial-gateway", settings.gateway_url),
            check_service(client, "ai-risk-service", settings.ai_url),
            return_exceptions=True,
        )

    services_status = {
        "banking-portal": results[0] if isinstance(results[0], dict) else {"status": "ERROR"},
        "ledger-service": results[1] if isinstance(results[1], dict) else {"status": "ERROR"},
        "financial-gateway": results[2] if isinstance(results[2], dict) else {"status": "ERROR"},
        "ai-risk-service": results[3] if isinstance(results[3], dict) else {"status": "ERROR"},
    }

    return JSONResponse(
        status_code=200,
        content={
            "status": "UP",
            "service": settings.service_name,
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "downstream": services_status,
        },
    )


@router.get("/api/v1/routes")
async def list_routes():
    settings = get_settings()
    return {
        "gateway": settings.service_name,
        "routes": [
            {
                "pattern": "/api/v1/ledger/**, /api/v1/accounts/**, /api/v1/auth/**, /api/v1/users/**",
                "target": settings.ledger_url,
                "service": "ledger-service",
            },
            {
                "pattern": "/api/v1/transfers/**, /api/v1/cards/**, /api/v1/payment-requests/**",
                "target": settings.gateway_url,
                "service": "financial-gateway",
            },
            {
                "pattern": "/api/v1/risk/**, /api/v1/audit/**, /api/v1/chat/**",
                "target": settings.ai_url,
                "service": "ai-risk-service",
            },
            {
                "pattern": "/** (Web pages, assets, and BFF endpoints)",
                "target": settings.portal_url,
                "service": "banking-portal",
            },
        ],
    }
