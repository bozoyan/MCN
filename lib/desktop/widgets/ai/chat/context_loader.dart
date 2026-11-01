// 职责: AI 聊天面板 — 构建轻量 prompt 上下文与用户规则片段。
// 关联文件:
//   lib/desktop/widgets/ai/chat/panel.dart
//   lib/shared/services/ai/chat_prompt_builder.dart
//   lib/shared/models/ai_chat_models.dart
part of 'panel.dart';

extension _AiChatPanelContextLoader on AiChatPanel {
  AiSessionContext _buildPromptContext({
    required ChatPromptBuilder promptBuilder,
    required String username,
    required String? userRules,
    required int? novelChatSessionCount,
  }) {
    return _buildPanelContext().copyWith(
      chapterId: chapterId,
      chapterTitle: chapterTitle,
      chapterNum: chapterNumber,
      workspaceTitle: workspaceMetaTitle ?? workspaceTitle ?? chapterTitle,
      workspaceContent: promptBuilder.buildWorkspaceSeedContent(),
      username: username,
      userRules: userRules,
      novelChatSessionCount: novelChatSessionCount,
    );
  }

  String? _formatAgentRules(List<AgentRule> rules) => rules.formatForPrompt();
}
