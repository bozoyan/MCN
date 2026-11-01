// 职责: AI 图片生成 handler — GenerateAvatar/GeneratePhoto 的处理逻辑（slash 命令 / UI 按钮驱动）。
// 关联文件:
//   lib/shared/agent/tools.dart
//   lib/shared/services/ai/image.dart
// 遵循的 Rules:
//   .agents/rules/error-handling.md
part of 'tools.dart';

const _avatarImageSize = '1024x1024';
const _photoImageSize = '864x1536';

mixin _AiToolManagerImageMixin on _AiToolManagerBase {
  Future<Map<String, dynamic>> _handleGenerateAvatar(
    Map<String, dynamic> input, {
    String? referenceImagePath,
  }) async {
    if (imageGenerationCallback == null) {
      return {
        'success': false,
        'error': tr(LocaleKeys.aiNoImageModelConfigured),
        '_noImageModel': true,
        'error_code': ToolErrorCode.unavailable.name,
      };
    }
    final prompt = _parseStringArgument(input['prompt']);
    if (prompt.isEmpty) {
      return {
        'success': false,
        'error': tr(LocaleKeys.aiImagePromptEmpty),
        'error_code': ToolErrorCode.invalid_argument.name,
      };
    }
    final characterId = _parseStringArgument(input['character_id']);
    final imagePath = referenceImagePath ?? '';
    try {
      final result = imagePath.isNotEmpty
          ? await _handleGenerateAvatarFromSource(prompt, imagePath: imagePath)
          : await imageGenerationCallback!(prompt, size: _avatarImageSize);
      if (result.assetId == null || result.assetId!.isEmpty) {
        throw StateError('Image callback returned no registered asset ID');
      }
      return {
        'success': true,
        'asset_id': result.assetId,
        'local_path':
            RevericPaths.toRelative(result.localFilePath) ??
            result.localFilePath!,
        'character_id': characterId,
      };
    } catch (error, stackTrace) {
      return _imageFailure(
        operation:
            'GenerateAvatar characterId=$characterId '
            'hasReference=${imagePath.isNotEmpty}',
        error: error,
        stackTrace: stackTrace,
        userMessage: tr(LocaleKeys.aiAvatarGenRetry),
      );
    }
  }

  Future<AiImageGenerationResult> _handleGenerateAvatarFromSource(
    String prompt, {
    required String imagePath,
  }) async {
    if (imageEditCallback == null) {
      throw AiImageGenerationException(tr(LocaleKeys.aiImageEditUnavailable));
    }
    if (imagePath.isEmpty) {
      throw AiImageGenerationException(tr(LocaleKeys.aiImagePathEmpty));
    }
    return imageEditCallback!(prompt, imageData: imagePath);
  }

  Future<Map<String, dynamic>> _handleGeneratePhoto(
    Map<String, dynamic> input, {
    String? referenceImagePath,
  }) async {
    if (imageGenerationCallback == null) {
      return {
        'success': false,
        'error': tr(LocaleKeys.aiNoImageModelConfigured),
        '_noImageModel': true,
        'error_code': ToolErrorCode.unavailable.name,
      };
    }
    final prompt = _parseStringArgument(input['prompt']);
    if (prompt.isEmpty) {
      return {
        'success': false,
        'error': tr(LocaleKeys.aiImagePromptEmpty),
        'error_code': ToolErrorCode.invalid_argument.name,
      };
    }
    final characterId = _parseStringArgument(input['character_id']);
    final itemId = _parseStringArgument(input['item_id']);
    // 快捷出图参数:size/loras 缺省时用各模型的默认值。
    final sizeInput = _parseStringArgument(input['size']);
    final size = sizeInput.trim().isEmpty ? _photoImageSize : sizeInput.trim();
    if (RegExp(r'^\d+x\d+$').hasMatch(size) == false) {
      return {
        'success': false,
        'error': 'size 必须是「宽x高」格式(如 1440x816),收到: $size',
        'error_code': ToolErrorCode.invalid_argument.name,
      };
    }
    final lorasError = _parseLoras(input['loras']);
    final loras = lorasError.extras;
    if (lorasError.error != null) {
      return {
        'success': false,
        'error': lorasError.error,
        'error_code': ToolErrorCode.invalid_argument.name,
      };
    }
    final referencePaths = <String>[];
    final referenceError = await _resolveReferenceImagePaths(
      input['asset_ids'],
      referencePaths,
    );
    if (referenceError != null) {
      return {
        'success': false,
        'error': referenceError,
        'error_code': ToolErrorCode.invalid_argument.name,
      };
    }
    final imagePath = referenceImagePath ?? '';
    try {
      final result = switch (referencePaths) {
        // 显式参考图素材(最多 4 张)走多图编辑;size/loras 原样下发。
        final List<String> paths when paths.isNotEmpty =>
          await _editPhotoWithReferences(
            prompt,
            referencePaths: paths,
            size: size,
            extras: loras,
          ),
        _ when imagePath.isNotEmpty => await _handleGeneratePhotoFromSource(
          prompt,
          imagePath: imagePath,
        ),
        _ => await imageGenerationCallback!(
          prompt,
          size: size,
          extras: loras,
        ),
      };
      if (result.assetId == null || result.assetId!.isEmpty) {
        throw StateError('Image callback returned no registered asset ID');
      }
      return {
        'success': true,
        'asset_id': result.assetId,
        'local_path':
            RevericPaths.toRelative(result.localFilePath) ??
            result.localFilePath!,
        if (characterId.isNotEmpty) 'character_id': characterId,
        if (itemId.isNotEmpty) 'item_id': itemId,
      };
    } catch (error, stackTrace) {
      return _imageFailure(
        operation:
            'GeneratePhoto characterId=$characterId itemId=$itemId '
            'hasReference=${imagePath.isNotEmpty} '
            'references=${referencePaths.length}',
        error: error,
        stackTrace: stackTrace,
        userMessage: tr(LocaleKeys.aiPhotoGenRetry),
      );
    }
  }

  /// 解析 options.loras 为请求级扩展参数;[ImageRequestExtrasParseResult.error]
  /// 非空表示 AI 给的格式或数值非法,需要把原因返回给模型。
  ({ImageRequestExtras? extras, String? error}) _parseLoras(Object? raw) {
    if (raw == null) {
      return (extras: null, error: null);
    }
    final List entries;
    if (raw is List) {
      entries = raw;
    } else if (raw is String && raw.trim().isNotEmpty) {
      entries = [raw];
    } else {
      entries = const [];
    }
    if (entries.isEmpty) {
      return (extras: null, error: null);
    }
    final parsed = <ModelScopeLora>[];
    for (final entry in entries) {
      if (entry is Map) {
        final repoId =
            (entry['repo_id'] ?? entry['repoId'])?.toString().trim() ?? '';
        final weight = (entry['weight'] as num?)?.toDouble() ?? 1;
        parsed.add(ModelScopeLora(repoId: repoId, weight: weight));
      } else {
        parsed.add(ModelScopeLora(repoId: entry.toString().trim(), weight: 1));
      }
    }
    if (parsed.any((lora) => lora.repoId.isEmpty)) {
      return (
        extras: null,
        error: 'loras 格式非法:需要 repo_id 字符串或 {"repo_id": "...", '
            '"weight": 0.6},收到: $raw',
      );
    }
    final extras = ImageRequestExtras(loras: parsed);
    final validation = extras.validateLoras();
    if (validation != null) {
      return (
        extras: null,
        error: 'loras 校验失败($validation):最多 6 个,权重需在 (0,1] 内,'
            '多 LoRA 权重之和必须为 1.0。',
      );
    }
    return (extras: extras, error: null);
  }

  /// 把 asset_ids(≤4)解析为本地参考图路径;非法或不属于本作品时返回错误文案。
  Future<String?> _resolveReferenceImagePaths(
    Object? raw,
    List<String> out,
  ) async {
    if (raw == null) {
      return null;
    }
    final ids = switch (raw) {
      final List list => [
        for (final entry in list) entry.toString().trim(),
      ],
      final String single when single.trim().isNotEmpty => [single.trim()],
      _ => const <String>[],
    };
    if (ids.isEmpty) {
      return null;
    }
    if (ids.length > 4) {
      return '参考图最多 4 张,收到 ${ids.length} 张。';
    }
    final library = _contentService.imageLibraryService;
    if (library == null) {
      return '图库不可用,无法解析参考图素材。';
    }
    for (final id in ids) {
      if (id.isEmpty) {
        return 'asset_ids 里包含空 id。';
      }
      final asset = await library.getAsset(id);
      if (asset == null || workId == null || asset.novelId != workId) {
        return '参考图素材不属于本作品或不存在: $id';
      }
      final path = RevericPaths.resolveStored(asset.path);
      if (path == null) {
        return '参考图文件缺失: $id';
      }
      out.add(path);
    }
    return null;
  }

  /// 带参考图(1-4 张)的出图:走多图编辑并入库,保证返回带 asset_id。
  Future<AiImageGenerationResult> _editPhotoWithReferences(
    String prompt, {
    required List<String> referencePaths,
    required String size,
    required ImageRequestExtras? extras,
  }) async {
    if (imageMultiEditCallback == null) {
      throw AiImageGenerationException(tr(LocaleKeys.aiImageEditUnavailable));
    }
    final result = await imageMultiEditCallback!(
      prompt,
      imageData: referencePaths,
      size: size,
      extras: extras,
    );
    // 多图编辑回调不负责入库;这里统一入库拿 asset_id,保持工具返回契约一致。
    final library = _contentService.imageLibraryService;
    if (library == null) {
      throw AiImageGenerationException(tr(LocaleKeys.aiImageEditUnavailable));
    }
    final asset = await library.importGenerated(
      result,
      novelId: workId!,
      purpose: AssetPurpose.ai_chat_generated,
      prompt: prompt,
    );
    return AiImageGenerationResult(
      imageUrl: result.imageUrl,
      imageBase64: result.imageBase64,
      revisedPrompt: result.revisedPrompt,
      mimeSubtype: result.mimeSubtype,
      localFilePath: library.resolve(asset.path),
      assetId: asset.id,
    );
  }

  Map<String, dynamic> _imageFailure({
    required String operation,
    required Object error,
    required StackTrace stackTrace,
    required String userMessage,
  }) {
    final detail = safeMediaDiagnostic(
      error is AiImageGenerationException
          ? error.debugMessage ?? error.userMessage
          : error,
      '',
    );
    final type = safeErrorTypeName(error);
    final imageCode = error is AiImageGenerationException ? error.code : null;
    _log.error(
      '$operation failed workId=$workId '
      'callId=${_activeRunCallId ?? _currentToolExecutionContext?.approvalHostCallId} '
      'exceptionType=$type imageErrorCode=${imageCode?.name}',
      error: detail,
      stackTrace: stackTrace,
    );
    return {
      'success': false,
      'error': error is AiImageGenerationException
          ? error.userMessage
          : userMessage,
      'error_code': ToolErrorCode.internal.name,
      'exception_type': type,
      'exception_message': detail,
      'stack_top': sanitizeStackTop(stackTrace),
      if (imageCode != null) 'image_error_code': imageCode.name,
    };
  }

  Future<AiImageGenerationResult> _handleGeneratePhotoFromSource(
    String prompt, {
    required String imagePath,
  }) async {
    if (imageEditCallback == null) {
      throw AiImageGenerationException(tr(LocaleKeys.aiImageEditUnavailable));
    }
    if (imagePath.isEmpty) {
      throw AiImageGenerationException(tr(LocaleKeys.aiImagePathEmpty));
    }
    return imageEditCallback!(prompt, imageData: imagePath);
  }
}
