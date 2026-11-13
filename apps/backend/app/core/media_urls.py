"""The one place that turns stored media object keys into public URLs at
read time (T-021).

Why this module exists: media URLs used to be minted once, at upload time,
and stored as absolute strings. When the CDN moved from `cdn.de-duke.com` to
`cdn.de-duke.org`, every stored URL kept pointing at the dead host, because
nothing re-derived it on read. The fix is a single rule followed by every
write path and every read path:

- **write** paths call `app.core.storage.upload_file_key` /
  `upload_bytes_key` and persist the returned *object key*;
- **read** paths pass the stored value through `build_media_url`, which
  renders the currently configured host and accepts a legacy absolute URL
  just as happily as a bare key.

There are exactly two ways to satisfy the second half, and both go through
that one function:

1. Response schemas annotate their URL fields `MediaURL` / `OptionalMediaURL`
   below. Pydantic runs the validator at construction, so a schema can never
   be built from a raw model attribute and leak a key into JSON -- including
   a field a future endpoint fills from somewhere new.
2. Responses assembled as plain dicts (FastAPI passes those through without
   validating them against a schema, e.g. the listing bundle in
   app/services/listing_service.py) are passed through `render_media_urls`,
   which rewrites the same field names anywhere in the payload including
   nested media arrays.

Every function here is pure string work -- no I/O, no storage client call --
so applying it across a listing response costs nothing measurable.
"""

from __future__ import annotations

from typing import Annotated, Any

from pydantic import AfterValidator

from app.core.storage import build_media_url, optional_media_url

#: Every response field that carries a stored media object key, in either
#: form. Verified against app/models/ (the columns) and app/schemas/ (the
#: fields): listing_media.media_url/poster_url, host_accounts.host_photo_url,
#: the fourteen host_account_* verification-document columns,
#: users.profile_photo_url and receipts.pdf_url, plus the flattened
#: `primary_image_url` (listing cards) and `receipt_url` (transaction detail)
#: the API derives from them.
MEDIA_URL_FIELDS: frozenset[str] = frozenset(
    {
        # Listing media (and the card thumbnail derived from it)
        "media_url",
        "poster_url",
        "primary_image_url",
        # Avatars
        "profile_photo_url",
        "host_photo_url",
        # Receipts
        "pdf_url",
        "receipt_url",
        # Host-account verification documents, one name per column
        "cac_cert_doc_url",
        "industry_license_url",
        "proof_of_address_url",
        "rep_id_url",
        "cac_reg_doc_url",
        "valid_practicing_cert_url",
        "govt_issued_id_url",
        "practice_license_url",
    }
)

#: A required media URL field on a response schema.
MediaURL = Annotated[str, AfterValidator(build_media_url)]

#: A nullable media URL field on a response schema. Null stays null; an
#: empty string stays empty (see storage.optional_media_url).
OptionalMediaURL = Annotated[str | None, AfterValidator(optional_media_url)]


def render_media_urls(payload: dict[str, Any]) -> dict[str, Any]:
    """Return a copy of a response payload with every media URL rendered.

    Only values under a `MEDIA_URL_FIELDS` name are rewritten; everything
    else is copied through untouched (nested mappings and lists are walked
    so a listing's `media` array is covered, but a field the API never
    stores a key in -- `legal_documents`, a Paystack `authorization_url` --
    is never reinterpreted).

    Returns a new dict rather than mutating in place: the dicts passed in
    here are assembled per request, and silently rewriting a mapping that a
    caller still owns would be a surprising side effect.
    """
    rendered: dict[str, Any] = {}
    for field, value in payload.items():
        if field in MEDIA_URL_FIELDS:
            rendered[field] = _render_url_value(value)
        elif isinstance(value, dict):
            rendered[field] = render_media_urls(value)
        elif isinstance(value, list):
            rendered[field] = [
                render_media_urls(item) if isinstance(item, dict) else item for item in value
            ]
        else:
            rendered[field] = value
    return rendered


def _render_url_value(value: Any) -> Any:
    """Render one URL-bearing field: a string, a list of strings, or null."""
    if isinstance(value, str):
        return optional_media_url(value)
    if isinstance(value, list):
        return [optional_media_url(item) if isinstance(item, str) else item for item in value]
    return value
