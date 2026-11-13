"""store media object keys instead of absolute CDN URLs

Revision ID: c1f2e3d4a5b6
Revises: c9d0e1f2a3b4
Create Date: 2026-11-13 00:00:00.000000

Why this migration exists -- the T-021 production incident.

Every media URL the API returned used to be minted once, at upload time, by
app/core/storage.py's `build_media_url` and then stored as a string. When the
CDN moved from `cdn.de-duke.com` to `cdn.de-duke.org` (the `.com` domain is
undelegated), no read path re-derived anything, so the whole catalogue kept
serving URLs on a host that no longer resolves. The objects themselves were
never lost: all of them still serve correctly at the `.org` host.

The durable fix is structural, and it is in application code, not here: write
paths now persist the *object key* and read paths derive the URL against
whatever MEDIA_CDN_DOMAIN is configured (app/core/media_urls.py). This
migration completes that contract for rows already in the database, so the
columns stop carrying a domain that a future move can strand again.

Every statement below is idempotent: a value that is already a bare key does
not start with a scheme and is therefore never rewritten, which is also why
this is safe to reason about alongside the read-time rendering -- either one
alone produces a correct URL, and both together change nothing twice.

Rewritten prefixes:
  https://cdn.de-duke.com/<key>            -> <key>   (the host that died)
  https://cdn.de-duke.org/<key>            -> <key>   (the current host: a
                                                        future move must not
                                                        strand these either)
  <base>/storage/v1/b/<bucket>/o/<key>?alt=media     -> <key>   (local
                                                        fake-gcs-server form,
                                                        including any dev or
                                                        staging database that
                                                        was seeded that way)

Deliberately NOT rewritten: an absolute URL on any other host. The API never
minted those (the load-test seed script uses example.com placeholders; the
account-deletion flow writes the literal "anonymized"), so guessing at them
would corrupt data this migration does not understand.

Runs through the existing de-duke-migrate Cloud Run job in CI. All 19 columns
were verified against app/models/ at the time of writing -- the prompt that
dispatched this work counted 13, which undercounted the host-account subtype
tables (there are 14 verification-document columns, not 8).
"""

from collections.abc import Sequence

from alembic import op

revision: str = "c1f2e3d4a5b6"
down_revision: str | None = "c9d0e1f2a3b4"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

#: (table, column) for every column this codebase stores a media object key
#: in. ListingMedia.media_url/poster_url, HostAccount.host_photo_url, the
#: fourteen verification-document columns across the six host_account_*
#: subtype tables, User.profile_photo_url, Receipt.pdf_url.
_MEDIA_KEY_COLUMNS: tuple[tuple[str, str], ...] = (
    ("listing_media", "media_url"),
    ("listing_media", "poster_url"),
    ("host_accounts", "host_photo_url"),
    # host_account_agents
    ("host_account_agents", "cac_cert_doc_url"),
    ("host_account_agents", "industry_license_url"),
    ("host_account_agents", "proof_of_address_url"),
    ("host_account_agents", "rep_id_url"),
    # host_account_companies
    ("host_account_companies", "cac_reg_doc_url"),
    ("host_account_companies", "proof_of_address_url"),
    ("host_account_companies", "rep_id_url"),
    # host_account_lawyers
    ("host_account_lawyers", "valid_practicing_cert_url"),
    ("host_account_lawyers", "govt_issued_id_url"),
    ("host_account_lawyers", "proof_of_address_url"),
    # host_account_architects
    ("host_account_architects", "practice_license_url"),
    ("host_account_architects", "govt_issued_id_url"),
    # host_account_surveyors
    ("host_account_surveyors", "practice_license_url"),
    ("host_account_surveyors", "govt_issued_id_url"),
    # avatars + receipts
    ("users", "profile_photo_url"),
    ("receipts", "pdf_url"),
)

#: The two domain-move prefixes. Kept as one pattern so the `.com` host (dead)
#: and the `.org` host (live) are treated identically -- both must end up as
#: bare keys, or the next move repeats the incident.
#:
#: Deliberately a capturing group, not `(?:com|org)`: SQLAlchemy's text()
#: parses `?:` as a bind-parameter marker and mangles the pattern under
#: literal rendering (`alembic upgrade --sql` emits `(?NULL|org)`), so the
#: non-capturing form is not safe inside op.execute. Nothing here references
#: the capture, so a plain group is equivalent.
_CDN_PREFIX_PATTERN = r"^https?://cdn\.de-duke\.(com|org)/"

#: fake-gcs-server's JSON-API media-download form (see storage.build_media_url
#: local-dev branch): the object name sits after `/o/` and the `?alt=media`
#: query follows it.
_EMULATOR_PREFIX_PATTERN = r"^https?://[^/]+/storage/v1/b/[^/]+/o/"
_EMULATOR_QUERY_PATTERN = r"\?.*$"


def _strip_to_key_sql(table: str, column: str) -> str:
    """One idempotent UPDATE for one column.

    A single CASE keeps it to one statement (and one row rewrite) per column
    instead of several passes over the table. The WHERE clause matches only
    the two prefixes this migration is responsible for, so a row that is
    already a bare key -- or a third-party URL the API never minted -- is not
    merely left with the same value, it is never rewritten at all. Re-running
    the migration therefore touches zero rows.
    """
    return f"""
        UPDATE {table}
        SET {column} = CASE
            WHEN {column} ~ '{_CDN_PREFIX_PATTERN}'
                THEN regexp_replace({column}, '{_CDN_PREFIX_PATTERN}', '')
            WHEN {column} ~ '{_EMULATOR_PREFIX_PATTERN}'
                THEN regexp_replace(
                    regexp_replace({column}, '{_EMULATOR_PREFIX_PATTERN}', ''),
                    '{_EMULATOR_QUERY_PATTERN}',
                    ''
                )
            ELSE {column}
        END
        WHERE {column} ~ '{_CDN_PREFIX_PATTERN}'
            OR {column} ~ '{_EMULATOR_PREFIX_PATTERN}'
    """


def upgrade() -> None:
    for table, column in _MEDIA_KEY_COLUMNS:
        op.execute(_strip_to_key_sql(table, column))


def downgrade() -> None:
    # Deliberately a no-op, and deliberately not a best-effort reversal.
    #
    # Reversing would mean prefixing each key with a host, and there is no
    # correct host to pick: the `.com` domain is undelegated (that is this
    # incident), and the `.org` host is exactly the value a future domain
    # move would make wrong again. A downgrade that wrote URLs back would
    # also silently undo the application-level contract that made this
    # class of bug impossible -- the code this migration ships with reads
    # these columns as keys, so a URL written here would still render
    # correctly, but only because the read path compensates. Refusing to
    # guess is the honest behaviour; restoring URLs is a decision for a
    # human with a specific host in mind.
    pass
