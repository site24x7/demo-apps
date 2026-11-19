"""JWT and internal token authentication."""

from __future__ import annotations

import hmac
import logging
import time
from typing import Any

import jwt
from fastapi import Header, HTTPException, status
from pydantic import BaseModel

from app.config import get_settings

logger = logging.getLogger("auth")


class AuthenticatedUser(BaseModel):
    user_id: str
    email: str = ""
    name: str = ""
    account_number: str = ""
    raw_token: str = ""


def create_access_token(
    user_id: str,
    email: str = "",
    name: str = "",
    account_number: str = "",
    expires_in: int = 86400,
) -> str:
    settings = get_settings()
    now = int(time.time())
    payload = {
        "sub": user_id,
        "email": email,
        "name": name,
        "account_number": account_number,
        "iat": now,
        "exp": now + expires_in,
    }
    return jwt.encode(payload, settings.jwt_secret, algorithm="HS256")


def decode_access_token(token: str) -> dict[str, Any]:
    settings = get_settings()
    try:
        return jwt.decode(
            token,
            settings.jwt_secret,
            algorithms=["HS256"],
            options={"require": ["sub", "exp"]},
        )
    except jwt.ExpiredSignatureError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"error": "TOKEN_EXPIRED", "message": "JWT token has expired"},
        ) from exc
    except jwt.PyJWTError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"error": "INVALID_TOKEN", "message": f"Invalid JWT token: {exc}"},
        ) from exc


async def get_current_user(
    authorization: str | None = Header(None, alias="Authorization"),
) -> AuthenticatedUser:
    if not authorization or not authorization.strip():
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"error": "UNAUTHORIZED", "message": "Missing Authorization header"},
        )
    parts = authorization.strip().split()
    if len(parts) != 2 or parts[0].lower() != "bearer":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"error": "INVALID_TOKEN", "message": "Authorization header must be Bearer <token>"},
        )
    raw_token = parts[1]
    payload = decode_access_token(raw_token)
    return AuthenticatedUser(
        user_id=str(payload.get("sub", "")),
        email=str(payload.get("email", "")),
        name=str(payload.get("name", "")),
        account_number=str(payload.get("account_number", "")),
        raw_token=raw_token,
    )


async def get_optional_user(
    authorization: str | None = Header(None, alias="Authorization"),
) -> AuthenticatedUser | None:
    if not authorization or not authorization.strip():
        return None
    try:
        return await get_current_user(authorization)
    except HTTPException:
        return None


async def verify_internal_token(
    x_internal_token: str | None = Header(None, alias="X-Internal-Token"),
) -> str | None:
    settings = get_settings()
    expected = settings.internal_token.strip()
    provided = (x_internal_token or "").strip()

    if settings.require_internal_token:
        if not provided or not hmac.compare_digest(provided, expected):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail={"error": "UNAUTHORIZED", "message": "Invalid or missing X-Internal-Token"},
            )
        return provided

    # Dev mode: tolerate missing in dev
    if not provided:
        logger.debug("X-Internal-Token missing in dev mode (tolerated)")
    elif not hmac.compare_digest(provided, expected):
        logger.warning("X-Internal-Token mismatch in dev mode (tolerated)")
    return provided
