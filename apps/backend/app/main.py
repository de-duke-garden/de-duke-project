"""De-Duke Backend API Service entrypoint (FastAPI, async-first)."""

from fastapi import FastAPI

from app.api.v1 import router as v1_router
from app.core.config import get_settings

settings = get_settings()

app = FastAPI(
    title="De-Duke Backend API",
    version="0.1.1",
    description="Core business logic: accounts, verification, listings, search, transactions.",
)

app.include_router(v1_router)


@app.get("/health/live", tags=["health"])
async def liveness() -> dict[str, str]:
    """Liveness check -- is the process running (architecture.md Health Checks)."""
    return {"status": "ok"}


@app.get("/health/ready", tags=["health"])
async def readiness() -> dict[str, str]:
    """Readiness check -- can this task actually serve traffic (reach the
    Primary Database and Cache). The ALB only routes to tasks passing this.

    TODO(Foundation follow-up): wire real DB/Redis connectivity checks once
    the connection pooler and cache client are exercised by a real endpoint.
    """
    return {"status": "ok"}
