"""Tests for app/core/storage.py -- the File Storage Service (GCS + Cloud
CDN) client used by verification_service.py, listings.py, auth_service.py
and receipt_service.py.

Never hits real GCS or the local emulator -- the client is monkeypatched,
and build_media_url's branches are pure functions tested directly against
Settings field overrides.

The key/URL behavior asserted here is the T-021 contract: uploads return
object keys, stored values are normalized back to keys, and the URL is
rendered against whatever CDN host is configured *now*.
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

    key = await storage.upload_file_key(upload, prefix="listings/listing-1")

    fake_client.bucket.assert_called_once_with("local-de-duke-media")
    fake_bucket.blob.assert_called_once()
    assert fake_bucket.blob.call_args.args[0] == key
    assert key.startswith("listings/listing-1/")
    # Returns the object key, never a URL -- that is the whole point of
    # T-021: persisting the URL is what broke the catalogue on a domain move.
    assert "://" not in key
    fake_blob.upload_from_string.assert_called_once_with(b"fake-image-bytes")


async def test_upload_file_sets_content_type_and_immutable_cache_control(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """AC (T-021): a new upload is stored with the object's real content
    type and with `Cache-Control: public, max-age=31536000, immutable` --
    without which Cloud CDN caches nothing (GCS served max-age=0, private)."""
    monkeypatch.setattr(storage.settings, "media_bucket_name", "local-de-duke-media")
    monkeypatch.setattr(storage.settings, "gcs_endpoint_url", "")

    fake_blob = MagicMock()
    fake_bucket = MagicMock()
    fake_bucket.blob.return_value = fake_blob
    fake_client = MagicMock()
    fake_client.bucket.return_value = fake_bucket
    monkeypatch.setattr(storage, "_get_client", lambda: fake_client)

    upload = UploadFile(filename="photo.jpg", file=BytesIO(b"\xff\xd8\xff\xe0real-jpeg"))

    await storage.upload_file_key(upload, prefix="listings/listing-1")

    assert fake_blob.content_type == "image/jpeg"
    assert fake_blob.cache_control == "public, max-age=31536000, immutable"


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

    key = await storage.upload_bytes_key(
        b"%PDF-1.7 pdf-bytes",
        prefix="receipts/order-1",
        filename="receipt.pdf",
        content_type="application/pdf",
    )

    assert key.startswith("receipts/order-1/")
    assert fake_bucket.blob.call_args.args[0] == key
    fake_blob.upload_from_string.assert_called_once_with(b"%PDF-1.7 pdf-bytes")
    assert fake_blob.content_type == "application/pdf"


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
        await storage.upload_file_key(upload, prefix="listings/listing-1")

    assert exc_info.value.status_code == 502


# ---------------------------------------------------------------------------
# T-021: stored values are object keys, and keys/legacy URLs both render
# against the currently configured host
# ---------------------------------------------------------------------------


@pytest.fixture
def _cdn_configured(monkeypatch: pytest.MonkeyPatch) -> None:
    """The live CDN host, with no emulator fallback in play."""
    monkeypatch.setattr(storage.settings, "media_cdn_domain", "cdn.de-duke.org")
    monkeypatch.setattr(storage.settings, "gcs_endpoint_url", "")
    monkeypatch.setattr(storage.settings, "media_local_public_base_url", "")


@pytest.mark.parametrize(
    ("stored", "expected_key"),
    [
        # The dead host from the incident.
        ("https://cdn.de-duke.com/listings/abc/photo.jpg", "listings/abc/photo.jpg"),
        # The host that replaced it -- stripped too, so the next move is
        # equally harmless.
        ("https://cdn.de-duke.org/listings/abc/photo.jpg", "listings/abc/photo.jpg"),
        # A bare key passes straight through (idempotent by construction).
        ("listings/abc/photo.jpg", "listings/abc/photo.jpg"),
        # fake-gcs-server's JSON-API media-download form.
        (
            "http://localhost:4443/storage/v1/b/local-de-duke-media/o/host-accounts/u/doc.pdf?alt=media",
            "host-accounts/u/doc.pdf",
        ),
        # A URL we do not own is never reinterpreted.
        ("https://example.com/placeholder.jpg", "https://example.com/placeholder.jpg"),
        ("anonymized", "anonymized"),
    ],
)
def test_to_object_key_normalizes_and_passes_through(stored: str, expected_key: str) -> None:
    assert storage.to_object_key(stored) == expected_key


def test_build_media_url_renders_legacy_com_url_on_the_current_host(
    _cdn_configured: None,
) -> None:
    """The incident, exactly: a row written before the move holds a
    cdn.de-duke.com URL, and comes back out on cdn.de-duke.org."""
    url = storage.build_media_url("https://cdn.de-duke.com/listings/abc/photo.jpg")

    assert url == "https://cdn.de-duke.org/listings/abc/photo.jpg"


def test_build_media_url_is_idempotent_for_a_current_host_url(
    _cdn_configured: None,
) -> None:
    url = "https://cdn.de-duke.org/listings/abc/photo.jpg"

    assert storage.build_media_url(url) == url
    assert storage.build_media_url(storage.build_media_url(url)) == url


def test_build_media_url_renders_emulator_url_on_the_current_host(
    _cdn_configured: None,
) -> None:
    """A key read out of an emulator-shaped URL must not stay an emulator
    URL once a real CDN host is configured."""
    url = storage.build_media_url(
        "http://fake-gcs:4443/storage/v1/b/local-de-duke-media/o/host-accounts/u/doc.pdf?alt=media"
    )

    assert url == "https://cdn.de-duke.org/host-accounts/u/doc.pdf"


def test_build_media_url_keeps_third_party_urls_intact(_cdn_configured: None) -> None:
    url = storage.build_media_url("https://example.com/placeholder.jpg")

    assert url == "https://example.com/placeholder.jpg"


def test_optional_media_url_preserves_null_and_empty() -> None:
    """Nullability is part of the frozen contract: a nullable field must not
    gain a URL, and the legacy empty receipt pdf_url must not become null."""
    assert storage.optional_media_url(None) is None
    assert storage.optional_media_url("") == ""


@pytest.mark.parametrize(
    ("declared", "body", "filename", "expected"),
    [
        # A meaningful client declaration wins outright.
        ("image/jpeg", b"\x89PNG\r\n\x1a\n...", "photo.png", "image/jpeg"),
        # "octet-stream" is a client admitting it does not know, not a type.
        ("application/octet-stream", b"\xff\xd8\xff\xe0jpeg", "no-extension", "image/jpeg"),
        (None, b"\x89PNG\r\n\x1a\nrest", "no-extension", "image/png"),
        ("", b"GIF89a....", "no-extension", "image/gif"),
        (None, b"RIFF\x00\x00\x00\x00WEBPVP8 ", "no-extension", "image/webp"),
        (None, b"\x00\x00\x00\x18ftypmp42", "no-extension", "video/mp4"),
        (None, b"%PDF-1.7\n", "temp_key_without_suffix", "application/pdf"),
        # Nothing recognizable: fall back to the extension, then to octet-stream.
        ("application/octet-stream", b"\x00\x01\x02\x03", "scan.pdf", "application/pdf"),
        ("application/octet-stream", b"\x00\x01\x02\x03", "temp_key", "application/octet-stream"),
    ],
)
def test_resolve_content_type_order(
    declared: str | None, body: bytes, filename: str, expected: str
) -> None:
    """AC: client declaration, then magic bytes, then extension, then
    application/octet-stream -- the host-account document upload path sends
    a filename with no suffix, which is why extension-only resolution left
    those objects as octet-stream."""
    resolved = storage.resolve_content_type(declared=declared, body=body, filename=filename)

    assert resolved == expected
