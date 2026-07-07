"""Cache client (Redis, architecture.md's Caching Layer).

Also backs short-lived, single-use secrets that must survive correctly
across Fargate's many stateless tasks -- OTP codes, the phone-registration
name stash, refresh tokens, and password-reset tokens (all consumed by
app/services/auth_service.py). A per-process dict (this module's
predecessor) only works for a single process; any of these could be
written by one Fargate task and read by another on the very next request.

Deliberately a thin wrapper around a handful of primitives (get/set-with-
TTL/atomic-pop), not a general-purpose cache abstraction -- call sites
needing anything beyond that use get_redis_client() directly.
"""

from __future__ import annotations

from functools import lru_cache

import redis.asyncio as redis

from app.core.config import get_settings

settings = get_settings()

# Bounded timeouts -- a hung/degraded Redis must fail fast rather than pile
# up slow requests against the API service's own capacity (AGENTS.md /
# architecture.md External Service Resilience).
_SOCKET_TIMEOUT_SECONDS = 5


@lru_cache
def get_redis_client() -> redis.Redis:
    """Cached async Redis client, built from settings.redis_url.

    Tests never hit a real Redis -- see tests/conftest.py's autouse fixture,
    which monkeypatches this function to return a fakeredis instance
    instead (the same pattern app/core/storage.py's _get_client uses for
    its own tests).
    """
    return redis.from_url(
        settings.redis_url,
        decode_responses=True,
        socket_connect_timeout=_SOCKET_TIMEOUT_SECONDS,
        socket_timeout=_SOCKET_TIMEOUT_SECONDS,
    )


async def set_with_ttl(key: str, value: str, *, ttl_seconds: int) -> None:
    """Stores `value` under `key`, auto-expiring after ttl_seconds -- the
    Redis-native replacement for a dict entry that (in the old in-memory
    version) never actually expired despite OTP_TTL/RESET_TOKEN_TTL
    constants existing."""
    await get_redis_client().set(key, value, ex=ttl_seconds)


async def pop(key: str) -> str | None:
    """Atomically reads and deletes `key` in a single round-trip (Redis'
    GETDEL) -- prevents a single-use token/OTP from being validated twice
    by two concurrent requests racing a separate GET-then-DELETE."""
    return await get_redis_client().getdel(key)


async def peek(key: str) -> str | None:
    """Reads `key` without deleting it. Used only where a caller must
    validate one key (via `pop`, above) before it's safe to also consume a
    second, related key -- see verify_phone_otp's docstring."""
    return await get_redis_client().get(key)


async def delete(key: str) -> None:
    """Explicit delete for a key that was only `peek`-ed, not `pop`-ed."""
    await get_redis_client().delete(key)
