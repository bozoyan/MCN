// 职责: 执行 Reveric 所需的 OpenAI Chat Completions 普通与流式请求。
// 关联文件:
//   third/ai_clients_dart/packages/openai_dart/lib/src/client/openai_client.dart
//   third/ai_clients_dart/packages/openai_dart/lib/src/models/chat/chat_completion_request.dart
//   third/ai_clients_dart/packages/openai_dart/lib/src/models/streaming/chat_stream_event.dart

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../errors/exceptions.dart';
import '../models/chat/chat_completion.dart';
import '../models/chat/chat_completion_request.dart';
import '../models/streaming/chat_stream_event.dart';
import 'base_resource.dart';
import 'streaming_resource.dart';

class ChatResource extends ResourceBase {
  ChatResource({
    required super.config,
    required super.httpClient,
    required super.interceptorChain,
    required super.requestBuilder,
    super.ensureNotClosed,
    super.streamClientFactory,
  });

  ChatCompletionsResource? _completions;

  ChatCompletionsResource get completions =>
      _completions ??= ChatCompletionsResource(
        config: config,
        httpClient: httpClient,
        interceptorChain: interceptorChain,
        requestBuilder: requestBuilder,
        ensureNotClosed: ensureNotClosed,
        streamClientFactory: streamClientFactory,
      );
}

class ChatCompletionsResource extends ResourceBase with StreamingResource {
  ChatCompletionsResource({
    required super.config,
    required super.httpClient,
    required super.interceptorChain,
    required super.requestBuilder,
    super.ensureNotClosed,
    super.streamClientFactory,
  });

  static const _endpoint = '/chat/completions';

  Future<ChatCompletion> create(
    ChatCompletionCreateRequest request, {
    Future<void>? abortTrigger,
  }) async {
    ensureNotClosed?.call();
    final httpRequest = http.Request('POST', requestBuilder.buildUrl(_endpoint))
      ..headers.addAll(requestBuilder.buildHeaders())
      ..body = jsonEncode(request.toJson());
    final response = await interceptorChain.execute(
      httpRequest,
      abortTrigger: abortTrigger,
    );
    try {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      if (!json.containsKey('choices') &&
          (json.containsKey('message') || json.containsKey('error'))) {
        throw ParseException(
          message:
              'Server returned an error response with HTTP 200: '
              '${extractErrorMessage(json)}',
          responseBody: response.body,
        );
      }
      return ChatCompletion.fromJson(json);
    } on ParseException {
      rethrow;
    } on FormatException catch (error) {
      throw ParseException(
        message: 'Failed to parse chat completion response: $error',
        responseBody: response.body,
        cause: error,
      );
    } on TypeError catch (error) {
      throw ParseException(
        message: 'Failed to parse chat completion response: $error',
        responseBody: response.body,
        cause: error,
      );
    }
  }

  Stream<ChatStreamEvent> createStream(
    ChatCompletionCreateRequest request, {
    Future<void>? abortTrigger,
  }) {
    final body = request.toJson()..['stream'] = true;
    return streamSseEvents(
      endpoint: _endpoint,
      body: body,
      abortTrigger: abortTrigger,
    ).map((json) {
      final event = json['_event'] as String?;
      final error = json['error'];
      if (event == 'error' || error != null) {
        throwInlineStreamError(json, event, error);
      }
      try {
        return ChatStreamEvent.fromJson(json);
      } on FormatException catch (error) {
        throw ParseException(
          message: 'Failed to parse chat stream event: $error',
          responseBody: json.toString(),
          cause: error,
        );
      } on TypeError catch (error) {
        throw ParseException(
          message: 'Failed to parse chat stream event: $error',
          responseBody: json.toString(),
          cause: error,
        );
      }
    });
  }
}
