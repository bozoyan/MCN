import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../auth/auth_provider.dart';
import '../errors/exceptions.dart';
import '../utils/request_id.dart';
import '../utils/streaming_parser.dart';
import 'base_resource.dart';

/// Mixin that provides streaming capabilities for resources.
///
/// Handles SSE (Server-Sent Events) streaming for Anthropic API responses.
mixin StreamingResource on ResourceBase {
  /// Makes a streaming POST request.
  ///
  /// Returns a stream of parsed SSE events as JSON maps.
  /// The optional [abortTrigger] allows canceling the stream.
  Stream<Map<String, dynamic>> postStream(
    String path, {
    required Map<String, dynamic> body,
    Map<String, dynamic>? queryParams,
    Map<String, String>? headers,
    Future<void>? abortTrigger,
  }) async* {
    ensureNotClosed?.call();
    final uri = requestBuilder.buildUrl(path, queryParams: queryParams);
    final request = http.Request('POST', uri)
      ..headers.addAll(requestBuilder.buildHeaders(additionalHeaders: headers))
      ..body = jsonEncode(body);

    // Add authentication header if auth provider is configured
    await _applyAuthentication(request);

    final correlationId =
        request.headers['X-Request-ID'] ?? generateRequestId();

    // A shared client cannot be closed for one aborted stream: it may serve
    // other concurrent requests. When supplied, use a dedicated client and
    // close it both on abort and on every terminal stream path.
    final dedicatedClient = abortTrigger != null
        ? streamClientFactory?.call()
        : null;
    final requestClient = dedicatedClient ?? httpClient;
    var aborted = false;
    if (abortTrigger != null) {
      unawaited(
        abortTrigger.then((_) {
          aborted = true;
          dedicatedClient?.close();
        }),
      );
    }

    try {
      // Send the request
      http.StreamedResponse streamedResponse;
      try {
        streamedResponse = await requestClient.send(request);
      } catch (e) {
        // 消费方主动 abort 会关闭 dedicated client 使 send() 失败；此时消费方
        // 正在拆除订阅，抛错会落入已取消的 async* 生成器变成 zone 级 unhandled。
        // 直接结束生成器，abort 由消费方的超时/取消流程处理。
        if (aborted) {
          return;
        }
        rethrow;
      }

      // Check for errors
      if (streamedResponse.statusCode >= 400) {
        final responseBody = await streamedResponse.stream.bytesToString();
        throw _createStreamException(
          streamedResponse.statusCode,
          responseBody,
          correlationId,
        );
      }

      // Parse SSE stream
      final parser = SseParser();
      final eventStream = parser.parse(streamedResponse.stream);

      try {
        await for (final event in eventStream) {
          if (aborted) {
            // 主动 abort：结束流，不向已取消的订阅抛 AbortedException。
            return;
          }
          yield event;
        }
      } catch (e) {
        // abort 关闭 client 引发的底层流错误在消费方取消后到达：吞掉避免 unhandled。
        if (aborted) {
          return;
        }
        rethrow;
      }
    } finally {
      dedicatedClient?.close();
    }
  }

  /// Creates an exception for streaming errors.
  AnthropicException _createStreamException(
    int statusCode,
    String body,
    String correlationId,
  ) {
    final (message, details) = _parseErrorBody(body);

    if (statusCode == 401) {
      return AuthenticationException(message: message);
    }

    if (statusCode == 429) {
      return RateLimitException(
        statusCode: statusCode,
        message: message,
        details: details,
      );
    }

    return ApiException(
      statusCode: statusCode,
      message: message,
      details: details,
    );
  }

  /// Parses error message and details from response body.
  (String, List<Object>) _parseErrorBody(String body) {
    if (body.isEmpty) {
      return ('Unknown error', <Object>[]);
    }

    try {
      final json = jsonDecode(body);
      if (json is Map<String, dynamic>) {
        // Anthropic error format: {"type": "error", "error": {"type": "...", "message": "..."}}
        final error = json['error'];
        if (error is Map<String, dynamic>) {
          final message = error['message'] as String? ?? 'Unknown error';
          final errorType = error['type'] as String?;
          return (
            message,
            errorType != null ? <Object>[errorType] : <Object>[],
          );
        }
        // Fallback: {"message": "..."}
        final message = json['message'];
        if (message is String) {
          return (message, <Object>[]);
        }
        return (body, <Object>[]);
      }
      return (body, <Object>[]);
    } catch (_) {
      return (body, <Object>[]);
    }
  }

  /// Makes a streaming GET request.
  ///
  /// Returns a stream of parsed SSE events as JSON maps.
  /// The optional [abortTrigger] allows canceling the stream.
  Stream<Map<String, dynamic>> getStream(
    String path, {
    Map<String, dynamic>? queryParams,
    Map<String, String>? headers,
    Future<void>? abortTrigger,
  }) async* {
    ensureNotClosed?.call();
    final uri = requestBuilder.buildUrl(path, queryParams: queryParams);
    final request = http.Request('GET', uri)
      ..headers.addAll(requestBuilder.buildHeaders(additionalHeaders: headers));

    // Add authentication header if auth provider is configured
    await _applyAuthentication(request);

    final correlationId =
        request.headers['X-Request-ID'] ?? generateRequestId();

    // Send the request
    final streamedResponse = await httpClient.send(request);

    // Check for errors
    if (streamedResponse.statusCode >= 400) {
      final responseBody = await streamedResponse.stream.bytesToString();
      throw _createStreamException(
        streamedResponse.statusCode,
        responseBody,
        correlationId,
      );
    }

    // Parse SSE stream
    final parser = SseParser();
    final eventStream = parser.parse(streamedResponse.stream);

    // Handle abort during streaming
    if (abortTrigger != null) {
      var aborted = false;

      // Listen for abort signal
      abortTrigger.then((_) {
        aborted = true;
      }).ignore();

      try {
        await for (final event in eventStream) {
          if (aborted) {
            // 主动 abort：结束流，不向已取消的订阅抛 AbortedException。
            return;
          }
          yield event;
        }
      } catch (e) {
        // abort 引发的底层流错误在消费方取消后到达：吞掉避免 unhandled。
        if (aborted) {
          return;
        }
        rethrow;
      }
    } else {
      yield* eventStream;
    }
  }

  /// Applies authentication to a request.
  Future<void> _applyAuthentication(http.Request request) async {
    final provider = config.authProvider;
    if (provider == null) return;

    final credentials = await provider.getCredentials();
    switch (credentials) {
      case ApiKeyCredentials(:final apiKey):
        if (!request.headers.containsKey('x-api-key')) {
          request.headers['x-api-key'] = apiKey;
        }
      case NoAuthCredentials():
        // No authentication needed
        break;
    }
  }
}
