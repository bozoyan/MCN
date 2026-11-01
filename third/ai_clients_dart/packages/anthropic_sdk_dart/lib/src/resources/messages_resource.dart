// 职责: 执行 Reveric 所需的 Anthropic Messages 普通与流式请求。
// 关联文件:
//   third/ai_clients_dart/packages/anthropic_sdk_dart/lib/src/client/anthropic_client.dart
//   third/ai_clients_dart/packages/anthropic_sdk_dart/lib/src/models/messages/message_create_request.dart
//   third/ai_clients_dart/packages/anthropic_sdk_dart/lib/src/models/streaming/message_stream_event.dart

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/messages/message.dart';
import '../models/messages/message_create_request.dart';
import '../models/streaming/message_stream_event.dart';
import 'base_resource.dart';
import 'streaming_resource.dart';

class MessagesResource extends ResourceBase with StreamingResource {
  MessagesResource({
    required super.config,
    required super.httpClient,
    super.streamClientFactory,
    required super.interceptorChain,
    required super.requestBuilder,
    super.ensureNotClosed,
  });

  Future<Message> create(
    MessageCreateRequest request, {
    Future<void>? abortTrigger,
    List<String> betas = const [],
    String? userProfileId,
  }) async {
    ensureNotClosed?.call();
    final body = request.toJson()..remove('stream');
    final httpRequest =
        http.Request('POST', requestBuilder.buildUrl('/v1/messages'))
          ..headers.addAll(
            requestBuilder.buildHeaders(
              additionalHeaders: _requestHeaders(
                betas: betas,
                userProfileId: userProfileId,
              ),
            ),
          )
          ..body = jsonEncode(body);
    final response = await interceptorChain.execute(
      httpRequest,
      abortTrigger: abortTrigger,
    );
    return Message.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Stream<MessageStreamEvent> createStream(
    MessageCreateRequest request, {
    Future<void>? abortTrigger,
    List<String> betas = const [],
    String? userProfileId,
  }) async* {
    final body = request.toJson()..['stream'] = true;
    await for (final event in postStream(
      '/v1/messages',
      body: body,
      headers: _requestHeaders(betas: betas, userProfileId: userProfileId),
      abortTrigger: abortTrigger,
    )) {
      yield MessageStreamEvent.fromJson(event);
    }
  }

  static Map<String, String>? _requestHeaders({
    List<String> betas = const [],
    String? userProfileId,
  }) {
    final headers = <String, String>{
      if (betas.isNotEmpty) 'anthropic-beta': betas.join(','),
      'anthropic-user-profile-id': ?userProfileId,
    };
    return headers.isEmpty ? null : headers;
  }
}
