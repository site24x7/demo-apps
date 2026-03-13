from pydantic import BaseModel, Field
from typing import Optional
from datetime import datetime
from enum import Enum


class PaymentStatus(str, Enum):
    PENDING = "pending"
    PROCESSING = "processing"
    SUCCESS = "success"
    FAILED = "failed"
    REFUNDED = "refunded"


class PaymentMethod(str, Enum):
    CREDIT_CARD = "credit_card"
    DEBIT_CARD = "debit_card"
    UPI = "upi"
    WALLET = "wallet"
    COD = "cod"


class PaymentRequest(BaseModel):
    order_id: int = Field(..., gt=0)
    user_id: Optional[int] = None
    amount: float = Field(..., gt=0)
    currency: str = Field(default="USD", max_length=3)
    method: PaymentMethod
    upi_id: Optional[str] = None


class PaymentResponse(BaseModel):
    transaction_ref: str
    order_id: int
    user_id: Optional[int] = None
    amount: float
    currency: str
    method: str
    status: PaymentStatus
    fraud_score: float
    message: str
    created_at: Optional[str] = None


class RefundRequest(BaseModel):
    transaction_ref: str
    reason: str = Field(default="customer_request")
    amount: Optional[float] = None  # Partial refund
