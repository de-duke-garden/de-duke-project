"""HostAccount + its six type-specific subtype tables -- schema.md.

Table-per-type: each subtype is its own table joined 1:1 to `host_accounts`
via `host_account_id`, never SQLAlchemy joined-table inheritance (AGENTS.md).
"""

from datetime import UTC, datetime
from uuid import uuid4

from sqlalchemy import DateTime
from sqlmodel import Field, SQLModel


class HostAccount(SQLModel, table=True):
    __tablename__ = "host_accounts"

    id: str = Field(default_factory=lambda: str(uuid4()), primary_key=True)
    user_id: str = Field(foreign_key="users.id", index=True)

    # owner | agent | company | lawyer | architect | surveyor
    host_type: str = Field(index=True)

    host_photo_url: str
    bio: str

    # in_review | verified | rejected
    status: str = Field(default="in_review", index=True)
    status_reason: str | None = Field(default=None)

    # sa_type=DateTime(timezone=True) -- every datetime in this codebase is
    # timezone-aware UTC (datetime.now(UTC)); without this, SQLModel maps
    # plain `datetime` to TIMESTAMP WITHOUT TIME ZONE, and asyncpg refuses
    # to encode a tz-aware value into a tz-naive column at insert time.
    created_at: datetime = Field(default_factory=lambda: datetime.now(UTC), sa_type=DateTime(timezone=True))
    updated_at: datetime = Field(default_factory=lambda: datetime.now(UTC), sa_type=DateTime(timezone=True))


class HostAccountOwner(SQLModel, table=True):
    """Owners require no documents beyond HostAccount's photo + bio."""

    __tablename__ = "host_account_owners"

    id: str = Field(default_factory=lambda: str(uuid4()), primary_key=True)
    host_account_id: str = Field(foreign_key="host_accounts.id", unique=True)


class HostAccountAgent(SQLModel, table=True):
    __tablename__ = "host_account_agents"

    id: str = Field(default_factory=lambda: str(uuid4()), primary_key=True)
    host_account_id: str = Field(foreign_key="host_accounts.id", unique=True)

    cac_cert_doc_url: str
    industry_license_url: str | None = Field(default=None)
    proof_of_address_url: str
    rep_id_url: str


class HostAccountCompany(SQLModel, table=True):
    __tablename__ = "host_account_companies"

    id: str = Field(default_factory=lambda: str(uuid4()), primary_key=True)
    host_account_id: str = Field(foreign_key="host_accounts.id", unique=True)

    cac_reg_doc_url: str
    proof_of_address_url: str
    rep_id_url: str


class HostAccountLawyer(SQLModel, table=True):
    __tablename__ = "host_account_lawyers"

    id: str = Field(default_factory=lambda: str(uuid4()), primary_key=True)
    host_account_id: str = Field(foreign_key="host_accounts.id", unique=True)

    nba_enrol_no: str
    valid_practicing_cert_url: str
    govt_issued_id_url: str
    proof_of_address_url: str
    ref_phone_no: str


class HostAccountArchitect(SQLModel, table=True):
    __tablename__ = "host_account_architects"

    id: str = Field(default_factory=lambda: str(uuid4()), primary_key=True)
    host_account_id: str = Field(foreign_key="host_accounts.id", unique=True)

    arcon_reg_no: str
    practice_license_url: str
    govt_issued_id_url: str
    ref_phone_no: str


class HostAccountSurveyor(SQLModel, table=True):
    __tablename__ = "host_account_surveyors"

    id: str = Field(default_factory=lambda: str(uuid4()), primary_key=True)
    host_account_id: str = Field(foreign_key="host_accounts.id", unique=True)

    surcon_reg_no: str
    practice_license_url: str
    govt_issued_id_url: str
    ref_phone_no: str
