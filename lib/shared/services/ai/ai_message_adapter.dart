// 职责: AiMessage ↔ 文本格式的纯函数转换器
// 关联文件:
//   lib/shared/services/ai/chat.dart
//   lib/shared/agent/client.dart

import '../../models/ai_chat_models.dart';

class AiMessageAdapter {
  AiMessageAdapter._();

  /// [AiMessage] 列表 → 纯文本 prompt（Gemini 文本模式使用）。
  static String buildPromptFromMessages(List<AiMessage> messages) {
    final buffer = StringBuffer();
    for (final msg in messages) {
      switch (msg.role) {
        case AiMessageRole.system:
          buffer.writeln('System: ${msg.content}');
        case AiMessageRole.user:
          buffer.writeln('User: ${msg.content}');
        case AiMessageRole.assistant:
          buffer.writeln('Assistant: ${msg.content}');
      }
    }
    return buffer.toString();
  }
}
