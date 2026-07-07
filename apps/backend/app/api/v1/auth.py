"""Real endpoints for /v1/auth -- FEAT-001 (Email & Phone Sign-Up / Login).

Router stays thin; all logic lives in app.services.auth_service per AGENTS.md.
"""

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import get_session
from app.core.security import CurrentUser, get_current_user
from app.models.user import User
from app.schemas.auth import (
    AuthTokenResponse,
    CurrentUserResponse,
    ForgotPasswordRequest,
    LoginRequest,
    NotificationPreferencesResponse,
    RefreshRequest,
    RegisterEmailRequest,
    RegisterPhoneRequest,
    ResetPasswordRequest,
    UpdateNotificationPreferencesRequest,
    VerifyOtpRequest,
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


@router.post("/register", response_model=AuthTokenResponse, status_code=status.HTTP_201_CREATED)
async def register(
    payload: RegisterEmailRequest, session: AsyncSession = Depends(get_session)
) -> AuthTokenResponse:
    """Screen 1 Sign Up tab, email mode."""
    user = await auth_service.register_with_email(
        session, full_name=payload.full_name, email=payload.email, password=payload.password
    )
    access_token, refresh_token = await auth_service.issue_tokens(user)
    return AuthTokenResponse(
        access_token=access_token,
        refresh_token=refresh_token,
        user_id=user.id,
        role=user.role,
        is_verified_host=user.is_verified_host,
    )


@router.post("/register/phone/request-otp", status_code=status.HTTP_202_ACCEPTED)
async def register_phone_request_otp(
    payload: RegisterPhoneRequest, session: AsyncSession = Depends(get_session)
) -> dict[str, str]:
    """Screen 1 Sign Up tab, phone mode -- step 1 of 2."""
    await auth_service.request_phone_otp(
        session, full_name=payload.full_name, phone_number=payload.phone_number
    )
    return {"status": "otp_sent"}


@router.post(
    "/register/phone/verify-otp",
    response_model=AuthTokenResponse,
    status_code=status.HTTP_201_CREATED,
)
async def register_phone_verify_otp(
    payload: VerifyOtpRequest, session: AsyncSession = Depends(get_session)
) -> AuthTokenResponse:
    """Screen 1 Sign Up tab, phone mode -- step 2 of 2, finalizes account creation."""
    user = await auth_service.verify_phone_otp(
        session, phone_number=payload.phone_number, otp_code=payload.otp_code
    )
    access_token, refresh_token = await auth_service.issue_tokens(user)
    return AuthTokenResponse(
        access_token=access_token,
        refresh_token=refresh_token,
        user_id=user.id,
        role=user.role,
        is_verified_host=user.is_verified_host,
    )


@router.post("/login/phone/request-otp", status_code=status.HTTP_202_ACCEPTED)
async def login_phone_request_otp(phone_number: str) -> dict[str, str]:
    await auth_service.request_login_otp(phone_number)
    return {"status": "otp_sent"}


@router.post("/login", response_model=AuthTokenResponse)
async def login(
    payload: LoginRequest, session: AsyncSession = Depends(get_session)
) -> AuthTokenResponse:
    """Screen 1 Log In tab -- email+password or phone+OTP."""
    if payload.email:
        user = await auth_service.login_with_email(
            session, email=payload.email, password=payload.password or ""
        )
    else:
        user = await auth_service.login_with_phone_otp(
            session, phone_number=payload.phone_number or "", otp_code=payload.otp_code or ""
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
    """FEAT-001 AC: reset a forgotten password. Always returns 202 regardless
    of whether the email exists, to avoid leaking account existence."""
    await auth_service.request_password_reset(session, email=payload.email)
    return {"status": "if_account_exists_reset_email_sent"}


@router.post("/reset-password", status_code=status.HTTP_204_NO_CONTENT)
async def reset_password(
    payload: ResetPasswordRequest, session: AsyncSession = Depends(get_session)
) -> None:
    await auth_service.reset_password(
        session, reset_token=payload.reset_token, new_password=payload.new_password
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
