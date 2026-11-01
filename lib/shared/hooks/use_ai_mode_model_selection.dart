// 职责: AI 模式面板的会话级模型选择 hook — 选中模型/思考档位与默认模型选择，桌面面板与移动页共用。
// 关联文件:
//   lib/shared/hooks/use_theater_run.dart
//   lib/shared/models/ai_provider.dart
//   lib/shared/providers/settings_providers.dart
// 遵循的 Rules:
//   .agents/rules/hooks.md

import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../models/ai_provider.dart';
import '../providers/settings_providers.dart';

/// 一次 AI 模式会话的模型选择状态。
class AiModeModelSelection {
  const AiModeModelSelection({
    required this.availableModels,
    required this.displayed,
    required this.selectedEffort,
    required this.runnable,
    required this.select,
    required this.selectWithEffort,
  });

  final List<AiModelOption> availableModels;

  /// 当前选中的可用模型。
  final AiModelOption? displayed;

  /// null 表示跟随模型默认档位。
  final String? selectedEffort;

  /// 解析本次运行要用的模型；会把回退结果写回选中态。无可用模型时返回 null。
  final AiModelOption? Function() runnable;

  final void Function(AiModelOption option) select;
  final void Function(AiModelOption option, String effort) selectWithEffort;
}

AiModeModelSelection useAiModeModelSelection(WidgetRef ref) {
  final availableModels = ref.watch(availableAiModelsProvider);
  final defaultChatModelOptionId = ref.watch(
    defaultAiModelOptionIdProvider(AiModelKind.chat),
  );

  final selected = useState<AiModelOption?>(null);
  final selectedEffort = useState<String?>(null);

  final current = selected.value;
  final displayed = resolveSelectableModelOption(
    options: availableModels,
    preferredOptionId: current?.id ?? defaultChatModelOptionId,
  );

  return AiModeModelSelection(
    availableModels: availableModels,
    displayed: displayed,

    selectedEffort: selectedEffort.value,
    runnable: () {
      selected.value = displayed;
      return displayed;
    },
    select: (option) {
      selected.value = option;
      selectedEffort.value = null;
    },
    selectWithEffort: (option, effort) {
      selected.value = option;
      selectedEffort.value = effort;
    },
  );
}
