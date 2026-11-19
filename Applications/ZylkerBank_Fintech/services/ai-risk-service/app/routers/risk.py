"""Pre-transaction risk evaluation router."""

from __future__ import annotations

import logging

from fastapi import APIRouter, Depends, Header

from app.auth import verify_internal_token
from app.models.schemas import (
    RiskEvaluationRequest,
    RiskEvaluationResponse,
)
from app.services.risk_engine import RiskEngine

logger = logging.getLogger("risk_router")
router = APIRouter(prefix="/api/v1/risk", tags=["Risk"])


@router.post(
    "/evaluate",
    response_model=RiskEvaluationResponse,
    summary="Evaluate transaction risk score and approval status",
)
async def evaluate_risk(
    request: RiskEvaluationRequest,
    _token: str | None = Depends(verify_internal_token),
    x_correlation_id: str | None = Header(None, alias="X-Correlation-Id"),
) -> RiskEvaluationResponse:
    if not request.correlation_id and x_correlation_id:
        request.correlation_id = x_correlation_id

    engine = RiskEngine()
    result = await engine.evaluate(request)
    logger.info(
        "Risk evaluation from=%s to=%s amount=%s -> score=%d decision=%s",
        request.from_account,
        request.to_account,
        request.amount,
        result.risk_score,
        result.decision,
    )
    return result
