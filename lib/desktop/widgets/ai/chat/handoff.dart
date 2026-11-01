// 职责: 验证聊天接力来源并将当前输入和模型选择交给临时草稿激活流程。
// 关联文件:
//   lib/desktop/widgets/ai/chat/panel.dart
//   lib/desktop/widgets/ai/chat/state.dart
//   lib/shared/services/ai/handoff_service.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/ai.json
//   assets/translations/zh-CN/ai.json
part of 'panel.dart';

extension _AiChatPanelHandoff on AiChatPanel {
  Future<void> _continueSession(
    BuildContext context,
    WidgetRef ref,
    AiChatPanelState state,
    String sourceId,
  ) async {
    final dbPath = databasePath;
    if (dbPath == null || onRequestHandoff == null) {
      return;
    }
    bool sourceBusy() {
      final runtime = ref.read(aiChatRuntimeProvider(sourceId));
      return runtime.isRequestInFlight || runtime.isSessionMutationInFlight;
    }

    try {
      if (sourceBusy()) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.t(LocaleKeys.aiCancelFirst))),
        );
        return;
      }
      final source = await loadSessionContinuationSource(
        database: ref.read(appDatabaseProvider),
        contentDatabase: ref.read(novelContentDatabaseProvider(dbPath)),
        workId: novelId,
        sessionId: sourceId,
      );
      if (!context.mounted) {
        return;
      }
      if (source == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.t(LocaleKeys.aiChatSourceUnavailable)),
          ),
        );
        return;
      }
      if (sourceBusy()) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.t(LocaleKeys.aiCancelFirst))),
        );
        return;
      }
      final session = ref.read(aiChatSessionProvider(activeSessionId));
      final pending = state.pendingModelSelection.value;
      onRequestHandoff!(
        AiChatHandoffDraft.fromContinuation(
          buildSessionContinuation(
            source: source,
            initialText: state.composerController.text,
            references: state.attachedReferences.value,
            modelSelection: (
              providerId: pending?.providerId ?? session.providerId,
              model: pending?.model ?? session.model,
              reasoningEffort:
                  pending?.reasoningEffort ?? session.reasoningEffort,
            ),
          ),
        ),
      );
    } catch (error, stackTrace) {
      _log.error(
        'Prepare session continuation failed source=$sourceId',
        error: error,
        stackTrace: stackTrace,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.t(LocaleKeys.aiChatSourceUnavailable)),
          ),
        );
      }
    }
  }

  String _draftHandoffSessionSignal(String sourceSessionId, String targetSlug) {
    return '__handoff_draft__${sourceSessionId}_$targetSlug';
  }

  bool _isDraftHandoffSessionSignal(String targetId) {
    return targetId.startsWith('__handoff_draft__');
  }
}
