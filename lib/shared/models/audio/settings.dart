// 职责: 从音频节点样式读取与当前供应商和模型匹配的语音参数。
// 关联文件:
//   lib/shared/models/audio/config.dart
//   lib/shared/services/production/canvas_service.dart
//   lib/shared/services/production/audio_generate_orchestrator.dart
import 'config.dart';

AudioRequestDefaults audioParametersFromStyle(
  Map<String, dynamic>? style,
  String? providerId,
  String? modelId,
) {
  final saved = style?['audioGeneration'] as Map<String, dynamic>?;
  if (saved == null ||
      saved['provider_id'] != providerId ||
      saved['model_id'] != modelId) {
    return const AudioRequestDefaults();
  }
  return AudioRequestDefaults.fromJson(
    saved['parameters'] as Map<String, dynamic>,
  );
}
