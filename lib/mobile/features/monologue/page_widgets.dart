// 职责: 移动端独白页的渲染组件 — 角色选择 chip、已选标记、模型选择行/开始栏、独白卡片（生成中与完成共用 AgentMessageCard）、进行中/完成底部栏。
// 关联文件:
//   lib/mobile/features/monologue/page.dart
//   lib/mobile/features/monologue/page_sections.dart
//   lib/shared/widgets/character_avatar.dart
//   lib/shared/widgets/ai/agent_message_card.dart
//   lib/shared/widgets/ai/monologue_body.dart
//   lib/shared/widgets/ai/agent_round_detail_dialog.dart
//   lib/shared/widgets/ai/user_respecting_auto_scroll_controller.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/monologue.json
//   assets/translations/zh-CN/monologue.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
//   assets/translations/en/ai.json
//   assets/translations/zh-CN/ai.json
part of 'page.dart';

/// 已选角色标记 chip。
class _SelectedChip extends StatelessWidget {
  const _SelectedChip({
    required this.label,
    required this.accentColor,
    required this.colors,
    required this.typo,
  });

  final String label;
  final Color accentColor;
  final RevericColors colors;
  final RevericTypography typo;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: RevericSpacing.sm,
        vertical: RevericSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(RevericRadius.pill),
        border: Border.all(color: accentColor.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: typo.uiTiny.copyWith(
          color: accentColor,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Setup 底部固定栏：模型选择 + 开始独白按钮。
class _MonologueStartBar extends StatelessWidget {
  const _MonologueStartBar({
    required this.isRunning,
    required this.canStart,
    required this.availableModels,
    required this.displayedModel,
    required this.selectedEffort,
    required this.disabledModelIds,
    required this.onSelectModel,
    required this.onSelectEffort,
    required this.onStart,
  });

  final bool isRunning;
  final bool canStart;
  final List<AiModelOption> availableModels;
  final AiModelOption? displayedModel;
  final String? selectedEffort;
  final Set<String> disabledModelIds;
  final ValueChanged<AiModelOption> onSelectModel;
  final void Function(AiModelOption, String) onSelectEffort;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);

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
            MobileModelSelector.bar(
              models: availableModels,
              selectedId: displayedModel?.id,
              selectedEffort: selectedEffort,
              disabledModelIds: disabledModelIds,

              onSelectModel: onSelectModel,
              onSelectEffort: onSelectEffort,
            ),
            const SizedBox(height: RevericSpacing.md),
            FilledButton.icon(
              onPressed: canStart ? onStart : null,
              icon: isRunning
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colors.onAccent,
                      ),
                    )
                  : RevericIcon(
                      RevericIcons.person_rounded,
                      size: 18,
                      color: colors.onAccent,
                    ),
              label: Text(
                isRunning
                    ? context.t(LocaleKeys.monologueGenerating)
                    : context.t(LocaleKeys.monologueStart),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 独白列表：逐条渲染已生成独白，生成中时末尾挂同款卡片。
class _MonologueList extends StatefulWidget {
  const _MonologueList({
    required this.session,
    required this.activeRun,
    required this.runHistory,
    required this.colors,
    required this.typo,
    required this.onOpenActiveRunDetail,
  });

  final MonologueSession session;
  final AgentRunState? activeRun;
  final Map<String, AgentRunState> runHistory;
  final RevericColors colors;
  final RevericTypography typo;
  final Future<void> Function(String title) onOpenActiveRunDetail;

  @override
  State<_MonologueList> createState() => _MonologueListState();
}

class _MonologueListState extends State<_MonologueList> {
  final _autoScroll = UserRespectingAutoScrollController();

  @override
  void didUpdateWidget(covariant _MonologueList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.id != widget.session.id) {
      _autoScroll.resumeFollow();
    }
    // 用户点「生成」→ 恢复跟随。phase 在整段生成期间保持 generating，
    // 不会在流式过程中反复触发。
    if (!oldWidget.session.isActive && widget.session.isActive) {
      _autoScroll.resumeFollow();
    }
    final countChanged =
        oldWidget.session.monologues.length != widget.session.monologues.length;
    final streamingChanged =
        oldWidget.activeRun?.accumulatedText !=
            widget.activeRun?.accumulatedText ||
        oldWidget.activeRun?.blocks.length != widget.activeRun?.blocks.length ||
        (oldWidget.activeRun == null) != (widget.activeRun == null);
    final errorChanged = oldWidget.session.failure != widget.session.failure;
    if (countChanged || streamingChanged || errorChanged) {
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
    final run = widget.activeRun;
    final character = widget.session.character;
    final children = <Widget>[
      for (final monologue in widget.session.monologues)
        _MonologueCard(
          monologue: monologue,
          character: character,
          completedRun: widget.runHistory[monologue.id],
          colors: widget.colors,
        ),
      // 生成中但还没收到首个 delta 时也是同一张卡片（跳动三点），不另起占位组件。
      if (run != null || widget.session.phase == MonologuePhase.generating)
        _MonologueMessageCard(
          character: character,
          colors: widget.colors,
          thinking: run?.accumulatedThinking ?? '',
          streaming: true,
          onOpenDetail: run == null
              ? null
              : () => widget.onOpenActiveRunDetail(character.name),
          body: run == null
              ? null
              : MonologueBody.streaming(
                  run.accumulatedText,
                  AgentMessageDensity.mobile,
                ),
        ),
    ];

    final failure = widget.session.failure;
    if (widget.session.phase == MonologuePhase.error && failure != null) {
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

/// 独白卡片外壳：生成中与生成完成共用，避免完成瞬间排版跳变。
class _MonologueMessageCard extends StatelessWidget {
  const _MonologueMessageCard({
    required this.character,
    required this.colors,
    required this.thinking,
    required this.body,
    this.streaming = false,
    this.onOpenDetail,
  });

  final MonologueParticipant character;
  final RevericColors colors;
  final String thinking;
  final Widget? body;
  final bool streaming;
  final VoidCallback? onOpenDetail;

  @override
  Widget build(BuildContext context) {
    return AgentMessageCard(
      avatar: CharacterAvatar(
        avatarAssetId: character.avatarAssetId,
        fallbackName: character.name,
        size: AgentMessageCard.avatarSize(AgentMessageDensity.mobile),
        backgroundColor: colors.accent.withValues(alpha: 0.15),
      ),
      name: character.name,
      accentColor: colors.accent,
      density: AgentMessageDensity.mobile,
      thinking: thinking,
      streaming: streaming,
      onOpenDetail: onOpenDetail,
      body: body,
    );
  }
}

/// 单条已完成独白。
class _MonologueCard extends StatelessWidget {
  const _MonologueCard({
    required this.monologue,
    required this.character,
    this.completedRun,
    required this.colors,
  });

  final MonologueEntry monologue;
  final MonologueParticipant character;
  final AgentRunState? completedRun;
  final RevericColors colors;

  @override
  Widget build(BuildContext context) {
    final detailRun =
        completedRun ??
        AgentRunState(
          agentId: monologue.characterId,
          agentName: monologue.characterName,
          round: 1,
          accumulatedText: [
            if (monologue.innerThoughts.isNotEmpty) monologue.innerThoughts,
            if (monologue.plannedActions.isNotEmpty) monologue.plannedActions,
          ].join('\n\n'),
          isComplete: true,
        );
    return _MonologueMessageCard(
      character: character,
      colors: colors,
      thinking: completedRun?.accumulatedThinking ?? '',
      onOpenDetail: () => AgentRoundDetailDialog.show(
        context,
        runState: detailRun,
        title: character.name,
      ),
      body: MonologueBody(
        innerThoughts: monologue.innerThoughts,
        plannedActions: monologue.plannedActions,
        density: AgentMessageDensity.mobile,
      ),
    );
  }
}

/// 生成进行中的底部状态栏：进度文案 + 暂停 / 取消。
class _MonologueActiveBar extends StatelessWidget {
  const _MonologueActiveBar({
    required this.session,
    required this.modelSelector,
    required this.onPause,
    required this.onCancel,
  });

  final MonologueSession session;
  final Widget modelSelector;
  final VoidCallback onPause;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: RevericSpacing.lg,
        vertical: RevericSpacing.md,
      ),
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
            modelSelector,
            const SizedBox(height: RevericSpacing.sm),
            Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colors.accent,
                  ),
                ),
                const SizedBox(width: RevericSpacing.sm),
                Expanded(
                  child: Text(
                    context.t(
                      LocaleKeys.monologueThinkingFmt,
                      namedArgs: {'name': session.character.name},
                    ),
                    style: typo.uiSmall.copyWith(color: colors.textMuted),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(
                  onPressed: onPause,
                  child: Text(
                    context.t(LocaleKeys.commonPause),
                    style: typo.uiSmall.copyWith(color: colors.textMuted),
                  ),
                ),
                TextButton(
                  onPressed: onCancel,
                  child: Text(
                    context.t(LocaleKeys.commonCancel),
                    style: typo.uiSmall.copyWith(color: colors.textMuted),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 生成空闲时的底部操作栏：继续独白 + 切换写作模式。
class _MonologueCompletedBar extends StatelessWidget {
  const _MonologueCompletedBar({
    required this.isRunning,
    required this.modelSelector,
    required this.onContinue,
    this.onSwitchToWriteMode,
  });

  final bool isRunning;
  final Widget modelSelector;
  final VoidCallback onContinue;
  final Future<void> Function()? onSwitchToWriteMode;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final switchToWrite = onSwitchToWriteMode;
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
            modelSelector,
            const SizedBox(height: RevericSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: isRunning ? null : onContinue,
                    icon: RevericIcon(RevericIcons.add_rounded, size: 16),
                    label: Text(context.t(LocaleKeys.monologueContinue)),
                  ),
                ),
                if (switchToWrite != null) ...[
                  const SizedBox(width: RevericSpacing.sm),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: isRunning ? null : switchToWrite,
                      icon: RevericIcon(
                        RevericIcons.edit_note_outlined,
                        size: 16,
                      ),
                      label: Text(context.t(LocaleKeys.aiSwitchToWriteMode)),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
