"""File Storage Service client (S3 + CDN, architecture.md's File Storage
Service component; bucket/distribution provisioned by infra/modules/s3_cdn).

Used by app/services/verification_service.py (host verification documents)
and app/api/v1/listings.py (listing photos) to persist uploads and return
their durable, publicly-servable URL.

Every external dependency call uses a bounded timeout (AGENTS.md Behavior
Rules) -- see _CLIENT_CONFIG below. A slow/unavailable S3 fails fast with a
clear 502 rather than hanging the request indefinitely; there is no
meaningful "degrade gracefully" fallback for a file upload (unlike, say,
search falling back to keyword-only), so this raises rather than silently
dropping the file.
"""

from __future__ import annotations

import mimetypes
import uuid
from functools import lru_cache
from typing import Any

import anyio
import boto3
from botocore.config import Config
from fastapi import HTTPException, UploadFile, status

from app.core.config import get_settings

settings = get_settings()

# Bounded timeouts + limited retries -- a hung/degraded S3 must fail fast,
# never pile up slow requests against the API service's own capacity
# (AGENTS.md / architecture.md External Service Resilience).
_CLIENT_CONFIG = Config(connect_timeout=5, read_timeout=10, retries={"max_attempts": 2})


@lru_cache
def _get_client() -> Any:  # noqa: ANN401 -- boto3 has no first-party type stubs in this project
    """Cached boto3 S3 client.

    endpoint_url is only ever set locally (docker-compose.yml's
    AWS_ENDPOINT_URL, see Settings.aws_endpoint_url) to redirect this at
    LocalStack instead of real AWS -- boto3's default (None) talks to real
    AWS in every deployed environment, where that env var is unset.
    """
    return boto3.client(
        "s3",
        region_name=settings.aws_region,
        endpoint_url=settings.aws_endpoint_url or None,
        config=_CLIENT_CONFIG,
    )


def _build_key(*, prefix: str, filename: str) -> str:
    """A collision-proof, path-safe object key.

    Deliberately does not reuse the client-supplied filename as-is (path
    traversal / overwrite risk) -- prefixes a random UUID and keeps only
    the original extension for content-type inference and readability in
    the bucket.
    """
    suffix = filename.rsplit(".", 1)[-1].lower() if "." in filename else ""
    unique_name = f"{uuid.uuid4()}.{suffix}" if suffix else str(uuid.uuid4())
    return f"{prefix}/{unique_name}"


def build_media_url(key: str) -> str:
    """The durable, publicly-servable URL for an already-uploaded object key.

    Pure/no I/O -- deliberately split out from upload_file so it's cheaply
    unit-testable and so callers that already know a key (rare) can build
    its URL without re-uploading.

    In every deployed environment, the bucket's policy only grants
    s3:GetObject to CloudFront's Origin Access Control (see
    infra/modules/s3_cdn) -- a direct S3 URL would 403. The CDN domain is
    therefore mandatory there. Locally (no CloudFront), media_cdn_domain
    stays at its REPLACE_ME default, so this falls back to a
    LocalStack-servable path-style URL instead.
    """
    if settings.media_cdn_domain != "REPLACE_ME":
        return f"https://{settings.media_cdn_domain}/{key}"

    if settings.aws_endpoint_url:
        public_base_url = settings.media_local_public_base_url or settings.aws_endpoint_url
        return f"{public_base_url}/{settings.media_bucket_name}/{key}"

    # No CDN domain and no LocalStack endpoint configured -- misconfigured
    # environment. Surface this loudly instead of returning a URL that
    # will silently 403 for every user who tries to view it.
    raise RuntimeError(
        "media_cdn_domain is unset and aws_endpoint_url is unset -- cannot build a "
        "servable media URL. Populate MEDIA_CDN_DOMAIN (deployed environments) or "
        "AWS_ENDPOINT_URL (local dev, see docker-compose.yml)."
    )


async def upload_bytes(body: bytes, *, prefix: str, filename: str, content_type: str) -> str:
    """Same upload as `upload_file` below, but for already-in-memory bytes
    rather than a live `UploadFile` -- used by listing_service.py's video
    upload path, which must read the video's bytes into memory anyway (to
    probe its duration and extract a poster frame server-side, see
    listing_service._process_video_sync) before deciding whether to
    persist it at all, so re-reading from an already-consumed UploadFile
    isn't an option. `upload_file` below is now a thin wrapper over this.
    """
    key = _build_key(prefix=prefix, filename=filename or "upload")

    def _put() -> None:
        _get_client().put_object(
            Bucket=settings.media_bucket_name,
            Key=key,
            Body=body,
            ContentType=content_type,
        )

    try:
        await anyio.to_thread.run_sync(_put)
    except Exception as exc:  # noqa: BLE001 -- boto3 raises many distinct exception types
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="File upload failed -- please retry.",
        ) from exc

    return build_media_url(key)


async def upload_file(upload: UploadFile, *, prefix: str) -> str:
    """Uploads a FastAPI/Starlette UploadFile to the media bucket and
    returns its durable URL (via build_media_url).

    `prefix` namespaces the object key by what it belongs to (e.g.
    `listings/{listing_id}` or `host-accounts/{host_account_id}`) so the
    bucket stays browsable/auditable rather than one flat namespace.

    boto3 is synchronous -- put_object runs in a worker thread (anyio, the
    same primitive Starlette's own UploadFile uses) so it never blocks the
    event loop, preserving the async-native concurrency benefit AGENTS.md
    calls out as the whole reason FastAPI was chosen.
    """
    filename = upload.filename or "upload"
    content_type = (
        upload.content_type or mimetypes.guess_type(filename)[0] or "application/octet-stream"
    )
    body = await upload.read()
    return await upload_bytes(body, prefix=prefix, filename=filename, content_type=content_type)
