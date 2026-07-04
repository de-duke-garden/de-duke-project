"""SQLModel ORM models, one module per schema.md entity group.

Table-per-type FK relationships model every polymorphic entity (HostAccount
+ its 6 subtypes, Listing + CommercialListing/ShortletListing) -- never
SQLAlchemy joined-table inheritance, per AGENTS.md.

ChatConversation/ChatMessage are defined here as plain (non-table) Pydantic
shapes for type-sharing purposes only -- per architecture.md and schema.md's
storage note, they physically live in Firestore, not the Primary Database,
so they are never registered against SQLModel.metadata / Alembic.
"""

from app.models.agency import AgencyTeamMember, Lead, LeadAssignment
from app.models.discovery import ListingAnalytics, SavedSearch, ShareableSummary
from app.models.host_account import (
    HostAccount,
    HostAccountAgent,
    HostAccountArchitect,
    HostAccountCompany,
    HostAccountLawyer,
    HostAccountOwner,
    HostAccountSurveyor,
)
from app.models.listing import (
    CommercialListing,
    CommercialListingRoom,
    Listing,
    ListingImage,
    ShortletListing,
)
from app.models.ops import AuditLogEntry, CommissionRateConfig, Dispute
from app.models.transaction import Receipt, Transaction
from app.models.user import User

__all__ = [
    "User",
    "HostAccount",
    "HostAccountOwner",
    "HostAccountAgent",
    "HostAccountCompany",
    "HostAccountLawyer",
    "HostAccountArchitect",
    "HostAccountSurveyor",
    "Listing",
    "ListingImage",
    "CommercialListing",
    "CommercialListingRoom",
    "ShortletListing",
    "Transaction",
    "Receipt",
    "AgencyTeamMember",
    "Lead",
    "LeadAssignment",
    "SavedSearch",
    "ShareableSummary",
    "ListingAnalytics",
    "Dispute",
    "CommissionRateConfig",
    "AuditLogEntry",
]
