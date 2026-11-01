// 职责: 把 UIMessage 适配成共享 ChatMessageView — 计算重试、注入图片/头像/接力/分叉回调。
// 关联文件:
//   lib/desktop/widgets/ai/chat/panel.dart
//   lib/shared/widgets/ai/chat/chat_message_view.dart
//   lib/shared/widgets/ai/chat/ui_message.dart
//   lib/desktop/widgets/ai/chat/runtime.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/ai.json
//   assets/translations/zh-CN/ai.json
part of 'panel.dart';

extension _AiChatPanelMessageRenderer on AiChatPanel {
  /// 把 [UIMessage] 适配成共享渲染器 [ChatMessageView]。
  /// 真正的渲染逻辑在 shared;这里只做重试判定与桌面侧回调装配。
  Widget _buildChatMessage(
    BuildContext context,
    WidgetRef ref,
    RevericColors colors,
    UIMessage message,
    AiChatPanelState state,
    ChatPromptBuilder promptBuilder, {
    required AiSessionContext promptContext,
    required List<SubAgent> availableSubAgents,
    required bool isCompactingContext,
    required bool isWaitingForResponse,
    required String retryProgress,
    required AiChatSessionState sessionState,
  }) {
    final isSentByMe = message.role == AiMessageRole.user;
    // 回退入口在所有用户消息上常驻展示（回退本轮对作品改动 + 截断会话 + 回填 prompt）。
    final canRollbackTurn = isSentByMe;
    final isStreaming = message.isStreaming;
    final isRetryable =
        !isSentByMe &&
        !isStreaming &&
        (message.metadata?['retryable'] as bool? ?? false) &&
        message.blocks.isEmpty;
    // 仅已落库的真实会话可分叉；临时会话（__new__ / __handoff_draft__）不分叉。
    final canFork =
        !isSentByMe &&
        sessionState.sessionId != null &&
        !isTemporaryAiChatSessionId(sessionState.sessionId);

    return ChatMessageView(
      key: ValueKey(message.id),
      message: message,
      activeSessionId: activeSessionId,
      databasePath: databasePath,
      novelId: novelId,
      onRetry: isRetryable
          ? () => _retryAssistantMessage(
              context,
              ref,
              message.id,
              state: state,
              availableSubAgents: availableSubAgents,
              promptContext: promptContext,
              promptBuilder: promptBuilder,
              aiPromptService: ref.read(aiPromptServiceProvider),
            )
          : null,
      onConfigureImageModel: () => showAgentModelSettingsDialog(context),
      onFeedback: () => showAiChatFeedbackDialog(
        context: context,
        ref: ref,
        sessionState: sessionState,
        novelId: novelId,
        databasePath: databasePath,
      ),
      onFork: canFork
          ? () => _forkFromMessage(
              context,
              ref,
              sourceSessionId: sessionState.sessionId!,
              cutAtSourceId: message.sourceIds.last,
            )
          : null,
      onRollbackTurn: canRollbackTurn
          ? (messageId) async {
              await _rollbackTurnAndRedraft(
                context,
                ref,
                messageId,
                state: state,
                availableSubAgents: availableSubAgents,
                promptContext: promptContext,
                promptBuilder: promptBuilder,
                aiPromptService: ref.read(aiPromptServiceProvider),
              );
              return null;
            }
          : null,
      onSetAsAvatar: onSetAsAvatar,
      onAddPhoto: onAddPhoto,
      onOpenSessionReference: onOpenSessionReference,
      isCompactingContext: isCompactingContext,
      isWaitingForResponse: isWaitingForResponse,
      retryProgress: retryProgress,
    );
  }

  /// 把当前会话截止到（含）[cutAtSourceId] 这条消息分叉为一条新 chat session，
  /// 并切换过去。失败时弹 snackbar，不透出底层异常。
  Future<void> _forkFromMessage(
    BuildContext context,
    WidgetRef ref, {
    required String sourceSessionId,
    required String cutAtSourceId,
  }) async {
    final dbPath = databasePath;
    final nid = novelId;
    if (dbPath == null || dbPath.isEmpty) {
      return;
    }
    final confirmed = await showAiForkSessionConfirmDialog(context);
    if (!confirmed || !context.mounted) {
      return;
    }
    try {
      final persistence = ref.read(
        aiSessionPersistenceServiceProvider(novelId: nid, databasePath: dbPath),
      );
      final novelDb = ref.read(novelContentDatabaseProvider(dbPath));
      final forkedId = await persistence.forkSession(
        sourceSessionId: sourceSessionId,
        cutAtSourceId: cutAtSourceId,
        titleSuffix: context.t(LocaleKeys.aiForkSuffix),
        novelDatabase: novelDb,
      );
      await onActiveSessionIdChanged?.call(forkedId);
    } catch (error, stackTrace) {
      _log.error(
        'fork failed sourceSessionId=$sourceSessionId cutAt=$cutAtSourceId',
        error: error,
        stackTrace: stackTrace,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.t(LocaleKeys.aiForkFailed))),
        );
      }
    }
  }
}
