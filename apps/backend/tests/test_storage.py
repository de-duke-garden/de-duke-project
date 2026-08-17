"""Tests for app/core/storage.py -- the File Storage Service (GCS + Cloud
CDN) client used by verification_service.py, listings.py, auth_service.py
and receipt_service.py.

Never hits real GCS or the local emulator -- the client is monkeypatched,
and build_media_url's branches are pure functions tested directly against
Settings field overrides.
"""

from __future__ import annotations

from io import BytesIO
from unittest.mock import MagicMock

import pytest
from fastapi import HTTPException, UploadFile

from app.core import storage


@pytest.fixture(autouse=True)
def _clear_client_cache() -> None:
    """_get_client is @lru_cache-d and the emulator-bucket flag is
    module-level -- reset both before each test so settings overrides in
    one test don't leak a stale client/flag into the next.

    Deliberately only clears before, not after: a couple of tests below
    monkeypatch storage._get_client itself to a plain (non-cached) fake,
    and monkeypatch's own teardown -- which runs after this fixture's own
    post-yield code in some orderings -- would otherwise call
    .cache_clear() on that plain fake and fail.
    """
    storage._get_client.cache_clear()
    storage._emulator_bucket_ensured = False


def test_build_media_url_prefers_cdn_domain_when_configured(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(storage.settings, "media_cdn_domain", "media.deduke.example")
    monkeypatch.setattr(storage.settings, "gcs_endpoint_url", "")

    url = storage.build_media_url("listings/abc/photo.jpg")

    assert url == "https://media.deduke.example/listings/abc/photo.jpg"


def test_build_media_url_falls_back_to_emulator_endpoint(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(storage.settings, "media_cdn_domain", "REPLACE_ME")
    monkeypatch.setattr(storage.settings, "gcs_endpoint_url", "http://fake-gcs:4443")
    monkeypatch.setattr(storage.settings, "media_local_public_base_url", "")
    monkeypatch.setattr(storage.settings, "media_bucket_name", "local-de-duke-media")

    url = storage.build_media_url("host-accounts/user-1/doc.pdf")

    assert (
        url
        == "http://fake-gcs:4443/storage/v1/b/local-de-duke-media/o/host-accounts/user-1/doc.pdf?alt=media"
    )


def test_build_media_url_prefers_public_base_url_over_endpoint(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """docker-compose.yml's exact scenario: the GCS client talks to
    `fake-gcs` (Docker network hostname), but the returned URL should use
    `localhost` (host-published port) so a human can actually open it."""
    monkeypatch.setattr(storage.settings, "media_cdn_domain", "REPLACE_ME")
    monkeypatch.setattr(storage.settings, "gcs_endpoint_url", "http://fake-gcs:4443")
    monkeypatch.setattr(storage.settings, "media_local_public_base_url", "http://localhost:4443")
    monkeypatch.setattr(storage.settings, "media_bucket_name", "local-de-duke-media")

    url = storage.build_media_url("listings/abc/photo.jpg")

    assert (
        url
        == "http://localhost:4443/storage/v1/b/local-de-duke-media/o/listings/abc/photo.jpg?alt=media"
    )


def test_build_media_url_raises_when_unconfigured(monkeypatch: pytest.MonkeyPatch) -> None:
    """No CDN domain and no emulator endpoint -- a misconfigured
    environment must fail loudly, never return a URL that will silently
    403 for every viewer."""
    monkeypatch.setattr(storage.settings, "media_cdn_domain", "REPLACE_ME")
    monkeypatch.setattr(storage.settings, "gcs_endpoint_url", "")

    with pytest.raises(RuntimeError, match="cannot build a servable media URL"):
        storage.build_media_url("listings/abc/photo.jpg")


def test_build_key_is_collision_proof_and_keeps_extension() -> None:
    key_one = storage._build_key(prefix="listings/abc", filename="photo.jpg")
    key_two = storage._build_key(prefix="listings/abc", filename="photo.jpg")

    assert key_one != key_two, "two uploads of the same filename must not collide"
    assert key_one.startswith("listings/abc/")
    assert key_one.endswith(".jpg")


async def test_upload_file_uploads_via_gcs_client_with_bucket_and_content_type(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(storage.settings, "media_bucket_name", "local-de-duke-media")
    monkeypatch.setattr(storage.settings, "media_cdn_domain", "media.deduke.example")
    monkeypatch.setattr(storage.settings, "gcs_endpoint_url", "")
    monkeypatch.setattr(storage.settings, "media_local_public_base_url", "")

    fake_blob = MagicMock()
    fake_bucket = MagicMock()
    fake_bucket.blob.return_value = fake_blob
    fake_client = MagicMock()
    fake_client.bucket.return_value = fake_bucket
    monkeypatch.setattr(storage, "_get_client", lambda: fake_client)

    upload = UploadFile(filename="photo.jpg", file=BytesIO(b"fake-image-bytes"))

    url = await storage.upload_file(upload, prefix="listings/listing-1")

    fake_client.bucket.assert_called_once_with("local-de-duke-media")
    fake_bucket.blob.assert_called_once()
    key = fake_bucket.blob.call_args.args[0]
    assert key.startswith("listings/listing-1/")
    fake_blob.upload_from_string.assert_called_once_with(
        b"fake-image-bytes", content_type="image/jpeg"
    )
    assert url == f"https://media.deduke.example/{key}"


async def test_upload_bytes_targets_requested_prefix(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(storage.settings, "media_bucket_name", "local-de-duke-media")
    monkeypatch.setattr(storage.settings, "media_cdn_domain", "REPLACE_ME")
    monkeypatch.setattr(storage.settings, "gcs_endpoint_url", "http://fake-gcs:4443")
    monkeypatch.setattr(storage.settings, "media_local_public_base_url", "")

    fake_blob = MagicMock()
    fake_bucket = MagicMock()
    fake_bucket.blob.return_value = fake_blob
    fake_client = MagicMock()
    fake_client.bucket.return_value = fake_bucket
    monkeypatch.setattr(storage, "_get_client", lambda: fake_client)

    url = await storage.upload_bytes(
        b"pdf-bytes",
        prefix="receipts/order-1",
        filename="receipt.pdf",
        content_type="application/pdf",
    )

    key = fake_bucket.blob.call_args.args[0]
    assert key.startswith("receipts/order-1/")
    fake_blob.upload_from_string.assert_called_once_with(
        b"pdf-bytes", content_type="application/pdf"
    )
    assert url.startswith(
        "http://fake-gcs:4443/storage/v1/b/local-de-duke-media/o/receipts/order-1/"
    )
    assert url.endswith("?alt=media")


async def test_upload_file_raises_502_on_storage_failure(monkeypatch: pytest.MonkeyPatch) -> None:
    fake_blob = MagicMock()
    fake_blob.upload_from_string.side_effect = RuntimeError("GCS unavailable")
    fake_bucket = MagicMock()
    fake_bucket.blob.return_value = fake_blob
    fake_client = MagicMock()
    fake_client.bucket.return_value = fake_bucket
    monkeypatch.setattr(storage, "_get_client", lambda: fake_client)

    upload = UploadFile(filename="photo.jpg", file=BytesIO(b"fake-image-bytes"))

    with pytest.raises(HTTPException) as exc_info:
        await storage.upload_file(upload, prefix="listings/listing-1")

    assert exc_info.value.status_code == 502
