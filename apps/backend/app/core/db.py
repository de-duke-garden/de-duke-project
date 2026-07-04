"""Async database session management.

Uses an async-native driver (asyncpg) so the FastAPI event loop is never
blocked on DB I/O, per architecture.md's Scaling Strategy. In deployed
environments, `database_url` points at the RDS Proxy (Connection Pooler)
endpoint, not directly at the Primary Database writer.
"""

from collections.abc import AsyncGenerator

from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.core.config import get_settings

settings = get_settings()

engine = create_async_engine(settings.database_url, echo=False, pool_pre_ping=True)

async_session_factory = async_sessionmaker(engine, expire_on_commit=False, class_=AsyncSession)


async def get_session() -> AsyncGenerator[AsyncSession, None]:
    """FastAPI dependency yielding a request-scoped async DB session."""
    async with async_session_factory() as session:
        yield session
