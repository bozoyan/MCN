// 职责: 定义图片生成的错误分类与结果，并按 provider 的图片协议分发到对应客户端。
// 关联文件:
//   lib/shared/models/ai_provider.dart
//   lib/shared/models/image/channels.dart
//   lib/shared/services/ai/image/client.dart
//   lib/shared/services/ai/codex/image_client.dart
import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;

import '../../models/ai_provider.dart';
import '../../utils/storage_paths.dart';
import '../../models/image/channels.dart';
import '../../models/image/extras.dart';
import 'codex/image_client.dart';
import 'image/agnes.dart';
import 'image/ark.dart';
import 'image/atlascloud.dart';
import 'image/client.dart';
import 'image/codex.dart';
import 'image/gemini.dart';
import 'image/moss.dart';
import 'image/modelscope.dart';
import 'image/openai.dart';
import 'image/openrouter.dart';
import 'new_api.dart';
import 'image/qwen.dart';

/// 出图失败的分类。封面工作台按它决定那一格显示哪句「下一步怎么办」，
/// 所以分类逻辑只能有这一份，不要在调用方重写关键字匹配。
enum AiImageErrorCode {
  /// 提示词或图片内容未过审。
  moderation,

  /// 网关限流。
  rate_limit,

  /// 供应商凭据无效或已过期。
  auth,

  /// 该模型出不了这个尺寸 / 比例。
  size,

  /// 参考图文件超过服务端大小上限（如魔搭 image_url 限 5MB）。
  file_too_large,

  /// 模型不支持请求里的某个参数（例如参考图张数超限）。
  param,

  /// 供应商或网关余额不足（HTTP 402、credit.insufficient）。
  credit,

  /// 供应商或网关限制当前凭据访问该模型（HTTP 403、model.forbidden）。
  model_forbidden,
}

/// 从服务端返回的原始错误文案里认出 [AiImageErrorCode]；认不出返回 null。
AiImageErrorCode? classifyAiImageError(String? serverMessage) {
  final normalized = serverMessage?.trim();
  if (normalized == null || normalized.isEmpty) {
    return null;
  }
  final lower = normalized.toLowerCase();
  if (lower.contains('model forbidden for user') ||
      lower.contains('model.forbidden')) {
    return AiImageErrorCode.model_forbidden;
  }
  if (lower.contains('api key') ||
      lower.contains('unauthorized') ||
      lower.contains('authentication')) {
    return AiImageErrorCode.auth;
  }
  if (lower.contains('credit.insufficient') ||
      lower.contains('insufficient_quota') ||
      lower.contains('insufficient credit') ||
      lower.contains('payment required')) {
    return AiImageErrorCode.credit;
  }
  // 文件大小超限要在通用 size 判定之前认出：消息里的 "file size" 会被
  // contains('size') 误分类成尺寸错误，误导用户去调出图尺寸。
  if (lower.contains('file size') || lower.contains('file too large')) {
    return AiImageErrorCode.file_too_large;
  }
  if (lower.contains('size') ||
      lower.contains('resolution') ||
      lower.contains('aspect ratio')) {
    return AiImageErrorCode.size;
  }
  if (lower.contains('content') ||
      lower.contains('safety') ||
      lower.contains('moderation') ||
      lower.contains('review')) {
    return AiImageErrorCode.moderation;
  }
  if (lower.contains('rate limit') || lower.contains('too many requests')) {
    return AiImageErrorCode.rate_limit;
  }
  if (lower.contains('model') && lower.contains('not support')) {
    return AiImageErrorCode.param;
  }
  return null;
}

class AiImageGenerationException implements Exception {
  const AiImageGenerationException(
    this.userMessage, {
    this.debugMessage,
    this.code,
  });

  final String userMessage;
  final String? debugMessage;

  /// 认得出的失败分类；认不出时为 null，调用方按「未知错误」处理。
  final AiImageErrorCode? code;

  @override
  String toString() => userMessage;
}

/// 异步任务协议受理后回报上游任务 ID；调用方落库后才开始轮询。
typedef ImageSubmitted = Future<void> Function(String providerTaskId);

