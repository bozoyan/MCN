// 职责: 冻结图片生成规格、最终提示词及提交时采用的参考素材。
// 关联文件:
//   lib/shared/services/production/image_generate_orchestrator.dart
//   lib/shared/database/type_converters.dart
//   lib/shared/services/ai/image.dart
import '../ai_provider.dart';
import '../image/channels.dart';
import '../image/extras.dart';
import 'view_presets.dart';

class ProductionImageDraft {
  const ProductionImageDraft({
    required this.prompt,
    required this.modelId,
    required this.ratio,
    required this.resolution,
    this.providerId,
    this.title,
    this.preset,
  });
  final String prompt;
  final String modelId;
  final String ratio;
  final String resolution;
  final String? providerId;
  final String? title;
  final ImageGenerationPreset? preset;
}

class ProductionImageReference {
  const ProductionImageReference({
    required this.assetId,
    this.clipId,
    this.inputId,
  });
  final String assetId;
  final String? clipId;
  final String? inputId;
  Map<String, dynamic> toJson() => {
    'clip_id': clipId,
    'input_id': inputId,
    'asset_id': assetId,
  };
  factory ProductionImageReference.fromJson(Map<String, dynamic> json) =>
      ProductionImageReference(
        assetId: json['asset_id'] as String,
        clipId: json['clip_id'] as String?,
        inputId: json['input_id'] as String?,
      );
}

class ProductionImageRequest {
  ProductionImageRequest({
    required this.providerId,
    required this.modelId,
    required this.originalPrompt,
    required this.prompt,
    required this.ratio,
    required this.resolution,
    required this.size,
    this.extras,
    List<ProductionImageReference> references = const [],
  }) : references = List.unmodifiable(references);
  final String providerId;
  final String modelId;
  final String originalPrompt;
  final String prompt;
  final String ratio;
  final String resolution;
  final String? size;

  /// 请求级扩展参数(魔搭 LoRA/采样、MOSS 扩展开关);旧任务数据为 null。
  final ImageRequestExtras? extras;
  final List<ProductionImageReference> references;
  Map<String, dynamic> toJson() => {
    'version': 1,
    'provider_id': providerId,
    'model_id': modelId,
    'original_prompt': originalPrompt,
    'prompt': prompt,
    'ratio': ratio,
    'resolution': resolution,
    'size': size,
    if (extras != null && !extras!.isEmpty) 'extras': extras!.toJson(),
    'references': references.map((r) => r.toJson()).toList(),
  };
  factory ProductionImageRequest.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1) {
      throw const FormatException('Unsupported image request');
    }
    return ProductionImageRequest(
      providerId: json['provider_id'] as String,
      modelId: json['model_id'] as String,
      originalPrompt: json['original_prompt'] as String,
      prompt: json['prompt'] as String,
      ratio: json['ratio'] as String,
      resolution: json['resolution'] as String,
      size: json['size'] as String?,
      extras: json['extras'] is Map<String, dynamic>
          ? ImageRequestExtras.fromJson(json['extras'] as Map<String, dynamic>)
          : null,
      references: (json['references'] as List)
          .map(
            (r) => ProductionImageReference.fromJson(r as Map<String, dynamic>),
          )
          .toList(),
    );
  }
}

/// 制作场景的图像能力：只允许渠道登记了能力的型号，底层生图接口本身不拦截。
class ProductionImageCapabilities {
  const ProductionImageCapabilities(this.provider, this.model);
  final AiProvider provider;
  final String model;
  static bool supports(AiProvider provider) =>
      provider.typeConfig.imageProtocol != null;

  ImageChannelModel? get _channel =>
      lookupImageChannelModel(provider.type, model);
  ImageModelCapabilities get _capabilities =>
      _channel?.capabilities ?? const ImageModelCapabilities();

  /// 渠道登记了该型号的能力，可以在制作中选用。
  bool get isSupported => supports(provider) && _channel != null;

  /// 只暴露渠道登记的能力，未登记型号返回 null。
  ImageModelCapabilities? get verifiedCapabilities =>
      supports(provider) ? _channel?.capabilities : null;

  List<String> get ratios => _capabilities.ratios.toList();
  List<String> get resolutions => _capabilities.resolutions.toList();
  int get maxReferences => _capabilities.maxReferences;
  String? size(String ratio, String resolution) =>
      _capabilities.size(ratio, resolution);

  void validate({
    required String prompt,
    required String ratio,
    required String resolution,
    required int references,
  }) {
    if (!isSupported ||
        !provider.enabled ||
        !provider.availableImageModels.contains(model) ||
        prompt.trim().isEmpty) {
      throw const FormatException('Unsupported image generation configuration');
    }
    _capabilities.validateReferences(references);
    _capabilities.validateSize(size(ratio, resolution), references: references);
  }
}
