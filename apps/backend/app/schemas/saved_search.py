"""Request/response DTOs for /v1/searches/saved -- FEAT-023 (Saved Searches
& Listing Alerts). Kept separate from the `SavedSearch` ORM model
(app/models/discovery.py) per AGENTS.md's "ORM models are never reused as
API schemas" rule.
"""

from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, Field


class SavedSearchCreate(BaseModel):
    """Screen 5's "Save this search" button and Screen 20's own create
    entry point both post this shape. `listing_type` is nullable to allow
    saving a search across both commercial and shortlet listings."""

    label: str = Field(min_length=1, max_length=120)
    location_query: str = Field(min_length=1, max_length=200)
    radius_km: float = Field(gt=0, le=200)
    # commercial | shortlet | None (both)
    listing_type: str | None = Field(default=None)
    min_price: float | None = Field(default=None, ge=0)
    max_price: float | None = Field(default=None, ge=0)
    verified_only: bool = False
    alerts_enabled: bool = True


class SavedSearchUpdate(BaseModel):
    """Partial update -- Screen 20's alert `Switch` PATCHes just
    `alerts_enabled`, but the same endpoint also supports editing the full
    filter set (FEAT-023 AC: "User can manage (edit/delete) saved
    searches"). Omitted fields are left unchanged."""

    label: str | None = Field(default=None, min_length=1, max_length=120)
    location_query: str | None = Field(default=None, min_length=1, max_length=200)
    radius_km: float | None = Field(default=None, gt=0, le=200)
    listing_type: str | None = Field(default=None)
    clear_listing_type: bool = False
    min_price: float | None = Field(default=None, ge=0)
    max_price: float | None = Field(default=None, ge=0)
    verified_only: bool | None = None
    alerts_enabled: bool | None = None


class SavedSearchOut(BaseModel):
    id: str
    label: str
    location_query: str
    radius_km: float
    listing_type: str | None
    min_price: float | None
    max_price: float | None
    verified_only: bool
    alerts_enabled: bool
    created_at: datetime

    model_config = {"from_attributes": True}


class SavedSearchListResponse(BaseModel):
    """No pagination per screens.md Screen 20 (a seeker's saved search list
    is small and unpaginated -- unlike listing search results)."""

    results: list[SavedSearchOut]
