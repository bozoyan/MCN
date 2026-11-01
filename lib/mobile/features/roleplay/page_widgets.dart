// 职责: 移动端角色扮演页的渲染组件 — 底部输入栏（模型选择 + 切换写作 + 发送）与对话列表（生成中与完成共用 RoleplayMessageCard）。
// 关联文件:
//   lib/mobile/features/roleplay/page.dart
//   lib/mobile/features/roleplay/page_sections.dart
//   lib/shared/widgets/ai/roleplay_message_card.dart
//   lib/shared/widgets/ai/user_respecting_auto_scroll_controller.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/roleplay.json
//   assets/translations/zh-CN/roleplay.json
//   assets/translations/en/ai.json
//   assets/translations/zh-CN/ai.json
part of 'page.dart';

/// 底部输入栏：可选「切换写作模式」+ 文本框 + 模型选择 + 发送，setup 与 chat 共用。
class _RoleplayComposer extends StatelessWidget {
  const _RoleplayComposer({
    required this.run,
    required this.hintName,
    this.onSwitchToWriteMode,
  });

  final RoleplayRun run;
  final String hintName;
  final Future<void> Function()? onSwitchToWriteMode;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final switchToWrite = onSwitchToWriteMode;
    final models = run.models;
    final isSending = run.isSending;
    final isEnabled = run.canCompose;

    return Container(
      padding: const EdgeInsets.all(RevericSpacing.lg),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.borderSubtle)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: colors.surfaceDim,
                borderRadius: BorderRadius.circular(RevericRadius.x2l),
                border: Border.all(color: colors.borderInput),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: run.inputController,
                    style: typo.ui.copyWith(color: colors.textPrimary),
                    enabled: isEnabled && !isSending,
                    minLines: 1,
                    maxLines: 6,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: context.t(
                        LocaleKeys.roleplayInputHint,
                        namedArgs: {'name': hintName},
                      ),
                      hintStyle: typo.ui.copyWith(color: colors.textSubtle),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: RevericSpacing.lg,
                        vertical: RevericSpacing.md,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      RevericSpacing.sm,
                      0,
                      RevericSpacing.sm,
                      RevericSpacing.sm,
                    ),
                    child: Row(
                      children: [
                        if (switchToWrite != null) ...[
                          IconButton(
                            tooltip: context.t(LocaleKeys.aiSwitchToWriteMode),
                            onPressed: isSending ? null : () => switchToWrite(),
                            icon: RevericIcon(
                              RevericIcons.edit_note_outlined,
                              size: 20,
                              color: isSending
                                  ? colors.textSubtle
                                  : colors.textMuted,
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                        Flexible(
                          child: MobileModelSelector.pill(
                            models: models.availableModels
                                .where((m) => m.kind == AiModelKind.chat)
                                .toList(growable: false),
                            selectedId: models.displayed?.id,
                            selectedEffort: models.selectedEffort,
                            disabledModelIds: const <String>{},

                            onSelectModel: models.select,
                            onSelectEffort: models.selectWithEffort,
                          ),
                        ),
                        const Spacer(),
                        ValueListenableBuilder<TextEditingValue>(
                          valueListenable: run.inputController,
                          builder: (context, value, child) {
                            final hasDraft = value.text.trim().isNotEmpty;
                            final canSend = isEnabled && !isSending && hasDraft;
                            return IconButton(
                              onPressed: canSend ? run.send : null,
                              icon: isSending
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: colors.accent,
                                      ),
                                    )
                                  : RevericIcon(
                                      RevericIcons.arrow_upward_rounded,
                                      color: colors.accent,
                                      size: 18,
                                    ),
                              style: IconButton.styleFrom(
                                backgroundColor: colors.accent.withValues(
                                  alpha: 0.12,
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 对话消息列表：逐条渲染气泡，末尾挂流式卡片 / 打字指示，并自动滚动到底部。
class _RoleplayMessageList extends StatefulWidget {
  const _RoleplayMessageList({
    required this.session,
    required this.activeRun,
    required this.runHistory,
    required this.userAvatarPath,
    required this.userName,
    required this.onOpenActiveRunDetail,
    this.databasePath,
    this.novelId,
  });

  final RoleplaySession session;
  final AgentRunState? activeRun;
  final Map<String, AgentRunState> runHistory;
  final String userAvatarPath;
  final String userName;
  final Future<void> Function(String title) onOpenActiveRunDetail;
  final String? databasePath;
  final String? novelId;

  @override
  State<_RoleplayMessageList> createState() => _RoleplayMessageListState();
}

class _RoleplayMessageListState extends State<_RoleplayMessageList> {
  final _autoScroll = UserRespectingAutoScrollController();

  @override
  void initState() {
    super.initState();
    // 历史恢复后直接挂载完整列表，首次布局也需要贴底。
    _autoScroll.scheduleScrollToBottom();
  }

  @override
  void didUpdateWidget(covariant _RoleplayMessageList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sessionChanged = oldWidget.session.id != widget.session.id;
    if (sessionChanged) {
      _autoScroll.resumeFollow();
    }
    final countChanged =
        oldWidget.session.messages.length != widget.session.messages.length;
    // 用户自己发出的消息必须可见：即使正在回看历史也恢复跟随。
    // 依赖 countChanged 才判断，避免流式期间每个 token 都把暂停状态冲掉。
    if (countChanged &&
        widget.session.messages.isNotEmpty &&
        widget.session.messages.last.speakerId == roleplayUserSpeakerId) {
      _autoScroll.resumeFollow();
    }
    final streamingChanged =
        oldWidget.activeRun?.accumulatedText !=
            widget.activeRun?.accumulatedText ||
        oldWidget.activeRun?.blocks.length != widget.activeRun?.blocks.length ||
        (oldWidget.activeRun == null) != (widget.activeRun == null);
    final errorChanged = oldWidget.session.failure != widget.session.failure;
    if (sessionChanged || countChanged || streamingChanged || errorChanged) {
      _autoScroll.scheduleScrollToBottom(streaming: widget.activeRun != null);
    }
  }

  @override
  void dispose() {
    _autoScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final children = <Widget>[
      for (final message in session.messages)
        RoleplayMessageCard(
          message: message,
          character: session.character,
          density: AgentMessageDensity.mobile,
          userName: widget.userName,
          userAvatarPath: widget.userAvatarPath,
          completedRun: widget.runHistory[message.id],
          databasePath: widget.databasePath,
          novelId: widget.novelId,
        ),
      // 生成中但还没收到首个 delta 时也是同一张卡片（跳动三点），不另起占位组件。
      if (widget.activeRun != null || session.phase == RoleplayPhase.generating)
        RoleplayStreamingCard(
          run: widget.activeRun,
          character: session.character,
          density: AgentMessageDensity.mobile,
          onOpenDetail: () =>
              widget.onOpenActiveRunDetail(session.character.name),
        ),
    ];

    final failure = session.failure;
    if (session.phase == RoleplayPhase.error && failure != null) {
      children.add(
        AiModeErrorNotice(
          title: context.t(LocaleKeys.aiRunInterrupted),
          failure: failure,
        ),
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: _autoScroll.handleScrollNotification,
      child: ListView(
        controller: _autoScroll.scrollController,
        padding: const EdgeInsets.fromLTRB(
          RevericSpacing.lg,
          RevericSpacing.lg,
          RevericSpacing.lg,
          RevericSpacing.x2l,
        ),
        children: children,
      ),
    );
  }
}
