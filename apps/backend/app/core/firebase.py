"""Shared Firebase Admin SDK app lifecycle.

Lazily initializes ONE `firebase_admin` app (a Firebase Admin SDK
singleton is process-wide by design -- `firebase_admin.initialize_app`
raises if called twice for the same name) and hands it to both:
  - app/services/chat_service.py (Firestore access + scoped custom tokens
    for Staff/Admin chat sessions, FEAT-010).
  - app/services/auth_service.py (verifying consumer Firebase ID tokens at
    sign-in, FEAT-001).

Both consume the SAME Firebase project/service-account credentials
(settings.firebase_service_account_json / firestore_project_id) --
architecture.md's Authentication & Authorization section documents this as
a deliberate simplification: a consumer's real Firebase Authentication
identity (created at FEAT-001 sign-in) IS the same identity Firestore's
security rules evaluate for chat, with no separate chat-specific identity
to keep in sync.

Each call site still owns its own "am I configured" check and its own
domain-specific error type (ChatServiceUnavailableError,
FirebaseAuthUnavailableError) rather than this module raising directly --
this mirrors chat_service.py's pre-existing structure exactly, so its
tests (which patch chat_service._is_configured/_get_firebase_app directly)
keep working unchanged.
"""

from __future__ import annotations

import json
from typing import Any

from app.core.config import get_settings

_firebase_app: Any = None


def is_configured() -> bool:
    """True once real Firebase credentials are provisioned (Secrets
    Manager in deployed environments, or a developer's own `.env`) --
    False in every environment that still carries the REPLACE_ME
    placeholder defaults (local dev without a project, CI)."""
    settings = get_settings()
    return (
        settings.firebase_service_account_json != "REPLACE_ME"
        and settings.firestore_project_id != "REPLACE_ME"
    )


def get_firebase_app() -> Any:
    """Returns the cached `firebase_admin` App, initializing it on first
    call. Callers MUST check `is_configured()` first -- this function
    assumes it's already true and will raise a raw json/SDK error
    otherwise, rather than a caller-facing domain error (each caller wraps
    that itself, per this module's docstring)."""
    global _firebase_app
    if _firebase_app is not None:
        return _firebase_app

    import firebase_admin
    from firebase_admin import credentials

    settings = get_settings()
    cred_info = json.loads(settings.firebase_service_account_json)
    cred = credentials.Certificate(cred_info)
    _firebase_app = firebase_admin.initialize_app(
        cred, {"projectId": settings.firestore_project_id}
    )
    return _firebase_app


def reset_cached_app_for_tests() -> None:
    """Test-only escape hatch -- mirrors the `svc._firebase_app = None`
    reset test_chat.py already does directly on the module global before a
    test that needs `is_configured()`/`get_firebase_app()` to actually run
    their real (mocked-downstream) logic rather than return a stale cached
    App from an earlier test."""
    global _firebase_app
    _firebase_app = None
