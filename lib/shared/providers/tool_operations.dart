// 职责: 共享操作身份与历史快照，并声明宿主是否提供会话媒体操作。
// 关联文件:
//   lib/shared/services/ai/tool_operations.dart
//   lib/shared/providers/ai_providers.dart
//   lib/shared/providers/novel_providers.dart
// 遵循的 Rules:
//   .agents/rules/state-management.md
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../services/ai/tool_operations.dart';

final toolOperationRegistryProvider = Provider<ToolOperationRegistry>((ref) {
  final registry = ToolOperationRegistry();
  ref.onDispose(registry.dispose);
  return registry;
});

/// 宿主是否提供制片、剪辑、ffmpeg 等会话媒体操作；桌面入口覆盖为 true。
final mediaOperationsSupportedProvider = Provider<bool>((ref) => false);
