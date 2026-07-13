"""add listing semantic search embedding (FEAT-031)

Revision ID: c3d4e5f6a7b8
Revises: b2c3d4e5f6a7
Create Date: 2026-07-13 00:00:00.000000

Hand-edited (never trust autogenerate for pgvector types, per AGENTS.md):
autogenerate does not reliably emit `Vector(n)` for a pgvector column, nor
does it know how to express an HNSW index's `vector_cosine_ops` operator
class. Both are written out explicitly below.

Expand-only (AGENTS.md's expand-contract pattern): both new columns are
nullable and additive -- nothing reads/writes them yet at deploy time until
app/services/search_service.py and app/workers/listing_embedding_worker.py
(this same feature slice) start using them, and existing rows are backfilled
lazily by that worker rather than in this migration, so this step never
blocks or locks the table for a long-running backfill.

The `vector` extension itself was already provisioned by the initial schema
migration (231e83887366) ahead of this column's existence -- see that
migration's comment.
"""

from collections.abc import Sequence

import pgvector.sqlalchemy
import sqlalchemy as sa

from alembic import op

revision: str = "c3d4e5f6a7b8"
down_revision: str | None = "b2c3d4e5f6a7"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

# Must match app/models/listing.py's EMBEDDING_DIMENSIONS constant.
_EMBEDDING_DIMENSIONS = 256


def upgrade() -> None:
    op.add_column(
        "listings",
        sa.Column(
            "description_embedding",
            pgvector.sqlalchemy.Vector(_EMBEDDING_DIMENSIONS),
            nullable=True,
        ),
    )
    op.add_column(
        "listings",
        sa.Column("embedding_updated_at", sa.DateTime(timezone=True), nullable=True),
    )

    # HNSW (not IVFFlat) -- IVFFlat's list count must be tuned against
    # existing row counts (poor recall on an empty/near-empty table at
    # migration time); HNSW needs no such training step and is the
    # currently-recommended pgvector default for this reason. Cosine
    # distance ops class to match Listing.description_embedding.cosine_distance()
    # usage in app/services/search_service.py.
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_listings_description_embedding_hnsw "
        "ON listings USING hnsw (description_embedding vector_cosine_ops)"
    )


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS ix_listings_description_embedding_hnsw")
    op.drop_column("listings", "embedding_updated_at")
    op.drop_column("listings", "description_embedding")
