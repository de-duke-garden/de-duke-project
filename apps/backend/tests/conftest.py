"""Shared pytest fixtures -- overrides the Primary Database (Postgres+PostGIS,
asyncpg-only in app/core/db.py) with an in-memory SQLite (aiosqlite) engine
for endpoints that don't require Postgres-only features (PostGIS geospatial
types, pgvector). FEAT-001/002/030 endpoints under test here only use plain
relational tables, so SQLite is a safe stand-in per AGENTS.md test guidance.
"""

from collections.abc import AsyncGenerator

import fakeredis
import pytest
import pytest_asyncio
from fastapi.testclient import TestClient
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.pool import StaticPool
from sqlmodel import SQLModel

import app.models  # noqa: F401  -- populates SQLModel.metadata before create_all
from app.core import cache
from app.core.db import get_session
from app.main import app

test_engine = create_async_engine(
    "sqlite+aiosqlite:///:memory:",
    connect_args={"check_same_thread": False},
    poolclass=StaticPool,
)
TestSessionFactory = async_sessionmaker(test_engine, expire_on_commit=False, class_=AsyncSession)


def _sqlite_safe_tables() -> list:
    """Excludes tables with PostGIS/pgvector column types (e.g. Listing's
    Geography column) that SQLite can't create -- FEAT-001/002/030 endpoints
    under test here never touch those tables, so this is a safe, generic
    filter rather than a hardcoded table-name allowlist."""
    unsupported_type_names = {"geography", "geometry", "vector"}
    safe_tables = []
    for table in SQLModel.metadata.sorted_tables:
        column_type_names = {col.type.__class__.__name__.lower() for col in table.columns}
        if column_type_names & unsupported_type_names:
            continue
        safe_tables.append(table)
    return safe_tables


async def _override_get_session() -> AsyncGenerator[AsyncSession, None]:
    async with TestSessionFactory() as session:
        yield session


@pytest_asyncio.fixture(autouse=True)
async def _reset_schema() -> AsyncGenerator[None, None]:
    """Recreates SQLite-compatible tables before each test for isolation.

    Also re-applies the get_session override on every test, not just once at
    import time -- other test modules (test_chat.py, test_staff_accounts.py)
    call app.dependency_overrides.clear() in their own teardown, which would
    otherwise silently drop this override for every test that runs
    afterwards in the same pytest session, causing later tests to fall
    through to the real (unconfigured) Postgres connection."""
    app.dependency_overrides[get_session] = _override_get_session
    tables = _sqlite_safe_tables()
    async with test_engine.begin() as conn:
        await conn.run_sync(
            lambda sync_conn: SQLModel.metadata.create_all(sync_conn, tables=tables)
        )
    yield
    async with test_engine.begin() as conn:
        await conn.run_sync(lambda sync_conn: SQLModel.metadata.drop_all(sync_conn, tables=tables))


@pytest.fixture
def client() -> TestClient:
    return TestClient(app)


@pytest_asyncio.fixture
async def session() -> AsyncGenerator[AsyncSession, None]:
    """Direct DB session access for tests that need to set up/inspect rows
    without going through an HTTP endpoint (e.g. test_email_service.py).
    Same test_engine/table set as the `client` fixture's own session
    override above, so rows created here are visible to requests made via
    `client` in the same test."""
    async with TestSessionFactory() as session:
        yield session


@pytest_asyncio.fixture(autouse=True)
async def _stub_redis(monkeypatch: pytest.MonkeyPatch) -> AsyncGenerator[None, None]:
    """Replaces app.core.cache's real Redis client with fakeredis (an
    in-memory, protocol-compatible fake) -- the same "safe stand-in per
    AGENTS.md test guidance" principle _reset_schema above applies to
    Postgres/SQLite, applied here to Redis, so tests never depend on a
    live Redis instance (matches auth_service.py's OTP/refresh/reset-token
    storage, which now lives entirely in the Cache).

    A fresh FakeServer per test gives natural isolation (no explicit
    flush needed). get_redis_client() is patched to build a *new*
    FakeAsyncRedis client per call, all sharing that one FakeServer's
    backing data, rather than one long-lived client instance -- Starlette's
    TestClient runs the ASGI app in its own thread with its own event
    loop, separate from this fixture's/test's loop, and fakeredis's async
    client binds internal asyncio primitives (locks/connections) to
    whichever loop first touches it. A single shared client silently
    breaks the moment two different loops call it; a fresh client per
    call sidesteps that entirely.
    """
    fake_server = fakeredis.FakeServer()

    def _make_fake_client() -> fakeredis.FakeAsyncRedis:
        return fakeredis.FakeAsyncRedis(server=fake_server, decode_responses=True)

    monkeypatch.setattr(cache, "get_redis_client", _make_fake_client)
    yield


async def _fake_upload_to_media_storage(upload, *, prefix: str) -> str:
    """Deterministic stand-in for app.core.storage.upload_file -- endpoint
    tests (host account verification, listing image upload) only care that
    *a* URL is returned and persisted, not that a real S3/LocalStack call
    happened. storage.py's own upload/URL-building logic is covered in
    isolation by test_storage.py."""
    return f"https://test-media.example/{prefix}/{upload.filename or 'upload'}"


@pytest.fixture(autouse=True)
def _stub_media_storage(monkeypatch: pytest.MonkeyPatch) -> None:
    """Patches the name each call site bound at import time (`from
    app.core.storage import upload_file as upload_to_media_storage`) --
    patching app.core.storage.upload_file itself would not affect those
    already-bound references."""
    monkeypatch.setattr(
        "app.services.verification_service.upload_to_media_storage",
        _fake_upload_to_media_storage,
    )
    monkeypatch.setattr(
        "app.api.v1.listings.upload_to_media_storage",
        _fake_upload_to_media_storage,
    )
