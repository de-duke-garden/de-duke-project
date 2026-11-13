"""Regression tests for T-021: a stored media value must render as a URL on
the *current* CDN host, and the write paths must store object keys.

The incident this guards against: URLs were minted once at upload time and
stored as strings, so moving the CDN from `cdn.de-duke.com` to
`cdn.de-duke.org` left every image, avatar, verification document and
receipt pointing at a host that no longer resolves.

`tests/conftest.py`'s `_stub_media_storage` pins MEDIA_CDN_DOMAIN to
`cdn.de-duke.org` for every test, so these assertions read like the
production data they describe.
"""

from __future__ import annotations

import io
import json
from typing import Any

from fastapi.testclient import TestClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlmodel import SQLModel

from app.core.media_urls import render_media_urls
from app.core.security import UserRole, create_access_token
from app.models.host_account import HostAccount, HostAccountLawyer
from app.models.listing import ListingMedia
from app.schemas.host_account import HostAccountStatusResponse
from tests.conftest import TestSessionFactory, mock_firebase_verify

LEGACY_HOST = "https://cdn.de-duke.com"
CURRENT_HOST = "https://cdn.de-duke.org"


def _signin(client: TestClient, email: str) -> tuple[str, str]:
    """FEAT-001 sign-in via a faked Firebase ID token exchange -- same helper
    shape as test_host_accounts.py's _register_and_login."""
    with mock_firebase_verify(uid=f"uid-{email}", email=email, name="Media User"):
        response = client.post("/v1/auth/firebase-exchange", json={"id_token": "fake-token"})
    body = response.json()
    return body["access_token"], body["user_id"]


def _submit_owner(client: TestClient, token: str) -> None:
    submission = {
        "host_type": "owner",
        "bio": "I own a property in Lekki.",
        "profile_photo_temp_key": "photo.jpg",
        "documents": [],
    }
    response = client.post(
        "/v1/host-accounts",
        headers={"Authorization": f"Bearer {token}"},
        data={"submission": json.dumps(submission)},
        files=[("files", ("photo.jpg", io.BytesIO(b"\xff\xd8\xff\xe0jpeg"), "image/jpeg"))],
    )
    assert response.status_code == 201


# ---------------------------------------------------------------------------
# Serialization layer (pure, no HTTP)
# ---------------------------------------------------------------------------


def test_schema_renders_legacy_com_host_photo_as_org() -> None:
    """The response schema is the last stop before JSON for every endpoint
    that builds one -- a stored legacy URL must not survive it."""
    response = HostAccountStatusResponse(
        id="ha-1",
        host_type="owner",
        status="verified",
        status_reason=None,
        host_photo_url=f"{LEGACY_HOST}/host-accounts/user-1/photo.jpg",
        bio="A host.",
    )

    assert response.host_photo_url == f"{CURRENT_HOST}/host-accounts/user-1/photo.jpg"


def test_schema_renders_a_bare_object_key() -> None:
    """Rows written after this change hold a key, and a key must never reach
    a client as if it were a URL."""
    response = HostAccountStatusResponse(
        id="ha-1",
        host_type="owner",
        status="verified",
        status_reason=None,
        host_photo_url="host-accounts/user-1/photo.jpg",
        bio="A host.",
    )

    assert response.host_photo_url == f"{CURRENT_HOST}/host-accounts/user-1/photo.jpg"


