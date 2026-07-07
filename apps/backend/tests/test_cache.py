"""Tests for app/core/cache.py -- the Redis-backed Cache client that
replaced auth_service.py's old in-process dict (which silently broke the
moment more than one Fargate task was running).

Uses fakeredis (see tests/conftest.py's autouse _stub_redis fixture) --
never hits a real Redis instance.
"""

from __future__ import annotations

from app.core import cache


async def test_set_with_ttl_then_get_round_trips() -> None:
    await cache.set_with_ttl("test:key", "hello", ttl_seconds=60)

    value = await cache.peek("test:key")

    assert value == "hello"


async def test_pop_returns_value_and_deletes_it() -> None:
    await cache.set_with_ttl("test:pop-me", "value", ttl_seconds=60)

    first = await cache.pop("test:pop-me")
    second = await cache.pop("test:pop-me")

    assert first == "value"
    assert second is None, "a popped key must not be readable again -- single-use guarantee"


async def test_peek_does_not_delete() -> None:
    await cache.set_with_ttl("test:peek-me", "value", ttl_seconds=60)

    first = await cache.peek("test:peek-me")
    second = await cache.peek("test:peek-me")

    assert first == "value"
    assert second == "value", "peek must be non-destructive, unlike pop"


async def test_delete_removes_a_peeked_key() -> None:
    await cache.set_with_ttl("test:delete-me", "value", ttl_seconds=60)

    await cache.delete("test:delete-me")

    assert await cache.peek("test:delete-me") is None


async def test_missing_key_returns_none_for_pop_and_peek() -> None:
    assert await cache.pop("test:never-set") is None
    assert await cache.peek("test:never-set") is None


async def test_set_with_ttl_actually_expires(monkeypatch) -> None:
    """Confirms a TTL is genuinely set on the Redis key (not just accepted
    as a no-op parameter) -- the exact bug the old in-memory dict had:
    OTP_TTL/RESET_TOKEN_TTL constants existed but nothing ever enforced
    them, so entries lived forever until explicitly popped."""
    await cache.set_with_ttl("test:expires", "value", ttl_seconds=60)

    ttl = await cache.get_redis_client().ttl("test:expires")

    assert 0 < ttl <= 60
