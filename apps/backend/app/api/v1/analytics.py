"""FEAT-034 (Operations Analytics Dashboard, Staff + Admin) and FEAT-035
(Business & Revenue Analytics Dashboard, Admin only) -- screens.md Screens
29/30. Role gates enforced server-side via `require_roles`, same pattern
as moderation.py/disputes.py -- never rely on hiding UI elements
client-side.
"""

from __future__ import annotations

from datetime import datetime

from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import get_session
from app.core.security import CurrentUser, UserRole, require_roles
from app.schemas.analytics import BusinessDashboardOut, OperationsDashboardOut
from app.services import business_analytics_service, ops_analytics_service

router = APIRouter()

staff_or_admin = require_roles(UserRole.DEDUKE_STAFF, UserRole.DEDUKE_ADMIN)
admin_only = require_roles(UserRole.DEDUKE_ADMIN)


@router.get("/operations", response_model=OperationsDashboardOut)
async def get_operations_dashboard(
    _current_user: CurrentUser = Depends(staff_or_admin),
    session: AsyncSession = Depends(get_session),
) -> OperationsDashboardOut:
    data = await ops_analytics_service.get_operations_dashboard(session)
    return OperationsDashboardOut(**data)


@router.get("/business", response_model=BusinessDashboardOut)
async def get_business_dashboard(
    since: datetime | None = Query(default=None),
    _current_user: CurrentUser = Depends(admin_only),
    session: AsyncSession = Depends(get_session),
) -> BusinessDashboardOut:
    data = await business_analytics_service.get_business_dashboard(session, since=since)
    return BusinessDashboardOut(**data)
