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
            "One-time link the invitee uses to set their own password. "
            "TODO(email dispatch): app/services/email_service.py does not yet exist "
            "(no other subagent has created it) -- this link is returned in the "
            "response instead of being emailed. Wire this through SES once that "
            "service lands."
        )
    )


class StaffActionResponse(BaseModel):
    account: StaffAccountOut
    message: str
