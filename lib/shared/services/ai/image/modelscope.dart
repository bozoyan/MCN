// 职责: 将图片请求编码为魔搭 API-Inference 异步任务,轮询到完成并解析输出图片。
// 关联文件:
//   lib/shared/services/ai/image/client.dart
//   lib/shared/models/image/channels.dart
//   lib/shared/models/image/extras.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/zh-CN/ai.json
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:http/http.dart' as http;

import '../../../localization/locale_keys.dart';
import '../../../models/ai_provider.dart';
import '../../../models/image/channels.dart';
import '../image.dart';
import 'client.dart';

class ModelScopeImageClient extends ImageClient {
  ModelScopeImageClient(super.config);

  static const _attempts = 3;
  static const _pollInterval = Duration(seconds: 5);

  /// 魔搭对 image_url 解码后文件体积的硬上限（5MB），超出直接 400。
  static const _referenceMaxBytes = 5 * 1024 * 1024;

  @override
  bool get supportsEdit => true;

  @override
  Future<AiImageGenerationResult> generate(
    ImageGenerationRequest request,
  ) async {
    final channel = validatedChannel(request);
    final options =
        channel?.protocolOptions is ModelScopeImageOptions
        ? channel!.protocolOptions as ModelScopeImageOptions
        : null;
    final extras = request.extras;
    if (extras != null && extras.hasLoras) {
      final loraError = extras.validateLoras(
        maxCount: options?.maxLoras ?? 6,
      );
      if (loraError != null) {
        throw invalidImageParameter();
      }
    }
    final body = <String, dynamic>{
      'model': request.model,
      'prompt': request.prompt,
    };
    final size = _resolveSize(request, channel);
    if (size != null) {
      body['size'] = size;
    }
    if (extras != null) {
      final loras = extras.modelScopeLoras;
      if (loras != null) {
        body['loras'] = loras;
      }
      if (extras.steps != null) {
        body['steps'] = extras.steps;
      }
      if (extras.guidance != null) {
        body['guidance'] = extras.guidance;
      }
      if (extras.seed != null) {
        body['seed'] = extras.seed;
      }
    }
    if (request.images.isNotEmpty) {
      body['image_url'] = [
        for (final input in request.images)
          await imageInputAsDataUriWithinLimit(input, _referenceMaxBytes),
      ];
    }
    final client = config.createProxyClient() ?? http.Client();
    final elapsed = Stopwatch()..start();
    try {
      final submitted = await _send(
        client,
        elapsed,
        _uri('/v1/images/generations'),
        data: body,
        headers: const {'X-ModelScope-Async-Mode': 'true'},
      );
      final id = submitted['task_id'];
      if (id is! String || id.trim().isEmpty) {
        throw _taskError(submitted, _uri('/v1/images/generations'));
      }
      try {
        await request.onSubmitted?.call(id);
      } catch (error) {
        throw AiImageFetchException(
          '图片结果获取失败，请稍后重试。',
          providerTaskId: id,
          debugMessage: 'ModelScope task $id record failed: $error',
        );
      }
      return await _settle(client, elapsed, id);
    } finally {
      client.close();
    }
  }

  @override
  Future<AiImageGenerationResult> resumeResult(String providerTaskId) async {
    final client = config.createProxyClient() ?? http.Client();
    final elapsed = Stopwatch()..start();
    try {
      return await _settle(client, elapsed, providerTaskId);
    } finally {
      client.close();
    }
  }

  Uri _uri(String path) =>
      Uri.parse(config.effectiveBaseUrl).replace(
        path: '${Uri.parse(config.effectiveBaseUrl).path}$path',
      );

  /// 渠道登记的型号用档位/比例换算像素;未登记型号原样透传。
  String? _resolveSize(ImageGenerationRequest request, channel) {
    final caps = channel?.capabilities;
    final size = request.size;
    if (caps == null || caps.sizes.isEmpty) {
      return size;
    }
    if (size != null && caps.resolutions.contains(size)) {
      return caps.size(request.aspectRatio ?? '1:1', size);
    }
    if (size != null) {
      return size;
    }
    if (request.aspectRatio != null || request.resolution != null) {
      return caps.size(
        request.aspectRatio ?? '1:1',
        request.resolution ?? caps.resolutions.first,
      );
    }
    return channel!.requestDefaults.size;
  }

