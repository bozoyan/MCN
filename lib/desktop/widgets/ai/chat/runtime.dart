// 职责: AI 聊天面板发送编排薄包装 — 构造共享 ChatSessionController 并转调 send/retry/cancel，签名对外保持不变。
// 关联文件:
//   lib/desktop/widgets/ai/chat/panel.dart
//   lib/desktop/widgets/ai/chat/agent_factory.dart
//   lib/shared/services/ai/chat_session_controller.dart
//   lib/shared/widgets/ai/chat/chat_send_completion_guard.dart
part of 'panel.dart';

extension _AiChatPanelRuntime on AiChatPanel {
  Future<void> _handleSendMessage(
    BuildContext context,
    WidgetRef ref,
    String text, {
    required AiChatPanelState state,
    required List<SubAgent> availableSubAgents,
    required AiSessionContext promptContext,
    required ChatPromptBuilder promptBuilder,
    required AiPromptService aiPromptService,
  }) async {
    // 快捷出图指令:参数缺省时用参数记忆补齐,不进 AI 对话轮。
    final imageCommand = parseChatImageCommand(text);
    if (imageCommand != null &&
        activeSessionId != null &&
        activeSessionId!.isNotEmpty) {
      state.composerController.clear();
      final referencePaths = state.referenceImagePaths.value;
      state.referenceImagePaths.value = const [];
      await runChatImageCommand(
        context: context,
        ref: ref,
        novelId: novelId,
        sessionId: activeSessionId!,
        command: imageCommand,
        referencePaths: referencePaths,
      );
      return;
    }
    final container = ProviderScope.containerOf(context, listen: false);
    final controller = _buildChatSessionController(
      context: context,
      container: container,
      state: state,
      availableSubAgents: availableSubAgents,
      aiPromptService: aiPromptService,
      promptContext: promptContext,
      promptBuilder: promptBuilder,
    );
    final pendingModelSelection = state.pendingModelSelection.value;
    await state.composerController.submit(
      () => runChatSendWithMountedCompletion(
        context: context,
        send: () => controller.send(
          text,
          draft: state.composerController.snapshot(text),
          pendingModelSelection: pendingModelSelection,
        ),
        onMounted: () {
          if (pendingModelSelection == null) {
            return;
          }
          final session = container.read(
            aiChatSessionProvider(activeSessionId),
          );
          if (pendingModelSelection.hasSameModelAs(session) &&
              pendingModelSelection.reasoningEffort ==
                  session.reasoningEffort) {
            state.pendingModelSelection.value = null;
          }
        },
      ),
    );
  }

  Future<void> _retryAssistantMessage(
    BuildContext context,
    WidgetRef ref,
    String assistantMessageId, {
    required AiChatPanelState state,
    required List<SubAgent> availableSubAgents,
    required AiSessionContext promptContext,
    required ChatPromptBuilder promptBuilder,
    required AiPromptService aiPromptService,
  }) async {
    final controller = _buildChatSessionController(
      context: context,
      container: ProviderScope.containerOf(context, listen: false),
      state: state,
      availableSubAgents: availableSubAgents,
      aiPromptService: aiPromptService,
      promptContext: promptContext,
      promptBuilder: promptBuilder,
    );
    await controller.retry(assistantMessageId);
  }

  void _cancelActiveRequest(
    BuildContext context,
    ProviderContainer container, {
    required String? runtimeSessionId,
    required AiChatPanelState state,
    required List<SubAgent> availableSubAgents,
    required AiSessionContext promptContext,
    required ChatPromptBuilder promptBuilder,
    required AiPromptService aiPromptService,
  }) {
    _buildChatSessionController(
      context: context,
      container: container,
      state: state,
      availableSubAgents: availableSubAgents,
      aiPromptService: aiPromptService,
      promptContext: promptContext,
      promptBuilder: promptBuilder,
    ).cancel(runtimeSessionId);
  }

  void _clearQueuedMessage(
    BuildContext context, {
    required AiChatPanelState state,
    required List<SubAgent> availableSubAgents,
    required AiSessionContext promptContext,
    required ChatPromptBuilder promptBuilder,
    required AiPromptService aiPromptService,
  }) {
    _buildChatSessionController(
      context: context,
      container: ProviderScope.containerOf(context, listen: false),
      state: state,
      availableSubAgents: availableSubAgents,
      aiPromptService: aiPromptService,
      promptContext: promptContext,
      promptBuilder: promptBuilder,
    ).clearQueuedMessage(restoreToComposer: true);
  }

  Future<void> _sendQueuedMessageNow(
    BuildContext context, {
    required AiChatPanelState state,
    required List<SubAgent> availableSubAgents,
    required AiSessionContext promptContext,
    required ChatPromptBuilder promptBuilder,
    required AiPromptService aiPromptService,
  }) {
    return _buildChatSessionController(
      context: context,
      container: ProviderScope.containerOf(context, listen: false),
      state: state,
      availableSubAgents: availableSubAgents,
      aiPromptService: aiPromptService,
      promptContext: promptContext,
      promptBuilder: promptBuilder,
    ).sendQueuedMessageNow();
  }

  Future<void> _rollbackTurnAndRedraft(
    BuildContext context,
    WidgetRef ref,
    String userMessageId, {
    required AiChatPanelState state,
    required List<SubAgent> availableSubAgents,
    required AiSessionContext promptContext,
    required ChatPromptBuilder promptBuilder,
    required AiPromptService aiPromptService,
  }) async {
    final confirmed = await showAiRollbackMessageConfirmDialog(context);
    if (!confirmed || !context.mounted) {
      return;
    }
    final controller = _buildChatSessionController(
      context: context,
      container: ProviderScope.containerOf(context, listen: false),
      state: state,
      availableSubAgents: availableSubAgents,
      aiPromptService: aiPromptService,
      promptContext: promptContext,
      promptBuilder: promptBuilder,
    );
    final prompt = await controller.rollbackTurnAndPrepareResend(userMessageId);
    if (prompt != null) {
      // 写入时刻才 append：若用户正在组词而被延后，要基于组词上屏后的内容拼接。
      writeControllerTextAfterComposing(
        state.composerController,
        (currentText) => currentText.isEmpty ? prompt : '$currentText\n$prompt',
      );
      state.composerFocusNode.requestFocus();
    }
  }
}
