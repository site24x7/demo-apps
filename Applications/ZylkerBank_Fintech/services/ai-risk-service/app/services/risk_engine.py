"""Pre-transaction fraud & risk intelligence engine."""

from __future__ import annotations

import logging
from collections import deque
from datetime import datetime, time, timedelta, timezone
from decimal import Decimal
from typing import Any
from zoneinfo import ZoneInfo

from app.config import Settings, get_settings
from app.db import Database, DatabaseUnavailable, get_db
from app.models.schemas import (
    RiskEvaluationRequest,
    RiskEvaluationResponse,
    RiskReason,
)

logger = logging.getLogger("risk_engine")

# In-memory fallbacks for velocity & transfer history (works standalone without Postgres)
_in_memory_evaluations: deque[dict[str, Any]] = deque(maxlen=1000)
_in_memory_completed_transfers: set[tuple[str, str]] = set()


def record_completed_transfer_in_memory(from_account: str, to_account: str) -> None:
    _in_memory_completed_transfers.add((from_account, to_account))


def clear_in_memory_risk_state() -> None:
    _in_memory_evaluations.clear()
    _in_memory_completed_transfers.clear()


class RiskEngine:
    def __init__(self, db: Database | None = None, settings: Settings | None = None) -> None:
        self.settings = settings or get_settings()
        self.db = db or get_db(self.settings)

    async def _get_velocity_count(self, from_account: str, eval_dt: datetime) -> int:
        cutoff = eval_dt - timedelta(seconds=60)
        try:
            val = await self.db.fetchval(
                """
                SELECT COUNT(*) FROM risk_evaluations
                WHERE from_account = $1 AND created_at >= $2
                """,
                from_account,
                cutoff,
            )
            return int(val or 0)
        except (DatabaseUnavailable, Exception) as exc:
            logger.debug("Database velocity check failed (%s), using in-memory tracker", exc)
            # Count in-memory evaluations from same account in last 60s
            return sum(
                1
                for ev in _in_memory_evaluations
                if ev["from_account"] == from_account and ev["created_at"] >= cutoff
            )

    async def _has_prior_completed_transfers(
        self, from_account: str, to_account: str
    ) -> bool:
        if (from_account, to_account) in _in_memory_completed_transfers:
            return True
        try:
            row = await self.db.fetchrow(
                """
                SELECT 1 FROM audit_events
                WHERE event_type = 'TransferCompleted'
                  AND (
                    (payload->>'from_account' = $1 AND payload->>'to_account' = $2)
                    OR
                    (payload->'data'->>'from_account' = $1 AND payload->'data'->>'to_account' = $2)
                  )
                LIMIT 1
                """,
                from_account,
                to_account,
            )
            return row is not None
        except (DatabaseUnavailable, Exception) as exc:
            logger.debug("Database audit check failed (%s), checking in-memory set", exc)
            return (from_account, to_account) in _in_memory_completed_transfers

    async def evaluate(self, req: RiskEvaluationRequest) -> RiskEvaluationResponse:
        # Determine evaluation timestamp
        if req.timestamp is not None:
            eval_dt = req.timestamp
            if eval_dt.tzinfo is None:
                eval_dt = eval_dt.replace(tzinfo=timezone.utc)
        else:
            eval_dt = datetime.now(timezone.utc)

        amount = Decimal(str(req.amount))
        reasons: list[RiskReason] = []

        # ── Rule 1: Velocity in last 60s (≥3 → +30, ≥6 → +60) ───────────────
        velocity_count = await self._get_velocity_count(req.from_account, eval_dt)
        if velocity_count >= 6:
            reasons.append(
                RiskReason(
                    rule="velocity_high",
                    points=60,
                    detail=f"High velocity: {velocity_count} evaluations from account {req.from_account} in last 60s (+60)",
                )
            )
        elif velocity_count >= 3:
            reasons.append(
                RiskReason(
                    rule="velocity_moderate",
                    points=30,
                    detail=f"Moderate velocity: {velocity_count} evaluations from account {req.from_account} in last 60s (+30)",
                )
            )

        # ── Rule 2: High Amount (>2000 +30, >5000 +30 more) ─────────────────
        if amount > Decimal("2000.00"):
            reasons.append(
                RiskReason(
                    rule="amount_exceeds_2000",
                    points=30,
                    detail=f"Transfer amount ${amount:,.2f} exceeds threshold $2,000.00 (+30)",
                )
            )
        if amount > Decimal("5000.00"):
            reasons.append(
                RiskReason(
                    rule="amount_exceeds_5000",
                    points=30,
                    detail=f"Transfer amount ${amount:,.2f} exceeds high-risk threshold $5,000.00 (+30 more)",
                )
            )

        # ── Rule 3: First-time Beneficiary (+15) ─────────────────────────────
        has_prior = await self._has_prior_completed_transfers(req.from_account, req.to_account)
        if not has_prior:
            reasons.append(
                RiskReason(
                    rule="first_time_beneficiary",
                    points=15,
                    detail=f"First-time beneficiary: no prior completed transfers between {req.from_account} and {req.to_account} (+15)",
                )
            )

        # ── Rule 4: Hour Anomaly 01:00-04:00 with amount > 500 (+25) ────────
        try:
            tz = ZoneInfo(self.settings.risk_timezone)
        except Exception:
            tz = timezone.utc

        local_dt = eval_dt.astimezone(tz)
        local_time = local_dt.time()
        # 01:00:00 to 04:00:00 inclusive
        is_hour_window = time(1, 0, 0) <= local_time <= time(4, 0, 0)
        if is_hour_window and amount > Decimal("500.00"):
            reasons.append(
                RiskReason(
                    rule="hour_anomaly",
                    points=25,
                    detail=(
                        f"Transfer initiated during high-risk window "
                        f"({local_dt.strftime('%H:%M:%S')} {self.settings.risk_timezone}) "
                        f"with amount ${amount:,.2f} > $500.00 (+25)"
                    ),
                )
            )

        # ── Decision Logic ──────────────────────────────────────────────────
        total_points = sum(r.points for r in reasons)
        risk_score = min(100, max(0, total_points))

        if risk_score >= 70:
            decision = "BLOCKED"
        elif risk_score >= 30:
            decision = "FLAGGED_FOR_REVIEW"
        else:
            decision = "APPROVED"

        # ── Record in memory ────────────────────────────────────────────────
        eval_record = {
            "from_account": req.from_account,
            "to_account": req.to_account,
            "amount": float(amount),
            "risk_score": risk_score,
            "decision": decision,
            "reasons": [r.model_dump() for r in reasons],
            "correlation_id": req.correlation_id,
            "created_at": eval_dt,
        }
        _in_memory_evaluations.append(eval_record)

        # ── Persist to PostgreSQL risk_evaluations table ──────────────────────
        try:
            await self.db.execute(
                """
                INSERT INTO risk_evaluations (
                    from_account, to_account, amount, risk_score, decision, reasons, correlation_id, created_at
                )
                VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
                """,
                req.from_account,
                req.to_account,
                amount,
                risk_score,
                decision,
                [r.model_dump() for r in reasons],
                req.correlation_id,
                eval_dt,
            )
        except (DatabaseUnavailable, Exception) as exc:
            logger.warning("Could not persist risk evaluation to PostgreSQL: %s", exc)

        return RiskEvaluationResponse(
            risk_score=risk_score,
            decision=decision,
            reasons=reasons,
            evaluated_at=eval_dt,
        )
