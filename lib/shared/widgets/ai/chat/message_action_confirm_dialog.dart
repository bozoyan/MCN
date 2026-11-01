// 职责: AI 消息操作确认弹窗 — 为分叉会话与回退消息等高影响操作提供统一二次确认。
// 关联文件:
//   lib/shared/widgets/confirm_dialog.dart
//   lib/shared/widgets/ai/chat/chat_message_view.dart
//   lib/desktop/widgets/ai/chat/message_renderer.dart
//   lib/mobile/pages/novel_chat_page.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/ai.json
//   assets/translations/zh-CN/ai.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
import 'package:flutter/material.dart';

import '../../../localization/app_localization.dart';
import '../../../localization/locale_keys.dart';
import '../../confirm_dialog.dart';

Future<bool> showAiForkSessionConfirmDialog(BuildContext context) {
  return showConfirmDialog(
    context,
    title: context.t(LocaleKeys.aiForkConfirmTitle),
    message: context.t(LocaleKeys.aiForkConfirmMessage),
    confirmLabel: context.t(LocaleKeys.aiForkConfirmAction),
  );
}

Future<bool> showAiRollbackMessageConfirmDialog(BuildContext context) {
  return showConfirmDialog(
    context,
    title: context.t(LocaleKeys.aiRollbackMessageConfirmTitle),
    message: context.t(LocaleKeys.aiRollbackMessageConfirmMessage),
    confirmLabel: context.t(LocaleKeys.aiRollbackMessageConfirmAction),
    variant: ConfirmDialogVariant.error,
  );
}
