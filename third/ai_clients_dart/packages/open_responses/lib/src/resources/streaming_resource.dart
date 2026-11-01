import 'dart:async' show StreamController, StreamSubscription, unawaited;
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../auth/auth_provider.dart';
import '../errors/exceptions.dart';
import 'base_resource.dart';

/// Mixin providing streaming HTTP request capabilities.
///
/// Provides methods for preparing and sending streaming requests
/// that bypass the interceptor chain for unbuffered response handling.
mixin StreamingResource on ResourceBase {
  /// Prepares a streaming request by applying authentication.
  Future<http.Request> prepareStreamingRequest(http.Request request) async {
    await _applyAuthentication(request);
    return request;
  }

  /// Sends a streaming request and returns the streamed response.
  ///
  /// Throws appropriate exceptions for HTTP error responses.
  Future<http.StreamedResponse> sendStreamingRequest(
    http.Request request, {
    Future<void>? abortTrigger,
  }) async {
    final streamedResponse = await _sendRequest(request, abortTrigger);
    if (streamedResponse.statusCode >= 400) {
      final body = await streamedResponse.stream.bytesToString();
      throw mapHttpErrorForStreaming(streamedResponse.statusCode, body);
    }
    return streamedResponse;
  }

  Future<http.StreamedResponse> _sendRequest(
    http.Request request,
    Future<void>? abortTrigger,
  ) async {
    if (abortTrigger == null) {
      return httpClient.send(request);
    }

    final dedicatedClient = streamClientFactory?.call() ?? http.Client();
    var aborted = false;
    var clientClosed = false;

    void closeClientOnce() {
      if (!clientClosed) {
        clientClosed = true;
        dedicatedClient.close();
      }
    }

    unawaited(
      abortTrigger.then(
        (_) {
          aborted = true;
          closeClientOnce();
        },
        onError: (_) {
          aborted = true;
          closeClientOnce();
        },
      ),
    );

    try {
      final response = await dedicatedClient.send(request);
      final controller = StreamController<List<int>>();
      late final StreamSubscription<List<int>> subscription;
      var controllerClosed = false;

      void closeController() {
        if (!controllerClosed) {
          controllerClosed = true;
          unawaited(controller.close());
        }
      }

      subscription = response.stream.listen(
        (data) {
          // 消费方取消订阅后 controller 已关闭：直接丢弃残留数据，
          // 否则向已关闭 controller 加事件会抛 StateError 变成 unhandled。
          if (!controllerClosed) {
            controller.add(data);
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          closeClientOnce();
          // 主动 abort 导致的响应体断连属于取消；真实网络错误仍向上传递。
          if (!aborted && !controllerClosed) {
            controller.addError(error, stackTrace);
          }
          unawaited(subscription.cancel());
          closeController();
        },
        onDone: () {
          closeClientOnce();
          closeController();
        },
        cancelOnError: false,
      );

      controller.onCancel = () async {
        closeClientOnce();
        await subscription.cancel();
        closeController();
      };

      return http.StreamedResponse(
        controller.stream,
        response.statusCode,
        contentLength: response.contentLength,
        request: response.request,
        headers: response.headers,
        isRedirect: response.isRedirect,
        persistentConnection: response.persistentConnection,
        reasonPhrase: response.reasonPhrase,
      );
    } catch (error) {
      closeClientOnce();
      // 消费方主动 abort（2 分钟无事件超时 / 用户取消）时，关闭 dedicated
      // client 会使 send() 失败。此刻消费方正在拆除订阅：若抛 AbortedException
      // 会落入已取消的 async* 生成器，变成 zone 级 unhandled（匿名库误报为
      // uncaught_async）。返回空 200 响应让生成器正常结束，abort 由消费方的
      // 超时/取消流程处理。
      if (aborted) {
        return http.StreamedResponse(
          const Stream<List<int>>.empty(),
          200,
          request: request,
        );
      }
      rethrow;
    }
  }

  /// Applies authentication to a request.
  Future<void> _applyAuthentication(http.BaseRequest request) async {
    final authProvider = config.authProvider;
    if (authProvider == null) return;
    final credentials = await authProvider.getCredentials();
    switch (credentials) {
      case BearerTokenCredentials(:final token):
        if (!request.headers.containsKey('authorization') &&
            !request.headers.containsKey('Authorization')) {
          request.headers['Authorization'] = 'Bearer $token';
        }
      case NoAuthCredentials():
        break;
    }
  }

  /// Maps an HTTP error status code to the appropriate exception.
  OpenResponsesException mapHttpErrorForStreaming(int statusCode, String body) {
    final message = _parseErrorMessage(body);
    switch (statusCode) {
      case 400:
        return ValidationException(
          message: message,
          fieldErrors: _parseFieldErrors(body),
        );
      case 401:
        return AuthenticationException(message: message);
      case 429:
        return RateLimitException(statusCode: statusCode, message: message);
      default:
        return ApiException(statusCode: statusCode, message: message);
    }
  }

  String _parseErrorMessage(String body) {
    if (body.isEmpty) return 'Unknown error';
    try {
      final json = jsonDecode(body);
      if (json is Map<String, dynamic>) {
        final error = json['error'];
        if (error is Map<String, dynamic>) {
          return error['message'] as String? ?? 'Unknown error';
        }
        return json['message'] as String? ?? body;
      }
      return body;
    } catch (_) {
      return body;
    }
  }

  Map<String, List<String>> _parseFieldErrors(String body) {
    try {
      final json = jsonDecode(body);
      if (json is Map<String, dynamic>) {
        final error = json['error'];
        if (error is Map<String, dynamic>) {
          final param = error['param'] as String?;
          final message = error['message'] as String?;
          if (param != null && message != null) {
            return {
              param: [message],
            };
          }
        }
      }
    } catch (_) {}
    return {};
  }
}
