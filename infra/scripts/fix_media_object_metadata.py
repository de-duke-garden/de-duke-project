#!/usr/bin/env python3
"""Normalise Content-Type and Cache-Control metadata on the De-Duke media bucket.

Why this exists
---------------
Cloud CDN on the media backend bucket runs ``cache_mode = CACHE_ALL_STATIC``,
which honours the origin's ``Cache-Control``. Objects uploaded without cache
metadata are served by GCS as ``Cache-Control: private, max-age=0``, and Cloud
CDN never caches a response that says ``private`` -- so every media request was
an origin hit no matter what the CDN policy said.

The same uploads also failed to set a content type whenever the object key had
no file extension (``app/core/storage.py`` names host-account documents by bare
UUID, so ``mimetypes.guess_type`` found nothing and the SDK stored
``application/octet-stream``). ``application/octet-stream`` is not a static
content type, browsers download instead of displaying, and the verification
documents look like files instead of images.

This script rewrites both metadata fields on objects that are already stored:

    Cache-Control: public, max-age=31536000, immutable
    Content-Type:   sniffed from the object's own leading bytes

Content type is derived from magic bytes, never from the key. Extension-less
keys are the entire reason the metadata is wrong, so the key is the one source
that cannot be trusted here. An object whose leading bytes are not recognised is
reported as undetermined and left untouched (it is never guessed).

Media objects are UUID-named and never overwritten, which is what makes a
one-year ``immutable`` TTL correct: a given key always means the same bytes.

Metadata-only updates do not create a new object generation, so the bucket's
versioning history stays clean.

Runbook
-------
Check which account gcloud will use (needs storage.objects.get/update on the
bucket -- the operator account, or `de-duke-backend`)::

    gcloud auth list

1. Dry run. This is the default and mutates nothing. It prints every object key
   with its current and intended Content-Type / Cache-Control, then a summary::

       python infra/scripts/fix_media_object_metadata.py

2. Apply, once the dry-run table has been reviewed::

       python infra/scripts/fix_media_object_metadata.py --apply

   The script is idempotent: objects already carrying the intended metadata are
   reported ``OK`` and skipped.

3. Verify through the CDN (Cloud CDN passes the object's metadata downstream).
   Pick any key from the dry-run output::

       curl -sSI https://cdn.de-duke.org/listings/<listing-id>/<uuid>.jpg

   Expect ``content-type: image/jpeg`` and
   ``cache-control: public, max-age=31536000, immutable``. Before the fix the
   same request returned ``application/octet-stream`` (or the extension-derived
   type) and ``private, max-age=0``.

4. Optional sanity check that the CDN is now caching (a second request should
   carry ``age`` and ``cache-status`` headers)::

       curl -sSI https://cdn.de-duke.org/listings/<listing-id>/<uuid>.jpg

Exit codes: 0 = every object has a determined type, 1 = at least one object was
undetermined (review the table, the object is skipped), 2 = a gcloud call failed.

Deliberately implemented on the `gcloud` CLI rather than google-cloud-storage:
this is an operator runbook script for `infra/gcp`, it runs before/independently
of the backend image, and it should not add a dependency to this repo for one
one-off migration. Uses only the standard library.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from typing import Optional

# Frozen decision shared with the backend/frontend dispatches: media objects are
# immutable and publicly cacheable for one year.
INTENDED_CACHE_CONTROL = "public, max-age=31536000, immutable"

# How many leading bytes to read per object for magic-byte sniffing. 64 covers
# every signature used below (webp/mp4 need offsets 4-12).
SNIFF_BYTES = 64

DEFAULT_BUCKET = "de-duke-media-531781610440"
DEFAULT_PROJECT = "de-duke-services"


@dataclass
class ObjectPlan:
    """One bucket object and the metadata it should carry."""

    name: str
    size: int
    current_content_type: str
    current_cache_control: str
    intended_content_type: Optional[str]
    evidence: str

    @property
    def undetermined(self) -> bool:
        return self.intended_content_type is None

    @property
    def content_type_changes(self) -> bool:
        return (
            self.intended_content_type is not None
            and self.current_content_type != self.intended_content_type
        )

    @property
    def cache_control_changes(self) -> bool:
        return self.current_cache_control != INTENDED_CACHE_CONTROL

    @property
    def needs_update(self) -> bool:
        return not self.undetermined and (self.content_type_changes or self.cache_control_changes)


def _resolve_gcloud(explicit: Optional[str]) -> list[str]:
    """Return the argv prefix used to invoke gcloud.

    The returned element is the executable itself; `_run` handles the Windows
    `.cmd` shim, because how it is launched (not what it is) is the part that
    differs there.
    """
    candidate = explicit or shutil.which("gcloud") or ""
    if not candidate:
        sys.exit(
            "gcloud not found on PATH. Install the Google Cloud SDK, or pass "
            "--gcloud /path/to/gcloud (Windows: ...\\google-cloud-sdk\\bin\\gcloud.cmd)."
        )
    return [candidate]


class GcloudError(RuntimeError):
    """A gcloud invocation exited non-zero."""


# Bounds a single gcloud call: the parallel signature reads below fire many
# short-lived gcloud processes at once, and the SDK's resolver intermittently
# fails one of them with getaddrinfo/ConnectionError on otherwise healthy
# network. Those are transient by nature -- the same command succeeds on the
# next attempt -- so they are retried instead of aborting a 51-object run (or
# a mid-apply batch) over one lost DNS lookup.
_TRANSIENT_MARKERS = (
    "NameResolutionError",
    "ConnectionError",
    "getaddrinfo",
    "Failed to establish a new connection",
    "Timeout",
    "Connection reset",
    "429",
    "503",
)
_ATTEMPTS = 4


def _run(prefix: list[str], args: list[str], *, text: bool = True) -> bytes | str:
    """Run a gcloud subcommand, returning raw bytes (or text when asked)."""
    # GCLOUD_USER_AGENT / CLU less noise: --quiet suppresses "do you want to
    # continue" style prompts, which must never fire in a batch run.
    argv = [*args, "--quiet"]
    exe = prefix[0]
    if os.name == "nt" and exe.lower().endswith((".cmd", ".bat")):
        # Windows only: the SDK's entry point is a `.cmd` shim, which
        # CreateProcess cannot execute, and routing it through
        # `cmd /c "<path>"` loses the path at its first space (cmd strips the
        # outer quotes of a /c argument, so it runs `C:\Users\...\Google\Cloud`
        # instead). A single explicitly quoted command line is the form that
        # survives a shim path containing spaces. Object keys and values are
        # still quoted by list2cmdline, never pasted raw.
        command: str | list[str] = f'"{exe}" ' + subprocess.list2cmdline(argv)
    else:
        command = [exe, *argv]

    completed: subprocess.CompletedProcess[bytes] | None = None
    for attempt in range(1, _ATTEMPTS + 1):
        if isinstance(command, str):
            completed = subprocess.run(command, shell=True, capture_output=True)
        else:
            completed = subprocess.run(command, capture_output=True)
        if completed.returncode == 0:
            break
        stderr = completed.stderr.decode("utf-8", "replace").strip()
        transient = any(marker in stderr for marker in _TRANSIENT_MARKERS)
        if not transient or attempt == _ATTEMPTS:
            shown = command if isinstance(command, str) else " ".join(command)
            raise GcloudError(f"{shown} failed ({completed.returncode}): {stderr}")
        time.sleep(2 * attempt)
    assert completed is not None  # loop always runs at least once
    return completed.stdout.decode("utf-8", "replace") if text else completed.stdout


def list_objects(prefix: list[str], bucket: str, project: str) -> list[dict]:
    """Return the bucket's objects, newest-version metadata only.

    `ls -r --json` emits one JSON document per object; `/**` is gcloud's
    recursive glob so the whole bucket is listed in a single call.
    """
    raw = _run(prefix, ["storage", "ls", "-r", "--json", f"gs://{bucket}/**", f"--project={project}"])
    documents = json.loads(raw) if raw.strip() else []
    objects: dict[str, dict] = {}
    for document in documents:
        metadata = document.get("metadata") or {}
        name = metadata.get("name")
        # `ls` can also emit bucket/prefix entries; only cloud objects have a
        # name and generation.
        if name and metadata.get("generation"):
            objects[name] = metadata
    return list(objects.values())


def sniff_content_type(head: bytes) -> tuple[Optional[str], str]:
    """Derive a content type from an object's leading bytes.

    Returns (content_type, evidence). content_type is None when the signature is
    not recognised -- callers must not fall back to the object key.
    """
    if head.startswith(b"\xff\xd8\xff"):
        return "image/jpeg", "JPEG SOI marker (ff d8 ff)"

    if head.startswith(b"\x89PNG\r\n\x1a\n"):
        return "image/png", "PNG signature (89 50 4e 47)"

    if head[:4] == b"RIFF" and head[8:12] == b"WEBP":
        return "image/webp", "RIFF/WEBP container"

    if head[:6] in (b"GIF87a", b"GIF89a"):
        # Outside the canonical media type set, but unambiguous -- record it
        # rather than leaving the object undetermined.
        return "image/gif", f"{head[:6].decode('ascii')} header"

    if head[:5] == b"%PDF-":
        return "application/pdf", "PDF header (%PDF-)"

    if head[4:8] == b"ftyp":
        # ISO base media: the major brand at offset 8 decides still image vs
        # video. AVIF is an image despite sharing the ftfy-based container.
        brand = head[8:12]
        if brand in (b"avif", b"avis"):
            return "image/avif", f"ISO-BMFF ftyp brand {brand.decode('ascii', 'replace')}"
        return "video/mp4", f"ISO-BMFF ftyp brand {brand.decode('ascii', 'replace')}"

    if head[:4] == b"\x1a\x45\xdf\xa3":
        return "video/webm", "EBML header (webm/mkv)"

    return None, "unrecognised signature: " + head[:8].hex(" ")


def read_head(prefix: list[str], bucket: str, name: str, project: str) -> bytes:
    """Read the first SNIFF_BYTES of one object without downloading it.

    `gcloud storage cat --range` issues a ranged request, so this stays cheap
    even for the videos (whose smallest siblings are the point of the exercise:
    we never need more than a signature).
    """
    args = [
        "storage",
        "cat",
        f"--range=0-{SNIFF_BYTES - 1}",
        f"gs://{bucket}/{name}",
        f"--project={project}",
    ]
    return _run(prefix, args, text=False)  # type: ignore[return-value]


def build_plan(prefix: list[str], bucket: str, project: str, objects: list[dict], workers: int) -> list[ObjectPlan]:
    """Sniff every object's leading bytes and pair them with current metadata."""

    def describe(metadata: dict) -> ObjectPlan:
        name = metadata["name"]
        head = read_head(prefix, bucket, name, project)
        content_type, evidence = sniff_content_type(head)
        return ObjectPlan(
            name=name,
            size=int(metadata.get("size") or 0),
            current_content_type=metadata.get("contentType") or "(none)",
            current_cache_control=metadata.get("cacheControl") or "(none)",
            intended_content_type=content_type,
            evidence=evidence,
        )

    # Sniff in parallel: each object is a separate read-only gcloud call, and a
    # bucket's worth of them is dominated by process startup.
    with ThreadPoolExecutor(max_workers=max(1, workers)) as pool:
        plans = list(pool.map(describe, objects))
    plans.sort(key=lambda plan: plan.name)
    return plans


