"""Business logic for FEAT-001 (Email & Phone Sign-Up / Login).

Kept separate from app/api/v1/auth.py so the router stays thin per
AGENTS.md. OTP codes, the phone-registration name stash, refresh tokens,
and password-reset tokens all live in the Cache (Redis, app/core/cache.py)
-- not an in-process dict, which would silently break the moment Fargate
runs more than one task (a token written by one task would be invisible to
another handling the next request).
"""

from __future__ import annotations

import secrets
from datetime import UTC, datetime, timedelta

from fastapi import HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlmodel import select

from app.core import cache
from app.core.security import UserRole, create_access_token, hash_password, verify_password
from app.models.user import User

OTP_TTL = timedelta(minutes=10)
RESET_TOKEN_TTL = timedelta(hours=1)
# Not specified in schema.md/features.md -- chosen to comfortably outlast
# the mobile-first "stay logged in" expectation (FEAT-001 AC) across
# repeated refresh cycles, without keeping a token alive indefinitely.
REFRESH_TOKEN_TTL = timedelta(days=30)


def _otp_key(phone_number: str) -> str:
    return f"otp:register:{phone_number}"


def _otp_name_key(phone_number: str) -> str:
    return f"otp:register:{phone_number}:name"


def _login_otp_key(phone_number: str) -> str:
    return f"otp:login:{phone_number}"


def _refresh_key(refresh_token: str) -> str:
    return f"auth:refresh:{refresh_token}"


def _pwreset_key(reset_token: str) -> str:
    return f"auth:pwreset:{reset_token}"


def _generate_otp() -> str:
    return f"{secrets.randbelow(1_000_000):06d}"


def _generate_token() -> str:
    return secrets.token_urlsafe(32)


async def register_with_email(
    session: AsyncSession, *, full_name: str, email: str, password: str
) -> User:
    """FEAT-001 AC: register with email + password."""
    existing = (await session.execute(select(User).where(User.email == email))).scalars()
    if existing.first() is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="An account with this email already exists.",
        )

    user = User(
        full_name=full_name,
        email=email,
        role=UserRole.SEEKER.value,
        password_hash=hash_password(password),
    )
    session.add(user)
    await session.commit()
    await session.refresh(user)
    # TODO(FEAT-024): trigger welcome/confirmation email via Notification Service (SES).
    return user


async def request_phone_otp(session: AsyncSession, *, full_name: str, phone_number: str) -> None:
    """Step 1 of phone sign-up: send an OTP. Does not create the user yet --
    the account materializes on successful verify_phone_otp so a user who
    never completes OTP verification never becomes an orphaned unverified row."""
    existing = (
        await session.execute(select(User).where(User.phone_number == phone_number))
    ).scalars()
    if existing.first() is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="An account with this phone number already exists.",
        )
    otp = _generate_otp()
    ttl_seconds = int(OTP_TTL.total_seconds())
    await cache.set_with_ttl(_otp_key(phone_number), otp, ttl_seconds=ttl_seconds)
    # Stash full_name alongside the OTP so verify_phone_otp can finish registration.
    await cache.set_with_ttl(_otp_name_key(phone_number), full_name, ttl_seconds=ttl_seconds)
    # TODO(architecture.md Notification Service / SMS provider): send `otp` via SMS.
    # Not sent anywhere yet -- no SMS provider is configured (no fabricated credentials).


async def verify_phone_otp(session: AsyncSession, *, phone_number: str, otp_code: str) -> User:
    """Validates via `peek` (not an atomic pop) -- an incorrect attempt must
    not burn the code, so a user who mistypes it can still retry with the
    correct one until OTP_TTL expires, matching the original in-memory
    implementation's behavior."""
    stored = await cache.peek(_otp_key(phone_number))
    if stored is None or stored != otp_code:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid or expired OTP code."
        )

    full_name = await cache.pop(_otp_name_key(phone_number)) or "New User"
    await cache.delete(_otp_key(phone_number))

    user = User(full_name=full_name, phone_number=phone_number, role=UserRole.SEEKER.value)
    session.add(user)
    await session.commit()
    await session.refresh(user)
    return user


async def login_with_email(session: AsyncSession, *, email: str, password: str) -> User:
    result = (await session.execute(select(User).where(User.email == email))).scalars()
    user = result.first()
    if (
        user is None
        or user.password_hash is None
        or not verify_password(password, user.password_hash)
    ):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="We couldn't verify those details. Try again or reset your password.",
        )
    if not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN, detail="This account has been deactivated."
        )
    return user


async def login_with_phone_otp(session: AsyncSession, *, phone_number: str, otp_code: str) -> User:
    result = (
        await session.execute(select(User).where(User.phone_number == phone_number))
    ).scalars()
    user = result.first()
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="No account found for that phone number."
        )
    stored = await cache.peek(_login_otp_key(phone_number))
    if stored is None or stored != otp_code:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid or expired OTP code."
        )
    await cache.delete(_login_otp_key(phone_number))
    if not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN, detail="This account has been deactivated."
        )
    return user


async def request_login_otp(phone_number: str) -> None:
    otp = _generate_otp()
    await cache.set_with_ttl(
        _login_otp_key(phone_number), otp, ttl_seconds=int(OTP_TTL.total_seconds())
    )
    # TODO(architecture.md SMS provider): actually deliver `otp`.


async def issue_tokens(user: User) -> tuple[str, str]:
    """Returns (access_token, refresh_token). Refresh tokens are opaque
    random strings tracked server-side (see refresh_session()), not JWTs,
    so they can be revoked on logout without needing a blocklist for every
    JWT."""
    access_token = create_access_token(user_id=user.id, role=UserRole(user.role))
    refresh_token = _generate_token()
    await cache.set_with_ttl(
        _refresh_key(refresh_token), user.id, ttl_seconds=int(REFRESH_TOKEN_TTL.total_seconds())
    )
    return access_token, refresh_token


async def refresh_session(session: AsyncSession, *, refresh_token: str) -> tuple[User, str, str]:
    """Rotates the refresh token on every use (old one atomically popped/
    invalidated here, a new one issued by issue_tokens) -- a stolen,
    already-used refresh token can never be replayed."""
    user_id = await cache.pop(_refresh_key(refresh_token))
    if user_id is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid or expired refresh token."
        )
    user = await session.get(User, user_id)
    if user is None or not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="Account no longer available."
        )
    access_token, new_refresh_token = await issue_tokens(user)
    return user, access_token, new_refresh_token


async def revoke_refresh_token(refresh_token: str) -> None:
    await cache.delete(_refresh_key(refresh_token))


async def request_password_reset(session: AsyncSession, *, email: str) -> None:
    """FEAT-001 AC: reset a forgotten password. Always succeeds silently for
    unknown emails to avoid leaking account existence."""
    result = (await session.execute(select(User).where(User.email == email))).scalars()
    user = result.first()
    if user is None:
        return
    token = _generate_token()
    await cache.set_with_ttl(
        _pwreset_key(token), user.id, ttl_seconds=int(RESET_TOKEN_TTL.total_seconds())
    )
    # TODO(FEAT-024 / SES): email the reset link containing `token`.


async def reset_password(session: AsyncSession, *, reset_token: str, new_password: str) -> None:
    user_id = await cache.pop(_pwreset_key(reset_token))
    if user_id is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid or expired reset token."
        )
    user = await session.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Account not found.")
    user.password_hash = hash_password(new_password)
    user.updated_at = datetime.now(UTC)
    session.add(user)
    await session.commit()
