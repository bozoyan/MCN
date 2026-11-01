// 职责: 聊天发送完成生命周期守卫 — 仅在宿主 Widget 仍挂载时执行 UI 收尾。
// 关联文件:
//   lib/mobile/pages/novel_chat_page.dart
//   lib/desktop/widgets/ai/chat/runtime.dart
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/state-management.md

import 'package:flutter/widgets.dart';

Future<void> runChatSendWithMountedCompletion({
  required BuildContext context,
  required Future<void> Function() send,
  required VoidCallback onMounted,
}) async {
  await send();
  if (!context.mounted) {
    return;
  }
  onMounted();
}