def apply_plan(prefix: list[str], bucket: str, project: str, plan: ObjectPlan) -> None:
    """Write the intended Content-Type and Cache-Control onto one object.

    Metadata-only: the object's bytes and generation are unchanged.
    """
    assert plan.intended_content_type is not None
    _run(
        prefix,
        [
            "storage",
            "objects",
            "update",
            f"gs://{bucket}/{plan.name}",
            f"--content-type={plan.intended_content_type}",
            f"--cache-control={INTENDED_CACHE_CONTROL}",
            f"--project={project}",
        ],
    )


def _human_size(size: int) -> str:
    if size >= 1 << 20:
        return f"{size / (1 << 20):.1f}M"
    if size >= 1 << 10:
        return f"{size / (1 << 10):.0f}K"
    return str(size)


def print_table(plans: list[ObjectPlan]) -> None:
    """Print one line per object: key plus current -> intended metadata."""
    width = max((len(plan.name) for plan in plans), default=20)
    width = min(max(width, 20), 96)
    print()
    for plan in plans:
        key = plan.name if len(plan.name) <= width else plan.name[: width - 3] + "..."
        print(f"{key:<{width}}  {_human_size(plan.size):>5}")
        print(f"{'':<{width}}    content-type: {plan.current_content_type} -> {plan.intended_content_type or 'UNDETERMINED'}")
        print(f"{'':<{width}}    cache-control: {plan.current_cache_control} -> {INTENDED_CACHE_CONTROL}")
        print(f"{'':<{width}}    sniffed as: {plan.evidence}")
        if plan.undetermined:
            status = "SKIP (undetermined)"
        elif plan.needs_update:
            status = "UPDATE"
        else:
            status = "OK"
        print(f"{'':<{width}}    action: {status}")


