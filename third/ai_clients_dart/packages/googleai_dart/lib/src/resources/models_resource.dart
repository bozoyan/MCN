// 职责: 执行 Reveric 所需的 Gemini 内容生成、流式生成与文本嵌入请求。
// 关联文件:
//   third/ai_clients_dart/packages/googleai_dart/lib/src/client/googleai_client.dart
//   third/ai_clients_dart/packages/googleai_dart/lib/src/models/generation/generate_content_request.dart
//   third/ai_clients_dart/packages/googleai_dart/lib/src/models/embeddings/embed_content_request.dart

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/embeddings/embed_content_request.dart';
import '../models/embeddings/embed_content_response.dart';
import '../models/generation/generate_content_request.dart';
import '../models/generation/generate_content_response.dart';
import '../utils/request_id.dart';
import '../utils/streaming_parser.dart';
import 'base_resource.dart';
import 'streaming_resource.dart';

class ModelsResource extends ResourceBase with StreamingResource {
  ModelsResource({
    required super.config,
    required super.httpClient,
    super.streamClientFactory,
    required super.interceptorChain,
    required super.requestBuilder,
    super.ensureNotClosed,
  });

  Future<GenerateContentResponse> generateContent({
    required String model,
    required GenerateContentRequest request,
    Future<void>? abortTrigger,
  }) async {
    final httpRequest =
        http.Request(
            'POST',
            requestBuilder.buildUrl('/{version}/models/$model:generateContent'),
          )
          ..headers.addAll(
            requestBuilder.buildHeaders(
              additionalHeaders: {'Content-Type': 'application/json'},
            ),
          )
          ..body = jsonEncode(request.toJson());
    final response = await interceptorChain.execute(
      httpRequest,
      abortTrigger: abortTrigger,
    );
    return GenerateContentResponse.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Stream<GenerateContentResponse> streamGenerateContent({
    required String model,
    required GenerateContentRequest request,
    Future<void>? abortTrigger,
  }) async* {
    var httpRequest =
        http.Request(
            'POST',
            requestBuilder.buildUrl(
              '/{version}/models/$model:streamGenerateContent',
              queryParams: {'alt': 'sse'},
            ),
          )
          ..headers.addAll(
            requestBuilder.buildHeaders(
              additionalHeaders: {'Content-Type': 'application/json'},
            ),
          )
          ..body = jsonEncode(request.toJson());
    httpRequest = await prepareStreamingRequest(httpRequest);
    final requestId =
        httpRequest.headers['X-Request-ID'] ?? generateRequestId();

    // Closing the shared client would abort unrelated turns. A configured
    // factory gives this stream its own client so abort also works while
    // waiting for response headers.
    final dedicatedClient = abortTrigger != null
        ? streamClientFactory?.call()
        : null;
    final requestClient = dedicatedClient ?? httpClient;
    if (abortTrigger != null) {
      unawaited(
        abortTrigger.then((_) {
          dedicatedClient?.close();
        }),
      );
    }

    try {
      final response = await sendStreamingRequest(
        httpRequest,
        client: requestClient,
      );
      final events = parseSSE(bytesToLines(response.stream));

      GenerateContentResponse decode(Map<String, dynamic> json) {
        final event = json['_event'] as String?;
        final error = json['error'];
        if (event == 'error' || error != null) {
          throwInlineStreamError(json, event, error);
        }
        return GenerateContentResponse.fromJson(json);
      }

      if (abortTrigger != null) {
        yield* streamWithAbortMonitoring(
          source: events,
          abortTrigger: abortTrigger,
          requestId: requestId,
          fromJson: decode,
        );
        return;
      }
      await for (final json in events) {
        yield decode(json);
      }
    } finally {
      dedicatedClient?.close();
    }
  }

  Future<EmbedContentResponse> embedContent({
    required String model,
    required EmbedContentRequest request,
    Future<void>? abortTrigger,
  }) async {
    final httpRequest =
        http.Request(
            'POST',
            requestBuilder.buildUrl('/{version}/models/$model:embedContent'),
          )
          ..headers.addAll(
            requestBuilder.buildHeaders(
              additionalHeaders: {'Content-Type': 'application/json'},
            ),
          )
          ..body = jsonEncode(request.toJson());
    final response = await interceptorChain.execute(
      httpRequest,
      abortTrigger: abortTrigger,
    );
    return EmbedContentResponse.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }
}
