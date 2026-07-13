"""Pydantic request/response schemas for FEAT-020 (Shareable Listing
Summary for Internal Approval) -- Screen 17 (Generate) / Screen 18
(External View)."""

from pydantic import BaseModel, Field


class ShareCreateOut(BaseModel):
    """Response for POST /v1/listings/{id}/share -- Screen 17's "Generated"
    state. `share_token` is embedded client-side into the full external URL
    (e.g. `https://app.example/s/{share_token}`); the backend does not know
    its own public web origin, so it returns the bare token."""

    share_token: str
    listing_id: str
    expires_at: str | None = None


class ShareRevokeOut(BaseModel):
    share_token: str
    is_revoked: bool


class SharedListingSummaryOut(BaseModel):
    """Screen 18's public, no-login summary panel -- deliberately narrow:
    only the fields screens.md Screen 18 lists (price, location, key terms,
    verification status), never seeker/host PII, per Screen 18's Edge Case
    ("no sensitive personal data... beyond what's already public")."""

    listing_id: str
    title: str
    listing_type: str  # commercial | shortlet
    location_city: str
    location_state: str
    location_address_line: str
    price: float
    price_label: str  # e.g. "sale", "lease", "per night"
    key_terms: list[str] = Field(default_factory=list)
    verification_status: str  # verified | unverified
    primary_image_url: str | None = None
    listing_is_active: bool


class ShareStatusOut(BaseModel):
    """Non-viewable states for GET /v1/share/{token} (Screen 18's Revoked/
    Expired state) -- returned instead of SharedListingSummaryOut so the
    external page can distinguish "gone" from a transient fetch error
    without parsing HTTP status text."""

    status: str  # revoked | expired | not_found
    message: str
