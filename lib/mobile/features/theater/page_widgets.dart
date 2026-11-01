// 职责: 移动端小剧场页的渲染组件 — 参演角色徽章、模型选择行/开始栏、台词卡片、流式卡片、打字指示、进行中/完成底部栏。
// 关联文件:
//   lib/mobile/features/theater/page.dart
//   lib/mobile/features/theater/page_sections.dart
//   lib/shared/widgets/character_avatar.dart
//   lib/shared/widgets/ai/thinking_card.dart
//   lib/shared/widgets/ai/agent_round_detail_dialog.dart
//   lib/shared/widgets/ai/user_respecting_auto_scroll_controller.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/theater.json
//   assets/translations/zh-CN/theater.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
//   assets/translations/en/ai.json
//   assets/translations/zh-CN/ai.json
part of 'page.dart';

/// 表演区顶部参演角色徽章。
class _TheaterParticipantBadge extends StatelessWidget {
  const _TheaterParticipantBadge({
    required this.participant,
    required this.colors,
    required this.typo,
  });

  final TheaterParticipant participant;
  final RevericColors colors;
  final RevericTypography typo;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: RevericSpacing.sm,
        vertical: RevericSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceDim,
        borderRadius: BorderRadius.circular(RevericRadius.pill),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CharacterAvatar(
            avatarAssetId: participant.avatarAssetId,
            fallbackName: participant.name,
            size: 20,
            backgroundColor: colors.accentWarm.withValues(alpha: 0.15),
          ),
          const SizedBox(width: RevericSpacing.xs),
          Text(
            participant.name,
            style: typo.uiTiny.copyWith(
              color: colors.accentWarm,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Setup 底部固定栏：模型选择 + 开始表演按钮。
class _TheaterStartBar extends StatelessWidget {
  const _TheaterStartBar({
    required this.isRunning,
    required this.isEnabled,
    required this.availableModels,
    required this.displayedModel,
    required this.selectedEffort,
    required this.disabledModelIds,
    required this.onSelectModel,
    required this.onSelectEffort,
    required this.onStart,
  });

  final bool isRunning;
  final bool isEnabled;
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
              onPressed: isRunning || !isEnabled ? null : onStart,
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
                      RevericIcons.theater_comedy_rounded,
                      size: 18,
                      color: colors.onAccent,
                    ),
              label: Text(
                isRunning
                    ? context.t(LocaleKeys.theaterPerforming)
                    : context.t(LocaleKeys.theaterStart),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 小剧场台词列表：逐条渲染已生成台词，末尾挂流式卡片 / 打字指示。
class _TheaterLineList extends StatefulWidget {
  const _TheaterLineList({
    required this.session,
    required this.activeRun,
    required this.runHistory,
    required this.colors,
    required this.typo,
    required this.onOpenActiveRunDetail,
    this.databasePath,
    this.novelId,
    this.onRegenerate,
    this.onRewindAfter,
    this.onRemoveDirection,
  });

  final TheaterSession session;
  final AgentRunState? activeRun;
  final Map<String, AgentRunState> runHistory;
  final RevericColors colors;
  final RevericTypography typo;
  final Future<void> Function(String title) onOpenActiveRunDetail;
  final String? databasePath;
  final String? novelId;

  /// 改写历史的操作；表演进行中为 null。
  final void Function(TheaterLine line)? onRegenerate;
  final void Function(String lineId)? onRewindAfter;
  final void Function(String lineId)? onRemoveDirection;

  @override
  State<_TheaterLineList> createState() => _TheaterLineListState();
}

class _TheaterLineListState extends State<_TheaterLineList> {
  final _autoScroll = UserRespectingAutoScrollController();

  @override
  void didUpdateWidget(covariant _TheaterLineList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.id != widget.session.id) {
      _autoScroll.resumeFollow();
    }
    // 用户点「开演」→ 恢复跟随。phase 在整场演出期间保持 performing，
    // 不会在逐条台词生成时反复触发。
    if (!oldWidget.session.isActive && widget.session.isActive) {
      _autoScroll.resumeFollow();
    }
    final countChanged =
        oldWidget.session.lines.length != widget.session.lines.length;
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
    final lines = widget.session.lines;
    final removeDirection = widget.onRemoveDirection;
    final regenerate = widget.onRegenerate;
    final rewindAfter = widget.onRewindAfter;

    final children = <Widget>[];
    for (final (index, line) in lines.indexed) {
      if (line.isDirection) {
        children.add(
          TheaterDirectionNote(
            line: line,
            onRemove: removeDirection == null
                ? null
                : () => removeDirection(line.id),
          ),
        );
        continue;
      }
      final participant = widget.session.participants.firstWhere(
        (p) => p.characterId == line.characterId,
        orElse: () => TheaterParticipant(
          characterId: line.characterId,
          name: line.characterName,
          role: '',
          biography: '',
        ),
      );
      children.add(
        _TheaterLineCard(
          line: line,
          participant: participant,
          completedRun: widget.runHistory[line.id],
          colors: widget.colors,
          typo: widget.typo,
          databasePath: widget.databasePath,
          novelId: widget.novelId,
          onRegenerate: regenerate == null ? null : () => regenerate(line),
          onRewindAfter: rewindAfter == null || index == lines.length - 1
              ? null
              : () => rewindAfter(line.id),
        ),
      );
    }

    final run = widget.activeRun;
    if (run != null) {
      final participant = widget.session.participants.firstWhere(
        (p) => p.characterId == run.agentId,
        orElse: () => TheaterParticipant(
          characterId: run.agentId,
          name: run.agentName,
          role: '',
          biography: '',
        ),
      );
      children.add(
        _TheaterStreamingCard(
          runState: run,
          participant: participant,
          colors: widget.colors,
          typo: widget.typo,
          onOpenDetail: () => widget.onOpenActiveRunDetail(participant.name),
        ),
      );
    }

    final failure = widget.session.failure;
    if (widget.session.phase == TheaterPhase.error && failure != null) {
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

/// 单条已完成台词：与生成中的 [_TheaterStreamingCard] 共用同一张卡片外观。
class _TheaterLineCard extends StatelessWidget {
  const _TheaterLineCard({
    required this.line,
    required this.participant,
    this.completedRun,
    required this.colors,
    required this.typo,
    this.databasePath,
    this.novelId,
    this.onRegenerate,
    this.onRewindAfter,
  });

  final TheaterLine line;
  final TheaterParticipant participant;
  final AgentRunState? completedRun;
  final RevericColors colors;
  final RevericTypography typo;
  final String? databasePath;
  final String? novelId;

  /// 改写历史的菜单项；为 null 时不显示对应项（表演中全部为 null）。
  final VoidCallback? onRegenerate;
  final VoidCallback? onRewindAfter;

  @override
  Widget build(BuildContext context) {
    final detailRun =
        completedRun ??
        AgentRunState(
          agentId: line.characterId,
          agentName: line.characterName,
          round: line.turn,
          accumulatedText: [
            if (line.stageDirection != null && line.stageDirection!.isNotEmpty)
              '（${line.stageDirection}）',
            '「${line.dialogue}」',
          ].join('\n'),
          isComplete: true,
        );
    final menu = AgentMessageMenu(
      onRegenerate: onRegenerate,
      regenerateLabel: context.t(LocaleKeys.theaterLineRegenerate),
      onRewindAfter: onRewindAfter,
    );
    return AgentMessageCard(
      avatar: _theaterAvatar(participant, colors),
      name: participant.name,
      accentColor: colors.accentWarm,
      density: AgentMessageDensity.mobile,
      meta: '${context.t(LocaleKeys.theaterTurn)} ${line.turn}',
      thinking: completedRun?.accumulatedThinking ?? '',
      onOpenDetail: () => AgentRoundDetailDialog.show(
        context,
        runState: detailRun,
        title: participant.name,
        databasePath: databasePath,
        novelId: novelId,
      ),
      trailing: menu.hasEntries ? menu : null,
      body: TheaterLineBody(
        dialogue: line.dialogue,
        stageDirection: line.stageDirection,
        density: AgentMessageDensity.mobile,
      ),
    );
  }
}

/// 正在生成的台词：正文边收边解析，还没出字时显示跳动三点。
class _TheaterStreamingCard extends StatelessWidget {
  const _TheaterStreamingCard({
    required this.runState,
    required this.participant,
    required this.colors,
    required this.typo,
    required this.onOpenDetail,
  });

  final AgentRunState runState;
  final TheaterParticipant participant;
  final RevericColors colors;
  final RevericTypography typo;
  final VoidCallback onOpenDetail;

  @override
  Widget build(BuildContext context) {
    return AgentMessageCard(
      avatar: _theaterAvatar(participant, colors),
      name: participant.name,
      accentColor: colors.accentWarm,
      density: AgentMessageDensity.mobile,
      meta: runState.round > 0
          ? '${context.t(LocaleKeys.theaterTurn)} ${runState.round}'
          : null,
      thinking: runState.accumulatedThinking,
      streaming: true,
      onOpenDetail: onOpenDetail,
      body: TheaterLineBody.streaming(
        runState.accumulatedText,
        AgentMessageDensity.mobile,
      ),
    );
  }
}

Widget _theaterAvatar(TheaterParticipant participant, RevericColors colors) {
  return CharacterAvatar(
    avatarAssetId: participant.avatarAssetId,
    fallbackName: participant.name,
    size: AgentMessageCard.avatarSize(AgentMessageDensity.mobile),
    backgroundColor: colors.accentWarm.withValues(alpha: 0.15),
  );
}

/// 表演进行中的底部状态栏：进度文案 + 暂停 / 取消。
class _TheaterActiveBar extends StatelessWidget {
  const _TheaterActiveBar({
    required this.session,
    required this.activeRun,
    required this.directorBar,
    required this.modelSelector,
    required this.onPause,
    required this.onCancel,
  });

  final TheaterSession session;
  final AgentRunState? activeRun;
  final Widget directorBar;
  final Widget modelSelector;
  final VoidCallback onPause;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final label = activeRun != null
        ? context.t(
            LocaleKeys.theaterSpeakingFmt,
            namedArgs: {'name': activeRun!.agentName},
          )
        : context.t(LocaleKeys.theaterPerforming);
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
            directorBar,
            const SizedBox(height: RevericSpacing.sm),
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
                    label,
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

/// 表演空闲时的底部操作栏：导演栏 + 追加一轮 + 转到写作（写成正文或只带剧本）。
class _TheaterCompletedBar extends StatelessWidget {
  const _TheaterCompletedBar({
    required this.isRunning,
    required this.directorBar,
    required this.modelSelector,
    required this.session,
    required this.onContinue,
    this.onSwitchToWriteMode,
  });

  final bool isRunning;
  final TheaterSession session;
  final Widget directorBar;
  final Widget modelSelector;
  final VoidCallback onContinue;
  final Future<void> Function(String? instruction)? onSwitchToWriteMode;

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
            directorBar,
            const SizedBox(height: RevericSpacing.sm),
            modelSelector,
            const SizedBox(height: RevericSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: isRunning ? null : onContinue,
                    icon: RevericIcon(RevericIcons.add_rounded, size: 16),
                    label: Text(context.t(LocaleKeys.theaterAddRound)),
                  ),
                ),
                if (switchToWrite != null) ...[
                  const SizedBox(width: RevericSpacing.sm),
                  Expanded(
                    child: TheaterWriteButton(
                      session: session,
                      onWrite: isRunning ? null : switchToWrite,
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
