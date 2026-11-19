"""Tests for fraud & risk evaluation engine and endpoint."""

from datetime import datetime, timezone
from decimal import Decimal

import pytest
from httpx import AsyncClient

from app.models.schemas import RiskEvaluationRequest
from app.services.risk_engine import RiskEngine, record_completed_transfer_in_memory


@pytest.mark.asyncio
async def test_risk_clean_transfer():
    """Transfer with prior history, small amount, daytime hours -> APPROVED (score 0)."""
    engine = RiskEngine()
    record_completed_transfer_in_memory("2170000001", "2170000002")

    req = RiskEvaluationRequest(
        from_account="2170000001",
        to_account="2170000002",
        amount=Decimal("150.00"),
        timestamp=datetime(2026, 11, 18, 14, 0, 0, tzinfo=timezone.utc),  # 14:00 UTC (daytime)
    )
    res = await engine.evaluate(req)
    assert res.risk_score == 0
    assert res.decision == "APPROVED"
    assert len(res.reasons) == 0


@pytest.mark.asyncio
async def test_risk_first_time_beneficiary():
    """No prior transfer -> +15 points -> APPROVED (<30)."""
    engine = RiskEngine()
    req = RiskEvaluationRequest(
        from_account="2170000001",
        to_account="2170000099",
        amount=Decimal("100.00"),
        timestamp=datetime(2026, 11, 18, 12, 0, 0, tzinfo=timezone.utc),
    )
    res = await engine.evaluate(req)
    assert res.risk_score == 15
    assert res.decision == "APPROVED"
    assert any(r.rule == "first_time_beneficiary" for r in res.reasons)


@pytest.mark.asyncio
async def test_risk_high_amount():
    """Amount > 2000 -> +30 points -> FLAGGED_FOR_REVIEW (>=30)."""
    engine = RiskEngine()
    record_completed_transfer_in_memory("2170000001", "2170000002")

    req = RiskEvaluationRequest(
        from_account="2170000001",
        to_account="2170000002",
        amount=Decimal("2500.00"),
        timestamp=datetime(2026, 11, 18, 12, 0, 0, tzinfo=timezone.utc),
    )
    res = await engine.evaluate(req)
    assert res.risk_score == 30
    assert res.decision == "FLAGGED_FOR_REVIEW"
    assert any(r.rule == "amount_exceeds_2000" for r in res.reasons)


@pytest.mark.asyncio
async def test_risk_very_high_amount():
    """Amount > 5000 -> +30 (for >2000) and +30 (for >5000) = 60 points -> FLAGGED_FOR_REVIEW."""
    engine = RiskEngine()
    record_completed_transfer_in_memory("2170000001", "2170000002")

    req = RiskEvaluationRequest(
        from_account="2170000001",
        to_account="2170000002",
        amount=Decimal("6000.00"),
        timestamp=datetime(2026, 11, 18, 12, 0, 0, tzinfo=timezone.utc),
    )
    res = await engine.evaluate(req)
    assert res.risk_score == 60
    assert res.decision == "FLAGGED_FOR_REVIEW"
    rules = [r.rule for r in res.reasons]
    assert "amount_exceeds_2000" in rules
    assert "amount_exceeds_5000" in rules


@pytest.mark.asyncio
async def test_risk_hour_anomaly():
    """Hour 02:30 UTC with amount > 500 -> +25 points."""
    engine = RiskEngine()
    record_completed_transfer_in_memory("2170000001", "2170000002")

    # 02:30 UTC
    req = RiskEvaluationRequest(
        from_account="2170000001",
        to_account="2170000002",
        amount=Decimal("750.00"),
        timestamp=datetime(2026, 11, 18, 2, 30, 0, tzinfo=timezone.utc),
    )
    res = await engine.evaluate(req)
    assert res.risk_score == 25
    assert res.decision == "APPROVED"
    assert any(r.rule == "hour_anomaly" for r in res.reasons)


@pytest.mark.asyncio
async def test_risk_blocked_combination():
    """Amount > 5000 (+60) + first-time (+15) -> score 75 -> BLOCKED (>=70)."""
    engine = RiskEngine()
    # No prior completed transfer
    req = RiskEvaluationRequest(
        from_account="2170000001",
        to_account="2170000099",
        amount=Decimal("5500.00"),
        timestamp=datetime(2026, 11, 18, 15, 0, 0, tzinfo=timezone.utc),
    )
    res = await engine.evaluate(req)
    assert res.risk_score == 75
    assert res.decision == "BLOCKED"


@pytest.mark.asyncio
async def test_risk_velocity_thresholds():
    """Test velocity rule: 3 evaluations -> +30, 6 evaluations -> +60."""
    engine = RiskEngine()
    record_completed_transfer_in_memory("2170000001", "2170000002")

    now = datetime(2026, 11, 18, 12, 0, 0, tzinfo=timezone.utc)

    # Perform 2 evaluations (count < 3)
    for _ in range(2):
        await engine.evaluate(
            RiskEvaluationRequest(
                from_account="2170000001",
                to_account="2170000002",
                amount=Decimal("100.00"),
                timestamp=now,
            )
        )

    # 3rd evaluation: previous count is 2 (<3) -> velocity not triggered
    res3 = await engine.evaluate(
        RiskEvaluationRequest(
            from_account="2170000001",
            to_account="2170000002",
            amount=Decimal("100.00"),
            timestamp=now,
        )
    )
    assert not any(r.rule.startswith("velocity") for r in res3.reasons)

    # 4th evaluation: previous count is 3 (>=3) -> velocity_moderate (+30)
    res4 = await engine.evaluate(
        RiskEvaluationRequest(
            from_account="2170000001",
            to_account="2170000002",
            amount=Decimal("100.00"),
            timestamp=now,
        )
    )
    assert res4.risk_score == 30
    assert any(r.rule == "velocity_moderate" for r in res4.reasons)

    # Add 2 more to reach 6 previous evaluations
    await engine.evaluate(
        RiskEvaluationRequest(
            from_account="2170000001",
            to_account="2170000002",
            amount=Decimal("100.00"),
            timestamp=now,
        )
    )
    await engine.evaluate(
        RiskEvaluationRequest(
            from_account="2170000001",
            to_account="2170000002",
            amount=Decimal("100.00"),
            timestamp=now,
        )
    )

    # 7th evaluation: previous count is 6 (>=6) -> velocity_high (+60)
    res7 = await engine.evaluate(
        RiskEvaluationRequest(
            from_account="2170000001",
            to_account="2170000002",
            amount=Decimal("100.00"),
            timestamp=now,
        )
    )
    assert res7.risk_score == 60
    assert any(r.rule == "velocity_high" for r in res7.reasons)


@pytest.mark.asyncio
async def test_risk_evaluate_endpoint(client: AsyncClient):
    """Test POST /api/v1/risk/evaluate endpoint."""
    payload = {
        "from_account": "2170000001",
        "to_account": "2170000002",
        "amount": "3500.00",
    }
    resp = await client.post("/api/v1/risk/evaluate", json=payload)
    assert resp.status_code == 200
    data = resp.json()
    assert "risk_score" in data
    assert "decision" in data
    assert "reasons" in data
    assert "evaluated_at" in data
    assert data["decision"] in ("APPROVED", "FLAGGED_FOR_REVIEW", "BLOCKED")
