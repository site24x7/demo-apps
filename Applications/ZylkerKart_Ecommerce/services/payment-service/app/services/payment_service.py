import uuid
import random
import logging
import time
from datetime import datetime
from typing import Optional

from app.config.database import get_connection
from app.models.payment import (
    PaymentRequest,
    PaymentResponse,
    PaymentStatus,
    RefundRequest,
)

logger = logging.getLogger(__name__)


def calculate_fraud_score(req: PaymentRequest) -> float:
    """Mock fraud scoring - returns 0.0 (safe) to 1.0 (fraud)"""
    score = 0.0

    # Large amounts are suspicious
    if req.amount > 50000:
        score += 0.3
    elif req.amount > 20000:
        score += 0.15

    # COD has higher risk
    if req.method.value == "cod":
        score += 0.1

    # Random jitter for demo purposes
    score += random.uniform(0, 0.2)

    return min(round(score, 2), 1.0)


def process_payment(req: PaymentRequest) -> PaymentResponse:
    """Process a payment with mock gateway"""
    transaction_ref = f"TXN-{uuid.uuid4().hex[:12].upper()}"
    fraud_score = calculate_fraud_score(req)

    # Reject if fraud score too high
    if fraud_score > 0.7:
        status = PaymentStatus.FAILED
        message = "Payment declined: high fraud risk"
    else:
        # Simulate ~5% random failure rate
        if random.random() < 0.05:
            status = PaymentStatus.FAILED
            message = "Payment gateway timeout"
        else:
            status = PaymentStatus.SUCCESS
            message = "Payment processed successfully"

    # Simulate processing delay (100-500ms)
    time.sleep(random.uniform(0.1, 0.5))

    # Save to database
    conn = get_connection()
    try:
        cursor = conn.cursor()
        cursor.execute(
            """INSERT INTO transactions 
               (transaction_ref, order_id, user_id, amount, currency, method, 
                status, fraud_score, created_at) 
               VALUES (%s, %s, %s, %s, %s, %s, %s, %s, NOW())""",
            (
                transaction_ref,
                req.order_id,
                req.user_id,
                req.amount,
                req.currency,
                req.method.value,
                status.value,
                fraud_score,
            ),
        )
        conn.commit()
        logger.info(
            f"Payment {transaction_ref}: {status.value} (fraud_score={fraud_score})"
        )
    except Exception as e:
        conn.rollback()
        logger.error(f"Failed to save transaction: {e}")
        raise
    finally:
        cursor.close()
        conn.close()

    return PaymentResponse(
        transaction_ref=transaction_ref,
        order_id=req.order_id,
        user_id=req.user_id,
        amount=req.amount,
        currency=req.currency,
        method=req.method.value,
        status=status,
        fraud_score=fraud_score,
        message=message,
        created_at=datetime.now().isoformat(),
    )


def get_transaction(transaction_ref: str) -> Optional[dict]:
    """Get transaction by ref"""
    conn = get_connection()
    try:
        cursor = conn.cursor(dictionary=True)
        cursor.execute(
            "SELECT * FROM transactions WHERE transaction_ref = %s", (transaction_ref,)
        )
        row = cursor.fetchone()
        if row:
            for key in row:
                if isinstance(row[key], datetime):
                    row[key] = row[key].isoformat()
        return row
    finally:
        cursor.close()
        conn.close()


def get_transactions_by_order(order_id: int) -> list:
    """Get all transactions for an order"""
    conn = get_connection()
    try:
        cursor = conn.cursor(dictionary=True)
        cursor.execute(
            "SELECT * FROM transactions WHERE order_id = %s ORDER BY created_at DESC",
            (order_id,),
        )
        rows = cursor.fetchall()
        for row in rows:
            for key in row:
                if isinstance(row[key], datetime):
                    row[key] = row[key].isoformat()
        return rows
    finally:
        cursor.close()
        conn.close()


def process_refund(req: RefundRequest) -> dict:
    """Process a refund"""
    conn = get_connection()
    try:
        cursor = conn.cursor(dictionary=True)
        cursor.execute(
            "SELECT * FROM transactions WHERE transaction_ref = %s", (req.transaction_ref,)
        )
        txn = cursor.fetchone()

        if not txn:
            return {"error": f"Transaction {req.transaction_ref} not found"}

        if txn["status"] != "success":
            return {"error": f"Cannot refund transaction with status: {txn['status']}"}

        refund_amount = req.amount if req.amount else txn["amount"]
        if refund_amount > float(txn["amount"]):
            return {"error": "Refund amount exceeds transaction amount"}

        # Create refund transaction
        refund_id = f"RFD-{uuid.uuid4().hex[:12].upper()}"
        cursor.execute(
            """INSERT INTO transactions 
               (transaction_ref, order_id, user_id, amount, currency, method, 
                status, fraud_score, created_at) 
               VALUES (%s, %s, %s, %s, %s, %s, 'refunded', 0, NOW())""",
            (
                refund_id,
                txn["order_id"],
                txn["user_id"],
                -refund_amount,
                txn["currency"],
                txn["method"],
            ),
        )

        # Update original transaction
        cursor.execute(
            "UPDATE transactions SET status = 'refunded' WHERE transaction_ref = %s",
            (req.transaction_ref,),
        )
        conn.commit()

        return {
            "refund_id": refund_id,
            "original_transaction": req.transaction_ref,
            "refund_amount": refund_amount,
            "status": "refunded",
            "reason": req.reason,
        }
    except Exception as e:
        conn.rollback()
        raise
    finally:
        cursor.close()
        conn.close()
