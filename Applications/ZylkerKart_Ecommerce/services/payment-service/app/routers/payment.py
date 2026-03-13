from fastapi import APIRouter, HTTPException
from app.models.payment import PaymentRequest, RefundRequest
from app.services.payment_service import (
    process_payment,
    get_transaction,
    get_transactions_by_order,
    process_refund,
)

router = APIRouter(prefix="/payments", tags=["payments"])


@router.post("/process")
async def create_payment(req: PaymentRequest):
    """Process a new payment"""
    try:
        result = process_payment(req)
        status_code = 200 if result.status == "success" else 402
        return result
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/{transaction_ref}")
async def get_payment(transaction_ref: str):
    """Get transaction details"""
    txn = get_transaction(transaction_ref)
    if not txn:
        raise HTTPException(status_code=404, detail="Transaction not found")
    return txn


@router.get("/order/{order_id}")
async def get_order_payments(order_id: int):
    """Get all transactions for an order"""
    return get_transactions_by_order(order_id)


@router.post("/refund")
async def refund_payment(req: RefundRequest):
    """Process a refund"""
    result = process_refund(req)
    if "error" in result:
        raise HTTPException(status_code=400, detail=result["error"])
    return result
