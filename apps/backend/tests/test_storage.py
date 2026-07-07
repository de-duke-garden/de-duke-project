"""Tests for app/core/storage.py -- the File Storage Service (S3 + CDN)
client used by verification_service.py and listings.py.

Never hits real S3/LocalStack -- put_object is monkeypatched, and
build_media_url's branches are pure functions tested directly against
Settings field overrides.
"""

from __future__ import annotations

from io import BytesIO
from unittest.mock import MagicMock

import pytest
from fastapi import HTTPException, UploadFile

from app.core import storage


@pytest.fixture(autouse=True)
def _clear_client_cache():
    """_get_client is @lru_cache-d -- clear before each test so settings
    overrides in one test don't leak a stale client into the next.

    Deliberately only clears before, not after: a couple of tests below
    monkeypatch storage._get_client itself to a plain (non-cached) fake,
    and monkeypatch's own teardown -- which runs after this fixture's own
    post-yield code in some orderings -- would otherwise call
    .cache_clear() on that plain fake and fail.
    """
    storage._get_client.cache_clear()


def test_build_media_url_prefers_cdn_domain_when_configured(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(storage.settings, "media_cdn_domain", "media.deduke.example")
    monkeypatch.setattr(storage.settings, "aws_endpoint_url", "")

    url = storage.build_media_url("listings/abc/photo.jpg")

    assert url == "https://media.deduke.example/listings/abc/photo.jpg"


def test_build_media_url_falls_back_to_localstack_endpoint(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(storage.settings, "media_cdn_domain", "REPLACE_ME")
    monkeypatch.setattr(storage.settings, "aws_endpoint_url", "http://localstack:4566")
    monkeypatch.setattr(storage.settings, "media_local_public_base_url", "")
    monkeypatch.setattr(storage.settings, "media_bucket_name", "local-de-duke-media")

    url = storage.build_media_url("host-accounts/user-1/doc.pdf")

    assert url == "http://localstack:4566/local-de-duke-media/host-accounts/user-1/doc.pdf"


def test_build_media_url_prefers_public_base_url_over_endpoint(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """docker-compose.yml's exact scenario: the S3 client talks to
    `localstack` (Docker network hostname), but the returned URL should use
    `localhost` (host-published port) so a human can actually open it."""
    monkeypatch.setattr(storage.settings, "media_cdn_domain", "REPLACE_ME")
    monkeypatch.setattr(storage.settings, "aws_endpoint_url", "http://localstack:4566")
    monkeypatch.setattr(storage.settings, "media_local_public_base_url", "http://localhost:4566")
    monkeypatch.setattr(storage.settings, "media_bucket_name", "local-de-duke-media")

    url = storage.build_media_url("listings/abc/photo.jpg")

    assert url == "http://localhost:4566/local-de-duke-media/listings/abc/photo.jpg"


def test_build_media_url_raises_when_unconfigured(monkeypatch: pytest.MonkeyPatch) -> None:
    """No CDN domain and no LocalStack endpoint -- a misconfigured
    environment must fail loudly, never return a URL that will silently
    403 for every viewer."""
    monkeypatch.setattr(storage.settings, "media_cdn_domain", "REPLACE_ME")
    monkeypatch.setattr(storage.settings, "aws_endpoint_url", "")

    with pytest.raises(RuntimeError, match="cannot build a servable media URL"):
        storage.build_media_url("listings/abc/photo.jpg")


def test_build_key_is_collision_proof_and_keeps_extension() -> None:
    key_one = storage._build_key(prefix="listings/abc", filename="photo.jpg")
    key_two = storage._build_key(prefix="listings/abc", filename="photo.jpg")

    assert key_one != key_two, "two uploads of the same filename must not collide"
    assert key_one.startswith("listings/abc/")
    assert key_one.endswith(".jpg")


async def test_upload_file_calls_put_object_with_bucket_and_content_type(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(storage.settings, "media_bucket_name", "local-de-duke-media")
    monkeypatch.setattr(storage.settings, "media_cdn_domain", "REPLACE_ME")
    monkeypatch.setattr(storage.settings, "aws_endpoint_url", "http://localstack:4566")
    monkeypatch.setattr(storage.settings, "media_local_public_base_url", "")

    fake_client = MagicMock()
    monkeypatch.setattr(storage, "_get_client", lambda: fake_client)

    upload = UploadFile(filename="photo.jpg", file=BytesIO(b"fake-image-bytes"))

    url = await storage.upload_file(upload, prefix="listings/listing-1")

    fake_client.put_object.assert_called_once()
    call_kwargs = fake_client.put_object.call_args.kwargs
    assert call_kwargs["Bucket"] == "local-de-duke-media"
    assert call_kwargs["Body"] == b"fake-image-bytes"
    assert call_kwargs["Key"].startswith("listings/listing-1/")
    assert call_kwargs["ContentType"] in ("image/jpeg", "application/octet-stream")
    assert url.startswith("http://localstack:4566/local-de-duke-media/listings/listing-1/")


async def test_upload_file_raises_502_on_s3_failure(monkeypatch: pytest.MonkeyPatch) -> None:
    fake_client = MagicMock()
    fake_client.put_object.side_effect = RuntimeError("S3 unavailable")
    monkeypatch.setattr(storage, "_get_client", lambda: fake_client)

    upload = UploadFile(filename="photo.jpg", file=BytesIO(b"fake-image-bytes"))

    with pytest.raises(HTTPException) as exc_info:
        await storage.upload_file(upload, prefix="listings/listing-1")

    assert exc_info.value.status_code == 502
