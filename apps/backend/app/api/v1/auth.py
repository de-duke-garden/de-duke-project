"""Real endpoints for /v1/auth -- FEAT-001 (Email & Phone Sign-Up / Login).

Router stays thin; all logic lives in app.services.auth_service per AGENTS.md.
"""

from fastapi import APIRouter, Depends, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import get_session
from app.core.security import CurrentUser, get_current_user
from app.schemas.auth import (
    AuthTokenResponse,
    ForgotPasswordRequest,
    LoginRequest,
    RefreshRequest,
    RegisterEmailRequest,
    RegisterPhoneRequest,
    ResetPasswordRequest,
    VerifyOtpRequest,
)
from app.services import auth_service

router = APIRouter()


@router.post("/register", response_model=AuthTokenResponse, status_code=status.HTTP_201_CREATED)
async def register(
    payload: RegisterEmailRequest, session: AsyncSession = Depends(get_session)
) -> AuthTokenResponse:
    """Screen 1 Sign Up tab, email mode."""
    user = await auth_service.register_with_email(
        session, full_name=payload.full_name, email=payload.email, password=payload.password
    )
    access_token, refresh_token = auth_service.issue_tokens(user)
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
    access_token, refresh_token = auth_service.issue_tokens(user)
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
    access_token, refresh_token = auth_service.issue_tokens(user)
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
    auth_service.revoke_refresh_token(payload.refresh_token)


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
