"""FEAT-033: Admin Staff Account Management.

Every endpoint here is gated with `require_roles(UserRole.DEDUKE_ADMIN)` --
Staff accounts have NO access to this router at all (list, invite,
deactivate, promote, demote), per acceptance criteria. This is server-side
enforcement; the Admin Web Console additionally hides these UI elements
from Staff as a UX nicety only, never as the real gate (AGENTS.md).

Note: the FIRST Admin account is created exclusively via
`apps/backend/scripts/bootstrap_admin.py` (a CLI script, not part of this
router / not HTTP-reachable). There is deliberately no endpoint here that
can create a deduke_admin account from nothing.
"""

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import get_session
from app.core.security import CurrentUser, UserRole, require_roles
from app.schemas.staff_account import (
    InviteStaffRequest,
    InviteStaffResponse,
    StaffAccountOut,
    StaffActionResponse,
)
from app.services import staff_account_service as svc

router = APIRouter()

require_admin = require_roles(UserRole.DEDUKE_ADMIN)


def _to_out(user) -> StaffAccountOut:  # noqa: ANN001
    return StaffAccountOut(
        id=user.id,
        full_name=user.full_name,
        email=user.email,
        role=user.role,
        is_active=user.is_active,
        invited_by_id=user.invited_by_id,
        created_at=user.created_at,
    )


@router.get("", response_model=list[StaffAccountOut])
async def list_staff_accounts(
    current_user: CurrentUser = Depends(require_admin),
    session: AsyncSession = Depends(get_session),
) -> list[StaffAccountOut]:
    accounts = await svc.list_staff_accounts(session)
    return [_to_out(a) for a in accounts]


@router.post("/invite", response_model=InviteStaffResponse, status_code=status.HTTP_201_CREATED)
async def invite_staff(
    payload: InviteStaffRequest,
    current_user: CurrentUser = Depends(require_admin),
    session: AsyncSession = Depends(get_session),
) -> InviteStaffResponse:
    try:
        user, raw_token = await svc.invite_staff(
            session, actor=current_user, full_name=payload.full_name, email=payload.email
        )
    except svc.EmailAlreadyInUseError as exc:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(exc)) from exc

    # TODO(email_service): app/services/email_service.py does not exist yet.
    # Once it lands, dispatch this link via SES instead of returning it in
    # the response body. Placeholder base URL -- point at the real Admin
    # Web Console "accept invite" route once app/api/v1/auth.py exposes it.
    invite_link = f"https://admin.deduke.app/accept-invite?token={raw_token}&uid={user.id}"

    return InviteStaffResponse(account=_to_out(user), invite_link=invite_link)


@router.post("/{user_id}/deactivate", response_model=StaffActionResponse)
async def deactivate_staff_account(
    user_id: str,
    current_user: CurrentUser = Depends(require_admin),
    session: AsyncSession = Depends(get_session),
) -> StaffActionResponse:
    user = await _run_or_raise(
        svc.deactivate_account, session, actor=current_user, target_id=user_id
    )
    return StaffActionResponse(account=_to_out(user), message="Account deactivated.")


@router.post("/{user_id}/reactivate", response_model=StaffActionResponse)
async def reactivate_staff_account(
    user_id: str,
    current_user: CurrentUser = Depends(require_admin),
    session: AsyncSession = Depends(get_session),
) -> StaffActionResponse:
    user = await _run_or_raise(
        svc.reactivate_account, session, actor=current_user, target_id=user_id
    )
    return StaffActionResponse(account=_to_out(user), message="Account reactivated.")


@router.post("/{user_id}/promote", response_model=StaffActionResponse)
async def promote_to_admin(
    user_id: str,
    current_user: CurrentUser = Depends(require_admin),
    session: AsyncSession = Depends(get_session),
) -> StaffActionResponse:
    user = await _run_or_raise(svc.promote_to_admin, session, actor=current_user, target_id=user_id)
    return StaffActionResponse(account=_to_out(user), message="Promoted to Admin.")


@router.post("/{user_id}/demote", response_model=StaffActionResponse)
async def demote_to_staff(
    user_id: str,
    current_user: CurrentUser = Depends(require_admin),
    session: AsyncSession = Depends(get_session),
) -> StaffActionResponse:
    user = await _run_or_raise(svc.demote_to_staff, session, actor=current_user, target_id=user_id)
    return StaffActionResponse(account=_to_out(user), message="Demoted to Staff.")


async def _run_or_raise(action, session, *, actor, target_id):  # noqa: ANN001, ANN201
    try:
        return await action(session, actor=actor, target_id=target_id)
    except svc.LastActiveAdminError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc
    except svc.AccountNotFoundError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)) from exc
    except svc.InvalidAccountRoleError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc
