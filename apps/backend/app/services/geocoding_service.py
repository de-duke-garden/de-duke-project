"""Google Geocoding for FEAT-023 (Saved Searches & Listing Alerts).

`SavedSearch.location_query` is free text (e.g. "Lekki, Lagos"), entered
without a client-side map/autocomplete step (unlike FEAT-006's main search,
which always receives ready-made device/GPS coordinates -- see
app/api/v1/search.py's docstring). Saved-search matching happens later, in
a headless background worker (app/workers/saved_search_alert_job.py) with
no user/client in the loop to resolve that text to coordinates -- so the
backend must geocode it itself, once, at save time.

Bounded timeout + no raised exceptions on failure (AGENTS.md's external-
dependency resilience rule): a Google Maps outage, an invalid/quota-
exhausted API key, or an unresolvable address must never block saving a
search -- it only means that search falls back to substring matching
(saved_search_service.py's pre-existing degraded path) until geocoding
succeeds on a later edit/retry.
"""

from __future__ import annotations

import httpx

from app.core.config import get_settings

_GEOCODE_URL = "https://maps.googleapis.com/maps/api/geocode/json"


async def geocode_address(
    address: str, *, timeout_seconds: float = 5.0
) -> tuple[float, float] | None:
    """Resolves free-text `address` to (latitude, longitude) via the Google
    Geocoding API. Returns None (never raises) if the API key is
    unconfigured, the call fails/times out, or Google returns zero results
    -- callers must treat None as "no coordinates available yet", not an
    error.
    """
    settings = get_settings()
    if settings.google_maps_api_key == "REPLACE_ME":
        return None

    address = address.strip()
    if not address:
        return None

    try:
        async with httpx.AsyncClient(timeout=timeout_seconds) as client:
            response = await client.get(
                _GEOCODE_URL,
                params={"address": address, "key": settings.google_maps_api_key},
            )
            response.raise_for_status()
            data = response.json()
    except Exception:  # noqa: BLE001 -- any failure degrades to None, never raises
        return None

    if data.get("status") != "OK" or not data.get("results"):
        return None

    location = data["results"][0]["geometry"]["location"]
    return (location["lat"], location["lng"])