def test_render_media_urls_covers_listing_bundle_including_media_array() -> None:
    """The listing bundle is a plain dict (no response_model), so
    render_media_urls is what guarantees a key or legacy URL never leaks."""
    bundle: dict[str, Any] = {
        "id": "listing-1",
        "host_photo_url": f"{LEGACY_HOST}/host-accounts/user-1/photo.jpg",
        "media": [
            {
                "media_type": "image",
                "media_url": f"{LEGACY_HOST}/listings/listing-1/photo.jpg",
                "poster_url": None,
            },
            {
                "media_type": "video",
                "media_url": "listings/listing-1/clip.mp4",
                "poster_url": f"{LEGACY_HOST}/listings/listing-1/posters/poster.jpg",
            },
        ],
        "commercial": {
            # Document *type* names, not URLs -- must never be reinterpreted.
            "legal_documents": ["Certificate of Occupancy", "Survey Plan"],
            "rooms": [{"level": "ground", "width_meters": 4.0, "length_meters": 5.0}],
        },
    }

    rendered = render_media_urls(bundle)

    assert rendered["host_photo_url"] == f"{CURRENT_HOST}/host-accounts/user-1/photo.jpg"
    assert rendered["media"][0]["media_url"] == f"{CURRENT_HOST}/listings/listing-1/photo.jpg"
    assert rendered["media"][0]["poster_url"] is None
    assert rendered["media"][1]["media_url"] == f"{CURRENT_HOST}/listings/listing-1/clip.mp4"
    assert (
        rendered["media"][1]["poster_url"]
        == f"{CURRENT_HOST}/listings/listing-1/posters/poster.jpg"
    )
    assert rendered["commercial"]["legal_documents"] == [
        "Certificate of Occupancy",
        "Survey Plan",
    ]
    # Copied through, not mutated in place: callers keep the dict they built.
    assert bundle["media"][0]["media_url"].startswith(LEGACY_HOST)


def test_render_media_urls_is_idempotent() -> None:
    once = render_media_urls({"media_url": f"{LEGACY_HOST}/listings/a/photo.jpg"})
    twice = render_media_urls(once)

    assert once == twice


# ---------------------------------------------------------------------------
# End to end: database value -> request -> JSON
# ---------------------------------------------------------------------------


async def test_submitted_host_photo_is_stored_as_an_object_key(
    client: TestClient, session: AsyncSession
) -> None:
    """AC: write paths store the key, not a URL -- so no future domain move
    can strand this row."""
    token, user_id = _signin(client, "stored-key@example.com")

    _submit_owner(client, token)

    async with TestSessionFactory() as fresh_session:
        row = (
            (
                await fresh_session.execute(
                    select(HostAccount).where(
                        # SQLModel's mypy support does not type a model
                        # class attribute as a SQL expression, so this
                        # comparison reads as `bool` to mypy -- the same
                        # noise app/ code carries throughout.
                        HostAccount.user_id == user_id  # type: ignore[arg-type]
                    )
                )
            )
            .scalars()
            .first()
        )
    assert row is not None
    assert row.host_photo_url == f"host-accounts/{user_id}/photo.jpg"
    assert "://" not in row.host_photo_url


async def test_legacy_com_stored_row_serializes_to_org_url(
    client: TestClient, session: AsyncSession
) -> None:
    """The incident's exact reproduction: a row in the database still holds a
    `https://cdn.de-duke.com/...` string; the API must answer with the live
    host without any migration having run against this row."""
    token, user_id = _signin(client, "legacy-row@example.com")
    session.add(
        HostAccount(
            user_id=user_id,
            host_type="owner",
            host_photo_url=f"{LEGACY_HOST}/host-accounts/{user_id}/photo.jpg",
            bio="A host from before the move.",
            status="verified",
        )
    )
    await session.commit()

    response = client.get("/v1/host-accounts/me", headers={"Authorization": f"Bearer {token}"})

    assert response.status_code == 200
    assert response.json()["host_photo_url"] == f"{CURRENT_HOST}/host-accounts/{user_id}/photo.jpg"


async def test_legacy_com_verification_document_serializes_to_org_url(
    client: TestClient, session: AsyncSession
) -> None:
    """Screen 27 (staff review) copies the type-specific document columns
    generically -- all fourteen of them must render through the same path."""
    _, user_id = _signin(client, "legacy-docs@example.com")
    host_account = HostAccount(
        user_id=user_id,
        host_type="lawyer",
        host_photo_url=f"{LEGACY_HOST}/host-accounts/{user_id}/photo.jpg",
        bio="Called to the bar.",
        status="verified",
    )
    session.add(host_account)
    await session.flush()
    session.add(
        HostAccountLawyer(
            host_account_id=host_account.id,
            nba_enrol_no="NBA/12345",
            valid_practicing_cert_url=f"{LEGACY_HOST}/host-accounts/{user_id}/cert.pdf",
            govt_issued_id_url=f"host-accounts/{user_id}/id.png",
            proof_of_address_url=f"{LEGACY_HOST}/host-accounts/{user_id}/address.pdf",
            ref_phone_no="+2348000000000",
        )
    )
    await session.commit()

    staff_token = create_access_token(user_id="staff-1", role=UserRole.DEDUKE_STAFF)
    response = client.get(
        f"/v1/host-accounts/admin/{host_account.id}",
        headers={"Authorization": f"Bearer {staff_token}"},
    )

    assert response.status_code == 200
    body = response.json()
    assert body["host_photo_url"] == f"{CURRENT_HOST}/host-accounts/{user_id}/photo.jpg"
    assert body["valid_practicing_cert_url"] == f"{CURRENT_HOST}/host-accounts/{user_id}/cert.pdf"
    # A key stored after this change renders the same way.
    assert body["govt_issued_id_url"] == f"{CURRENT_HOST}/host-accounts/{user_id}/id.png"
    assert body["proof_of_address_url"] == f"{CURRENT_HOST}/host-accounts/{user_id}/address.pdf"


