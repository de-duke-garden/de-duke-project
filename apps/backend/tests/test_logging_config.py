"""Tests for app/core/logging_config.py -- the structured logging +
request-correlation-ID setup that replaced the previously-unconfigured
root logger (every logger.info(...) call across the codebase was
silently swallowed before this existed).
"""

from __future__ import annotations

import json
import logging

from app.core.logging_config import JsonFormatter, RequestIdFilter, request_id_var


def _make_record(message: str = "hello", level: int = logging.INFO) -> logging.LogRecord:
    return logging.LogRecord(
        name="test.logger",
        level=level,
        pathname=__file__,
        lineno=1,
        msg=message,
        args=(),
        exc_info=None,
    )


def test_json_formatter_produces_valid_json_with_expected_fields() -> None:
    record = _make_record("something happened")
    record.request_id = "abc-123"

    output = JsonFormatter().format(record)
    parsed = json.loads(output)

    assert parsed["level"] == "INFO"
    assert parsed["logger"] == "test.logger"
    assert parsed["message"] == "something happened"
    assert parsed["request_id"] == "abc-123"
    assert "timestamp" in parsed


def test_json_formatter_includes_exception_when_present() -> None:
    try:
        raise ValueError("boom")
    except ValueError:
        import sys

        record = _make_record("failure", level=logging.ERROR)
        record.exc_info = sys.exc_info()

    parsed = json.loads(JsonFormatter().format(record))

    assert "exception" in parsed
    assert "ValueError: boom" in parsed["exception"]


def test_request_id_filter_injects_current_context_value() -> None:
    token = request_id_var.set("req-42")
    try:
        record = _make_record()
        assert RequestIdFilter().filter(record) is True
        assert record.request_id == "req-42"
    finally:
        request_id_var.reset(token)


def test_request_id_filter_defaults_to_dash_outside_a_request() -> None:
    # No request_id_var set -- simulates a log emitted at startup or from
    # a background job invoked directly, not through an HTTP request.
    record = _make_record()
    assert RequestIdFilter().filter(record) is True
    assert record.request_id == "-"
