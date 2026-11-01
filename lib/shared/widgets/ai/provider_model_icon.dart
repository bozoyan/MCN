// 职责: provider id → RevericIcon 图标映射 — 供各模型选择器统一取 provider 图标。
// 关联文件:
//   lib/shared/theme/theme.dart
//   lib/desktop/widgets/ai/model/model_selector.dart
//   lib/mobile/widgets/model_effort_sheet.dart
// 遵循的 Rules:
//   .agents/rules/icons.md
import '../../theme/theme.dart';

/// 根据 provider id 返回对应的 [RevericIcons] 图标名。
String providerModelIcon(String providerId) {
  return switch (providerId) {
    'openai' => RevericIcons.auto_awesome_outlined,
    'xai' => RevericIcons.rocket_launch_outlined,
    'deepseek' => RevericIcons.water_drop_outlined,
    'gemini' => RevericIcons.diamond_outlined,
    'anthropic' => RevericIcons.psychology_outlined,
    'moonshot' => RevericIcons.nightlight_outlined,
    'zhipu' => RevericIcons.auto_awesome,
    'doubao' => RevericIcons.coffee_outlined,
    _ => RevericIcons.smart_toy_outlined,
  };
}
