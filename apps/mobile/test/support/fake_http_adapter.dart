/// A minimal fake Dio [HttpClientAdapter] for repository unit tests --
/// avoids any real network I/O while still exercising the repository's
/// real request-building and response-parsing/error-mapping code, unlike
/// mocking the repository itself (which would just test the mock).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

typedef FakeResponder = ({int statusCode, Object? body});

class FakeHttpClientAdapter implements HttpClientAdapter {
  FakeHttpClientAdapter(this.responder);

  /// Called once per request; returns the canned status/body to respond
  /// with, or throws to simulate a connection error.
  final FakeResponder Function(RequestOptions options) responder;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final result = responder(options);
    final encoded = utf8.encode(jsonEncode(result.body));
    return ResponseBody.fromBytes(
      encoded,
      result.statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

/// Simulates a connection-level failure (offline), for exercising the
/// `DioExceptionType.connectionError` branch every repository's error
/// mapper checks for.
class ConnectionErrorHttpClientAdapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    throw DioException.connectionError(
        requestOptions: options, reason: 'Simulated offline');
  }
}
