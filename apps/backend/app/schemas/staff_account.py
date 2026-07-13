"""Request/response contracts for FEAT-033 Admin Staff Account Management.

Deliberately decoupled from the `User` ORM model (AGENTS.md: ORM models are
never reused as API schemas) -- in particular `password_hash` and other
internal fields are never exposed here.
"""

from datetime import datetime

from pydantic import BaseModel, Field


class StaffAccountOut(BaseModel):
    id: str
    full_name: str
    email: str | None
    role: str
    is_active: bool
    invited_by_id: str | None
    created_at: datetime


class InviteStaffRequest(BaseModel):
    full_name: str = Field(min_length=1, max_length=200)
    email: str = Field(min_length=3, max_length=320)


class InviteStaffResponse(BaseModel):
    account: StaffAccountOut
    invite_link: str = Field(
        description=(
            "One-time link the invitee uses to set their own password via "
            "POST /v1/auth/accept-invite (app/services/auth_service.py). "
            "Also emailed to the invitee directly (see "
            "app/api/v1/staff_accounts.py's invite_staff) -- returned here too "
            "so the inviting Admin can copy/share it directly if needed."
        )
    )


class StaffActionResponse(BaseModel):
    account: StaffAccountOut
    message: str
