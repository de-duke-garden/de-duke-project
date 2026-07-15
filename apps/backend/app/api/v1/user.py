"""Real endpoints for /v1/user -- FEAT-041 (Self-Service Profile Editing).

Deliberately a separate router/prefix from /v1/auth's "/me" (GET
/v1/auth/me exists for server-side session validation, per that
endpoint's own docstring) -- this is the mobile Account Settings/Admin
Web Console "My Account" screen's own profile data source, matching
screens.md Screen 21's long-documented `GET/PATCH /user/profile` contract.

Router stays thin; all logic lives in app.services.auth_service per AGENTS.md.
"""

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile, status
from pydantic import EmailStr, TypeAdapter, ValidationError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import get_session
from app.core.security import CurrentUser, get_current_user
from app.schemas.auth import UserProfileResponse
from app.services import auth_service

router = APIRouter()

_email_adapter = TypeAdapter(EmailStr)


def _to_profile_response(user) -> UserProfileResponse:  # type: ignore[no-untyped-def]
    return UserProfileResponse(
        user_id=user.id,
        full_name=user.full_name,
        email=user.email,
        phone_number=user.phone_number,
        auth_provider=user.auth_provider,
        is_firebase_linked=user.firebase_uid is not None,
        profile_photo_url=user.profile_photo_url,
    )


@router.get("/profile", response_model=UserProfileResponse)
async def get_profile(
    current_user: CurrentUser = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> UserProfileResponse:
    """Screen 21 (Account Settings) data need: profile fields plus
    `auth_provider`/`is_firebase_linked`, which the screen needs to decide
    which fields are editable (FEAT-041) and what the Linked Sign-In
    Methods section shows (FEAT-040)."""
    user = await auth_service.get_profile(session, user_id=current_user.user_id)
    return _to_profile_response(user)


@router.patch("/profile", response_model=UserProfileResponse)
async def update_profile(
    full_name: str | None = Form(default=None),
    email: str | None = Form(default=None),
    profile_photo: UploadFile | None = File(default=None),
    clear_profile_photo: bool = Form(default=False),
    current_user: CurrentUser = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> UserProfileResponse:
    """Multipart (not JSON), since `profile_photo` (FEAT-041) is a file
    upload -- matching app/api/v1/host_accounts.py's PATCH /me. Partial
    update -- only fields actually sent are changed. `email` is rejected
    server-side for `authProvider` "firebase" accounts regardless of what's
    sent -- see auth_service.update_profile. `profile_photo`/
    `clear_profile_photo` are independent of `full_name`/`email` and of
    each other's validation -- a caller may change any subset in one call.
    """
    if full_name is not None and len(full_name.strip()) == 0:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Full name cannot be empty.",
        )
    if email is not None:
        try:
            email = _email_adapter.validate_python(email)
        except ValidationError as exc:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="Enter a valid email address.",
            ) from exc

    user = await auth_service.update_profile(
        session,
        user_id=current_user.user_id,
        full_name=full_name,
        email=email,
        profile_photo=profile_photo,
        clear_profile_photo=clear_profile_photo,
    )
    return _to_profile_response(user)
