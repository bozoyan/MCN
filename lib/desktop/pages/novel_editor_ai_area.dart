// 职责: 桌面端小说编辑页 — 构建右侧 AI 聊天区域及其与制片画布浮窗共用的聊天面板；封面工作台由 Main 接管。
// 关联文件:
//   lib/desktop/pages/novel_editor.dart
//   lib/desktop/widgets/ai/chat/panel.dart
//   lib/desktop/widgets/ai/chat/floating.dart
//   lib/shared/services/ai/chat_session_controller.dart
//   lib/desktop/features/cover_studio/studio_page.dart
part of 'novel_editor.dart';

const _aiAreaMotionDuration = Duration(milliseconds: 220);
const _aiAreaCollapseDuration = Duration(milliseconds: 160);

extension _NovelEditorAiArea on NovelEditorPage {
  Widget _buildAiArea({
    required WorkspaceSelection selection,
    required _EditorContentSelection contentSelection,
    required ValueNotifier<bool> aiPanelCollapsed,
    required bool isExpandedChatInMain,
    required bool isChatFloating,
    required double panelWidth,
    required Widget Function() buildLeadingDivider,
    required Widget Function() buildChatPanel,
  }) {
    // Immersive chat owns Main; hide the entire right AI rail (panel + strip).
    if (isExpandedChatInMain) {
      return const SizedBox.shrink();
    }

    if (contentSelection is _EditorCoverStudioSelection) {
      return const SizedBox.shrink();
    }

    // 制片画布把聊天收进画布浮窗，右栏整列让出。
    if (isChatFloating) {
      return const SizedBox.shrink();
    }

    if (!aiPanelCollapsed.value) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          buildLeadingDivider(),
          SizedBox(width: panelWidth, child: buildChatPanel()),
        ],
      );
    }

    return NovelEditorCollapsedAiPanel(
      onExpand: () => aiPanelCollapsed.value = false,
    );
  }

  /// 右栏和制片画布浮窗共用这一份面板；同一个 [key] 让面板换位时保留草稿和滚动位置。
  Widget _buildAiChatPanel(
    BuildContext context, {
    required Key key,
    required bool floating,
    required VoidCallback onClose,
    required Novel novel,
    required WorkspaceSelection selection,
    required TextEditingController chapterTitleController,
    required ValueNotifier<int?> chapterNumber,
    required String? databasePath,
    required String? selectedChapterId,
    required VoidCallback onExpandChat,
    required Future<bool> Function() onRequestNewSession,
    required ValueNotifier<String?> activeAiSessionId,
    required String? resolvedActiveAiSessionId,
    required Widget Function() loading,
    required ValueNotifier<AiChatDraftMessage?> pendingCoverDraft,
    required ValueNotifier<AiChatHandoffDraft?> pendingHandoffDraft,
    required ValueNotifier<AiChatShortcutDraft?> pendingShortcutDraft,
    required ValueNotifier<bool> isAgentEditing,
    required String? Function() currentAiWorkspaceTitle,
    required String? Function() currentAiWorkspaceContent,
    required String? Function(BuildContext context) currentAiWorkspaceMetaTitle,
    required String? Function() currentAiWorkspaceMetaContent,
    required Future<void> Function(String content) applyAiWorkspaceContent,
    required Future<void> Function(String assetId, String characterId)
    onSetAsAvatar,
    required Future<void> Function(
      String assetId, {
      String? characterId,
      String? itemId,
    })
    onAddPhoto,
    required Future<void> Function(String sessionId, AiSessionMode mode)
    onOpenSessionReference,
    required void Function(FeatureId feature, String? seedText) onOpenFeature,
    ScreenplayWorkspaceState? screenplayWorkspace,
    bool hasMultipleSeasons = false,
    int chatOnboardingStep = 0,
    VoidCallback? onAdvanceChatOnboarding,
    VoidCallback? onDismissChatOnboarding,
  }) {
    if (resolvedActiveAiSessionId == null) {
      return loading();
    }
    final chapterTitle = selectedChapterId != null
        ? chapterTitleController.text
        : null;
    return AiChatPanel(
      key: key,
      onClose: onClose,
      onExpand: onExpandChat,
      floating: floating,
      novel: novel,
      chapterId: selectedChapterId,
      chapterTitle: chapterTitle,
      chapterNumber: selectedChapterId != null ? chapterNumber.value : null,
      databasePath: databasePath,
      currentSeasonId: screenplayWorkspace?.seasonId,
      currentEpisodeId: screenplayWorkspace?.episodeId,
      hasMultipleSeasons: hasMultipleSeasons,
      workspaceSection: selection.section,
      workspaceItemId: selection.itemId,
      workspaceTitle: currentAiWorkspaceTitle(),
      workspaceContent: currentAiWorkspaceContent(),
      workspaceMetaTitle: currentAiWorkspaceMetaTitle(context),
      workspaceMetaContent: currentAiWorkspaceMetaContent(),
      onApplyGeneratedContent: selection.section.isReadOnly
          ? null
          : applyAiWorkspaceContent,
      onSetAsAvatar: onSetAsAvatar,
      onAddPhoto: onAddPhoto,
      activeSessionId: resolvedActiveAiSessionId,
      draftMessage: pendingCoverDraft.value,
      handoffDraft: pendingHandoffDraft.value,
      onRequestHandoff: (draft) => pendingHandoffDraft.value = draft,
      shortcutDraft: pendingShortcutDraft.value,
      onHandoffDraftConsumed: (id) {
        if (pendingHandoffDraft.value?.id == id) {
          pendingHandoffDraft.value = null;
        }
      },
      onShortcutDraftConsumed: (id) {
        if (pendingShortcutDraft.value?.id == id) {
          pendingShortcutDraft.value = null;
        }
      },
      onRequestNewSession: () async {
        await onRequestNewSession();
      },
      onEditingStateChanged: (isEditing) {
        isAgentEditing.value = isEditing;
      },
      onSessionRestored: (sessionId) {
        activeAiSessionId.value = sessionId;
      },
      onActiveSessionIdChanged: (sessionId) async {
        activeAiSessionId.value = sessionId;
      },
      onOpenSessionReference: onOpenSessionReference,

      onboardingStep: chatOnboardingStep,
      onOnboardingNext: onAdvanceChatOnboarding,
      onOnboardingDismiss: onDismissChatOnboarding,
      onOpenFeature: onOpenFeature,
    );
  }
}