def print_summary(plans: list[ObjectPlan], applied: bool) -> None:
    """Print the counts an operator needs to decide whether to --apply."""
    total = len(plans)
    undetermined = [plan for plan in plans if plan.undetermined]
    updatable = [plan for plan in plans if plan.needs_update]
    already_ok = [plan for plan in plans if not plan.undetermined and not plan.needs_update]
    ct_changes = [plan for plan in plans if not plan.undetermined and plan.content_type_changes]
    cc_changes = [plan for plan in plans if not plan.undetermined and plan.cache_control_changes]

    by_type: dict[str, int] = {}
    for plan in plans:
        label = plan.intended_content_type or "undetermined"
        by_type[label] = by_type.get(label, 0) + 1

    print()
    print("Summary")
    print(f"  objects scanned          : {total}")
    print(f"  content-type changes     : {len(ct_changes)}")
    print(f"  cache-control changes    : {len(cc_changes)}")
    print(f"  already correct (skipped): {len(already_ok)}")
    print(f"  undetermined (skipped)   : {len(undetermined)}")
    print("  sniffed content types    : " + ", ".join(f"{key}={value}" for key, value in sorted(by_type.items())))
    if undetermined:
        print()
        print("  Undetermined objects (left untouched -- content type is never guessed from the key):")
        for plan in undetermined:
            print(f"    - {plan.name}: {plan.evidence}")
    print()
    if applied:
        print(f"Applied to {len(updatable)} object(s).")
    else:
        print(f"DRY RUN -- nothing changed. {len(updatable)} object(s) would be updated.")
        if updatable:
            print("Re-run with --apply to write the metadata.")


