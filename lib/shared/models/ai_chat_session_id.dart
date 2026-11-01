// 职责: 定义 AI Chat 临时会话 ID 的统一识别规则。
// 关联文件:
//   lib/shared/providers/ai_providers.dart
//   lib/shared/services/ai/chat_session_controller.dart
//   lib/shared/services/ai/spawn_agent_handler.dart

/// UI 尚未物化为持久化会话时使用的临时 session ID。
bool isTemporaryAiChatSessionId(String? sessionId) {
  return sessionId != null &&
      (sessionId.startsWith('__new__') ||
          sessionId.startsWith('__handoff_draft__'));
}
