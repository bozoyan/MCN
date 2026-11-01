// 职责: AI 互动 mode 共享 runtime 状态 — 标记 session 级处理中，与 UI 生命周期解耦。
// 关联文件:
//   lib/shared/providers/ai_mode_processing.dart
//   lib/shared/providers/agent_council_providers.dart
//   lib/shared/providers/theater_providers.dart
//   lib/shared/providers/monologue_providers.dart
//   lib/shared/providers/roleplay_providers.dart

class AiModeRuntimeState {
  const AiModeRuntimeState({this.isProcessing = false});

  final bool isProcessing;

  AiModeRuntimeState copyWith({bool? isProcessing}) {
    return AiModeRuntimeState(isProcessing: isProcessing ?? this.isProcessing);
  }
}
