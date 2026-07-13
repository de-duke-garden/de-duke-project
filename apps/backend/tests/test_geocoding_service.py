"""Tests for FEAT-023's Google Geocoding wrapper
(app/services/geocoding_service.py)."""

from __future__ import annotations

from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from app.services import geocoding_service
from app.services.geocoding_service import geocode_address


def _settings(*, api_key: str = "real-key") -> MagicMock:
    return MagicMock(google_maps_api_key=api_key)


class TestGeocodeAddress:
    async def test_returns_none_when_api_key_unconfigured(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        monkeypatch.setattr(
            geocoding_service, "get_settings", lambda: _settings(api_key="REPLACE_ME")
        )
        result = await geocode_address("Lekki, Lagos")
        assert result is None

    async def test_returns_none_for_blank_address(self, monkeypatch: pytest.MonkeyPatch) -> None:
        monkeypatch.setattr(geocoding_service, "get_settings", lambda: _settings())
        assert await geocode_address("   ") is None

    async def test_returns_coordinates_on_success(self, monkeypatch: pytest.MonkeyPatch) -> None:
        monkeypatch.setattr(geocoding_service, "get_settings", lambda: _settings())

        fake_response = MagicMock()
        fake_response.raise_for_status = MagicMock()
        fake_response.json.return_value = {
            "status": "OK",
            "results": [{"geometry": {"location": {"lat": 6.4407, "lng": 3.4763}}}],
        }
        fake_client = AsyncMock()
        fake_client.get.return_value = fake_response
        fake_client.__aenter__.return_value = fake_client
        fake_client.__aexit__.return_value = False

        with patch("app.services.geocoding_service.httpx.AsyncClient", return_value=fake_client):
            result = await geocode_address("Lekki Phase 1, Lagos")

        assert result == (6.4407, 3.4763)
        _, kwargs = fake_client.get.call_args
        assert kwargs["params"]["address"] == "Lekki Phase 1, Lagos"
        assert kwargs["params"]["key"] == "real-key"

    async def test_returns_none_when_google_finds_no_results(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        monkeypatch.setattr(geocoding_service, "get_settings", lambda: _settings())

        fake_response = MagicMock()
        fake_response.raise_for_status = MagicMock()
        fake_response.json.return_value = {"status": "ZERO_RESULTS", "results": []}
        fake_client = AsyncMock()
        fake_client.get.return_value = fake_response
        fake_client.__aenter__.return_value = fake_client
        fake_client.__aexit__.return_value = False

        with patch("app.services.geocoding_service.httpx.AsyncClient", return_value=fake_client):
            result = await geocode_address("a completely made up nonexistent place")

        assert result is None

    async def test_returns_none_on_network_failure(self, monkeypatch: pytest.MonkeyPatch) -> None:
        monkeypatch.setattr(geocoding_service, "get_settings", lambda: _settings())

        fake_client = AsyncMock()
        fake_client.get.side_effect = RuntimeError("network error")
        fake_client.__aenter__.return_value = fake_client
        fake_client.__aexit__.return_value = False

        with patch("app.services.geocoding_service.httpx.AsyncClient", return_value=fake_client):
            result = await geocode_address("Lekki")

        assert result is None
