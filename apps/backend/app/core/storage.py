"""File Storage Service client (GCS + Cloud CDN, architecture.md's File
Storage Service component; bucket + LB/CDN provisioned by
infra/gcp/storage_cdn.tf).

Used by app/services/verification_service.py (host verification documents),
app/api/v1/listings.py (listing photos/videos), app/services/auth_service.py
(profile photos) and app/services/receipt_service.py (PDF receipts) to
persist uploads.

**The database stores object keys, never URLs.** `upload_*_key` returns the
key it wrote; the one place that turns a key into a publicly servable URL is
`build_media_url`. That split exists because of a real production incident
(T-021): every URL used to be minted once, at upload time, and stored as a
string, so moving the CDN from `cdn.de-duke.com` to `cdn.de-duke.org` left
the entire catalogue pointing at a host that no longer resolved. Deriving
the URL on read means the host is a deployment setting
(MEDIA_CDN_DOMAIN), not data.

`build_media_url` therefore accepts *either* a stored key *or* a legacy
absolute URL and always renders the current host, so rows written before
that change (and before the accompanying data migration) still render
correctly.

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
import re
import uuid
from functools import lru_cache
from urllib.parse import unquote, urlsplit

import anyio
from fastapi import HTTPException, UploadFile, status
from google.auth.credentials import AnonymousCredentials
from google.cloud import storage
from google.cloud.storage import Blob
from google.cloud.storage import Client as StorageClient

from app.core.config import get_settings

settings = get_settings()

#: Cache-Control for every uploaded object. Keys are random UUIDs and an
#: object's bytes never change once written (a re-upload gets a new key), so
#: the response is immutable by construction -- which is exactly what lets
#: Cloud CDN cache it at all. Before this, GCS served its default
#: `max-age=0, private` and the CDN cached nothing (T-021).
MEDIA_CACHE_CONTROL = "public, max-age=31536000, immutable"

#: Every host this API has ever minted a media URL on. A stored absolute URL
#: on one of these hosts is reduced back to its object key and re-rendered
#: against the currently configured host, so legacy rows survive a domain
#: move with no migration required.
_LEGACY_MEDIA_HOSTS = frozenset({"cdn.de-duke.com", "cdn.de-duke.org"})

#: fake-gcs-server's JSON-API media-download path. Unlike the CDN's plain
#: `/<key>` form, the bucket and key live in the path and the host is
#: whatever GCS_ENDPOINT_URL/MEDIA_LOCAL_PUBLIC_BASE_URL happens to be, so
#: this is matched by shape rather than by host.
_EMULATOR_OBJECT_PATH = re.compile(r"^/storage/v1/b/[^/]+/o/(?P<key>.+)$")

#: Declared types that carry no information -- the client could not determine
#: the real one (host-account document uploads send a filename with no
#: suffix, so they arrived at the bucket as application/octet-stream and
#: every browser downloaded them instead of rendering them, T-021).
_UNINFORMATIVE_CONTENT_TYPES = frozenset({"", "application/octet-stream", "binary/octet-stream"})

#: Enough bytes for every signature below (the widest is the RIFF/WebP probe,
#: which needs bytes 8-11).
_SNIFF_PREFIX_BYTES = 16


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


def _configured_cdn_domain() -> str | None:
    """MEDIA_CDN_DOMAIN when it is actually configured, else None.

    `REPLACE_ME` is config.py's placeholder default for every unset
    setting; treating it as a real host would mint URLs like
    `https://REPLACE_ME/<key>` instead of failing loudly.
    """
    domain = settings.media_cdn_domain.strip().strip("/")
    if not domain or domain == "REPLACE_ME":
        return None
    return domain


def _known_media_hosts() -> frozenset[str]:
    """Hosts whose URLs this API is responsible for re-rendering."""
    hosts = set(_LEGACY_MEDIA_HOSTS)
    cdn_domain = _configured_cdn_domain()
    if cdn_domain is not None:
        hosts.add(cdn_domain.lower())
    return frozenset(hosts)


def sniff_content_type(body: bytes) -> str | None:
    """Content type from magic bytes, or None if the signature is unknown.

    Pure/no I/O -- only the first handful of bytes are inspected. Covers
    exactly the formats this API stores (listing photos/videos, avatars,
    host-account document scans, receipt PDFs); anything else falls through
    to the filename extension in `resolve_content_type`.
    """
    header = body[:_SNIFF_PREFIX_BYTES]
    if header.startswith(b"\xff\xd8\xff"):
        return "image/jpeg"
    if header.startswith(b"\x89PNG\r\n\x1a\n"):
        return "image/png"
    if header.startswith((b"GIF87a", b"GIF89a")):
        return "image/gif"
    if header[:4] == b"RIFF" and header[8:12] == b"WEBP":
        return "image/webp"
    if header[4:8] == b"ftyp":
        # ISO base media file format -- mp4 (and quicktime) put the box type
        # at offset 4, right after the 4-byte box size.
        return "video/mp4"
    if header.startswith(b"%PDF-"):
        return "application/pdf"
    return None


def resolve_content_type(*, declared: str | None, body: bytes, filename: str) -> str:
    """The Content-Type to store an object with, in resolution order:

    1. what the client declared, when it said something meaningful;
    2. the magic bytes in the body;
    3. the filename's extension;
    4. `application/octet-stream`.

    Step 1 skips `application/octet-stream` on purpose: that is not a client
    telling us the type, it is a client admitting it does not know, and
    storing it means a browser downloads a host's verification document
    instead of displaying it.
    """
    declared_type = (declared or "").strip()
    if declared_type.lower() not in _UNINFORMATIVE_CONTENT_TYPES:
        return declared_type

    sniffed = sniff_content_type(body)
    if sniffed is not None:
        return sniffed

    guessed, _encoding = mimetypes.guess_type(filename)
    if guessed is not None:
        return guessed

    return "application/octet-stream"


def to_object_key(key_or_url: str) -> str:
    """Reduce a stored value to its object key. Pure/no I/O.

    - a bare key (`listings/<id>/<uuid>.jpg`) passes through untouched;
    - a CDN URL on a host this API owns (`https://cdn.de-duke.com/<key>`,
      `https://cdn.de-duke.org/<key>`, or the currently configured
      MEDIA_CDN_DOMAIN) is stripped to its path;
    - an emulator URL in fake-gcs-server's JSON-API form
      (`<base>/storage/v1/b/<bucket>/o/<key>?alt=media`) is stripped to the
      `o/<key>` segment;
    - any other absolute URL is a third-party address this API did not
      mint, so it is returned unchanged and re-rendered as-is.

    Idempotent by construction, which is what lets the T-021 data migration
    and the read-time rendering overlap safely: either one alone leaves a
    correct value, and running both is a no-op the second time.
    """
    value = key_or_url.strip()
    if not value or "://" not in value:
        return value

    parts = urlsplit(value)

    emulator_match = _EMULATOR_OBJECT_PATH.match(parts.path)
    if emulator_match is not None:
        return unquote(emulator_match.group("key"))

    if (parts.hostname or "").lower() in _known_media_hosts():
        return unquote(parts.path.lstrip("/"))

    return value


def build_media_url(key_or_url: str) -> str:
    """The publicly servable URL for a stored object key or legacy URL.

    Pure/no I/O -- deliberately split out from the upload functions so it's
    cheaply unit-testable and so every read path can re-render a URL
    without touching storage. This is the only function in the codebase
    that knows how a media URL is shaped.

    Accepts either form because the database has held both: keys (write
    paths since T-021) and absolute URLs minted at upload time (everything
    written before it). Both render against the currently configured host.

    In every deployed environment, the bucket is private (uniform bucket
    level access, no public IAM -- see infra/gcp/storage_cdn.tf) and is
    served only through the global LB's backend bucket with Cloud CDN
    enabled -- a direct storage.googleapis.com URL would 403. The CDN
    domain (MEDIA_CDN_DOMAIN, e.g. cdn.de-duke.org) is therefore mandatory
    there. Locally (no LB), media_cdn_domain stays at its REPLACE_ME
    default, so this falls back to an emulator-servable path-style URL
    instead.
    """
    key = to_object_key(key_or_url)
    if "://" in key:
        # A third-party URL this API did not mint -- nothing to re-derive.
        return key
    key = key.lstrip("/")

    cdn_domain = _configured_cdn_domain()
    if cdn_domain is not None:
        return f"https://{cdn_domain}/{key}"

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


def optional_media_url(value: str | None) -> str | None:
    """`build_media_url` for a nullable URL column.

    Null and empty stay exactly as they are: a nullable response field
    (profile photo, video poster, receipt) must not gain a URL when there is
    nothing stored, and `Receipt.pdf_url`'s legacy empty-string placeholder
    must not silently become `null` in TransactionDetail.
    """
    if value is None or not value.strip():
        return value
    return build_media_url(value)


async def upload_bytes_key(
    body: bytes, *, prefix: str, filename: str, content_type: str | None = None
) -> str:
    """Store `body` and return its object key (never a URL).

    Same upload as `upload_file_key` below, but for already-in-memory bytes
    rather than a live `UploadFile` -- used by listing_service.py's video
    upload path, which must read the video's bytes into memory anyway (to
    probe its duration and extract a poster frame server-side, see
    listing_service._process_video_sync) before deciding whether to
    persist it at all, so re-reading from an already-consumed UploadFile
    isn't an option. `upload_file_key` below is a thin wrapper over this.

    `content_type` is the client's declaration, not the stored value: see
    `resolve_content_type` for how the real one is decided.
    """
    key = _build_key(prefix=prefix, filename=filename or "upload")
    resolved_content_type = resolve_content_type(
        declared=content_type, body=body, filename=filename or "upload"
    )

    def _put() -> None:
        client = _get_client()
        _ensure_emulator_bucket(client)
        blob: Blob = client.bucket(settings.media_bucket_name).blob(key)
        # Set on the blob rather than passed to upload_from_string: that
        # method's signature has no cache_control parameter, but both
        # properties are serialized into the upload's metadata.
        blob.content_type = resolved_content_type
        blob.cache_control = MEDIA_CACHE_CONTROL
        blob.upload_from_string(body)

    try:
        await anyio.to_thread.run_sync(_put)
    except Exception as exc:  # noqa: BLE001 -- the GCS client raises many distinct exception types
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="File upload failed -- please retry.",
        ) from exc

    return key


async def upload_file_key(upload: UploadFile, *, prefix: str) -> str:
    """Store a FastAPI/Starlette UploadFile and return its object key.

    Deliberately returns the key, not a URL: persisting a URL is what broke
    every image on the CDN domain move (T-021). Call sites store this value
    as-is and leave the URL to `build_media_url` at read time.

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
    body = await upload.read()
    return await upload_bytes_key(
        body, prefix=prefix, filename=filename, content_type=upload.content_type
    )
