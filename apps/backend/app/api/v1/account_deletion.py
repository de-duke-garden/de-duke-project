"""Endpoints for /v1/account-deletion -- FEAT-030 (Data Retention & Account
Deletion, NDPR Compliance). Router stays thin; logic lives in
app.services.data_retention_service.
"""

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import get_session
from app.core.security import CurrentUser, get_current_user
from app.services import data_retention_service

router = APIRouter()


@router.post("/request")
async def request_deletion(
    current_user: CurrentUser = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> dict:
    """Account Settings 'Request Account Deletion' action. Response details
    what's deleted immediately vs. retained for a defined period (FEAT-030 AC)."""
    return await data_retention_service.request_account_deletion(
        session, user_id=current_user.user_id
    )
