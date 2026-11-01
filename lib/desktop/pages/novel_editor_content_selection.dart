// 职责: 桌面端小说编辑页 Main 区域内容选择的密封类型定义。
// 关联文件:
//   lib/desktop/pages/novel_editor.dart
part of 'novel_editor.dart';

sealed class _EditorContentSelection {
  const _EditorContentSelection();
}

final class _EditorWorkspaceContentSelection extends _EditorContentSelection {
  const _EditorWorkspaceContentSelection();
}

final class _EditorCoverStudioSelection extends _EditorContentSelection {
  const _EditorCoverStudioSelection();
}

final class _EditorSubAgentSelection extends _EditorContentSelection {
  const _EditorSubAgentSelection(this.agent);

  final SubAgent agent;
}

final class _EditorAgentRuleSelection extends _EditorContentSelection {
  const _EditorAgentRuleSelection(this.rule);

  final AgentRule rule;
}

final class _EditorAgentRulesListSelection extends _EditorContentSelection {
  const _EditorAgentRulesListSelection();
}

final class _EditorAgentCouncilSelection extends _EditorContentSelection {
  final String? sessionId;

  /// 由 chat 下一步建议跳转带入的议题种子。
  final String? initialTopic;

  const _EditorAgentCouncilSelection({this.sessionId, this.initialTopic});
}

final class _EditorMonologueSelection extends _EditorContentSelection {
  final String? initialCharacterId;
  final String? sessionId;

  const _EditorMonologueSelection({this.initialCharacterId, this.sessionId});
}

final class _EditorTheaterSelection extends _EditorContentSelection {
  final String? sessionId;

  /// 由 chat 下一步建议跳转带入的场景种子。
  final String? initialScene;

  const _EditorTheaterSelection({this.sessionId, this.initialScene});
}

final class _EditorRoleplaySelection extends _EditorContentSelection {
  final String? sessionId;

  /// 从 chat 的下一步建议跳入时预选的角色；为 null 时进入角色选择器。
  final String? initialCharacterId;

  const _EditorRoleplaySelection({this.sessionId, this.initialCharacterId});
}

final class _EditorAiChatExpandedSelection extends _EditorContentSelection {
  const _EditorAiChatExpandedSelection();
}
