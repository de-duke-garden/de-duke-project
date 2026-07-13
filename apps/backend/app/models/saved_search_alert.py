"""SavedSearchAlertLog -- FEAT-023 (Saved Searches & Listing Alerts) support
table, not itself in schema.md's entity list (schema.md defines SavedSearch
but no dedupe/log table for alerts already sent). Added here as the
minimal extra state needed to satisfy FEAT-023's AC "does not double-notify"
without inventing fields on the shared `SavedSearch` model
(app/models/discovery.py, owned by the Search & Discovery slice).

NOT registered in app/models/__init__.py by this change -- report the
required import/`__all__` lines to whoever owns that file (per this
feature's file-boundary instructions) rather than editing it directly.
"""

from datetime import UTC, datetime
from uuid import uuid4

from sqlalchemy import DateTime, UniqueConstraint
from sqlmodel import Field, SQLModel


class SavedSearchAlertLog(SQLModel, table=True):
    """One row per (saved_search, listing) pair that has already triggered
    a push notification. The unique constraint is the actual
    double-notification guard -- `saved_search_alert_job.run_alert_sweep`
    checks/inserts against it before sending, so re-running the sweep
    (periodic, possibly overlapping) never re-notifies for a pair it's
    already processed."""

    __tablename__ = "saved_search_alert_logs"
    __table_args__ = (
        UniqueConstraint("saved_search_id", "listing_id", name="uq_saved_search_alert_pair"),
    )

    id: str = Field(default_factory=lambda: str(uuid4()), primary_key=True)
    saved_search_id: str = Field(foreign_key="saved_searches.id", index=True)
    listing_id: str = Field(foreign_key="listings.id", index=True)
    notified_at: datetime = Field(
        default_factory=lambda: datetime.now(UTC), sa_type=DateTime(timezone=True)
    )
