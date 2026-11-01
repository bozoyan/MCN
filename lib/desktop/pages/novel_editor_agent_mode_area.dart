// 职责: 构建小说编辑页 Main 区域的智能体模式面板，并协调模式会话回写和切回写作。
// 关联文件:
//   lib/desktop/pages/novel_editor.dart
//   lib/desktop/pages/novel_editor_content_selection.dart
//   lib/desktop/features/council/panel.dart
//   lib/desktop/features/monologue/panel.dart
//   lib/desktop/features/theater/panel.dart
// 遵循的 Rules:
//   .agents/rules/state-management.md
part of 'novel_editor.dart';

/// 智能体模式面板的「切回写作 / handoff 草稿 / 回写 session」动作集合。
/// 持有编辑页的回写状态，向四个面板暴露行为而非裸 notifier。
class _AgentModeActions {
  const _AgentModeActions({
    required this.showWorkspaceContent,
    required this.aiPanelCollapsed,
    required this.activeAiSessionId,
    required this.pendingHandoffDraft,
    required this.contentSelection,
  });

  final VoidCallback showWorkspaceContent;
  final ValueNotifier<bool> aiPanelCollapsed;
  final ValueNotifier<String?> activeAiSessionId;
  final ValueNotifier<AiChatHandoffDraft?> pendingHandoffDraft;
  final ValueNotifier<_EditorContentSelection> contentSelection;

  Future<void> switchToWriteMode(String sessionId) async {
    showWorkspaceContent();
    aiPanelCollapsed.value = false;
    activeAiSessionId.value = sessionId;
  }

  Future<void> handoffToWriteMode(AiChatHandoffDraft draft) async {
    showWorkspaceContent();
    aiPanelCollapsed.value = false;
    pendingHandoffDraft.value = draft;
    activeAiSessionId.value = draft.id;
  }

  void selectSession(_EditorContentSelection selection) {
    contentSelection.value = selection;
  }
}

Widget _buildAgentModeArea({
  required _EditorContentSelection selection,
  required Novel novel,
  required String? chapterTitle,
  required String? databasePath,
  required String? Function() currentAiWorkspaceContent,
  required _AgentModeActions actions,
}) {
  return switch (selection) {
    _EditorAgentCouncilSelection(:final sessionId, :final initialTopic) =>
      AgentCouncilPanel(
        onClose: actions.showWorkspaceContent,
        onSwitchToWriteMode: actions.switchToWriteMode,
        onDraftHandoffToWriteMode: actions.handoffToWriteMode,
        novel: novel,
        databasePath: databasePath,
        initialSessionId: sessionId,
        initialTopic: initialTopic,
        onActiveSessionIdChanged: (sessionId) => actions.selectSession(
          _EditorAgentCouncilSelection(sessionId: sessionId),
        ),
      ),
    _EditorMonologueSelection(:final initialCharacterId, :final sessionId) =>
      MonologuePanel(
        onClose: actions.showWorkspaceContent,
        onSwitchToWriteMode: actions.switchToWriteMode,
        onDraftHandoffToWriteMode: actions.handoffToWriteMode,
        novelId: novel.id,
        novelName: novel.title,
        chapterTitle: chapterTitle,
        databasePath: databasePath,
        workspaceContent: currentAiWorkspaceContent(),
        initialCharacterId: initialCharacterId,
        initialSessionId: sessionId,
        onActiveSessionIdChanged: (sessionId) => actions.selectSession(
          _EditorMonologueSelection(sessionId: sessionId),
        ),
      ),
    _EditorTheaterSelection(:final sessionId, :final initialScene) =>
      TheaterPanel(
        onClose: actions.showWorkspaceContent,
        onSwitchToWriteMode: actions.switchToWriteMode,
        onDraftHandoffToWriteMode: actions.handoffToWriteMode,
        novelId: novel.id,
        novelName: novel.title,
        chapterTitle: chapterTitle,
        databasePath: databasePath,
        workspaceContent: currentAiWorkspaceContent(),
        initialSessionId: sessionId,
        initialScene: initialScene,
        onActiveSessionIdChanged: (sessionId) => actions.selectSession(
          _EditorTheaterSelection(sessionId: sessionId),
        ),
      ),
    _EditorRoleplaySelection(:final sessionId, :final initialCharacterId) =>
      RoleplayPanel(
        onClose: actions.showWorkspaceContent,
        onSwitchToWriteMode: actions.switchToWriteMode,
        onDraftHandoffToWriteMode: actions.handoffToWriteMode,
        novelId: novel.id,
        novelName: novel.title,
        chapterTitle: chapterTitle,
        databasePath: databasePath,
        workspaceContent: currentAiWorkspaceContent(),
        initialCharacterId: initialCharacterId,
        initialSessionId: sessionId,
        onActiveSessionIdChanged: (sessionId) => actions.selectSession(
          _EditorRoleplaySelection(sessionId: sessionId),
        ),
      ),
    _ => throw ArgumentError.value(
      selection,
      'selection',
      'Expected an agent-mode content selection.',
    ),
  };
}
