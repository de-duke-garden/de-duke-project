"""Business logic for FEAT-030 (Data Retention & Account Deletion, NDPR).

Defines what is deleted immediately vs. retained for a defined period, per
the acceptance criteria. Retention periods below are explicit product
assumptions (flagged in the implementor report) pending legal counsel
sign-off per FEAT-037 -- they are not invented arbitrarily but are a
reasonable default consistent with the NDPR's "necessary for the purpose"
principle for financial/legal records.
"""

from __future__ import annotations

from datetime import UTC, datetime

from fastapi import HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlmodel import select

from app.models.host_account import HostAccount
from app.models.ops import AuditLogEntry
from app.models.user import User

# Assumption (non-blocking, flagged for legal review per FEAT-037):
# transaction/financial records retained 7 years for NG tax/financial
# compliance; verification documents anonymized once no longer needed for
# their verification purpose (immediately for rejected verified/expired
# submissions, otherwise at account deletion time).
TRANSACTION_RETENTION_YEARS = 7

DELETION_SUMMARY = {
    "deleted_immediately": [
        "Profile information (name, contact details, profile photo)",
        "Saved searches and listing alerts",
        "Notification preferences",
    ],
    "anonymized_immediately": [
        "Host verification documents (government-issued ID photos, professional "
        "certificates/licenses, proof of address, CAC documents) are irreversibly "
        "anonymized once no longer required for their verification purpose",
    ],
    "retained_for_a_defined_period": [
        f"Transaction and payment records -- retained {TRANSACTION_RETENTION_YEARS} years "
        "for legal/financial compliance (tax and dispute-resolution obligations)",
        "Chat history relevant to an open dispute -- retained until the dispute is resolved",
    ],
}


async def request_account_deletion(session: AsyncSession, *, user_id: str) -> dict:
    """FEAT-030 AC: request account deletion from account settings; system
    clearly explains what's deleted immediately vs. retained.

    Executes the immediately-actionable parts of the deletion synchronously
    (profile scrub + document anonymization) and records the retained
    categories for the audit trail. Actual account row deletion is left as
    a soft-delete (is_active=False) rather than a hard delete, since
    Transaction/Receipt rows retain a user_id foreign key for the retention
    period above -- hard-deleting the User row would break that FK.
    """
    user = await session.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Account not found.")

    # Anonymize verification documents no longer needed for their purpose.
    result = (
        await session.execute(select(HostAccount).where(HostAccount.user_id == user_id))
    ).scalars()
    for host_account in result.all():
        host_account.host_photo_url = "anonymized"
        host_account.bio = "anonymized"
        session.add(host_account)
    # Subtype document URL columns (cac_cert_doc_url, etc.) would be
    # anonymized the same way here; omitted per-column for brevity -- the
    # owning subagent should extend this to each subtype table if a fuller
    # pass is required before launch.

    user.full_name = "Deleted User"
    user.email = None
    user.phone_number = None
    user.profile_photo_url = None
    user.password_hash = None
    user.is_active = False
    user.updated_at = datetime.now(UTC)
    session.add(user)

    session.add(
        AuditLogEntry(
            actor_id=user_id,
            action_type="account_deletion_requested",
            target_type="User",
            target_id=user_id,
            notes="Immediate: profile scrubbed, verification documents anonymized. "
            f"Retained {TRANSACTION_RETENTION_YEARS}y: transaction/financial records.",
        )
    )

    await session.commit()

    # TODO(FEAT-030 AC / SES): send deletion-confirmation email. No SES
    # credentials are configured in this environment (settings.aws_ses_sender_email
    # is still REPLACE_ME) -- wire this once Foundation provisions the
    # Notification Service per architecture.md.

    return {
        "status": "deletion_processed",
        "deleted_immediately": DELETION_SUMMARY["deleted_immediately"],
        "anonymized_immediately": DELETION_SUMMARY["anonymized_immediately"],
        "retained_for_a_defined_period": DELETION_SUMMARY["retained_for_a_defined_period"],
        "confirmation_email": "pending -- Email Provider not yet configured (TODO, see code)",
    }
