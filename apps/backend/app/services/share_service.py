"""Business logic for FEAT-020 (Shareable Listing Summary for Internal
Approval) -- generate/revoke a `ShareableSummary` token (Screen 17) and
resolve one into a public, no-login summary (Screen 18).

Depends on FEAT-004 (Listing) per features.md's dependency note -- a share
token is always generated against an existing Listing (+ its Commercial/
Shortlet subtype + owning HostAccount for verification status).
"""

from __future__ import annotations

from datetime import UTC, datetime
from secrets import token_urlsafe

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.discovery import ShareableSummary
from app.models.host_account import HostAccount
from app.models.listing import CommercialListing, Listing, ListingMedia, ShortletListing

# Default link lifetime when the caller doesn't request a shorter one --
# generous enough for an internal approval loop (Screen 17's user story:
# "send it to my manager for quick sign-off") without living forever.
DEFAULT_SHARE_LIFETIME_DAYS = 30


class ShareNotFoundError(Exception):
    """Raised when a share_token doesn't correspond to any ShareableSummary row."""


class ShareForbiddenError(Exception):
    """Raised when a caller tries to revoke a share they didn't create."""


def _generate_token() -> str:
    """URL-safe, unguessable token -- Screen 18's Edge Case explicitly
    anticipates enumeration attempts, so this must not be sequential or
    otherwise predictable."""
    return token_urlsafe(32)


async def create_share(
    session: AsyncSession,
    *,
    listing_id: str,
    created_by_id: str,
    expires_at: datetime | None = None,
) -> ShareableSummary:
    """Creates a new share token for a listing. The previous-link edge case
    ("generates a new link after revoking a previous one -> old token
    remains invalid") is naturally satisfied: revoking sets is_revoked on
    that row only, and a fresh call here always inserts a brand-new row
    with its own token, never reusing or reviving the old one."""
    listing = (
        await session.execute(select(Listing).where(Listing.id == listing_id))
    ).scalar_one_or_none()
    if listing is None:
        raise ShareNotFoundError(f"Listing {listing_id} not found")

    resolved_expiry = expires_at
    if resolved_expiry is None:
        from datetime import timedelta

        resolved_expiry = datetime.now(UTC) + timedelta(days=DEFAULT_SHARE_LIFETIME_DAYS)

    share = ShareableSummary(
        listing_id=listing_id,
        created_by_id=created_by_id,
        share_token=_generate_token(),
        is_revoked=False,
        expires_at=resolved_expiry,
    )
    session.add(share)
    await session.commit()
    await session.refresh(share)
    return share


async def revoke_share(
    session: AsyncSession,
    *,
    share_token: str,
    requesting_user_id: str,
) -> ShareableSummary:
    """Revokes a share -- only the originating user may do this (Screen 17:
    "Revoke Link... by the originating user"). Server-side ownership check,
    never left to client-side hiding of the Revoke button (AGENTS.md)."""
    share = (
        await session.execute(
            select(ShareableSummary).where(ShareableSummary.share_token == share_token)
        )
    ).scalar_one_or_none()
    if share is None:
        raise ShareNotFoundError(f"Share token {share_token} not found")
    if share.created_by_id != requesting_user_id:
        raise ShareForbiddenError("Only the originating user may revoke this share link.")

    share.is_revoked = True
    session.add(share)
    await session.commit()
    await session.refresh(share)
    return share


def is_expired(share: ShareableSummary) -> bool:
    if share.expires_at is None:
        return False
    expires_at = share.expires_at
    if expires_at.tzinfo is None:
        expires_at = expires_at.replace(tzinfo=UTC)
    return datetime.now(UTC) >= expires_at


async def resolve_public_summary(
    session: AsyncSession, *, share_token: str
) -> tuple[str, dict | None]:
    """Resolves a public share token into either a status tuple
    ("revoked"|"expired"|"not_found", None) or ("ok", summary_dict) for
    Screen 18. Never raises for a bad/expired/revoked token -- the public
    endpoint always returns 200 with a distinguishable body, since this is
    an unauthenticated, externally-shared surface and a stack-trace-style
    404/410 is worse UX than a clear in-page message (Screen 18's Revoked/
    Expired state)."""
    share = (
        await session.execute(
            select(ShareableSummary).where(ShareableSummary.share_token == share_token)
        )
    ).scalar_one_or_none()
    if share is None:
        return "not_found", None
    if share.is_revoked:
        return "revoked", None
    if is_expired(share):
        return "expired", None

    listing = (
        await session.execute(select(Listing).where(Listing.id == share.listing_id))
    ).scalar_one_or_none()
    if listing is None:
        # Listing was hard-deleted after the share was generated -- treat as
        # not_found rather than crash; nothing left to summarize.
        return "not_found", None

    host_account = (
        await session.execute(select(HostAccount).where(HostAccount.id == listing.host_account_id))
    ).scalar_one_or_none()
    is_host_verified = host_account is not None and host_account.status == "verified"
    verification_status = "verified" if is_host_verified else "unverified"

    primary_image = (
        await session.execute(
            select(ListingMedia)
            .where(ListingMedia.listing_id == listing.id)
            .where(ListingMedia.is_primary == True)  # noqa: E712
        )
    ).scalar_one_or_none()

    price = 0.0
    price_label = ""
    key_terms: list[str] = []
    if listing.listing_type == "commercial":
        commercial = (
            await session.execute(
                select(CommercialListing).where(CommercialListing.listing_id == listing.id)
            )
        ).scalar_one_or_none()
        if commercial is not None:
            price = commercial.price
            price_label = commercial.deal_type  # sale | lease
            key_terms = [
                f"{commercial.property_subtype}",
                f"{commercial.size_square_meters} sqm",
                f"{commercial.bathrooms} bathroom(s)",
            ]
            if commercial.deal_type == "lease" and commercial.possession_period_days:
                key_terms.append(f"{commercial.possession_period_days}-day possession period")
    elif listing.listing_type == "shortlet":
        shortlet = (
            await session.execute(
                select(ShortletListing).where(ShortletListing.listing_id == listing.id)
            )
        ).scalar_one_or_none()
        if shortlet is not None:
            price = shortlet.nightly_price
            price_label = "per night"
            key_terms = [
                f"{shortlet.bedrooms} bedroom(s)",
                f"{shortlet.bathrooms} bathroom(s)",
                f"min stay {shortlet.minimum_stay_nights} night(s)",
            ]

    summary = {
        "listing_id": listing.id,
        "title": listing.title,
        "listing_type": listing.listing_type,
        "location_city": listing.location_city,
        "location_state": listing.location_state,
        "location_address_line": listing.location_address_line,
        "price": price,
        "price_label": price_label,
        "key_terms": key_terms,
        "verification_status": verification_status,
        "primary_image_url": primary_image.media_url if primary_image else None,
        # Screen 18 Data Flow step 4 / user_flow.md Flow 4 Alternate Path D:
        # a listing that's been unpublished/banned since the link was
        # generated still renders (static details), flagged via this field
        # rather than falling back to "not_found".
        "listing_is_active": listing.status == "active",
    }
    return "ok", summary