def main(argv: Optional[list[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Set Content-Type (sniffed from magic bytes) and "
            f"Cache-Control: {INTENDED_CACHE_CONTROL} on media bucket objects. "
            "Dry run by default."
        )
    )
    parser.add_argument("--apply", action="store_true", help="Write the metadata. Without this flag the script is a dry run.")
    parser.add_argument("--bucket", default=DEFAULT_BUCKET, help=f"Media bucket name (default: {DEFAULT_BUCKET}).")
    parser.add_argument("--project", default=DEFAULT_PROJECT, help=f"GCP project (default: {DEFAULT_PROJECT}).")
    parser.add_argument("--gcloud", default=None, help="Path to the gcloud executable (default: resolve from PATH).")
    parser.add_argument("--workers", type=int, default=8, help="Parallel signature reads (default: 8).")
    parser.add_argument("--limit", type=int, default=0, help="Only process the first N objects (0 = all). Smoke-testing aid.")
    args = parser.parse_args(argv)

    prefix = _resolve_gcloud(args.gcloud)
    try:
        objects = list_objects(prefix, args.bucket, args.project)
        if args.limit:
            objects = objects[: args.limit]
        if not objects:
            print(f"No objects found in gs://{args.bucket}.", file=sys.stderr)
            return 0

        print(f"Bucket : gs://{args.bucket} ({args.project})")
        print(f"Objects: {len(objects)}")
        print(f"Mode   : {'APPLY' if args.apply else 'DRY RUN'}")
        print(f"Intended Cache-Control: {INTENDED_CACHE_CONTROL}")

        plans = build_plan(prefix, args.bucket, args.project, objects, args.workers)
        print_table(plans)

        if args.apply:
            for plan in plans:
                if plan.needs_update:
                    apply_plan(prefix, args.bucket, args.project, plan)
        print_summary(plans, applied=args.apply)
    except GcloudError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 2

    return 1 if any(plan.undetermined for plan in plans) else 0


if __name__ == "__main__":
    sys.exit(main())
