"""Saved Searches & Listing Alerts -- FEAT-023. Backs Screen 20 (Saved
Searches) and Screen 5's "Save this search" exit point.

Mounted at `/v1/searches` (prefix registered in app/api/v1/__init__.py --
see this feature's report for the exact line, not applied here since that
file is out of this slice's owned scope). Deliberately the plural
`/searches` prefix, distinct from the existing singular `/search` prefix
(`app/api/v1/search.py`, FEAT-006/007/031, a parallel workstream) --
`/searches/saved` matches screens.md's documented endpoint path exactly and
avoids any router-mounting collision between the two feature slices.
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import get_session
from app.core.security import CurrentUser, get_current_user
from app.schemas.saved_search import (
    SavedSearchCreate,
    SavedSearchListResponse,
    SavedSearchOut,
    SavedSearchUpdate,
)
from app.services import saved_search_service

router = APIRouter()


@router.get("/saved", response_model=SavedSearchListResponse)
async def list_saved_searches(
    current_user: CurrentUser = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> SavedSearchListResponse:
    saved_searches = await saved_search_service.list_saved_searches(
        session, user_id=current_user.user_id
    )
    return SavedSearchListResponse(
        results=[SavedSearchOut.model_validate(s) for s in saved_searches]
    )


@router.post("/saved", response_model=SavedSearchOut, status_code=status.HTTP_201_CREATED)
async def create_saved_search(
    payload: SavedSearchCreate,
    current_user: CurrentUser = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> SavedSearchOut:
    saved_search = await saved_search_service.create_saved_search(
        session, user_id=current_user.user_id, payload=payload
    )
    return SavedSearchOut.model_validate(saved_search)


@router.patch("/saved/{saved_search_id}", response_model=SavedSearchOut)
async def update_saved_search(
    saved_search_id: str,
    payload: SavedSearchUpdate,
    current_user: CurrentUser = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> SavedSearchOut:
    """Backs both Screen 20's alert `Switch` (a `{"alerts_enabled": ...}`
    body) and full filter edits (FEAT-023 AC: "edit ... saved searches")."""
    saved_search = await saved_search_service.update_saved_search(
        session, user_id=current_user.user_id, saved_search_id=saved_search_id, payload=payload
    )
    return SavedSearchOut.model_validate(saved_search)


@router.delete("/saved/{saved_search_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_saved_search(
    saved_search_id: str,
    current_user: CurrentUser = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> None:
    await saved_search_service.delete_saved_search(
        session, user_id=current_user.user_id, saved_search_id=saved_search_id
    )
