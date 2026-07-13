"""Embedding generation for FEAT-031 (Semantic Property Search).

Vendor: Gemini (Google's `gemini-embedding-001` model, via the
Generative Language REST API -- see `GeminiEmbeddingProvider` below),
configured through `Settings.embedding_provider`/`gemini_api_key`
(app/core/config.py). `get_embedding_provider()` falls back to a
zero-dependency, deterministic LOCAL provider ("hashing trick"
bag-of-tokens, L2-normalized) whenever `embedding_provider != "gemini"` or
`gemini_api_key` is still the REPLACE_ME placeholder -- so an
unconfigured/misconfigured environment (including CI, which has no real
key) degrades to keyword-overlap-only ranking rather than hard-failing
FEAT-031 entirely.

`get_embedding_provider()` is the single seam for swapping providers --
no call site in search_service.py or the embedding worker needs to change.
Swapping providers does not require a new migration as long as the new
provider's output width matches `Settings.embedding_dimensions`; changing
the dimension count does, since a pgvector `Vector` column is fixed-width.

Resilience (AGENTS.md Behavior Rule -- "every external dependency call uses
a bounded timeout + circuit breaker; degrade gracefully rather than
cascading failure"): `embed_text()` wraps every provider call in
`asyncio.wait_for` and a simple in-process circuit breaker. The breaker is
deliberately per-process (unlike the rate-limit counters in app/core/cache.py,
which must be shared across Fargate tasks for *correctness*) -- here there is
no correctness requirement to share state across tasks, only a latency-
protection one; the worst case for a fresh task is one extra slow call
before it, too, opens its own breaker.
"""

from __future__ import annotations

import asyncio
import hashlib
import math
import re
import time
from typing import Protocol

import httpx

from app.core.config import get_settings

_GEMINI_EMBED_URL_TEMPLATE = (
    "https://generativelanguage.googleapis.com/v1beta/models/{model}:embedContent"
)
_GEMINI_MODEL = "gemini-embedding-001"

_TOKEN_RE = re.compile(r"[a-z0-9]+")


class EmbeddingProvider(Protocol):
    """Minimal provider interface -- any future real provider (OpenAI, a
    self-hosted sentence-transformers endpoint, etc.) only needs to satisfy
    this single method."""

    async def embed(self, text: str) -> list[float]: ...


class LocalHashingEmbeddingProvider:
    """Deterministic, dependency-free embedding via the classic "hashing
    trick": each token is hashed into one of `dimensions` buckets (stable
    across processes/restarts -- uses hashlib, never Python's per-process
    salted `hash()`), accumulated with a hash-derived sign so unrelated
    tokens partially cancel rather than only ever summing, then L2-normalized
    so pgvector's cosine distance is well-behaved.
    """

    def __init__(self, dimensions: int) -> None:
        self._dimensions = dimensions

    async def embed(self, text: str) -> list[float]:
        vector = [0.0] * self._dimensions
        for token in _TOKEN_RE.findall(text.lower()):
            digest = hashlib.blake2b(token.encode(), digest_size=8).digest()
            bucket = int.from_bytes(digest, "big") % self._dimensions
            sign = 1.0 if digest[0] % 2 == 0 else -1.0
            vector[bucket] += sign

        norm = math.sqrt(sum(v * v for v in vector))
        if norm == 0.0:
            return vector
        return [v / norm for v in vector]


class GeminiEmbeddingProvider:
    """Calls Google's Generative Language API (`gemini-embedding-001`) to
    produce a real semantic embedding. Uses `outputDimensionality` to
    request a vector matching `Settings.embedding_dimensions` directly
    (Gemini supports truncated/Matryoshka-style output widths for this
    model), so no separate re-projection step is needed to fit the
    pgvector column's fixed width.

    `task_type="SEMANTIC_SIMILARITY"` is used for both indexing (the
    embedding worker) and query-time embedding (search_service) -- Gemini
    also offers an asymmetric RETRIEVAL_DOCUMENT/RETRIEVAL_QUERY pairing
    that can be more accurate for retrieval, but that would require
    threading a task-type distinction through both call sites for a
    single shared `EmbeddingProvider.embed(text)` seam; SEMANTIC_SIMILARITY
    is a reasonable, simpler default that still meaningfully improves on
    the local hashing fallback.
    """

    def __init__(self, *, api_key: str, dimensions: int) -> None:
        self._api_key = api_key
        self._dimensions = dimensions

    async def embed(self, text: str) -> list[float]:
        url = _GEMINI_EMBED_URL_TEMPLATE.format(model=_GEMINI_MODEL)
        async with httpx.AsyncClient(timeout=10.0) as client:
            response = await client.post(
                url,
                params={"key": self._api_key},
                json={
                    "content": {"parts": [{"text": text}]},
                    "taskType": "SEMANTIC_SIMILARITY",
                    "outputDimensionality": self._dimensions,
                },
            )
            response.raise_for_status()
            data = response.json()

        values = data["embedding"]["values"]
        # gemini-embedding-001's non-full-width outputs are not
        # pre-normalized by the API (only the full 3072-dim output is) --
        # re-normalize here so pgvector's cosine distance is well-behaved
        # regardless of the requested outputDimensionality.
        norm = math.sqrt(sum(v * v for v in values))
        if norm == 0.0:
            return values
        return [v / norm for v in values]


