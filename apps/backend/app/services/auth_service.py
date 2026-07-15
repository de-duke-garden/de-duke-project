"""Business logic for FEAT-001 (Google & Firebase Sign-Up / Login) and the
Staff/Admin-only backend-managed password flow it left in place.

Kept separate from app/api/v1/auth.py so the router stays thin per
AGENTS.md. Refresh tokens and password-reset tokens live in the Cache
(Redis, app/core/cache.py) -- not an in-process dict, which would silently
break the moment Fargate runs more than one task (a token written by one
task would be invisible to another handling the next request).

Two distinct, deliberately non-overlapping auth paths live in this module
(architecture.md's Authentication & Authorization section):
  - Consumer roles (seeker/individual_host/agency/corporate) authenticate
    against Firebase Authentication client-side (Google Sign-In, Firebase
    email/password, or Firebase phone/OTP) and never send a raw
    password/OTP to this service at all -- see `exchange_firebase_token`,
    the only entry point for these roles. There is deliberately no
    backend-hosted register/OTP flow for them anymore (removed along with
    the old FEAT-001 scope) -- schema.md's User.authProvider is always
    "firebase" for these four roles, and a surviving password-based
    self-registration path here would silently violate that invariant.
  - Internal roles (deduke_staff/deduke_admin) are entirely unaffected and
    keep the pre-existing backend-managed email + password flow below
    (`login_with_email`, `request_password_reset`/`reset_password`,
    `accept_invite`) -- created only via CLI bootstrap or invitation
    (FEAT-033), never through Firebase/Google.
"""

from __future__ import annotations

import secrets
from datetime import UTC, datetime, timedelta
from functools import partial
from typing import Any

import anyio
from fastapi import HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlmodel import select

from app.core import cache
from app.core import firebase as firebase_core
from app.core.security import UserRole, create_access_token, hash_password, verify_password
from app.models.user import User
from app.services.email_service import PASSWORD_RESET, WELCOME, notify_user

RESET_TOKEN_TTL = timedelta(hours=1)
# Not specified in schema.md/features.md -- chosen to comfortably outlast
# the mobile-first "stay logged in" expectation (FEAT-001 AC) across
# repeated refresh cycles, without keeping a token alive indefinitely.
REFRESH_TOKEN_TTL = timedelta(days=30)


class FirebaseAuthUnavailableError(RuntimeError):
    """Raised when the Firebase Admin SDK isn't configured for this
    environment (firebase_service_account_json/firestore_project_id are
    still REPLACE_ME) -- mirrors chat_service.ChatServiceUnavailableError,
    the equivalent guard for the other Firebase Admin SDK consumer in this
    codebase. Both share app.core.firebase's underlying lazy app init."""


def _refresh_key(refresh_token: str) -> str:
    return f"auth:refresh:{refresh_token}"


def _pwreset_key(reset_token: str) -> str:
    return f"auth:pwreset:{reset_token}"


def _generate_token() -> str:
    return secrets.token_urlsafe(32)


def _is_configured() -> bool:
    return firebase_core.is_configured()


def _get_firebase_app() -> Any:
    if not _is_configured():
        raise FirebaseAuthUnavailableError(
            "Firebase Admin SDK is not configured (firebase_service_account_json/"
            "firestore_project_id are REPLACE_ME) -- Google/Firebase sign-in is "
            "unavailable in this environment until real Firebase credentials are "
            "provisioned."
        )
    return firebase_core.get_firebase_app()


