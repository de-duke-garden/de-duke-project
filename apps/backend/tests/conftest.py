"""Shared pytest fixtures -- overrides the Primary Database (Postgres+PostGIS,
asyncpg-only in app/core/db.py) with an in-memory SQLite (aiosqlite) engine
for endpoints that don't require Postgres-only features (PostGIS geospatial
types, pgvector). FEAT-001/002/030 endpoints under test here only use plain
relational tables, so SQLite is a safe stand-in per AGENTS.md test guidance.
"""

from collections.abc import AsyncGenerator, Iterator
from contextlib import contextmanager
from unittest.mock import patch

import fakeredis
import pytest
import pytest_asyncio
from fastapi.testclient import TestClient
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.pool import StaticPool
from sqlmodel import SQLModel

import app.models  # noqa: F401  -- populates SQLModel.metadata before create_all
from app.core import cache, storage
from app.core.db import get_session
from app.main import app

#: The live media host. Pinned for every test by _stub_media_storage below,
#: so response URLs are real: a stored `https://cdn.de-duke.com/<key>` row
#: must come back out as `https://cdn.de-duke.org/<key>` (T-021).
TEST_MEDIA_CDN_DOMAIN = "cdn.de-duke.org"

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


@contextmanager
def mock_firebase_verify(
    uid: str,
    *,
    email: str | None = None,
    phone_number: str | None = None,
    name: str | None = None,
) -> Iterator[None]:
    """Test helper (importable by any test module, e.g. `from
    tests.conftest import mock_firebase_verify`): makes
    POST /v1/auth/firebase-exchange (app.services.auth_service.
    exchange_firebase_token, FEAT-001) succeed without a real Firebase
    project, by faking the Firebase Admin SDK's ID-token verification --
    the same "patch _is_configured/_get_firebase_app directly, replace the
    real SDK call with a mock" pattern test_chat.py already established
    for chat_service's own Firebase Admin SDK calls (see that file's
    test_issue_custom_token_calls_admin_sdk_with_role_claim).

    Wrap exactly the request(s) that should reach `firebase-exchange`:

        with mock_firebase_verify(uid="uid-1", email="a@example.com"):
            client.post("/v1/auth/firebase-exchange", json={"id_token": "x"})
    """
    decoded: dict[str, str] = {"uid": uid}
    if email is not None:
        decoded["email"] = email
    if phone_number is not None:
        decoded["phone_number"] = phone_number
    if name is not None:
        decoded["name"] = name

    with (
        patch("app.services.auth_service._is_configured", return_value=True),
        patch("app.services.auth_service._get_firebase_app", return_value=object()),
        patch("firebase_admin.auth.verify_id_token", return_value=decoded),
    ):
        yield


async def _fake_upload_file_key(upload, *, prefix: str) -> str:
    """Deterministic stand-in for app.core.storage.upload_file_key --
    endpoint tests (host account verification, listing image upload) only
    care that *a key* is returned and persisted, not that a real GCS call
    happened. storage.py's own upload/URL-building logic is covered in
    isolation by test_storage.py.

    Returns an object key (never a URL), matching the real contract: the
    read path is what turns it into `https://{TEST_MEDIA_CDN_DOMAIN}/<key>`
    (see _stub_media_storage below).
    """
    return f"{prefix}/{upload.filename or 'upload'}"


async def _fake_upload_bytes_key(
    body: bytes, *, prefix: str, filename: str, content_type: str | None = None
) -> str:
    """Bytes-upload counterpart of `_fake_upload_file_key` above (listing
    video + poster uploads)."""
    return f"{prefix}/{filename or 'upload'}"


@pytest.fixture(autouse=True)
def _stub_media_storage(monkeypatch: pytest.MonkeyPatch) -> None:
    """Patches the name each call site bound at import time (`from
    app.core.storage import upload_file_key`) -- patching
    app.core.storage.upload_file_key itself would not affect those
    already-bound references.

    Also pins the media CDN domain for every test. Read paths now derive a
    URL from the stored object key on every response
    (app/core/media_urls.py), and storage.build_media_url deliberately
    raises on an unconfigured environment -- so without this every test
    that returns a media field would 500 in a repo whose .env leaves
    MEDIA_CDN_DOMAIN at REPLACE_ME. It is set to the real production host
    on purpose: it is exactly the host the T-021 migration rewrites to, so
    the regression test reads the way the incident did.
    """
    monkeypatch.setattr(storage.settings, "media_cdn_domain", TEST_MEDIA_CDN_DOMAIN)
    monkeypatch.setattr(storage.settings, "gcs_endpoint_url", "")
    monkeypatch.setattr(storage.settings, "media_local_public_base_url", "")

    monkeypatch.setattr(
        "app.services.verification_service.upload_file_key",
        _fake_upload_file_key,
    )
    monkeypatch.setattr(
        "app.api.v1.listings.upload_file_key",
        _fake_upload_file_key,
    )
    monkeypatch.setattr(
        "app.api.v1.listings.upload_bytes_key",
        _fake_upload_bytes_key,
    )
    # FEAT-041 -- User.profile_photo_url upload (auth_service.update_profile).
    monkeypatch.setattr(
        "app.services.auth_service.upload_file_key",
        _fake_upload_file_key,
    )