_provider: EmbeddingProvider | None = None


def get_embedding_provider() -> EmbeddingProvider:
    """Returns the process-wide embedding provider, built once from
    Settings. Falls back to LocalHashingEmbeddingProvider whenever
    `embedding_provider` isn't "gemini", or Gemini is selected but
    `gemini_api_key` is still at its REPLACE_ME placeholder -- an
    incomplete/typo'd config must never hard-break search, only run it in
    degraded (keyword-only-equivalent) mode."""
    global _provider
    if _provider is not None:
        return _provider

    settings = get_settings()
    if settings.embedding_provider == "gemini" and settings.gemini_api_key != "REPLACE_ME":
        _provider = GeminiEmbeddingProvider(
            api_key=settings.gemini_api_key, dimensions=settings.embedding_dimensions
        )
    else:
        _provider = LocalHashingEmbeddingProvider(settings.embedding_dimensions)
    return _provider


def reset_provider_for_tests() -> None:
    """Test-only: clears the cached provider so tests can change
    Settings.embedding_dimensions and get a provider matching the new value."""
    global _provider
    _provider = None


class _CircuitBreaker:
    """Simple consecutive-failure breaker -- opens after `failure_threshold`
    back-to-back failures/timeouts, refuses calls for `cooldown_seconds`,
    then half-opens (lets exactly one call through) to probe recovery."""

    def __init__(self, failure_threshold: int, cooldown_seconds: float) -> None:
        self._failure_threshold = failure_threshold
        self._cooldown_seconds = cooldown_seconds
        self._consecutive_failures = 0
        self._opened_at: float | None = None

    def is_open(self) -> bool:
        if self._opened_at is None:
            return False
        if time.monotonic() - self._opened_at >= self._cooldown_seconds:
            self._opened_at = None
            self._consecutive_failures = 0
            return False
        return True

    def record_success(self) -> None:
        self._consecutive_failures = 0
        self._opened_at = None

    def record_failure(self) -> None:
        self._consecutive_failures += 1
        if self._consecutive_failures >= self._failure_threshold and self._opened_at is None:
            self._opened_at = time.monotonic()

    def reset(self) -> None:
        self._consecutive_failures = 0
        self._opened_at = None


_breaker = _CircuitBreaker(failure_threshold=3, cooldown_seconds=30.0)


def reset_circuit_breaker_for_tests() -> None:
    """Test-only helper -- see tests/test_embedding_service.py."""
    _breaker.reset()


async def embed_text(text: str, *, timeout_seconds: float) -> list[float] | None:
    """Returns an embedding vector for `text`, or None if the circuit
    breaker is open, the provider call times out, or the provider raises.

    Callers (search_service.search_listings, the listing embedding worker)
    MUST treat None as "degrade gracefully" -- fall back to keyword/filter
    -only ranking (search) or simply retry the listing on the worker's next
    cycle (embedding) -- never raise or block further on it. This is the
    single choke point implementing FEAT-031's "degrades gracefully ... within
    a strict timeout" acceptance criterion and AGENTS.md's external-
    dependency resilience rule.
    """
    if not text or not text.strip():
        return None
    if _breaker.is_open():
        return None

    provider = get_embedding_provider()
    try:
        result = await asyncio.wait_for(provider.embed(text), timeout=timeout_seconds)
    except Exception:  # noqa: BLE001 -- any provider failure must degrade, never raise
        _breaker.record_failure()
        return None

    _breaker.record_success()
    return result
