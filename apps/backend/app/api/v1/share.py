"""FEAT-020 (Shareable Listing Summary for Internal Approval) endpoints.

Two auth surfaces in one router:
  - POST /listings/{listing_id}/share and DELETE .../share/{token} require
    an authenticated caller (Screen 17, mobile).
  - GET /share/{token} is deliberately public/unauthenticated (Screen 18,
    external web view) -- no `get_current_user` dependency anywhere on it.

Mounted twice from app/api/v1/__init__.py: the listing-scoped generate/
revoke routes under the existing `/listings` prefix (so they read as
`/v1/listings/{id}/share...`, matching screens.md's documented paths), and
the public by-token lookup under its own `/share` prefix.
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import get_session
from app.core.security import CurrentUser, get_current_user
from app.schemas.share import (
    ShareCreateOut,
    SharedListingSummaryOut,
    ShareRevokeOut,
    ShareStatusOut,
)
from app.services.share_service import (
    ShareForbiddenError,
    ShareNotFoundError,
    create_share,
    resolve_public_summary,
    revoke_share,
)

# Mounted at /v1/listings -- generate/revoke, auth required.
listing_share_router = APIRouter()
# Mounted at /v1/share -- public by-token lookup, no auth.
public_share_router = APIRouter()


@listing_share_router.post(
    "/{listing_id}/share", status_code=status.HTTP_201_CREATED, response_model=ShareCreateOut
)
async def generate_share_endpoint(
    listing_id: str,
    session: AsyncSession = Depends(get_session),
    current_user: CurrentUser = Depends(get_current_user),
) -> ShareCreateOut:
    try:
        share = await create_share(
            session, listing_id=listing_id, created_by_id=current_user.user_id
        )
    except ShareNotFoundError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)) from exc

    return ShareCreateOut(
        share_token=share.share_token,
        listing_id=share.listing_id,
        expires_at=share.expires_at.isoformat() if share.expires_at else None,
    )


@listing_share_router.delete("/{listing_id}/share/{share_token}", response_model=ShareRevokeOut)
async def revoke_share_endpoint(
    listing_id: str,  # noqa: ARG001 -- kept in the route for a screens.md-matching URL shape; ownership is enforced via share_token -> created_by_id, not this path param.
    share_token: str,
    session: AsyncSession = Depends(get_session),
    current_user: CurrentUser = Depends(get_current_user),
) -> ShareRevokeOut:
    try:
        share = await revoke_share(
            session, share_token=share_token, requesting_user_id=current_user.user_id
        )
    except ShareNotFoundError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)) from exc
    except ShareForbiddenError as exc:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail=str(exc)) from exc

    return ShareRevokeOut(share_token=share.share_token, is_revoked=share.is_revoked)


@public_share_router.get("/{share_token}", response_model=SharedListingSummaryOut | ShareStatusOut)
async def get_public_share_endpoint(
    share_token: str,
    session: AsyncSession = Depends(get_session),
) -> SharedListingSummaryOut | ShareStatusOut:
    """No `get_current_user`/`get_current_user_optional` dependency at all --
    Screen 18 is explicitly "Web (external, unauthenticated)"; a non-app-user
    approver must be able to load this with no session/token of their own.
    """
    outcome, summary = await resolve_public_summary(session, share_token=share_token)

    if outcome == "ok" and summary is not None:
        return SharedListingSummaryOut(**summary)

    messages = {
        "revoked": "This summary is no longer available.",
        "expired": "This summary is no longer available.",
        "not_found": "This summary is no longer available.",
    }
    # Deliberately a single, generic public-facing message across
    # revoked/expired/not_found -- Screen 18's Edge Case (no info leakage to
    # a token-guessing third party about *why* a token doesn't resolve).
    return ShareStatusOut(status=outcome, message=messages.get(outcome, messages["not_found"]))
