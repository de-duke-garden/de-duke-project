"""Real endpoints for /v1/host-accounts -- FEAT-002 (Become a Host).

Router stays thin; all logic lives in app.services.verification_service.
Staff-only endpoints (list-for-review, approve/reject) live under the same
router but are additionally guarded by require_roles.
"""

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import get_session
from app.core.security import CurrentUser, UserRole, get_current_user, require_roles
from app.schemas.host_account import (
    HostAccountDetailResponse,
    HostAccountQueueItem,
    HostAccountReviewAction,
    HostAccountStatusResponse,
    HostAccountSubmitRequest,
    PaginatedHostAccountQueue,
)
from app.services import verification_service

router = APIRouter()


def _to_status_response(host_account) -> HostAccountStatusResponse:  # type: ignore[no-untyped-def]
    return HostAccountStatusResponse(
        id=host_account.id,
        host_type=host_account.host_type,
        status=host_account.status,
        status_reason=host_account.status_reason,
        host_photo_url=host_account.host_photo_url,
        bio=host_account.bio,
    )


@router.get("/me", response_model=HostAccountStatusResponse | None)
async def get_my_submission(
    current_user: CurrentUser = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> HostAccountStatusResponse | None:
    """Screen 3a data need: current submission status, if any."""
    host_account = await verification_service.get_own_submission(
        session, user_id=current_user.user_id
    )
    if host_account is None:
        return None
    return _to_status_response(host_account)


@router.post("", response_model=HostAccountStatusResponse, status_code=status.HTTP_201_CREATED)
async def submit_host_account(
    submission: str = Form(..., description="JSON-encoded HostAccountSubmitRequest"),
    files: list[UploadFile] = File(default_factory=list),
    current_user: CurrentUser = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> HostAccountStatusResponse:
    """Screen 3b Submit button -- structured multi-file upload contract
    (architecture.md): `submission` is a JSON sub-record declaring each
    document's `temp_key`, matched here against the actual multipart `files`
    parts by each UploadFile's field name/filename, never by array index.
    """
    try:
        payload = HostAccountSubmitRequest.model_validate_json(submission)
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail=str(exc)
        ) from exc

    # Match each declared temp_key to its multipart file part by filename,
    # since Starlette's `list[UploadFile]` does not preserve custom per-part
    # field names beyond "files" -- the client sets each file part's
    # filename to the temp_key it declared in `submission`.
    files_by_temp_key = {f.filename: f for f in files if f.filename}

    host_account = await verification_service.submit_host_account(
        session, user_id=current_user.user_id, payload=payload, files_by_temp_key=files_by_temp_key
    )
    return _to_status_response(host_account)


@router.get("/admin", response_model=PaginatedHostAccountQueue)
async def list_submissions_for_review(
    status_filter: str = "in_review",
    cursor: str | None = None,
    limit: int = 25,
    current_user: CurrentUser = Depends(
        require_roles(UserRole.DEDUKE_STAFF, UserRole.DEDUKE_ADMIN)
    ),
    session: AsyncSession = Depends(get_session),
) -> PaginatedHostAccountQueue:
    """Screen 27: GET /admin/host-accounts?status=in_review. Cursor-based
    (keyset) pagination per architecture.md AGENTS.md pagination rules."""
    rows, next_cursor = await verification_service.list_queue(
        session, status_filter=status_filter, cursor=cursor, limit=limit
    )
    return PaginatedHostAccountQueue(
        items=[
            HostAccountQueueItem(
                id=r.id,
                user_id=r.user_id,
                host_type=r.host_type,
                status=r.status,
                created_at=r.created_at.isoformat(),
            )
            for r in rows
        ],
        next_cursor=next_cursor,
    )


@router.get("/admin/{host_account_id}", response_model=HostAccountDetailResponse)
async def get_submission_detail(
    host_account_id: str,
    current_user: CurrentUser = Depends(
        require_roles(UserRole.DEDUKE_STAFF, UserRole.DEDUKE_ADMIN)
    ),
    session: AsyncSession = Depends(get_session),
) -> HostAccountDetailResponse:
    """Screen 27 detail panel -- every type-specific document/field
    relevant to this submission's host_type, per screens.md."""
    detail = await verification_service.get_submission_detail_full(
        session, host_account_id=host_account_id
    )
    return HostAccountDetailResponse(**detail)


@router.patch("/admin/{host_account_id}/status", response_model=HostAccountStatusResponse)
async def review_submission(
    host_account_id: str,
    action: HostAccountReviewAction,
    current_user: CurrentUser = Depends(
        require_roles(UserRole.DEDUKE_STAFF, UserRole.DEDUKE_ADMIN)
    ),
    session: AsyncSession = Depends(get_session),
) -> HostAccountStatusResponse:
    """Screen 27 Verify/Reject action."""
    host_account = await verification_service.resolve_submission(
        session,
        host_account_id=host_account_id,
        staff_id=current_user.user_id,
        decision=action.decision,
        reason=action.reason,
    )
    return _to_status_response(host_account)
