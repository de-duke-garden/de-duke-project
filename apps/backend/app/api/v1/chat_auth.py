"""FEAT-010: Real-Time Three-Way Support Chat -- token issuance + server-side
conversation creation.

Real-time message send/receive/listening happens CLIENT-SIDE, direct against
Firestore (mobile app + admin console both connect directly using the
custom token issued by `POST /v1/chat/token`). The backend's only jobs here:
  (a) issue scoped Firebase custom auth tokens mapping a De-Duke user + role
      to the claims apps/backend/firestore.rules checks, and
  (b) create the initial conversation document server-side (moderation-
      adjacent, low-frequency, so it's not left to client-authored writes).
"""

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import get_session
from app.core.security import CurrentUser, UserRole, get_current_user, require_roles
from app.schemas.chat import (
    ChatConversationOut,
    ChatTokenResponse,
    ChatUserOut,
    StartConversationRequest,
)
from app.services import chat_service as svc

router = APIRouter()

# Chat Oversight (screens.md Screen 22) is available to any De-Duke Staff
# or Admin, same as Firestore's own isStaff() rule -- not admin-only.
staff_or_admin = require_roles(UserRole.DEDUKE_STAFF, UserRole.DEDUKE_ADMIN)

# Firebase custom tokens are valid for 1 hour before the client must refresh
# them (Firebase Admin SDK's own constraint) -- surfaced to the client so it
# knows when to re-request one.
_CUSTOM_TOKEN_TTL_SECONDS = 60 * 60


@router.post("/token", response_model=ChatTokenResponse)
async def issue_chat_token(
    current_user: CurrentUser = Depends(get_current_user),
) -> ChatTokenResponse:
    """Issues a Firebase custom auth token scoped to the caller's role. The
    client exchanges this (via the Firebase client SDK, not this backend)
    for a Firestore ID token, then reads/writes/listens directly against
    Firestore, gated by firestore.rules on the `role` custom claim.
    """
    try:
        token = svc.issue_custom_token(uid=current_user.user_id, role=current_user.role)
    except svc.ChatServiceUnavailableError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=str(exc),
        ) from exc

    return ChatTokenResponse(
        firebase_custom_token=token,
        role=svc.chat_role_for(current_user.role),
        expires_in_seconds=_CUSTOM_TOKEN_TTL_SECONDS,
    )


@router.post(
    "/conversations", response_model=ChatConversationOut, status_code=status.HTTP_201_CREATED
)
async def start_conversation(
    payload: StartConversationRequest,
    current_user: CurrentUser = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> ChatConversationOut:
    """Creates a new conversation for a listing, validating + resolving the
    property-management-side participant server-side (Listing ->
    HostAccount.user_id, or Listing.agency_id if set) so the client can never
    forge `assignedStaffId` or the other participant's identity.
    """
    try:
        conversation = await svc.create_conversation(
            session, listing_id=payload.listing_id, client_id=current_user.user_id
        )
    except svc.ListingNotFoundError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)) from exc
    except svc.ChatServiceUnavailableError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=str(exc),
        ) from exc

    return ChatConversationOut(
        id=conversation.id,
        listing_id=conversation.listing_id,
        client_id=conversation.client_id,
        property_management_id=conversation.property_management_id,
        assigned_staff_id=conversation.assigned_staff_id,
        last_message_at=conversation.last_message_at,
        created_at=conversation.created_at,
    )


@router.get("/users", response_model=list[ChatUserOut])
async def resolve_chat_user_names(
    ids: str,
    current_user: CurrentUser = Depends(staff_or_admin),
    session: AsyncSession = Depends(get_session),
) -> list[ChatUserOut]:
    """Admin Web Console's Chat Oversight Module (screens.md Screen 22):
    resolves the raw clientId/propertyManagementId/assignedStaffId User
    references a ChatConversation carries into display names, batched into
    one call per visible conversation list rather than one request per id.
    `ids` is a comma-separated list of User ids -- a query param, not a
    path segment, since the caller may need to resolve dozens at once for
    a full conversation list.
    """
    requested_ids = [i for i in ids.split(",") if i]
    users = await svc.resolve_user_names(session, requested_ids)
    return [ChatUserOut(id=u.id, full_name=u.full_name) for u in users]


@router.post("/conversations/{conversation_id}/notify", status_code=status.HTTP_202_ACCEPTED)
async def notify_new_message(
    conversation_id: str,
    current_user: CurrentUser = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> dict[str, str]:
    """FEAT-022 -- called by the SENDING client immediately after its own
    Firestore message write succeeds (see svc.notify_new_message's
    docstring for why this endpoint exists at all: the backend never sees
    a Firestore write happen on its own). Best-effort/fire-and-forget from
    the client's perspective -- 202, not 200/201, since there's no
    resource being created from the caller's point of view, just a
    side-effecting notification trigger.
    """
    await svc.notify_new_message(
        session, conversation_id=conversation_id, sender_id=current_user.user_id
    )
    return {"status": "accepted"}
