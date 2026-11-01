// 职责: 定义图像生成的请求级扩展参数（魔搭 LoRA/采样参数与 MOSS 扩展开关）及其 JSON 往返。
// 关联文件:
//   lib/shared/services/ai/image/client.dart
//   lib/shared/services/ai/image/modelscope.dart
//   lib/shared/services/ai/image/moss.dart
//   lib/shared/models/production/image_request.dart
// 遵循的 Rules:
//   .agents/rules/enum-naming.md

/// 魔搭请求叠加的单个 LoRA;多 LoRA 权重之和必须为 1.0,最多 6 个。
class ModelScopeLora {
  const ModelScopeLora({required this.repoId, required this.weight});

  factory ModelScopeLora.fromJson(Map<String, dynamic> json) =>
      ModelScopeLora(
        repoId: json['repo_id'] as String,
        weight: (json['weight'] as num).toDouble(),
      );
  final String repoId;
  final double weight;

  Map<String, dynamic> toJson() => {'repo_id': repoId, 'weight': weight};
}

/// 单次生图请求的可选扩展参数;字段为空表示沿用服务端或模型默认值。
class ImageRequestExtras {
  const ImageRequestExtras({
    this.loras = const [],
    this.steps,
    this.guidance,
    this.seed,
    this.negativePrompt,
    this.promptEnhance,
    this.outputWatermark,
  });

  factory ImageRequestExtras.fromJson(Map<String, dynamic> json) =>
      ImageRequestExtras(
        loras: (json['loras'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ModelScopeLora.fromJson)
            .toList(growable: false),
        steps: json['steps'] as int?,
        guidance: (json['guidance'] as num?)?.toDouble(),
        seed: json['seed'] as int?,
        negativePrompt: json['negative_prompt'] as String?,
        promptEnhance: json['prompt_enhance'] as bool?,
        outputWatermark: json['output_watermark'] as bool?,
      );

  /// 魔搭 LoRA 叠加;单条即服务端的字符串形式,多条走权重映射。
  final List<ModelScopeLora> loras;

  /// 魔搭采样步数(如 Qwen-Image-2.1-Turbo 为 8)。
  final int? steps;

  /// 魔搭提示词引导系数。
  final double? guidance;

  /// 魔搭随机种子;-1 表示随机。
  final int? seed;

  /// MOSS 负向提示词。
  final String? negativePrompt;

  /// MOSS 同请求内先增强提示词再生图。
  final bool? promptEnhance;

  /// MOSS 输出可见水印开关。
  final bool? outputWatermark;

  bool get hasLoras => loras.isNotEmpty;

  /// 多 LoRA 时的权重映射;单条返回 null,由协议端拼成字符串形式。
  Map<String, double>? get loraWeightMap {
    if (loras.length < 2) {
      return null;
    }
    return {for (final lora in loras) lora.repoId: lora.weight};
  }

  /// 魔搭 LoRA 参数的请求值:单条为 repo-id 字符串,多条为权重映射。
  Object? get modelScopeLoras {
    if (loras.isEmpty) {
      return null;
    }
    if (loras.length == 1) {
      return loras.first.repoId;
    }
    return loraWeightMap;
  }

  /// 发送前的快速校验:数量与权重总和;不合法时返回错误描述,合法返回 null。
  String? validateLoras({int maxCount = 6}) {
    if (loras.length > maxCount) {
      return 'loras_exceed_max';
    }
    for (final lora in loras) {
      if (lora.repoId.trim().isEmpty ||
          lora.weight <= 0 ||
          lora.weight > 1) {
        return 'lora_invalid_weight';
      }
    }
    if (loras.length >= 2) {
      final sum = loras.fold<double>(0, (total, lora) => total + lora.weight);
      if ((sum - 1.0).abs() > 0.001) {
        return 'lora_weight_sum';
      }
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    if (hasLoras)
      'loras': loras.map((lora) => lora.toJson()).toList(growable: false),
    if (steps != null) 'steps': steps,
    if (guidance != null) 'guidance': guidance,
    if (seed != null) 'seed': seed,
    if (negativePrompt != null) 'negative_prompt': negativePrompt,
    if (promptEnhance != null) 'prompt_enhance': promptEnhance,
    if (outputWatermark != null) 'output_watermark': outputWatermark,
  };

  bool get isEmpty => toJson().isEmpty;
}
