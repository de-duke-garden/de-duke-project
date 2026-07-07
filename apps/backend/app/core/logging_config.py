"""Structured logging setup + per-request correlation ID -- architecture.md's
Observability Stack: "Centralized structured logs correlated by a
request/trace ID across the Backend API Service and Background Task
Processor."

Before this module existed, NOTHING configured Python's logging anywhere
in the app -- every `logger.info(...)` call already written throughout the
codebase (email_service.py, checkout.py, payment_service.py, etc.) was
silently swallowed, since the root logger defaults to WARNING with no
handler attached. This wires:

  - A JSON-structured formatter (one object per line, queryable in
    CloudWatch Logs Insights) instead of Python logging's bare default.
  - A per-request correlation ID, propagated via a contextvar and injected
    onto every log record emitted while handling that request (see
    app/main.py's RequestIdMiddleware) -- so every log line from a single
    request can be found together regardless of which module emitted it,
    and a client-supplied X-Request-ID (if present) is honored rather than
    always minting a fresh one, so a trace can be correlated across
    services that sit in front of this one too.
  - The configured LOG_LEVEL (default INFO, see Settings.log_level) as the
    root logger's level, so those pre-existing logger.info(...) calls
    actually surface.
"""

from __future__ import annotations

import json
import logging
import sys
from contextvars import ContextVar

request_id_var: ContextVar[str | None] = ContextVar("request_id", default=None)


class RequestIdFilter(logging.Filter):
    """Injects the current request's correlation ID (if any) onto every
    log record as `record.request_id`. Logs emitted outside a request
    (startup, a background job invoked directly rather than through an
    HTTP request) get "-" instead of raising/crashing the formatter."""

    def filter(self, record: logging.LogRecord) -> bool:
        record.request_id = request_id_var.get() or "-"
        return True


class JsonFormatter(logging.Formatter):
    """One JSON object per line -- structured, queryable output rather
    than Python logging's free-text default, per architecture.md's
    Observability Stack."""

    def format(self, record: logging.LogRecord) -> str:
        payload = {
            "timestamp": self.formatTime(record, "%Y-%m-%dT%H:%M:%S%z"),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
            "request_id": getattr(record, "request_id", "-"),
        }
        if record.exc_info:
            payload["exception"] = self.formatException(record.exc_info)
        return json.dumps(payload)


def setup_logging(level: str = "INFO") -> None:
    """Configures the root logger. Call once at process startup
    (app/main.py, at import time).

    Idempotent -- clears any handlers a previous call (or uvicorn's own
    default logging config, which runs before this module is imported)
    already attached, so restarts/reloads (uvicorn --reload re-executes
    this module) never stack duplicate handlers and double-emit every
    log line.
    """
    root = logging.getLogger()
    root.setLevel(level.upper())
    root.handlers.clear()

    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JsonFormatter())
    handler.addFilter(RequestIdFilter())
    root.addHandler(handler)
