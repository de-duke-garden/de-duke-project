"""Validation tests for listing request schemas -- FEAT-004/005."""

import pytest
from pydantic import ValidationError

from app.schemas.listing import CommercialListingIn, ListingCreateIn, LocationIn


def _location() -> LocationIn:
    return LocationIn(
        latitude=6.5244,
        longitude=3.3792,
        address_line="1 Admiralty Way",
        city="Lagos",
        state="Lagos",
    )


def test_commercial_listing_requires_valid_deal_type() -> None:
    with pytest.raises(ValidationError):
        CommercialListingIn(
            deal_type="rent-to-own",
            price=1000,
            size_square_meters=100,
            property_subtype="office",
        )


def test_commercial_listing_requires_valid_subtype() -> None:
    with pytest.raises(ValidationError):
        CommercialListingIn(
            deal_type="sale", price=1000, size_square_meters=100, property_subtype="warehouse"
        )


def test_listing_create_requires_valid_listing_type() -> None:
    with pytest.raises(ValidationError):
        ListingCreateIn(
            listing_type="residential",
            title="Nice place",
            description="A place",
            location=_location(),
        )


def test_listing_create_commercial_ok() -> None:
    listing = ListingCreateIn(
        listing_type="commercial",
        title="Office space",
        description="Open plan office",
        location=_location(),
        commercial=CommercialListingIn(
            deal_type="lease", price=500000, size_square_meters=200, property_subtype="office"
        ),
    )
    assert listing.commercial is not None
    assert listing.commercial.deal_type == "lease"
