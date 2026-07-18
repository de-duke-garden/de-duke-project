"""generalize listing_images to listing_media (photo + video support)

Revision ID: d3e4f5a6b7c8
Revises: b1c2d3e4f5a6
Create Date: 2026-07-18 10:00:00.000000

Product decision (docs/De-Duke/schema.md's `ListingMedia` entity, shaped via
product-shaper): listings now support short video clips alongside photos,
displayed interleaved in the same gallery. Rather than adding a parallel
`listing_videos` table, `listing_images` is generalized in place -- a single
entity with a `media_type` discriminator keeps one shared `display_order`
sequence across both photos and videos, which the interleaved-gallery
product decision requires (a video and a photo need to be orderable against
each other, not just within their own type).

Existing rows migrate 1:1: every current `listing_images` row becomes a
`listing_media` row with `media_type='image'` (server_default handles this
for free -- no separate data migration needed) and the three video-only
columns (`poster_url`, `duration_seconds`, `processing_status`) stay NULL,
since they're meaningless for a photo. `processing_status` defaults to
'ready' for the same reason -- an image never goes through the
poster-generation step a video does (see app/services/listing_service.py's
video upload handling), so it's "ready" (i.e. immediately displayable) from
the moment it exists.

`is_primary` remains restricted to `media_type='image'` rows going forward
(enforced at the API layer, app/api/v1/listings.py) -- a video can never be
a listing's card thumbnail (schema.md's documented invariant). Not a CHECK
constraint here since this is app-layer-enforced, matching how the
"exactly one primary per listing" invariant was already enforced (see
listing_service.py's upload handling) rather than a DB constraint.
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "d3e4f5a6b7c8"
down_revision: str | None = "b1c2d3e4f5a6"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.rename_table("listing_images", "listing_media")
    op.execute("ALTER INDEX ix_listing_images_listing_id RENAME TO ix_listing_media_listing_id")

    op.alter_column("listing_media", "image_url", new_column_name="media_url")

    op.add_column(
        "listing_media",
        # image | video. server_default backfills every pre-existing row
        # (all of them photos) without a separate UPDATE statement.
        sa.Column("media_type", sa.String(), nullable=False, server_default="image"),
    )
    op.add_column(
        "listing_media",
        # Server-generated poster/thumbnail frame for a video (see
        # listing_service.py) -- always NULL for an image row.
        sa.Column("poster_url", sa.String(), nullable=True),
    )
    op.add_column(
        "listing_media",
        # Clip length in seconds, probed server-side at upload time --
        # always NULL for an image row.
        sa.Column("duration_seconds", sa.Float(), nullable=True),
    )
    op.add_column(
        "listing_media",
        # pending | ready | failed -- tracks server-side poster-frame
        # generation for a video row. 'ready' for every image row (there is
        # nothing to process), matching this migration's docstring.
        sa.Column(
            "processing_status", sa.String(), nullable=True, server_default="ready"
        ),
    )


def downgrade() -> None:
    op.drop_column("listing_media", "processing_status")
    op.drop_column("listing_media", "duration_seconds")
    op.drop_column("listing_media", "poster_url")
    op.drop_column("listing_media", "media_type")

    op.alter_column("listing_media", "media_url", new_column_name="image_url")

    op.execute("ALTER INDEX ix_listing_media_listing_id RENAME TO ix_listing_images_listing_id")
    op.rename_table("listing_media", "listing_images")
