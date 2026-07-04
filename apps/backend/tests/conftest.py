"""Shared pytest fixtures -- overrides the Primary Database (Postgres+PostGIS,
asyncpg-only in app/core/db.py) with an in-memory SQLite (aiosqlite) engine
for endpoints that don't require Postgres-only features (PostGIS geospatial
types, pgvector). FEAT-001/002/030 endpoints under test here only use plain
relational tables, so SQLite is a safe stand-in per AGENTS.md test guidance.
"""

from collections.abc import AsyncGenerator

import pytest
import pytest_asyncio
from fastapi.testclient import TestClient
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.pool import StaticPool
from sqlmodel import SQLModel

import app.models  # noqa: F401  -- populates SQLModel.metadata before create_all
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
