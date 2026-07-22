"""Shared SQLAlchemy column types.

`UTCDateTime` exists to close a real, already-recurring bug class: every
model in this app declares its timezone-aware datetime columns as
`sa_type=DateTime(timezone=True)` (required so asyncpg can encode a
tz-aware `datetime.now(UTC)` Python value into the column at INSERT time
-- see any model's own comment on this). That guarantees correct
behavior on WRITE, but does NOT guarantee the value comes back tz-aware
on READ: `booking_service.is_hold_active`'s own defensive comment already
documents asyncpg returning a naive (`tzinfo=None`) datetime for a
`timestamptz` column in this environment, discovered when it crashed an
internal comparison with "can't compare offset-naive and offset-aware
datetimes".

That fix only patched the one internal comparison it broke. The same
underlying naive round-trip silently affected a Transaction re-fetched
from the DB (as opposed to used directly from its just-created,
still-in-memory response) whenever `hold_expires_at` was serialized into
an API response: FastAPI/Pydantic serializes a naive datetime with no
`Z`/offset suffix, and the mobile client's `DateTime.parse()` then reads
that ambiguous string as DEVICE-LOCAL time instead of UTC -- making a
correctly-issued 15-minute booking hold appear already expired the
moment the Checkout screen re-fetched it, for any guest not in UTC+0.

Rather than requiring every future read site to remember the same
`if dt.tzinfo is None: dt.replace(tzinfo=UTC)` defensive line (which is
exactly how this recurred a second time), every model's
`sa_type=DateTime(timezone=True)` should use this type instead --
`process_result_value` normalizes once, at the ORM boundary, so nothing
downstream (a Pydantic response, an internal comparison, a background
job) can ever see a naive datetime for a column that's supposed to be
tz-aware.
"""

from __future__ import annotations

from datetime import UTC, datetime

from sqlalchemy import DateTime
from sqlalchemy.types import TypeDecorator


class UTCDateTime(TypeDecorator):
    impl = DateTime(timezone=True)
    cache_ok = True

    def process_result_value(self, value: datetime | None, dialect: object) -> datetime | None:
        if value is not None and value.tzinfo is None:
            return value.replace(tzinfo=UTC)
        return value
