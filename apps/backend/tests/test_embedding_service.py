"""Tests for FEAT-031's embedding provider, bounded timeout, and circuit
breaker (app/services/embedding_service.py)."""

from __future__ import annotations

import asyncio
import math
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from app.services import embedding_service
from app.services.embedding_service import (
    GeminiEmbeddingProvider,
    LocalHashingEmbeddingProvider,
    embed_text,
    get_embedding_provider,
    reset_circuit_breaker_for_tests,
    reset_provider_for_tests,
)


@pytest.fixture(autouse=True)
def _reset_embedding_state() -> None:
    """Every test starts with a closed breaker and a fresh cached provider,
    since both are process-global state (see embedding_service.py's module
    docstring for why the breaker is intentionally per-process)."""
    reset_circuit_breaker_for_tests()
    reset_provider_for_tests()
    yield
    reset_circuit_breaker_for_tests()
    reset_provider_for_tests()


class TestLocalHashingEmbeddingProvider:
    async def test_embedding_has_configured_dimensions(self) -> None:
        provider = LocalHashingEmbeddingProvider(dimensions=64)
        vector = await provider.embed("quiet 2-bedroom near a school with parking")
        assert len(vector) == 64

    async def test_embedding_is_l2_normalized(self) -> None:
        provider = LocalHashingEmbeddingProvider(dimensions=64)
        vector = await provider.embed("quiet 2-bedroom near a school with parking")
        norm = sum(v * v for v in vector) ** 0.5
        assert norm == pytest.approx(1.0, abs=1e-6)

    async def test_empty_text_returns_zero_vector(self) -> None:
        provider = LocalHashingEmbeddingProvider(dimensions=32)
        vector = await provider.embed("   ")
        assert vector == [0.0] * 32

    async def test_deterministic_across_calls(self) -> None:
        provider = LocalHashingEmbeddingProvider(dimensions=32)
        first = await provider.embed("2 bedroom apartment")
        second = await provider.embed("2 bedroom apartment")
        assert first == second

    async def test_similar_text_more_similar_than_unrelated_text(self) -> None:
        """Sanity check that the hashing-trick fallback captures *some*
        keyword-overlap signal -- cosine similarity between near-duplicate
        phrases should exceed similarity against an unrelated phrase."""
        provider = LocalHashingEmbeddingProvider(dimensions=256)
        base = await provider.embed("quiet 2 bedroom apartment near a school with parking")
        similar = await provider.embed("quiet 2 bedroom flat near a school with parking space")
        unrelated = await provider.embed("industrial warehouse for lease downtown")

        def cosine(a: list[float], b: list[float]) -> float:
            return sum(x * y for x, y in zip(a, b, strict=True))

        assert cosine(base, similar) > cosine(base, unrelated)


class TestGeminiEmbeddingProvider:
    async def test_calls_gemini_and_normalizes_result(self) -> None:
        provider = GeminiEmbeddingProvider(api_key="fake-key", dimensions=4)

        fake_response = MagicMock()
        fake_response.raise_for_status = MagicMock()
        fake_response.json.return_value = {"embedding": {"values": [3.0, 4.0, 0.0, 0.0]}}

        fake_client = AsyncMock()
        fake_client.post.return_value = fake_response
        fake_client.__aenter__.return_value = fake_client
        fake_client.__aexit__.return_value = False

        with patch("app.services.embedding_service.httpx.AsyncClient", return_value=fake_client):
            result = await provider.embed("quiet 2-bedroom near a school")

        # [3, 4, 0, 0] has norm 5 -- normalized to [0.6, 0.8, 0, 0].
        assert result == pytest.approx([0.6, 0.8, 0.0, 0.0])
        norm = math.sqrt(sum(v * v for v in result))
        assert norm == pytest.approx(1.0)

        _, kwargs = fake_client.post.call_args
        assert kwargs["params"] == {"key": "fake-key"}
        assert kwargs["json"]["outputDimensionality"] == 4
        assert kwargs["json"]["content"]["parts"][0]["text"] == "quiet 2-bedroom near a school"

    async def test_http_error_propagates_for_embed_text_to_catch(self) -> None:
        """GeminiEmbeddingProvider itself doesn't swallow errors --
        embed_text's own try/except + circuit breaker is the single place
        that degrades a failure to None (see TestEmbedTextResilience
        below), so this provider must raise, not return a sentinel."""
        provider = GeminiEmbeddingProvider(api_key="fake-key", dimensions=4)

        fake_client = AsyncMock()
        fake_client.post.side_effect = RuntimeError("network error")
        fake_client.__aenter__.return_value = fake_client
        fake_client.__aexit__.return_value = False

        with (
            patch("app.services.embedding_service.httpx.AsyncClient", return_value=fake_client),
            pytest.raises(RuntimeError),
        ):
            await provider.embed("query")


