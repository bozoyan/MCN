// 职责: 为聊天输入区随机选择默认提示，并在组件挂载期间保持选择稳定。
// 关联文件:
//   lib/desktop/widgets/ai/chat/composer.dart
//   lib/mobile/widgets/chat_composer.dart
//   lib/shared/localization/app_localization.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/ai.json
//   assets/translations/zh-CN/ai.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../localization/app_localization.dart';
import '../localization/locale_keys.dart';

String useChatComposerHint(BuildContext context) {
  const hintKeys = [
    LocaleKeys.aiInputHint,
    LocaleKeys.aiInputHintSkill,
    LocaleKeys.aiInputHintWriting,
    LocaleKeys.aiInputHintIdeas,
    LocaleKeys.aiInputHintOutline,
    LocaleKeys.aiInputHintRoughIdea,
    LocaleKeys.aiInputHintPlot,
    LocaleKeys.aiInputHintCharacter,
    LocaleKeys.aiInputHintWorldbuilding,
    LocaleKeys.aiInputHintStart,
    LocaleKeys.aiInputHintDevelop,
  ];
  final hintKey = useMemoized(
    () => hintKeys[Random().nextInt(hintKeys.length)],
  );
  return context.t(hintKey);
}
