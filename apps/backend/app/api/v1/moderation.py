"""Placeholder router for moderation -- filled in during Phase B feature dispatch.

Owning subagent implements real endpoints here per features.md/screens.md.
This stub exists only so the router is registered and app/main.py can boot
during Foundation verification.
"""

from fastapi import APIRouter

router = APIRouter()


@router.get("/_placeholder")
async def placeholder() -> dict[str, str]:
    """Temporary marker endpoint -- remove once real endpoints are added."""
    return {"module": "moderation", "status": "not_yet_implemented"}
