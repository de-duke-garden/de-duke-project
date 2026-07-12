"""FEAT-022 (Push Notifications) -- device token registration + push
preference management. Router stays thin; all logic lives in
app.services.push_service per AGENTS.md.
"""

from fastapi import APIRouter, Depends, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import get_session
from app.core.security import CurrentUser, get_current_user
from app.schemas.notifications import (
    PushNotificationPreferencesResponse,
    RegisterPushTokenRequest,
    UpdatePushNotificationPreferencesRequest,
)
from app.services import push_service

router = APIRouter()


@router.post("/push-token", status_code=status.HTTP_204_NO_CONTENT)
async def register_push_token(
    payload: RegisterPushTokenRequest,
    current_user: CurrentUser = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> None:
    """Called on app start/login once a real FCM token is available
    (mobile-side wiring: firebase_messaging.getToken()). Idempotent --
    see push_service.register_token's upsert-by-token docstring."""
    await push_service.register_token(
        session, user_id=current_user.user_id, token=payload.token, platform=payload.platform
    )


@router.get("/preferences", response_model=PushNotificationPreferencesResponse)
async def get_push_preferences(
    current_user: CurrentUser = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> PushNotificationPreferencesResponse:
    preferences = await push_service.get_notification_preferences(
        session, user_id=current_user.user_id
    )
    return PushNotificationPreferencesResponse(push_notification_preferences=preferences)


@router.patch("/preferences", response_model=PushNotificationPreferencesResponse)
async def update_push_preferences(
    payload: UpdatePushNotificationPreferencesRequest,
    current_user: CurrentUser = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> PushNotificationPreferencesResponse:
    updates = payload.model_dump(exclude_none=True)
    preferences = await push_service.update_notification_preferences(
        session, user_id=current_user.user_id, updates=updates
    )
    return PushNotificationPreferencesResponse(push_notification_preferences=preferences)
