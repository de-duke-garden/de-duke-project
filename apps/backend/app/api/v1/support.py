"""FEAT-029: General In-App Support / Help -- screens.md Screen 21 (Account
Settings, mobile entry point) / Screen 26 (Admin General Support Inbox).

Mirrors chat_auth.py's shape exactly: the backend only issues the Firebase
custom token (already covered by POST /v1/chat/token -- support
conversations use the SAME token/claims, just a different Firestore
collection gated by its own firestore.rules match block) and creates the
conversation document server-side. Real-time messages are client-side
direct to Firestore, same as regular chat.
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import get_session
from app.core.security import CurrentUser, get_current_user
from app.schemas.support import SupportConversationOut
from app.services import chat_service as svc

router = APIRouter()


@router.post(
    "/conversations", response_model=SupportConversationOut, status_code=status.HTTP_201_CREATED
)
async def get_or_create_support_conversation(
    current_user: CurrentUser = Depends(get_current_user),
) -> SupportConversationOut:
    """Idempotent -- returns the caller's existing support conversation if
    one already exists (there is at most one per user), otherwise creates
    it. Safe to call every time the mobile Help & Support entry point is
    opened."""
    try:
        conversation = await svc.get_or_create_support_conversation(
            user_id=current_user.user_id
        )
    except svc.ChatServiceUnavailableError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=str(exc),
        ) from exc

    return SupportConversationOut(
        id=conversation.id,
        user_id=conversation.user_id,
        assigned_staff_id=conversation.assigned_staff_id,
        status=conversation.status,
        last_message_at=conversation.last_message_at,
        created_at=conversation.created_at,
    )


@router.post("/conversations/{conversation_id}/notify", status_code=status.HTTP_202_ACCEPTED)
async def notify_new_support_message(
    conversation_id: str,
    current_user: CurrentUser = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> None:
    """Called by the sending client immediately after its own Firestore
    message write succeeds -- same design as chat_auth.py's
    /conversations/{id}/notify (the backend never sees the Firestore write
    itself, so it cannot trigger a push from that event directly)."""
    try:
        await svc.notify_new_support_message(
            session, conversation_id=conversation_id, sender_id=current_user.user_id
        )
    except svc.ChatServiceUnavailableError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=str(exc),
        ) from exc