def test_listing_to_dict_renders_legacy_media_urls() -> None:
    """The listing bundle path (GET /v1/listings/{id}, POST, PATCH) with a
    row that predates the change."""
    from app.services.listing_service import listing_to_dict

    class _Listing:
        id = "listing-1"
        host_account_id = "ha-1"
        listing_type = "commercial"
        title = "A warehouse"
        description = "Dry storage."
        location_latitude = 6.5
        location_longitude = 3.3
        location_address_line = "1 Test Street"
        location_city = "Lagos"
        location_state = "Lagos"
        amenities: list[str] = []
        status = "active"
        status_reason = None
        view_count = 0
        inquiry_count = 0
        owner_client_name = None

    media = ListingMedia(
        listing_id="listing-1",
        media_type="image",
        media_url=f"{LEGACY_HOST}/listings/listing-1/photo.jpg",
        display_order=0,
        is_primary=True,
    )

    out = listing_to_dict(_Listing(), [media])  # type: ignore[arg-type]

    assert out["media"][0]["media_url"] == f"{CURRENT_HOST}/listings/listing-1/photo.jpg"


# ---------------------------------------------------------------------------
# Migration coverage: the list of columns is checked against the models, not
# against a prose count (the dispatch for this work said 13; there are 19).
# ---------------------------------------------------------------------------


def test_migration_rewrites_exactly_the_media_url_columns_on_the_models() -> None:
    """Every `*_url` column on every model must appear in the migration, and
    the migration must not name a column that does not exist.

    This is the drift guard: adding a URL-bearing column later fails here
    until the data migration (and app/core/media_urls.py) covers it, which is
    the failure mode that caused T-021 to be possible in the first place.
    """
    migration = _load_migration_module()

    model_columns = {
        (table.name, column.name)
        for table in SQLModel.metadata.sorted_tables
        for column in table.columns
        if column.name.endswith("_url")
    }

    assert set(migration._MEDIA_KEY_COLUMNS) == model_columns
    assert len(model_columns) == 19


def test_migration_sql_strips_both_prefixes_and_is_scoped() -> None:
    """The generated UPDATE names both legacy hosts and the emulator form,
    and its WHERE clause only matches those -- so a bare key or a third-party
    URL is never rewritten (the idempotence claim in its docstring)."""
    migration = _load_migration_module()

    sql = migration._strip_to_key_sql("listing_media", "media_url")

    assert "cdn\\.de-duke\\.(com|org)" in sql
    assert "storage/v1/b/[^/]+/o/" in sql
    where_clause = sql.split("WHERE", 1)[1]
    assert "listing_media" not in where_clause
    assert where_clause.count("media_url ~") == 2


def _load_migration_module() -> Any:
    """Import alembic/versions/<revision>.py by path -- alembic/versions is
    not a package, and the file name carries the revision id by convention.

    Typed `Any` on purpose: the module is loaded dynamically, so its
    attributes cannot be checked at this call site.
    """
    import importlib.util
    from pathlib import Path

    path = (
        Path(__file__).resolve().parents[1]
        / "alembic"
        / "versions"
        / "c1f2e3d4a5b6_store_media_object_keys.py"
    )
    spec = importlib.util.spec_from_file_location("_media_key_migration", path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module
