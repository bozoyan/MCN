// 职责: 执行 Reveric 所需的 OpenResponses 普通与流式生成请求。
// 关联文件:
//   third/ai_clients_dart/packages/open_responses/lib/src/client/open_responses_client.dart
//   third/ai_clients_dart/packages/open_responses/lib/src/models/request/create_response_request.dart
//   third/ai_clients_dart/packages/open_responses/lib/src/models/streaming/streaming_event.dart

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/request/create_response_request.dart';
import '../models/response/response_resource.dart';
import '../models/streaming/streaming_event.dart';
import '../utils/sse_parser.dart';
import 'base_resource.dart';
import 'streaming_resource.dart';

class ResponsesResource extends ResourceBase with StreamingResource {
  ResponsesResource({
    required super.config,
    required super.httpClient,
    required super.interceptorChain,
    required super.requestBuilder,
    super.ensureNotClosed,
    super.streamClientFactory,
  });

  Future<ResponseResource> create(
    CreateResponseRequest request, {
    Future<void>? abortTrigger,
  }) async {
    ensureNotClosed?.call();
    final requestToSend = (request.stream ?? false)
        ? request.copyWith(stream: false)
        : request;
    final httpRequest =
        http.Request('POST', requestBuilder.buildUrl('/responses'))
          ..headers.addAll(requestBuilder.buildHeaders())
          ..body = jsonEncode(requestToSend.toJson());
    final response = await interceptorChain.execute(
      httpRequest,
      abortTrigger: abortTrigger,
    );
    return ResponseResource.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Stream<StreamingEvent> createStream(
    CreateResponseRequest request, {
    Future<void>? abortTrigger,
  }) async* {
    ensureNotClosed?.call();
    final requestToSend = request.stream != true
        ? request.copyWith(stream: true)
        : request;
    final httpRequest =
        http.Request('POST', requestBuilder.buildUrl('/responses'))
          ..headers.addAll(requestBuilder.buildHeaders())
          ..body = jsonEncode(requestToSend.toJson());
    await prepareStreamingRequest(httpRequest);
    final response = await sendStreamingRequest(
      httpRequest,
      abortTrigger: abortTrigger,
    );
    final parser = SseParser();
    await for (final json in parser.parse(response.stream)) {
      final cleaned = json.withoutEventType();
      final eventType = json.sseEventType ?? cleaned['type'] as String?;
      if (eventType != null) {
        cleaned['type'] = eventType;
      }
      yield StreamingEvent.fromJson(cleaned);
    }
  }
}
