"""De-Duke Backend API Service entrypoint (FastAPI, async-first)."""

import logging
import uuid

import sentry_sdk
from fastapi import Depends, FastAPI, Request
from fastapi.responses import JSONResponse
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession
from starlette.middleware.base import BaseHTTPMiddleware

from app.api.v1 import router as v1_router
from app.core import cache
from app.core.config import get_settings
from app.core.db import get_session
from app.core.logging_config import request_id_var, setup_logging

settings = get_settings()

# Configured before anything else touches logging -- app.core.storage,
# app.services.email_service, etc. all call logging.getLogger(...) at
# their own import time, but Python loggers resolve their effective
# level/handlers lazily (at emit time, via the root logger), so ordering
# here doesn't matter for them; this just has to run before uvicorn
# serves its first request.
setup_logging(settings.log_level)
logger = logging.getLogger("app.main")

# Error tracking (architecture.md Observability Stack: "automatic error
# capture and alerting when something fails") -- a no-op if sentry_dsn is
# still REPLACE_ME (no Secrets Manager value populated yet), matching
# every other third-party integration's REPLACE_ME-gated pattern
# (app/core/config.py). traces_sample_rate enables Sentry's basic
# performance tracing (request latency breakdown) -- a starting point for
# architecture.md's "distributed tracing" requirement; full cross-service
# (API -> DB vs Payment vs Firestore) tracing via OpenTelemetry is a
# deeper follow-up beyond this.
if settings.sentry_dsn != "REPLACE_ME":
    sentry_sdk.init(
        dsn=settings.sentry_dsn, environment=settings.environment, traces_sample_rate=0.1
    )
else:
    logger.info(
        "main: Sentry not configured (sentry_dsn is REPLACE_ME) -- error tracking disabled."
    )

app = FastAPI(
    title="De-Duke Backend API",
    version="0.1.1",
    description="Core business logic: accounts, verification, listings, search, transactions.",
)


class RequestIdMiddleware(BaseHTTPMiddleware):
    """Assigns (or propagates, if the caller already supplied one) a
    correlation ID for every request, available to every log line emitted
    while handling it (app/core/logging_config.py's RequestIdFilter) and
    echoed back in the response so a client/upstream proxy can correlate
    its own logs against this service's.
    """

    async def dispatch(self, request: Request, call_next):  # noqa: ANN001, ANN201
        incoming_id = request.headers.get("X-Request-ID")
        request_id = incoming_id or str(uuid.uuid4())
        token = request_id_var.set(request_id)
        try:
            response = await call_next(request)
        finally:
            request_id_var.reset(token)
        response.headers["X-Request-ID"] = request_id
        return response


app.add_middleware(RequestIdMiddleware)

app.include_router(v1_router)


@app.get("/health/live", tags=["health"])
async def liveness() -> dict[str, str]:
    """Liveness check -- is the process running (architecture.md Health Checks)."""
    return {"status": "ok"}


@app.get("/health/ready", tags=["health"])
async def readiness(session: AsyncSession = Depends(get_session)) -> JSONResponse:
    """Readiness check -- can this task actually reach the Primary Database
    and Cache (architecture.md Health Checks). The ALB only routes to
    tasks passing this, so a task that can't reach its dependencies is
    correctly pulled out of rotation instead of serving requests doomed to
    fail.

    Uses the same DI-injected `session` every other endpoint gets (so this
    respects test overrides / the RDS Proxy in deployed environments) and
    app.core.cache's Redis client directly, matching architecture.md's
    "can it reach the Primary Database and Cache" definition of ready.
    """
    checks = {"database": False, "cache": False}

    try:
        await session.execute(text("SELECT 1"))
        checks["database"] = True
    except Exception:
        logger.exception("readiness: database check failed")

    try:
        await cache.get_redis_client().ping()
        checks["cache"] = True
    except Exception:
        logger.exception("readiness: cache check failed")

    healthy = all(checks.values())
    return JSONResponse(
        status_code=200 if healthy else 503,
        content={"status": "ok" if healthy else "degraded", "checks": checks},
    )
