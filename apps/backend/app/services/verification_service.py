"""Business logic for FEAT-002 (Become a Host -- Type-Specific Verification).

Router stays thin; all logic lives here per AGENTS.md.
"""

from __future__ import annotations

from datetime import UTC, datetime

from fastapi import HTTPException, UploadFile, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlmodel import select

from app.core.storage import upload_file as upload_to_media_storage
from app.models.host_account import (
    HostAccount,
    HostAccountAgent,
    HostAccountArchitect,
    HostAccountCompany,
    HostAccountLawyer,
    HostAccountOwner,
    HostAccountSurveyor,
)
from app.schemas.host_account import HostAccountSubmitRequest, HostType
from app.services.email_service import (
    HOST_VERIFICATION_APPROVED,
    HOST_VERIFICATION_REJECTED,
    notify_user,
)

_SUBTYPE_TABLES = {
    HostType.OWNER: HostAccountOwner,
    HostType.AGENT: HostAccountAgent,
    HostType.COMPANY: HostAccountCompany,
    HostType.LAWYER: HostAccountLawyer,
    HostType.ARCHITECT: HostAccountArchitect,
    HostType.SURVEYOR: HostAccountSurveyor,
}


async def _store_file(upload: UploadFile, *, user_id: str) -> str:
    """Persists an uploaded verification document/photo to the File Storage
    Service (S3 + CDN, app/core/storage.py) and returns its durable URL.

    Namespaced by user_id (not host_account.id) because the profile photo
    is uploaded before the HostAccount row -- and therefore its id -- exists
    (see submit_host_account below).
    """
    return await upload_to_media_storage(upload, prefix=f"host-accounts/{user_id}")


async def get_own_submission(session: AsyncSession, *, user_id: str) -> HostAccount | None:
    """Screen 3a: GET /host-accounts/me -- most recent submission for this user."""
    result = await session.execute(
        select(HostAccount)
        .where(HostAccount.user_id == user_id)
        .order_by(HostAccount.created_at.desc())
    )
    return result.scalars().first()


async def update_profile(
    session: AsyncSession,
    *,
    user_id: str,
    bio: str | None = None,
    photo: UploadFile | None = None,
) -> HostAccount:
    """FEAT-042 AC: a host whose most recent submission is `verified` or
    `rejected` can edit their bio and/or their listing photo
    (`HostAccount.hostPhotoUrl`) via `PATCH /host-accounts/me`, without
    re-submitting documents -- independent of the full resubmission-after-
    rejection flow (Screen 3a "Resubmit"). Deliberately blocked while
    `in_review`: staff are actively evaluating exactly what was submitted,
    and letting either field change underneath an active review risks
    staff reviewing stale/mismatched content.

    Both fields are optional and independent -- a caller may update bio
    only, photo only, or both in the same call (the router's multipart
    endpoint only passes what the client actually sent). Photo behaves
    identically to bio: it takes effect on the host's existing live
    listings immediately, since Listing Detail reads `HostAccount` at
    render time rather than baking a copy into each listing (FEAT-042 AC).
    """
    host_account = await get_own_submission(session, user_id=user_id)
    if host_account is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="You don't have a host account submission yet.",
        )
    if host_account.status == "in_review":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=(
                "Your bio and photo can't be edited while your submission is "
                "under review -- they're part of what staff are currently "
                "evaluating."
            ),
        )

    if bio is not None:
        host_account.bio = bio
    if photo is not None:
        # Same File Storage Service (S3 + CDN) path the original Become a
        # Host submission uses -- see _store_file's docstring. Namespaced
        # by user_id, same as submission time.
        host_account.host_photo_url = await _store_file(photo, user_id=user_id)

    host_account.updated_at = datetime.now(UTC)
    session.add(host_account)
    await session.commit()
    await session.refresh(host_account)
    return host_account


