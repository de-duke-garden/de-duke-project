"""Real endpoints for /v1/auth -- FEAT-001 (Google & Firebase Sign-Up /
Login) plus the Staff/Admin-only backend-managed password flow it left in
place (FEAT-033).

Router stays thin; all logic lives in app.services.auth_service per AGENTS.md.
"""

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import get_session
from app.core.security import CurrentUser, UserRole, get_current_user
from app.models.user import User
from app.schemas.auth import (
    AcceptInviteRequest,
    AuthTokenResponse,
    ChangePasswordRequest,
    CurrentUserResponse,
    FirebaseExchangeRequest,
    ForgotPasswordRequest,
    LinkFirebaseIdentityRequest,
    LoginRequest,
    NotificationPreferencesResponse,
    RefreshRequest,
    ResetPasswordRequest,
    UpdateNotificationPreferencesRequest,
    UpdateRoleRequest,
)
from app.services import auth_service

router = APIRouter()


@router.get("/me", response_model=CurrentUserResponse)
async def get_me(
    current_user: CurrentUser = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> CurrentUserResponse:
    """Resolves the caller's identity from their access token.

    Used by server-side consumers (e.g. the Admin Web Console's session
    layer) that need to validate a session and read the current role
    without holding the JWT signing secret themselves -- they call this
    endpoint with the bearer token instead of decoding the JWT locally.
    """
    result = await session.execute(select(User).where(User.id == current_user.user_id))
    user = result.scalars().first()
    if user is None or not user.is_active:
        raise HTTPException(status_code=401, detail="Session is no longer valid.")
    return CurrentUserResponse(
        user_id=user.id,
        role=user.role,
        full_name=user.full_name,
        email=user.email,
        phone_number=user.phone_number,
        is_verified_host=user.is_verified_host,
        is_active=user.is_active,
    )


@router.post("/firebase-exchange", response_model=AuthTokenResponse)
async def firebase_exchange(
    payload: FirebaseExchangeRequest, session: AsyncSession = Depends(get_session)
) -> AuthTokenResponse:
    """Screen 1 (Sign-Up / Login) -- the single entry point for every
    consumer-role sign-in (Google Sign-In, Firebase email/password,
    Firebase phone/OTP). Always returns 200 (FastAPI can't vary
    status_code per branch on one route declaration) -- the client
    distinguishes new-vs-returning via `is_new_user` on the response body
    and routes to Role Selection vs. Home Feed accordingly (FEAT-001 AC),
    not via the HTTP status code.
    """
    user, is_new_user = await auth_service.exchange_firebase_token(
        session, id_token=payload.id_token
    )
    access_token, refresh_token = await auth_service.issue_tokens(user)
    return AuthTokenResponse(
        access_token=access_token,
        refresh_token=refresh_token,
        user_id=user.id,
        role=user.role,
        is_verified_host=user.is_verified_host,
        is_new_user=is_new_user,
    )


@router.post("/login", response_model=AuthTokenResponse)
async def login(
    payload: LoginRequest, session: AsyncSession = Depends(get_session)
) -> AuthTokenResponse:
    """Admin Web Console's login screen -- Staff/Admin only (FEAT-033).
    Consumer roles use POST /firebase-exchange above instead."""
    user = await auth_service.login_with_email(
        session, email=payload.email, password=payload.password
    )
    access_token, refresh_token = await auth_service.issue_tokens(user)
    return AuthTokenResponse(
        access_token=access_token,
        refresh_token=refresh_token,
        user_id=user.id,
        role=user.role,
        is_verified_host=user.is_verified_host,
    )


@router.post("/refresh", response_model=AuthTokenResponse)
async def refresh(
    payload: RefreshRequest, session: AsyncSession = Depends(get_session)
) -> AuthTokenResponse:
    """Lets a returning user "stay logged in across app restarts" (FEAT-001 AC)
    without re-entering credentials, by exchanging a long-lived refresh token."""
    user, access_token, refresh_token = await auth_service.refresh_session(
        session, refresh_token=payload.refresh_token
    )
    return AuthTokenResponse(
        access_token=access_token,
        refresh_token=refresh_token,
        user_id=user.id,
        role=user.role,
        is_verified_host=user.is_verified_host,
    )


@router.post("/logout", status_code=status.HTTP_204_NO_CONTENT)
async def logout(
    payload: RefreshRequest, current_user: CurrentUser = Depends(get_current_user)
) -> None:
    """Screen 21 Log Out action. Revokes the refresh token server-side;
    the mobile client separately clears its local session_store."""
    await auth_service.revoke_refresh_token(payload.refresh_token)


@router.post("/forgot-password", status_code=status.HTTP_202_ACCEPTED)
async def forgot_password(
    payload: ForgotPasswordRequest, session: AsyncSession = Depends(get_session)
) -> dict[str, str]:
    """FEAT-033 AC: Staff/Admin reset a forgotten password (Admin Web
    Console only). Always returns 202 regardless of whether the email
    exists or belongs to a Firebase-provider (consumer) account, to avoid
    leaking account existence/auth path -- see
    auth_service.request_password_reset."""
    await auth_service.request_password_reset(session, email=payload.email)
    return {"status": "if_account_exists_reset_email_sent"}


@router.post("/reset-password", status_code=status.HTTP_204_NO_CONTENT)
async def reset_password(
    payload: ResetPasswordRequest, session: AsyncSession = Depends(get_session)
) -> None:
    await auth_service.reset_password(
        session, reset_token=payload.reset_token, new_password=payload.new_password
    )


@router.post("/accept-invite", response_model=AuthTokenResponse, status_code=status.HTTP_200_OK)
async def accept_invite(
    payload: AcceptInviteRequest, session: AsyncSession = Depends(get_session)
) -> AuthTokenResponse:
    """FEAT-033 (Admin Web Console Staff/Admin invite) and FEAT-012 (mobile
    Agency team invite) AC: "the invitee sets their own password via an
    emailed invitation link" -- shared by both invite flows since they
    produce the same link shape (see auth_service.accept_invite). Returns
    a full session (like register/login) so the invitee lands signed-in
    immediately after choosing their password, rather than being sent back
    to a separate login screen.
    """
    user = await auth_service.accept_invite(
        session,
        user_id=payload.user_id,
        invite_token=payload.invite_token,
        new_password=payload.new_password,
    )
    access_token, refresh_token = await auth_service.issue_tokens(user)
    return AuthTokenResponse(
        access_token=access_token,
        refresh_token=refresh_token,
        user_id=user.id,
        role=user.role,
        is_verified_host=user.is_verified_host,
    )


@router.post("/link-firebase-identity", response_model=CurrentUserResponse)
async def link_firebase_identity(
    payload: LinkFirebaseIdentityRequest,
    current_user: CurrentUser = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> CurrentUserResponse:
    """FEAT-040 -- Account Settings' "Link a sign-in method" action.
    Authenticated by the caller's existing De-Duke bearer session
    (`current_user`), not by `payload.id_token` -- that token only proves
    control of the Firebase side; the session proves control of the
    De-Duke side. Both are required together."""
    user = await auth_service.link_firebase_identity(
        session, user_id=current_user.user_id, id_token=payload.id_token
    )
    return CurrentUserResponse(
        user_id=user.id,
        role=user.role,
        full_name=user.full_name,
        email=user.email,
        phone_number=user.phone_number,
        is_verified_host=user.is_verified_host,
        is_active=user.is_active,
    )


@router.delete("/link-firebase-identity", status_code=status.HTTP_204_NO_CONTENT)
async def unlink_firebase_identity(
    current_user: CurrentUser = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> None:
    """FEAT-040 -- Account Settings' "Unlink" action."""
    await auth_service.unlink_firebase_identity(session, user_id=current_user.user_id)


@router.post("/change-password", status_code=status.HTTP_204_NO_CONTENT)
async def change_password(
    payload: ChangePasswordRequest,
    current_user: CurrentUser = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> None:
    """FEAT-041 -- Admin Web Console "My Account" screen. Distinct from
    /forgot-password + /reset-password above (that pair is for a user who
    is locked out and not currently authenticated)."""
    await auth_service.change_password(
        session,
        user_id=current_user.user_id,
        current_password=payload.current_password,
        new_password=payload.new_password,
    )


@router.get("/me/notification-preferences", response_model=NotificationPreferencesResponse)
async def get_notification_preferences(
    current_user: CurrentUser = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> NotificationPreferencesResponse:
    """FEAT-024 AC: manage email notification preferences per category,
    separate from push preferences (FEAT-022)."""
    preferences = await auth_service.get_notification_preferences(
        session, user_id=current_user.user_id
    )
    return NotificationPreferencesResponse(email_notification_preferences=preferences)


@router.patch("/me/notification-preferences", response_model=NotificationPreferencesResponse)
async def update_notification_preferences(
    payload: UpdateNotificationPreferencesRequest,
    current_user: CurrentUser = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> NotificationPreferencesResponse:
    """Partial update -- only categories present (non-None) in the request
    body are changed."""
    updates = payload.model_dump(exclude_none=True)
    preferences = await auth_service.update_notification_preferences(
        session, user_id=current_user.user_id, updates=updates
    )
    return NotificationPreferencesResponse(email_notification_preferences=preferences)


@router.patch("/me/role", response_model=CurrentUserResponse)
async def update_role(
    payload: UpdateRoleRequest,
    current_user: CurrentUser = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> CurrentUserResponse:
    """FEAT-003 -- Screen 2 (Role Selection) and its Account Settings
    re-entry point. `payload.role` is already restricted to
    SELF_SERVICE_ROLES by UpdateRoleRequest's validator (see
    app/schemas/auth.py) -- deduke_staff/deduke_admin are never acceptable
    request values.

    Additionally refuses the call entirely for a caller who is ALREADY
    deduke_staff/deduke_admin -- those accounts don't go through
    self-service role selection at all (they're created via invite/CLI
    bootstrap, FEAT-033), and a staff member self-demoting to "seeker"
    through this endpoint would be a real, unintended privilege change,
    not a normal product-experience choice.
    """
    if current_user.role in (UserRole.DEDUKE_STAFF, UserRole.DEDUKE_ADMIN):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Staff/Admin accounts cannot change their role via self-service.",
        )

    user = await auth_service.update_role(session, user_id=current_user.user_id, role=payload.role)
    return CurrentUserResponse(
        user_id=user.id,
        role=user.role,
        full_name=user.full_name,
        email=user.email,
        phone_number=user.phone_number,
        is_verified_host=user.is_verified_host,
        is_active=user.is_active,
    )