  /// 轮询到终态并取回图片。任务已受理后,查询失败带上任务 ID 抛出,
  /// 供调用方稍后继续查询而不是重新出图。
  Future<AiImageGenerationResult> _settle(
    http.Client client,
    Stopwatch elapsed,
    String taskId,
  ) async {
    final uri = _uri('/v1/tasks/${Uri.encodeComponent(taskId)}');
    var firstPoll = true;
    while (true) {
      if (firstPoll) {
        firstPoll = false;
      } else {
        await Future<void>.delayed(_pollInterval);
      }
      Map<String, dynamic> task;
      try {
        task = await _send(client, elapsed, uri, headers: const {
          'X-ModelScope-Task-Type': 'image_generation',
        });
      } catch (error) {
        throw AiImageFetchException(
          '图片结果获取失败，请稍后重试。',
          providerTaskId: taskId,
          debugMessage:
              'ModelScope task $taskId poll failed at $uri: '
              '${error is AiImageGenerationException ? error.debugMessage ?? error.userMessage : error}',
        );
      }
      final status = task['task_status'];
      if (status == 'PENDING' || status == 'RUNNING') {
        continue;
      }
      if (status != 'SUCCEED') {
        // FAILED / CANCELED / 未知状态都按任务失败处理。
        throw _taskError(task, uri);
      }
      final images = task['output_images'];
      if (images is! List || images.isEmpty || images.first is! String) {
        throw _taskError(task, uri);
      }
      return parseImageResponse({
        'data': [
          {'url': images.first},
        ],
      }, emptyMessage: tr(LocaleKeys.aiImageNoResult));
    }
  }

  Future<Map<String, dynamic>> _send(
    http.Client client,
    Stopwatch elapsed,
    Uri uri, {
    Map<String, dynamic>? data,
    Map<String, String> headers = const {},
  }) async {
    final apiKey = requireApiKey();
    final remaining = imageHttpDataTimeout - elapsed.elapsed;
    if (remaining <= Duration.zero) {
      throw TimeoutException('ModelScope image task timed out');
    }
    http.Request build() {
      final request = http.Request(data == null ? 'GET' : 'POST', uri)
        ..followRedirects = false
        ..headers.addAll({
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
          ...headers,
        });
      if (data != null) {
        request.body = jsonEncode(data);
      }
      return request;
    }

    var request = build();
    http.Response? response;
    // 握手未完成时请求体尚未发出,提交也可安全重试;轮询是幂等 GET,
    // 连接层错误都可重试。
    for (var attempt = 1; response == null; attempt++) {
      try {
        response = await http.Response.fromStream(
          await client.send(request),
        ).timeout(remaining);
      } catch (error) {
        final retryable =
            error is HandshakeException ||
            (data == null &&
                (error is SocketException || error is http.ClientException));
        if (attempt >= _attempts || !retryable) {
          rethrow;
        }
        writeImageLog(
          '[IMGDBG] modelscope_retry method=${request.method} '
          'uri=${safeImageUriForLog(uri)} attempt=$attempt error=$error',
        );
        await Future<void>.delayed(Duration(seconds: attempt));
        request = build();
      }
    }
    writeImageLog(
      '[IMGDBG] modelscope_response method=${request.method} '
      'uri=${safeImageUriForLog(uri)} status=${response.statusCode}',
    );
    throwForImageHttpFailure(
      uri: uri,
      statusCode: response.statusCode,
      data: response.body,
      providerId: config.id,
    );
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    if (json['error'] != null ||
        (json['code'] != null && json['code'] != 200)) {
      throw _taskError(json, uri);
    }
    return json;
  }

  AiImageGenerationException _taskError(
    Map<String, dynamic> data,
    Uri uri,
  ) {
    final message = extractImageServerMessage(data);
    return AiImageGenerationException(
      imageUserMessageFromServerMessage(message) ??
          tr(LocaleKeys.aiImageGenerationFailed),
      debugMessage:
          'ModelScope task error at $uri response=${safeImageSerializeForLog(data)}',
      code: classifyAiImageError(message),
    );
  }
}
