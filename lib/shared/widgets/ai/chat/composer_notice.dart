// 职责: 为模型失效提示提供新建会话动作，并展示移动端聊天提示。
// 关联文件:
//   lib/desktop/widgets/ai/chat/composer.dart
//   lib/mobile/pages/novel_chat_page.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/ai.json
//   assets/translations/zh-CN/ai.json
// 遵循的 Rules:
//   .agents/rules/i18n.md

import 'package:flutter/material.dart';

import '../../../localization/app_localization.dart';
import '../../../localization/locale_keys.dart';

/// Composer / Snackbar 用：根据本地化 message 解析 CTA。
ComposerNoticeAction? resolveComposerNoticeAction(
  BuildContext context,
  String message, {
  VoidCallback? onNewSession,
}) {
  // 已有对话模型失效：引导新建会话（不中途跨模型续聊）。
  if (message == context.t(LocaleKeys.aiModelUnavailable) &&
      onNewSession != null) {
    return ComposerNoticeAction(
      label: context.t(LocaleKeys.aiNewSession),
      onTap: onNewSession,
    );
  }
  return null;
}

class ComposerNoticeAction {
  const ComposerNoticeAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;
}

/// 移动端 AI 请求可恢复提示（带 CTA 的 SnackBar）。
ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showAiComposerNotice(
  BuildContext context,
  String message, {
  VoidCallback? onNewSession,
}) {
  final action = resolveComposerNoticeAction(
    context,
    message,
    onNewSession: onNewSession,
  );
  return ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      action: action == null
          ? null
          : SnackBarAction(label: action.label, onPressed: action.onTap),
    ),
  );
}
