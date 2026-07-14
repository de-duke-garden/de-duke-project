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

import anyio
from fastapi import HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlmodel import select

from app.core import cache
from app.core.security import UserRole, create_access_token, hash_password, verify_password
from app.models.user import User
from app.services.email_service import PASSWORD_RESET, WELCOME, notify_user
from app.services.sms_service import SmsDeliveryError, send_sms

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

    # bcrypt hashing is CPU-bound and, at a realistic work factor, slow
    # enough (~100-300ms) to matter -- calling it synchronously inside an
    # `async def` blocks the whole event loop for that long, serializing
    # every other in-flight request behind it. Found via a real staging
    # load test run: 20 concurrent users hitting /auth/login alone was
    # enough to push p95 latency into the tens of seconds and fail nearly
    # every request, even though each individual bcrypt call is fast in
    # isolation. Offloaded to a worker thread (anyio.to_thread.run_sync,
    # same pattern app/core/storage.py and app/services/sms_service.py
    # already use for their own blocking I/O) at every call site in this
    # file, not just login -- register/reset/accept-invite hit the same
    # bcrypt cost and would reproduce the same stall under load.
    user = User(
        full_name=full_name,
        email=email,
        role=UserRole.SEEKER.value,
        password_hash=await anyio.to_thread.run_sync(hash_password, password),
    )
    session.add(user)
    await session.commit()
    await session.refresh(user)
    await notify_user(
        session, user_id=user.id, template=WELCOME, context={"full_name": user.full_name}
    )
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
    try:
        await send_sms(
            phone_number, f"Your De-Duke verification code is {otp}. It expires in 10 minutes."
        )
    except SmsDeliveryError as exc:
        # Unlike email_service.notify_user, this must surface -- the user
        # cannot complete sign-up at all if the code never arrives, so a
        # silent 202 here would be a false positive (see sms_service.py's
        # module docstring).
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Couldn't send the verification code. Please try again.",
        ) from exc


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
    # See register_with_email's comment on why verify_password is offloaded
    # to a thread here -- this is the hottest of these call sites (every
    # login hits it), and the one the load-test smoke run actually caught.
    password_ok = (
        user is not None
        and user.password_hash is not None
        and await anyio.to_thread.run_sync(verify_password, password, user.password_hash)
    )
    if not password_ok:
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
    try:
        await send_sms(phone_number, f"Your De-Duke login code is {otp}. It expires in 10 minutes.")
    except SmsDeliveryError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Couldn't send the login code. Please try again.",
        ) from exc


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
    # `reset_token` is the raw token, not a URL -- no mobile deep-link or
    # web reset-page base URL is defined anywhere yet (admin_console_url
    # is the Admin Web Console specifically, a different audience: this
    # reset flow serves any user, not just internal staff/admin). Once
    # that destination exists, build the full link here instead.
    await notify_user(
        session,
        user_id=user.id,
        template=PASSWORD_RESET,
        context={"reset_token": token},
    )


async def reset_password(session: AsyncSession, *, reset_token: str, new_password: str) -> None:
    user_id = await cache.pop(_pwreset_key(reset_token))
    if user_id is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid or expired reset token."
        )
    user = await session.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Account not found.")
    user.password_hash = await anyio.to_thread.run_sync(hash_password, new_password)
    user.updated_at = datetime.now(UTC)
    session.add(user)
    await session.commit()


async def accept_invite(
    session: AsyncSession, *, user_id: str, invite_token: str, new_password: str
) -> User:
    """FEAT-033 AC ("the invitee sets their own password via an emailed
    invitation link") and FEAT-012's identical agency-team-invite flow
    (app/services/agency_service.py::invite_team_member) -- both invite
    flows create the new account with `password_hash = hash_password(raw_token)`
    (see staff_account_service.invite_staff), using the invite token itself
    as a one-time bootstrap password rather than standing up a whole
    separate token store (the Cache-backed pattern `reset_password` above
    uses) for what is, structurally, the exact same "prove you hold the
    token, then set a real password" operation.

    This endpoint is that missing second half: it verifies `invite_token`
    against the account's *current* password hash (i.e. logs the invitee in
    with the token as their password, without going through the public
    /auth/login endpoint's is_active gate quirks) and then overwrites
    password_hash with a password the invitee actually chose. This is
    naturally single-use and needs no separate expiry/consumption tracking:
    once accepted, password_hash no longer matches the original raw token,
    so replaying the same invite link a second time simply fails the
    verify_password check below -- exactly like a reused one-time code
    would, but without a second piece of state to keep in sync.
    """
    user = await session.get(User, user_id)
    token_ok = (
        user is not None
        and user.password_hash is not None
        and await anyio.to_thread.run_sync(verify_password, invite_token, user.password_hash)
    )
    if not token_ok:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="This invite link is invalid or has already been used.",
        )
    assert user is not None  # narrowed by token_ok above, for the type checker
    if not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="This account has been deactivated. Contact an Admin for a new invite.",
        )

    user.password_hash = await anyio.to_thread.run_sync(hash_password, new_password)
    user.updated_at = datetime.now(UTC)
    session.add(user)
    await session.commit()
    await session.refresh(user)
    return user


async def get_notification_preferences(session: AsyncSession, *, user_id: str) -> dict[str, bool]:
    user = await session.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Account not found.")
    return dict(user.email_notification_preferences or {})


async def update_notification_preferences(
    session: AsyncSession, *, user_id: str, updates: dict[str, bool]
) -> dict[str, bool]:
    """Merges `updates` (only the categories the caller actually sent) into
    the user's existing preferences -- an omitted category is left as-is,
    never reset to its default."""
    user = await session.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Account not found.")

    preferences = dict(user.email_notification_preferences or {})
    preferences.update(updates)
    user.email_notification_preferences = preferences
    user.updated_at = datetime.now(UTC)
    session.add(user)
    await session.commit()
    return preferences


async def update_role(session: AsyncSession, *, user_id: str, role: str) -> User:
    """FEAT-003 (Role Selection) -- Screen 2's initial choice, and its
    change-later re-entry point from Account Settings (screens.md Screen 2
    Edge Cases). `role` is already validated against SELF_SERVICE_ROLES by
    UpdateRoleRequest before this is called -- this function trusts its
    caller on that, the same way every other service function here trusts
    its router to have validated the request shape.
    """
    user = await session.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Account not found.")

    user.role = role
    user.updated_at = datetime.now(UTC)
    session.add(user)
    await session.commit()
    await session.refresh(user)
    return user