class TestGetEmbeddingProvider:
    def test_defaults_to_local_when_provider_not_gemini(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        settings = MagicMock(
            embedding_provider="local", gemini_api_key="REPLACE_ME", embedding_dimensions=256
        )
        monkeypatch.setattr(embedding_service, "get_settings", lambda: settings)

        provider = get_embedding_provider()
        assert isinstance(provider, LocalHashingEmbeddingProvider)

    def test_falls_back_to_local_when_gemini_selected_but_key_unset(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        settings = MagicMock(
            embedding_provider="gemini", gemini_api_key="REPLACE_ME", embedding_dimensions=256
        )
        monkeypatch.setattr(embedding_service, "get_settings", lambda: settings)

        provider = get_embedding_provider()
        assert isinstance(provider, LocalHashingEmbeddingProvider)

    def test_uses_gemini_when_selected_and_key_configured(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        settings = MagicMock(
            embedding_provider="gemini", gemini_api_key="a-real-key", embedding_dimensions=256
        )
        monkeypatch.setattr(embedding_service, "get_settings", lambda: settings)

        provider = get_embedding_provider()
        assert isinstance(provider, GeminiEmbeddingProvider)


class TestEmbedTextResilience:
    """Force the zero-dependency Local provider for the ambient
    (non-monkeypatched-provider) tests below -- these must stay hermetic
    and pass with no network access, regardless of whatever
    EMBEDDING_PROVIDER/GEMINI_API_KEY happen to be set in whichever .env
    the environment running this suite has (e.g. a developer's own local
    Gemini config). Tests that need a specific fake provider behavior
    (slow/failing) already monkeypatch get_embedding_provider directly."""

    @pytest.fixture(autouse=True)
    def _force_local_provider(self, monkeypatch: pytest.MonkeyPatch) -> None:
        monkeypatch.setattr(
            embedding_service,
            "get_embedding_provider",
            lambda: LocalHashingEmbeddingProvider(256),
        )

    async def test_returns_embedding_on_success(self) -> None:
        result = await embed_text("2 bedroom flat", timeout_seconds=1.0)
        assert result is not None
        assert isinstance(result, list)

    async def test_blank_query_returns_none(self) -> None:
        assert await embed_text("", timeout_seconds=1.0) is None
        assert await embed_text("   ", timeout_seconds=1.0) is None

    async def test_timeout_degrades_to_none(self, monkeypatch: pytest.MonkeyPatch) -> None:
        """A slow provider must never block the caller past `timeout_seconds`
        -- FEAT-031's own acceptance criterion."""

        class _SlowProvider:
            async def embed(self, text: str) -> list[float]:
                await asyncio.sleep(5)
                return [0.0]

        monkeypatch.setattr(embedding_service, "get_embedding_provider", lambda: _SlowProvider())

        result = await embed_text("slow query", timeout_seconds=0.05)
        assert result is None

    async def test_provider_error_degrades_to_none(self, monkeypatch: pytest.MonkeyPatch) -> None:
        class _FailingProvider:
            async def embed(self, text: str) -> list[float]:
                raise RuntimeError("provider unavailable")

        monkeypatch.setattr(embedding_service, "get_embedding_provider", lambda: _FailingProvider())

        result = await embed_text("failing query", timeout_seconds=1.0)
        assert result is None

    async def test_circuit_breaker_opens_after_repeated_failures(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        call_count = 0

        class _FailingProvider:
            async def embed(self, text: str) -> list[float]:
                nonlocal call_count
                call_count += 1
                raise RuntimeError("down")

        monkeypatch.setattr(embedding_service, "get_embedding_provider", lambda: _FailingProvider())

        # Trip the breaker (failure_threshold=3, see embedding_service.py).
        for _ in range(3):
            assert await embed_text("query", timeout_seconds=1.0) is None
        assert call_count == 3

        # Breaker now open -- provider must not even be invoked again.
        assert await embed_text("query", timeout_seconds=1.0) is None
        assert call_count == 3

    async def test_circuit_breaker_recovers_after_cooldown(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        monkeypatch.setattr(embedding_service._breaker, "_cooldown_seconds", 0.01)

        class _FailingProvider:
            async def embed(self, text: str) -> list[float]:
                raise RuntimeError("down")

        monkeypatch.setattr(embedding_service, "get_embedding_provider", lambda: _FailingProvider())
        for _ in range(3):
            await embed_text("query", timeout_seconds=1.0)
        assert embedding_service._breaker.is_open()

        await asyncio.sleep(0.02)
        assert embedding_service._breaker.is_open() is False
