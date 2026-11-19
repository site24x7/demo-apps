"""Tests for JWT and internal token authentication."""

import time

import jwt
import pytest
from fastapi import HTTPException

from app.auth import (
    AuthenticatedUser,
    create_access_token,
    decode_access_token,
    get_current_user,
    verify_internal_token,
)
from app.config import get_settings


def test_create_and_decode_token():
    token = create_access_token(
        user_id="user-123",
        email="test@zylkerbank.com",
        name="Test User",
        account_number="2170000001",
    )
    payload = decode_access_token(token)
    assert payload["sub"] == "user-123"
    assert payload["email"] == "test@zylkerbank.com"
    assert payload["name"] == "Test User"
    assert payload["account_number"] == "2170000001"
    assert "exp" in payload


def test_expired_token():
    settings = get_settings()
    expired_payload = {
        "sub": "user-123",
        "iat": int(time.time()) - 3600,
        "exp": int(time.time()) - 10,
    }
    expired_token = jwt.encode(expired_payload, settings.jwt_secret, algorithm="HS256")
    with pytest.raises(HTTPException) as exc_info:
        decode_access_token(expired_token)
    assert exc_info.value.status_code == 401
    assert exc_info.value.detail["error"] == "TOKEN_EXPIRED"


def test_invalid_token():
    with pytest.raises(HTTPException) as exc_info:
        decode_access_token("not-a-valid-jwt-token")
    assert exc_info.value.status_code == 401
    assert exc_info.value.detail["error"] == "INVALID_TOKEN"


@pytest.mark.asyncio
async def test_get_current_user_valid():
    token = create_access_token(
        user_id="1111",
        email="alice@zylkerbank.com",
        name="Alice",
        account_number="2170000001",
    )
    user = await get_current_user(f"Bearer {token}")
    assert isinstance(user, AuthenticatedUser)
    assert user.user_id == "1111"
    assert user.email == "alice@zylkerbank.com"
    assert user.account_number == "2170000001"
    assert user.raw_token == token


@pytest.mark.asyncio
async def test_get_current_user_missing_header():
    with pytest.raises(HTTPException) as exc_info:
        await get_current_user(None)
    assert exc_info.value.status_code == 401
    assert exc_info.value.detail["error"] == "UNAUTHORIZED"


@pytest.mark.asyncio
async def test_get_current_user_malformed_header():
    with pytest.raises(HTTPException) as exc_info:
        await get_current_user("Basic some-credentials")
    assert exc_info.value.status_code == 401
    assert exc_info.value.detail["error"] == "INVALID_TOKEN"


@pytest.mark.asyncio
async def test_verify_internal_token():
    settings = get_settings()
    # In dev mode, missing is tolerated
    res = await verify_internal_token(None)
    assert res == ""

    # Matching token
    res = await verify_internal_token(settings.internal_token)
    assert res == settings.internal_token