/// 上游已受理，但结果没取回本地：有 [url] 时重新下载，
/// 否则凭 [providerTaskId] 继续查询上游任务。
class AiImageFetchException extends AiImageGenerationException {
  const AiImageFetchException(
    super.userMessage, {
    this.url,
    this.providerTaskId,
    super.debugMessage,
  });

  final String? url;
  final String? providerTaskId;
}

class AiImageGenerationResult {
  final String? imageUrl;
  final String? imageBase64;
  final String? revisedPrompt;
  final String? localFilePath;

  /// 图片入库后取得的资产 ID；尚未入库的客户端结果为空。
  final String? assetId;

  /// MIME subtype detected from the actual image bytes (e.g. 'png', 'jpeg').
  /// Used to build correct data-URI prefixes instead of hardcoding 'png'.
  final String mimeSubtype;

  const AiImageGenerationResult({
    this.imageUrl,
    this.imageBase64,
    this.revisedPrompt,
    this.localFilePath,
    this.assetId,
    this.mimeSubtype = 'png',
  });

  /// 只清理图片客户端在 media 根目录创建的未登记 .part 结果。
  Future<void> disposeTemporary() async {
    final path = localFilePath;
    if (path == null) {
      return;
    }
    final root = Directory(RevericPaths.fileWorkspaceParent);
    if (!RevericPaths.isImageResultPart(root, path)) {
      return;
    }

    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  bool get hasImage =>
      imageUrl != null || imageBase64 != null || localFilePath != null;

  String? get effectiveSource {
    if (localFilePath != null) return localFilePath;
    if (imageBase64 != null) {
      return 'data:image/$mimeSubtype;base64,$imageBase64';
    }
    if (imageUrl != null) return imageUrl;
    return null;
  }
}

/// 按 provider 的图片协议选择客户端，统一错误分类与日志。
class AiImageGenerationService {
  AiImageGenerationService(
    this._config, {
    required String model,
    CodexImageClient Function()? codexImageClientFactory,
  }) : _model = model,
       _codexImageClientFactory = codexImageClientFactory;

  final AiProvider _config;
  final String _model;
  final CodexImageClient Function()? _codexImageClientFactory;

  ImageClient? _client() => switch (_config.typeConfig.imageProtocol) {
    ImageProtocol.agnes_image => AgnesImageClient(_config),
    ImageProtocol.qwen_image => QwenImageClient(_config),
    ImageProtocol.ark_image => ArkImageClient(_config),
    ImageProtocol.openrouter_image => OpenRouterImageClient(_config),
    ImageProtocol.atlascloud_image => AtlasCloudImageClient(_config),
    ImageProtocol.new_api_images => NewApiClient(_config).image(),
    ImageProtocol.openai_images => OpenAiImageClient(_config),
    ImageProtocol.codex_image => CodexImageGenerationClient(
      _config,
      clientFactory: _codexImageClientFactory,
    ),
    ImageProtocol.gemini_image => GeminiImageClient(_config),
    ImageProtocol.modelscope_image => ModelScopeImageClient(_config),
    ImageProtocol.moss_image => MossImageClient(_config),
    null => null,
  };

  Future<AiImageGenerationResult> generateImage(
    String prompt, {
    String? model,
    String? size,
    String? quality,
    String? aspectRatio,
    String? resolution,
    ImageRequestExtras? extras,
    ImageSubmitted? onSubmitted,
  }) => _run(() async {
    final client =
        _client() ??
        (throw AiImageGenerationException('${_config.displayName} 当前不支持生图。'));
    return client.generate(
      ImageGenerationRequest(
        prompt: prompt,
        model: model ?? _model,
        size: size,
        quality: quality,
        aspectRatio: aspectRatio,
        resolution: resolution,
        extras: extras,
        onSubmitted: onSubmitted,
      ),
    );
  });