async def exchange_firebase_token(
    session: AsyncSession, *, id_token: str
) -> tuple[User, bool]:
    """FEAT-001: the ONLY entry point for consumer sign-in. Verifies a
    Firebase ID token (already produced client-side by Google Sign-In,
    Firebase email/password, or Firebase phone/OTP -- this service never
    sees the underlying credential) via the Firebase Admin SDK, then
    resolves it to a De-Duke `User` by `firebase_uid`, creating one on
    first sign-in.

    Deliberately does NOT return a session token itself -- callers (see
    app/api/v1/auth.py's POST /firebase-exchange) still call
    `issue_tokens()` separately, exactly like every other sign-in path in
    this file. This is architecture.md's key decision: the Firebase ID
    token is a one-time credential-collection proof, never the app's
    ongoing session credential -- a backend-issued, backend-revocable
    token is, for the same reasons `login_with_email` below already
    required one (stateless Fargate tasks, role/verification claims a
    Firebase ID token doesn't carry).

    Returns `(user, is_new_user)` -- the bool is NOT derivable from `user`
    alone by the caller (a returning user can still legitimately have
    role "seeker", the same default a brand-new account gets, if they
    haven't completed Role Selection yet) -- so it's threaded through
    explicitly for the router to put on AuthTokenResponse.is_new_user,
    which is what the mobile client actually branches on for FEAT-001 AC's
    "a first-time sign-in ... routes to Role Selection; a returning
    identity ... routes to Home Feed" -- not an inference from `role`.
    """
    from firebase_admin import auth as firebase_auth

    app = _get_firebase_app()
    # firebase_admin's verify_id_token is synchronous and makes a network
    # call on a cache miss (fetching Google's current signing keys) --
    # offloaded to a worker thread for the same reason hash_password/
    # verify_password are below: a blocking call inside an `async def`
    # stalls FastAPI's single event loop for every other in-flight
    # request, not just this one (see login_with_email's identical note).
    try:
        decoded = await anyio.to_thread.run_sync(
            partial(firebase_auth.verify_id_token, id_token, app=app)
        )
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Your sign-in could not be verified. Please try again.",
        ) from exc

    firebase_uid: str = decoded["uid"]
    email: str | None = decoded.get("email")
    phone_number: str | None = decoded.get("phone_number")
    full_name: str = decoded.get("name") or (email.split("@")[0] if email else "New User")

    result = (
        await session.execute(select(User).where(User.firebase_uid == firebase_uid))
    ).scalars()
    user = result.first()

    if user is None:
        # First-ever sign-in for this Firebase identity -- FEAT-001 AC:
        # "a first-time sign-in via any of the three methods creates a new
        # User record and routes to Role Selection." Defaults to seeker;
        # FEAT-003 Role Selection changes it immediately after.
        user = User(
            full_name=full_name,
            email=email,
            phone_number=phone_number,
            role=UserRole.SEEKER.value,
            auth_provider="firebase",
            firebase_uid=firebase_uid,
        )
        session.add(user)
        await session.commit()
        await session.refresh(user)
        await notify_user(
            session, user_id=user.id, template=WELCOME, context={"full_name": user.full_name}
        )
        return user, True

    if not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN, detail="This account has been deactivated."
        )
    return user, False


async def login_with_email(session: AsyncSession, *, email: str, password: str) -> User:
    """Staff/Admin-only (FEAT-033) -- see this module's docstring. Consumer
    roles never reach this function; their accounts have no password_hash
    (schema.md: null whenever auth_provider is "firebase"), so a consumer
    email accidentally posted here always falls through to the generic
    401 below rather than a confusing role-specific error."""
    result = (await session.execute(select(User).where(User.email == email))).scalars()
    user = result.first()
    # bcrypt hashing is CPU-bound and, at a realistic work factor, slow
    # enough (~100-300ms) to matter -- calling it synchronously inside an
    # `async def` blocks the whole event loop for that long, serializing
    # every other in-flight request behind it. Found via a real staging
    # load test run: 20 concurrent users hitting /auth/login alone was
    # enough to push p95 latency into the tens of seconds and fail nearly
    # every request, even though each individual bcrypt call is fast in
    # isolation. Offloaded to a worker thread (anyio.to_thread.run_sync,
    # same pattern app/core/storage.py already uses for its own blocking
    # I/O) at every hash_password/verify_password call site in this file
    # and in agency_service.py/staff_account_service.py's own invite
    # flows, not just login -- reset_password and accept_invite below
    # follow this same pattern without repeating the full rationale.
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
    """FEAT-033 AC: Staff/Admin reset a forgotten password (Admin Web
    Console only -- consumer roles reset via Firebase's own "forgot
    password" flow client-side, never through this endpoint per FEAT-001's
    rewrite). Always succeeds silently for unknown emails AND for
    auth_provider "firebase" accounts (same email might exist on a
    consumer account) to avoid leaking either account existence or which
    auth path a given email uses."""
    result = (await session.execute(select(User).where(User.email == email))).scalars()
    user = result.first()
    if user is None or user.auth_provider != "password":
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