async def submit_host_account(
    session: AsyncSession,
    *,
    user_id: str,
    payload: HostAccountSubmitRequest,
    files_by_temp_key: dict[str, UploadFile],
) -> HostAccount:
    """FEAT-002 AC: submit photo, bio, and type-specific documents.

    Blocks a second submission while one is In Review or Verified for this
    user (FEAT-002 AC), but allows a fresh submission after Rejected
    (resubmission).
    """
    existing = await get_own_submission(session, user_id=user_id)
    if existing is not None and existing.status in ("in_review", "verified"):
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"You already have a submission {existing.status.replace('_', ' ')}. "
            "You can't submit a new host type until it is resolved.",
        )

    profile_photo_upload = files_by_temp_key.get(payload.profile_photo_temp_key)
    if profile_photo_upload is None:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Missing profile photo file for the declared profile_photo_temp_key.",
        )
    photo_url = await _store_file(profile_photo_upload, user_id=user_id)

    host_account = HostAccount(
        user_id=user_id,
        host_type=payload.host_type.value,
        host_photo_url=photo_url,
        bio=payload.bio,
        status="in_review",
    )
    session.add(host_account)
    await session.flush()  # assign host_account.id before creating the subtype row

    document_urls: dict[str, str] = {}
    for doc in payload.documents:
        upload = files_by_temp_key.get(doc.temp_key)
        if upload is None:
            detail = (
                f"Missing file for declared document field '{doc.field}' (temp_key={doc.temp_key})."
            )
            raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail=detail)
        document_urls[doc.field] = await _store_file(upload, user_id=user_id)

    subtype_model = _SUBTYPE_TABLES[payload.host_type]
    subtype_kwargs: dict[str, object] = {"host_account_id": host_account.id}
    if payload.host_type == HostType.LAWYER:
        subtype_kwargs.update(
            nba_enrol_no=payload.nba_enrol_no,
            valid_practicing_cert_url=document_urls.get("valid_practicing_cert_url"),
            govt_issued_id_url=document_urls.get("govt_issued_id_url"),
            proof_of_address_url=document_urls.get("proof_of_address_url"),
            ref_phone_no=payload.ref_phone_no,
        )
    elif payload.host_type == HostType.ARCHITECT:
        subtype_kwargs.update(
            arcon_reg_no=payload.arcon_reg_no,
            practice_license_url=document_urls.get("practice_license_url"),
            govt_issued_id_url=document_urls.get("govt_issued_id_url"),
            ref_phone_no=payload.ref_phone_no,
        )
    elif payload.host_type == HostType.SURVEYOR:
        subtype_kwargs.update(
            surcon_reg_no=payload.surcon_reg_no,
            practice_license_url=document_urls.get("practice_license_url"),
            govt_issued_id_url=document_urls.get("govt_issued_id_url"),
            ref_phone_no=payload.ref_phone_no,
        )
    elif payload.host_type == HostType.AGENT:
        subtype_kwargs.update(
            cac_cert_doc_url=document_urls.get("cac_cert_doc_url"),
            industry_license_url=document_urls.get("industry_license_url"),
            proof_of_address_url=document_urls.get("proof_of_address_url"),
            rep_id_url=document_urls.get("rep_id_url"),
        )
    elif payload.host_type == HostType.COMPANY:
        subtype_kwargs.update(
            cac_reg_doc_url=document_urls.get("cac_reg_doc_url"),
            proof_of_address_url=document_urls.get("proof_of_address_url"),
            rep_id_url=document_urls.get("rep_id_url"),
        )
    # Owner: no additional fields beyond host_account_id.

    session.add(subtype_model(**subtype_kwargs))

    from app.models.user import User

    user = await session.get(User, user_id)
    if user is not None:
        user.verification_id = host_account.id
        user.updated_at = datetime.now(UTC)
        session.add(user)

    await session.commit()
    await session.refresh(host_account)
    return host_account


async def list_queue(
    session: AsyncSession, *, status_filter: str, cursor: str | None, limit: int
) -> tuple[list[HostAccount], str | None]:
    """Screen 27: GET /admin/host-accounts?status=in_review -- cursor-based
    (keyset) pagination per architecture.md, ordered oldest-first (queue
    priority) so "newest first" for the *submission age* reads as oldest id
    resolved first -- see AGENTS.md pagination rule."""
    query = select(HostAccount).where(HostAccount.status == status_filter).order_by(HostAccount.id)
    if cursor:
        query = query.where(HostAccount.id > cursor)
    query = query.limit(limit + 1)
    result = await session.execute(query)
    rows = result.scalars().all()
    next_cursor = None
    if len(rows) > limit:
        next_cursor = rows[limit - 1].id
        rows = rows[:limit]
    return list(rows), next_cursor


async def get_submission_detail(session: AsyncSession, *, host_account_id: str) -> HostAccount:
    host_account = await session.get(HostAccount, host_account_id)
    if host_account is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Submission not found.")
    return host_account


async def get_submission_detail_full(session: AsyncSession, *, host_account_id: str) -> dict:
    """Screen 27 detail panel: merges the base HostAccount row with its
    type-specific subtype row (whichever applies to host_type) into one
    flat dict matching HostAccountDetailResponse, so the frontend can
    render exactly the fields relevant to this submission's host type."""
    host_account = await get_submission_detail(session, host_account_id=host_account_id)

    detail: dict = {
        "id": host_account.id,
        "user_id": host_account.user_id,
        "host_type": host_account.host_type,
        "status": host_account.status,
        "status_reason": host_account.status_reason,
        "host_photo_url": host_account.host_photo_url,
        "bio": host_account.bio,
        "created_at": host_account.created_at.isoformat(),
    }

    subtype_model = _SUBTYPE_TABLES.get(HostType(host_account.host_type))
    if subtype_model is not None:
        result = await session.execute(
            select(subtype_model).where(subtype_model.host_account_id == host_account.id)  # type: ignore[attr-defined]
        )
        subtype_row = result.scalars().first()
        if subtype_row is not None:
            for field in type(subtype_row).model_fields:
                if field in ("id", "host_account_id"):
                    continue
                detail[field] = getattr(subtype_row, field)

    return detail


async def resolve_submission(
    session: AsyncSession, *, host_account_id: str, staff_id: str, decision: str, reason: str | None
) -> HostAccount:
    """Screen 27 Verify/Reject action. Guards against double-resolution
    (Screen 27 edge case: two staff act on the same submission) by only
    updating rows still `in_review`."""
    host_account = await get_submission_detail(session, host_account_id=host_account_id)
    if host_account.status != "in_review":
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"This submission was already reviewed (current status: {host_account.status}).",
        )

    host_account.status = decision
    host_account.status_reason = reason
    host_account.updated_at = datetime.now(UTC)
    session.add(host_account)

    if decision == "verified":
        from app.models.user import User

        user = await session.get(User, host_account.user_id)
        if user is not None:
            user.is_verified_host = True
            user.updated_at = datetime.now(UTC)
            session.add(user)

    from app.models.ops import AuditLogEntry

    session.add(
        AuditLogEntry(
            actor_id=staff_id,
            action_type=f"host_account_{decision}",
            target_type="HostAccount",
            target_id=host_account.id,
            notes=reason,
        )
    )

    await session.commit()
    await session.refresh(host_account)

    # TODO(FEAT-022): push notification counterpart -- email-only for now.
    await notify_user(
        session,
        user_id=host_account.user_id,
        template=HOST_VERIFICATION_APPROVED
        if decision == "verified"
        else HOST_VERIFICATION_REJECTED,
        context={"host_type": host_account.host_type, "reason": reason},
    )
    return host_account