  Future<AiImageGenerationResult> editImage(
    String prompt, {
    required String imageData,
    String? model,
    String? size,
    String? quality,
    String? aspectRatio,
    String? resolution,
    ImageRequestExtras? extras,
  }) {
    return editImages(
      prompt,
      imageData: [imageData],
      model: model,
      size: size,
      quality: quality,
      aspectRatio: aspectRatio,
      resolution: resolution,
      extras: extras,
    );
  }

  /// 按上游任务 ID 继续查询并取回结果，不重新出图。
  Future<AiImageGenerationResult> resumeResult(String providerTaskId) => _run(
    () async {
      final client =
          _client() ??
          (throw AiImageGenerationException('${_config.displayName} 当前不支持生图。'));
      return client.resumeResult(providerTaskId);
    },
  );

  /// 重新下载上游已生成的图片 URL，不重新出图。
  Future<AiImageGenerationResult> downloadResult(String url) => _run(() async {
    final client =
        _client() ??
        (throw AiImageGenerationException('${_config.displayName} 当前不支持生图。'));
    return client.downloadResult(url);
  });

  /// OpenAI Images API 多参考图编辑契约。
  Future<AiImageGenerationResult> editImages(
    String prompt, {
    required List<String> imageData,
    String? model,
    String? size,
    String? quality,
    String? aspectRatio,
    String? resolution,
    ImageRequestExtras? extras,
    ImageSubmitted? onSubmitted,
  }) => _run(() async {
    if (imageData.isEmpty) {
      throw const AiImageGenerationException('缺少待编辑的图片内容。');
    }
    final client = _client();
    if (client == null || !client.supportsEdit) {
      throw AiImageGenerationException('${_config.displayName} 当前不支持图片编辑。');
    }
    return client.generate(
      ImageGenerationRequest(
        prompt: prompt,
        model: model ?? _model,
        size: size,
        quality: quality,
        aspectRatio: aspectRatio,
        resolution: resolution,
        images: imageData,
        extras: extras,
        onSubmitted: onSubmitted,
      ),
    );
  });

  Future<AiImageGenerationResult> _run(
    Future<AiImageGenerationResult> Function() action,
  ) async {
    try {
      return await action();
    } on AiImageGenerationException catch (error, stackTrace) {
      _logGenerationError(error, stackTrace);
      rethrow;
    } catch (error, stackTrace) {
      _logGenerationError(error, stackTrace);
      throw switch (error) {
        DioException() => imageExceptionFromDio(error, providerId: _config.id),
        UnsupportedError() => AiImageGenerationException(
          error.message ?? '当前模型不支持生图。',
        ),
        SocketException() ||
        HandshakeException() ||
        http.ClientException() ||
        TimeoutException() => AiImageGenerationException(
          '无法连接到图片生成服务，请检查网络或服务地址。',
          debugMessage: '$error',
        ),
        _ => AiImageGenerationException(
          '图片生成失败，请稍后重试。',
          debugMessage: '$error',
        ),
      };
    }
  }

  void _logGenerationError(Object error, StackTrace stackTrace) {
    writeImageLog(
      '[AiImageGeneration] provider=${_config.id} model=$_model '
      'baseUrl=${_config.effectiveBaseUrl} error=$error',
    );
    if (error is DioException) {
      writeImageLog(
        '[AiImageGeneration] dio type=${error.type} '
        'status=${error.response?.statusCode} '
        'uri=${safeImageUriForLog(error.requestOptions.uri)}',
      );
      final responseData = error.response?.data;
      if (responseData != null) {
        writeImageLog(
          '[AiImageGeneration] response=${safeImageSerializeForLog(responseData)}',
        );
      }
    } else if (error is AiImageGenerationException &&
        error.debugMessage != null &&
        error.debugMessage!.isNotEmpty) {
      writeImageLog('[AiImageGeneration] detail=${error.debugMessage}');
    }
    // 已分类的业务失败（402/鉴权/限流等）堆栈没有排查价值，只保留摘要。
    final knownCode = error is AiImageGenerationException ? error.code : null;
    if (knownCode == null) {
      writeImageLog(stackTrace.toString());
    }
  }
}
