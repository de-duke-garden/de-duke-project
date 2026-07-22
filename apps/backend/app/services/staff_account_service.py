"""Business logic for FEAT-033 Admin Staff Account Management.

Server-side enforcement lives here and in the `require_roles` dependency
used by the router -- never in the Admin Web Console UI (AGENTS.md).

Every mutating action here writes an immutable `AuditLogEntry` as part of
the same unit of work, per AGENTS.md's audit-log requirement for sensitive
Admin actions.
"""

from __future__ import annotations

import secrets

import anyio
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import CurrentUser, UserRole, hash_password
from app.models.ops import AuditLogEntry
from app.models.user import User

STAFF_ROLES = (UserRole.DEDUKE_STAFF.value, UserRole.DEDUKE_ADMIN.value)


class StaffAccountError(Exception):
    """Base class for staff-account-management domain errors.

    Raised for conditions the router should surface as 4xx responses
    (never silently swallowed) -- see app/api/v1/staff_accounts.py.
    """


class EmailAlreadyInUseError(StaffAccountError):
    pass


class AccountNotFoundError(StaffAccountError):
    pass


class InvalidAccountRoleError(StaffAccountError):
    """Raised when an action is attempted against an account that is not a
    staff/admin account (e.g. targeting a guest/host account)."""


class LastActiveAdminError(StaffAccountError):
    """The platform must always have at least one active deduke_admin
    account (FEAT-033 acceptance criteria). Raised when an action would
    deactivate or demote the last remaining active Admin."""

    def __init__(self) -> None:
        super().__init__(
            "This is the last active Admin account. The platform must always have "
            "at least one active Admin -- deactivate or demote a different Admin "
            "first, or promote another Staff member to Admin before proceeding."
        )


async def _count_active_admins(session: AsyncSession, *, exclude_user_id: str | None = None) -> int:
    stmt = (
        select(func.count())
        .select_from(User)
        .where(
            User.role == UserRole.DEDUKE_ADMIN.value,
            User.is_active.is_(True),
        )
    )
    if exclude_user_id is not None:
        stmt = stmt.where(User.id != exclude_user_id)
    result = await session.execute(stmt)
    return int(result.scalar_one())


async def _get_staff_account(session: AsyncSession, user_id: str) -> User:
    user = await session.get(User, user_id)
    if user is None:
        raise AccountNotFoundError(f"No account found with id {user_id!r}.")
    if user.role not in STAFF_ROLES:
        raise InvalidAccountRoleError(
            "This action only applies to deduke_staff / deduke_admin accounts."
        )
    return user


async def _write_audit_log(
    session: AsyncSession,
    *,
    actor_id: str,
    action_type: str,
    target_id: str,
    notes: str | None = None,
) -> None:
    entry = AuditLogEntry(
        actor_id=actor_id,
        action_type=action_type,
        target_type="User",
        target_id=target_id,
        notes=notes,
    )
    session.add(entry)


async def list_staff_accounts(session: AsyncSession) -> list[User]:
    stmt = select(User).where(User.role.in_(STAFF_ROLES)).order_by(User.created_at.desc())
    result = await session.execute(stmt)
    return list(result.scalars().all())


async def invite_staff(
    session: AsyncSession, *, actor: CurrentUser, full_name: str, email: str
) -> tuple[User, str]:
    """Creates a new deduke_staff account and an invite token.

    Returns the created User and the *raw* invite token (never persisted in
    plaintext -- only its hash is stored on `password_hash`, reusing the
    same hashing primitive as real passwords). The invitee's own
    "accept invite / set password" endpoint belongs to app/api/v1/auth.py
    (owned by a different subagent) -- see the TODO on InviteStaffResponse.
    """
    existing = await session.execute(select(User).where(User.email == email))
    if existing.scalars().first() is not None:
        raise EmailAlreadyInUseError(f"{email} is already associated with an account.")

    raw_token = secrets.token_urlsafe(32)
    # Offloaded to a worker thread -- bcrypt is CPU-bound and synchronous;
    # calling it directly in this `async def` would block the event loop
    # for the hash's full duration. See auth_service.login_with_email's
    # comment for the load-test regression this pattern was found from.
    user = User(
        full_name=full_name,
        email=email,
        role=UserRole.DEDUKE_STAFF.value,
        is_active=True,
        invited_by_id=actor.user_id,
        password_hash=await anyio.to_thread.run_sync(hash_password, raw_token),
    )
    session.add(user)
    await session.flush()  # populate user.id for the audit log FK

    await _write_audit_log(
        session,
        actor_id=actor.user_id,
        action_type="staff_invited",
        target_id=user.id,
        notes=f"Invited {email} as deduke_staff.",
    )
    await session.commit()
    await session.refresh(user)
    return user, raw_token


async def deactivate_account(session: AsyncSession, *, actor: CurrentUser, target_id: str) -> User:
    user = await _get_staff_account(session, target_id)

    if user.role == UserRole.DEDUKE_ADMIN.value and user.is_active:
        remaining = await _count_active_admins(session, exclude_user_id=user.id)
        if remaining == 0:
            raise LastActiveAdminError()

    user.is_active = False
    session.add(user)

    await _write_audit_log(
        session,
        actor_id=actor.user_id,
        action_type="staff_deactivated",
        target_id=user.id,
    )
    await session.commit()
    await session.refresh(user)
    return user


async def reactivate_account(session: AsyncSession, *, actor: CurrentUser, target_id: str) -> User:
    user = await _get_staff_account(session, target_id)
    user.is_active = True
    session.add(user)

    await _write_audit_log(
        session,
        actor_id=actor.user_id,
        action_type="staff_reactivated",
        target_id=user.id,
    )
    await session.commit()
    await session.refresh(user)
    return user


async def promote_to_admin(session: AsyncSession, *, actor: CurrentUser, target_id: str) -> User:
    user = await _get_staff_account(session, target_id)
    if user.role != UserRole.DEDUKE_STAFF.value:
        raise InvalidAccountRoleError("Only a deduke_staff account can be promoted to Admin.")

    user.role = UserRole.DEDUKE_ADMIN.value
    session.add(user)

    await _write_audit_log(
        session,
        actor_id=actor.user_id,
        action_type="staff_promoted_to_admin",
        target_id=user.id,
    )
    await session.commit()
    await session.refresh(user)
    return user


async def demote_to_staff(session: AsyncSession, *, actor: CurrentUser, target_id: str) -> User:
    user = await _get_staff_account(session, target_id)
    if user.role != UserRole.DEDUKE_ADMIN.value:
        raise InvalidAccountRoleError("Only a deduke_admin account can be demoted to Staff.")

    if user.is_active:
        remaining = await _count_active_admins(session, exclude_user_id=user.id)
        if remaining == 0:
            raise LastActiveAdminError()

    user.role = UserRole.DEDUKE_STAFF.value
    session.add(user)

    await _write_audit_log(
        session,
        actor_id=actor.user_id,
        action_type="admin_demoted_to_staff",
        target_id=user.id,
    )
    await session.commit()
    await session.refresh(user)
    return user
