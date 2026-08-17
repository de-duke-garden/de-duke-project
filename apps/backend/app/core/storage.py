"""File Storage Service client (GCS + Cloud CDN, architecture.md's File
Storage Service component; bucket + LB/CDN provisioned by
infra/gcp/storage_cdn.tf).

Used by app/services/verification_service.py (host verification documents),
app/api/v1/listings.py (listing photos/videos), app/services/auth_service.py
(profile photos) and app/services/receipt_service.py (PDF receipts) to
persist uploads and return their durable, publicly-servable URL.

Every external dependency call uses a bounded timeout (AGENTS.md Behavior
Rules) -- the GCS client's transport enforces its own connection/read
timeouts, so a slow/unavailable GCS fails fast with a clear 502 rather than
hanging the request indefinitely; there is no meaningful "degrade
gracefully" fallback for a file upload (unlike, say, search falling back to
keyword-only), so this raises rather than silently dropping the file.

Authentication: Application Default Credentials in every deployed
environment (Cloud Run resolves them to the revision's service account,
which infra/gcp/main.tf grants roles/storage.objectAdmin on the media
bucket). Locally, GCS_ENDPOINT_URL points the client at the fake-gcs-server
emulator (docker-compose.yml), which does not authenticate.
"""

from __future__ import annotations

# google-cloud-storage ships no py.typed marker (same class of noise as
# boto3/reportlab elsewhere in the codebase) -- scope the untyped-import
# fallout to this module rather than the whole project.
# mypy: disable-error-code="import-untyped,no-untyped-call"
import mimetypes
import uuid
from functools import lru_cache

import anyio
from fastapi import HTTPException, UploadFile, status
from google.auth.credentials import AnonymousCredentials
from google.cloud import storage
from google.cloud.storage import Client as StorageClient

from app.core.config import get_settings

settings = get_settings()


@lru_cache
def _get_client() -> StorageClient:
    """Cached GCS client.

    With GCS_ENDPOINT_URL set (local dev only) the client targets
    fake-gcs-server with anonymous credentials -- the emulator does not
    authenticate. Otherwise it uses Application Default Credentials: on
    Cloud Run that is the revision's service account automatically, with no
    explicit configuration here.
    """
    if settings.gcs_endpoint_url:
        # project must be explicit (any value -- fake-gcs-server ignores
        # it): with project=None the Client constructor probes
        # google.auth.default() for a default project even when anonymous
        # credentials and an api_endpoint are supplied, and that probe
        # raises DefaultCredentialsError in a container with no ADC.
        return storage.Client(
            project="test",
            credentials=AnonymousCredentials(),
            client_options={"api_endpoint": settings.gcs_endpoint_url},
        )
    return storage.Client()


_emulator_bucket_ensured = False


def _ensure_emulator_bucket(client: StorageClient) -> None:
    """Create the media bucket on the local GCS emulator if it is missing.

    fake-gcs-server (docker-compose.yml) starts with an empty store and,
    unlike real GCS, does not create buckets implicitly -- without this,
    every local upload would 404. Real environments never reach this
    branch: the bucket is provisioned by Terraform
    (infra/gcp/storage_cdn.tf), and this is guarded to emulator mode only
    (GCS_ENDPOINT_URL set) plus cached per process.
    """
    global _emulator_bucket_ensured
    if _emulator_bucket_ensured or not settings.gcs_endpoint_url:
        return
    if not client.bucket(settings.media_bucket_name).exists():
        # `project` is required by the JSON API but irrelevant to
        # fake-gcs-server; "test" is the emulator's conventional value.
        client.create_bucket(settings.media_bucket_name, project="test")
    _emulator_bucket_ensured = True


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

    In every deployed environment, the bucket is private (uniform bucket
    level access, no public IAM -- see infra/gcp/storage_cdn.tf) and is
    served only through the global LB's backend bucket with Cloud CDN
    enabled -- a direct storage.googleapis.com URL would 403. The CDN
    domain (MEDIA_CDN_DOMAIN, e.g. cdn.de-duke.com) is therefore mandatory
    there. Locally (no LB), media_cdn_domain stays at its REPLACE_ME
    default, so this falls back to an emulator-servable path-style URL
    instead.
    """
    if settings.media_cdn_domain != "REPLACE_ME":
        return f"https://{settings.media_cdn_domain}/{key}"

    if settings.gcs_endpoint_url:
        # fake-gcs-server serves object downloads via the JSON API's
        # media-download form (path-style /{bucket}/{key} 404s on it).
        public_base_url = settings.media_local_public_base_url or settings.gcs_endpoint_url
        return f"{public_base_url}/storage/v1/b/{settings.media_bucket_name}/o/{key}?alt=media"

    # No CDN domain and no emulator endpoint configured -- misconfigured
    # environment. Surface this loudly instead of returning a URL that
    # will silently 403 for every user who tries to view it.
    raise RuntimeError(
        "media_cdn_domain is unset and gcs_endpoint_url is unset -- cannot build a "
        "servable media URL. Populate MEDIA_CDN_DOMAIN (deployed environments) or "
        "GCS_ENDPOINT_URL (local dev, see docker-compose.yml)."
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
        client = _get_client()
        _ensure_emulator_bucket(client)
        blob = client.bucket(settings.media_bucket_name).blob(key)
        blob.upload_from_string(body, content_type=content_type)

    try:
        await anyio.to_thread.run_sync(_put)
    except Exception as exc:  # noqa: BLE001 -- the GCS client raises many distinct exception types
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="File upload failed -- please retry.",
        ) from exc

    return build_media_url(key)


async def upload_file(upload: UploadFile, *, prefix: str) -> str:
    """Uploads a FastAPI/Starlette UploadFile to the media bucket and
    returns its durable URL (via build_media_url).

    `prefix` namespaces the object key by what it belongs to (e.g.
    `listings/{listing_id}` or `host-accounts/{user_id}`) so the bucket
    stays browsable/auditable rather than one flat namespace.

    google-cloud-storage's sync client is blocking -- the upload runs in a
    worker thread (anyio, the same primitive Starlette's own UploadFile
    uses) so it never blocks the event loop, preserving the async-native
    concurrency benefit AGENTS.md calls out as the whole reason FastAPI was
    chosen.
    """
    filename = upload.filename or "upload"
    content_type = (
        upload.content_type or mimetypes.guess_type(filename)[0] or "application/octet-stream"
    )
    body = await upload.read()
    return await upload_bytes(body, prefix=prefix, filename=filename, content_type=content_type)
