// 职责: 移动端圆桌会议页的视图分区 — 未配置提示、Setup 配置区、Discussion 讨论区，及参会者编辑/模型选择底部弹窗。
// 关联文件:
//   lib/mobile/features/council/page.dart
//   lib/mobile/features/council/page_widgets.dart
//   lib/shared/hooks/use_council_run.dart
//   lib/shared/widgets/ai/council/timeline.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/council.json
//   assets/translations/zh-CN/council.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
part of 'page.dart';

String? _councilPhaseSubtitle(
  BuildContext context,
  AgentCouncilSession? session,
) {
  if (session == null) {
    return null;
  }
  return switch (session.phase) {
    CouncilPhase.idle => context.t(LocaleKeys.councilPhasePreparing),
    CouncilPhase.discussing => context.t(
      LocaleKeys.councilPhaseDiscussingFmt,
      namedArgs: {
        'round': '${session.rounds.length}',
        'count': '${session.participants.length}',
      },
    ),
    CouncilPhase.summarizing => context.t(LocaleKeys.councilPhaseSummarizing),
    CouncilPhase.completed => context.t(
      LocaleKeys.councilPhaseCompletedFmt,
      namedArgs: {'count': '${session.rounds.length}'},
    ),
    CouncilPhase.cancelled => context.t(LocaleKeys.councilPhaseCancelled),
    CouncilPhase.error => context.t(LocaleKeys.councilPhaseError),
  };
}

extension _MobileCouncilPageSections on MobileCouncilPage {
  Widget _buildConfigHint(
    BuildContext context,
    RevericColors colors,
    RevericTypography typo,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(RevericSpacing.x3l),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            RevericIcon(
              RevericIcons.psychology_outlined,
              size: 48,
              color: colors.textMuted,
            ),
            const SizedBox(height: RevericSpacing.x2l),
            Text(
              context.t(LocaleKeys.aiNotConfigured),
              style: typo.uiSemibold.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: RevericSpacing.sm),
            Text(
              context.t(LocaleKeys.aiPleaseConfigure),
              textAlign: TextAlign.center,
              style: typo.uiSmall.copyWith(color: colors.textMuted),
            ),
            const SizedBox(height: RevericSpacing.x2l),
            RevericButton.primary(
              label: context.t(LocaleKeys.aiConfigureProvider),
              icon: RevericIcons.settings_outlined,
              onPressed: () => openMobileAiProvidersSettingsPage(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSetup(
    BuildContext context,
    RevericColors colors,
    RevericTypography typo, {
    required CouncilRun run,
  }) {
    final participants = run.participants;
    final models = run.models;
    final t = context.t;
    final selected = run.selectedParticipantIds;
    final selectedCount = selected.length;
    final totalCount = participants.length;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(RevericSpacing.x2l),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _setupSection(
                  colors: colors,
                  typo: typo,
                  icon: RevericIcons.edit_note_outlined,
                  accentColor: colors.accent,
                  title: t(LocaleKeys.councilTopic),
                  child: TextField(
                    controller: run.topicController,
                    maxLines: 4,
                    minLines: 2,
                    style: typo.ui.copyWith(color: colors.textPrimary),
                    decoration: InputDecoration(
                      hintText: t(LocaleKeys.councilTopicHint),
                      hintStyle: typo.ui.copyWith(color: colors.textSubtle),
                      filled: true,
                      fillColor: colors.surface,
                      border: _inputBorder(colors.borderInput),
                      enabledBorder: _inputBorder(colors.borderInput),
                      focusedBorder: _inputBorder(colors.accent),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: RevericSpacing.lg,
                        vertical: RevericSpacing.md,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: RevericSpacing.x2l),
                _setupSection(
                  colors: colors,
                  typo: typo,
                  icon: RevericIcons.groups_outlined,
                  accentColor: colors.accentWarm,
                  title: t(LocaleKeys.councilSelectParticipants),
                  trailing: Text(
                    t(
                      LocaleKeys.councilParticipantsCountFmt,
                      namedArgs: {
                        'selected': '$selectedCount',
                        'total': '$totalCount',
                      },
                    ),
                    style: typo.uiTiny.copyWith(color: colors.textMuted),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          TextButton(
                            onPressed: selectedCount == totalCount
                                ? null
                                : () => run.setSelectedParticipants({
                                    for (final p in participants) p.id,
                                  }),
                            style: _compactTextButton(),
                            child: Text(
                              t(LocaleKeys.commonSelectAll),
                              style: typo.uiTiny.copyWith(color: colors.accent),
                            ),
                          ),
                          TextButton(
                            onPressed: selectedCount == 0
                                ? null
                                : () => run.setSelectedParticipants(const {}),
                            style: _compactTextButton(),
                            child: Text(
                              t(LocaleKeys.commonClearSelection),
                              style: typo.uiTiny.copyWith(
                                color: colors.textMuted,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: RevericSpacing.sm),
                      Wrap(
                        spacing: RevericSpacing.sm,
                        runSpacing: RevericSpacing.sm,
                        children: [
                          for (final participant in participants)
                            CouncilParticipantChip(
                              participant: participant,
                              isSelected: selected.contains(participant.id),
                              density: AgentMessageDensity.mobile,
                              onToggle: () =>
                                  run.toggleParticipant(participant.id),
                              onEdit: () => _showParticipantEditSheet(
                                context,
                                run: run,
                                participant: participant,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: RevericSpacing.x2l),
                _setupSection(
                  colors: colors,
                  typo: typo,
                  icon: RevericIcons.history_rounded,
                  accentColor: colors.accentAmber,
                  title: t(LocaleKeys.councilDiscussionRounds),
                  trailing: Text(
                    '${run.config.maxRounds}',
                    style: typo.uiSemibold.copyWith(color: colors.accentAmber),
                  ),
                  child: Slider(
                    value: run.config.maxRounds.toDouble(),
                    min: 1,
                    max: 5,
                    divisions: 4,
                    label: run.config.maxRounds.toString(),
                    onChanged: (value) => run.setMaxRounds(value.toInt()),
                  ),
                ),
              ],
            ),
          ),
        ),
        _CouncilStartBar(
          isRunning: run.isRunning,
          isEnabled: run.canStart,
          modelSelector: _sessionModelSelector(models),
          onStart: run.start,
        ),
      ],
    );
  }

  Widget _setupSection({
    required RevericColors colors,
    required RevericTypography typo,
    required String icon,
    required Color accentColor,
    required String title,
    Widget? trailing,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            RevericIcon(icon, size: 14, color: accentColor),
            const SizedBox(width: RevericSpacing.xs),
            Text(
              title,
              style: typo.uiSemibold.copyWith(color: colors.textPrimary),
            ),
            if (trailing != null) ...[const Spacer(), trailing],
          ],
        ),
        const SizedBox(height: RevericSpacing.sm),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(RevericSpacing.lg),
          decoration: BoxDecoration(
            color: colors.surfaceDim,
            borderRadius: BorderRadius.circular(RevericRadius.x2l),
          ),
          child: child,
        ),
      ],
    );
  }

  Widget _buildDiscussion(
    BuildContext context,
    RevericColors colors,
    RevericTypography typo, {
    required CouncilRun run,
    required AgentCouncilSession session,
    required void Function(String title) onOpenActiveRunDetail,
    Future<void> Function()? onSwitchToWriteMode,
  }) {
    final modelSelector = _sessionModelSelector(run.models);
    // 只有空闲时能点名或改写历史。
    final idle = !session.isActive && !run.isRunning;
    // 议题可能很长：header 是 Column 的固定 child，必须给议题文本限高，
    // 否则长议题会把 Expanded 消息列表压到 0 高度，无法滚动查看讨论内容。
    // LayoutBuilder 必须包在 Column 外层：Column 给非 flex 子节点的高度约束
    // 无界（maxHeight = infinity），包在里面算出的比例限高不会生效。
    return LayoutBuilder(
      builder: (context, constraints) {
        final topicMaxHeight = constraints.maxHeight * 0.3;
        return Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(
                RevericSpacing.x2l,
                RevericSpacing.lg,
                RevericSpacing.x2l,
                RevericSpacing.lg,
              ),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: colors.borderSubtle)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.t(LocaleKeys.councilTopic),
                    style: typo.uiTiny.copyWith(color: colors.textMuted),
                  ),
                  const SizedBox(height: RevericSpacing.xs),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: topicMaxHeight),
                    // Column 的 start 对齐给的是宽松宽度，滚动视口会缩到最长行
                    // 宽，滚动条悬浮在文字中间；必须显式撑满宽度。
                    // shrinkWrap 让短议题按内容收缩，不会始终占满上限高度。
                    child: SizedBox(
                      width: double.infinity,
                      child: ListView(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        children: [
                          Text(
                            session.topic,
                            style: typo.body.copyWith(
                              color: colors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: RevericSpacing.md),
                  Wrap(
                    spacing: RevericSpacing.sm,
                    runSpacing: RevericSpacing.sm,
                    children: [
                      for (final participant in session.participants)
                        CouncilParticipantBadge(
                          participant: participant,
                          onTap: idle ? () => run.speak(participant.id) : null,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: CouncilTimeline(
                session: session,
                activeRun: run.activeRun,
                runHistory: run.runHistory,
                queuedMessageIds: run.queuedMessageIds,
                density: AgentMessageDensity.mobile,
                onOpenActiveRunDetail: onOpenActiveRunDetail,
                databasePath: databasePath,
                novelId: novelId,
                onRegenerate: idle ? run.regenerate : null,
                onRewindAfter: idle ? run.rewindAfter : null,
                onRemove: idle ? run.removeMessage : null,
              ),
            ),
            if (session.isActive)
              _CouncilActiveBar(
                run: run,
                session: session,
                speaker: run.activeRun?.agentName,
                modelSelector: modelSelector,
                onPause: run.pause,
                onCancel: run.cancel,
              )
            else
              _CouncilComposerBar(
                run: run,
                canUpdateSummary: session.canUpdateSummary,
                modelSelector: modelSelector,
                onSwitchToWriteMode: onSwitchToWriteMode,
              ),
          ],
        );
      },
    );
  }

  Future<void> _showParticipantEditSheet(
    BuildContext context, {
    required CouncilRun run,
    required CouncilParticipant participant,
  }) async {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final t = context.t;
    final models = run.models;
    final disabledModelIds = const <String>{};

    final chatModels = [
      for (final m in models.availableModels)
        if (m.kind == AiModelKind.chat) m,
    ];

    final nameController = TextEditingController(
      text: participant.resolveName(t),
    );
    final promptController = TextEditingController(
      text: participant.resolvePrompt(t),
    );
    final selectedModelId = ValueNotifier<String?>(
      disabledModelIds.contains(participant.modelOptionId)
          ? null
          : participant.modelOptionId,
    );

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: colors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(RevericRadius.x2l),
        ),
      ),
      builder: (sheetContext) {
        final viewInsets = MediaQuery.of(sheetContext).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: viewInsets),
          child: SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(sheetContext).size.height * 0.85,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      RevericSpacing.lg,
                      RevericSpacing.lg,
                      RevericSpacing.lg,
                      RevericSpacing.sm,
                    ),
                    child: Row(
                      children: [
                        AgentAvatar(
                          avatarPath: participant.avatarPath,
                          slug: participant.id,
                          avatarEmoji: participant.avatarEmoji,
                          size: 24,
                        ),
                        const SizedBox(width: RevericSpacing.sm),
                        Expanded(
                          child: Text(
                            t(LocaleKeys.commonEdit),
                            style: typo.uiSemibold.copyWith(
                              color: colors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(
                        RevericSpacing.lg,
                        0,
                        RevericSpacing.lg,
                        RevericSpacing.lg,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t(LocaleKeys.councilParticipantNameLabel),
                            style: typo.uiSmall.copyWith(
                              color: colors.textMuted,
                            ),
                          ),
                          const SizedBox(height: RevericSpacing.xs),
                          TextField(
                            controller: nameController,
                            style: typo.ui.copyWith(color: colors.textPrimary),
                            decoration: _sheetFieldDecoration(colors),
                          ),
                          const SizedBox(height: RevericSpacing.lg),
                          Text(
                            t(LocaleKeys.councilParticipantPromptLabel),
                            style: typo.uiSmall.copyWith(
                              color: colors.textMuted,
                            ),
                          ),
                          const SizedBox(height: RevericSpacing.xs),
                          TextField(
                            controller: promptController,
                            maxLines: 8,
                            minLines: 4,
                            style: typo.ui.copyWith(color: colors.textPrimary),
                            decoration: _sheetFieldDecoration(colors),
                          ),
                          const SizedBox(height: RevericSpacing.lg),
                          Text(
                            t(LocaleKeys.councilCustomModel),
                            style: typo.uiSmall.copyWith(
                              color: colors.textMuted,
                            ),
                          ),
                          const SizedBox(height: RevericSpacing.xs),
                          ValueListenableBuilder<String?>(
                            valueListenable: selectedModelId,
                            builder: (context, current, _) {
                              final option = chatModels
                                  .where((m) => m.id == current)
                                  .firstOrNull;
                              return _PickerRow(
                                colors: colors,
                                typo: typo,
                                icon: RevericIcons.psychology_outlined,
                                label:
                                    option?.displayModelName ??
                                    t(LocaleKeys.councilDefaultModel),
                                onTap: () => _showParticipantModelPicker(
                                  sheetContext,
                                  chatModels: chatModels,
                                  current: current,
                                  disabledModelIds: disabledModelIds,
                                  onSelect: (id) => selectedModelId.value = id,
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(RevericSpacing.lg),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () =>
                                Navigator.of(sheetContext).maybePop(),
                            child: Text(t(LocaleKeys.commonCancel)),
                          ),
                        ),
                        const SizedBox(width: RevericSpacing.sm),
                        Expanded(
                          child: FilledButton(
                            onPressed: () async {
                              final newName = nameController.text.trim();
                              final newPrompt = promptController.text.trim();
                              await run.updateParticipant(
                                participant.copyWith(
                                  name: newName.isNotEmpty
                                      ? newName
                                      : participant.name,
                                  prompt: newPrompt.isNotEmpty
                                      ? newPrompt
                                      : participant.prompt,
                                  modelOptionId: selectedModelId.value,
                                  clearModelOptionId:
                                      selectedModelId.value == null,
                                ),
                              );
                              if (sheetContext.mounted) {
                                Navigator.of(sheetContext).maybePop();
                              }
                            },
                            child: Text(t(LocaleKeys.commonSave)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    nameController.dispose();
    promptController.dispose();
    selectedModelId.dispose();
  }

  Future<void> _showParticipantModelPicker(
    BuildContext context, {
    required List<AiModelOption> chatModels,
    required String? current,
    required Set<String> disabledModelIds,
    required ValueChanged<String?> onSelect,
  }) async {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: colors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(RevericRadius.x2l),
        ),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetContext).size.height * 0.7,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.all(RevericSpacing.lg),
                  child: Text(
                    sheetContext.t(LocaleKeys.councilCustomModel),
                    style: typo.uiSemibold.copyWith(color: colors.textPrimary),
                  ),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      ListTile(
                        title: Text(
                          sheetContext.t(LocaleKeys.councilDefaultModel),
                          style: typo.body.copyWith(color: colors.textPrimary),
                        ),
                        trailing: current == null
                            ? RevericIcon(
                                RevericIcons.check,
                                size: 18,
                                color: colors.accent,
                              )
                            : null,
                        onTap: () {
                          onSelect(null);
                          Navigator.of(sheetContext).maybePop();
                        },
                      ),
                      for (final option in chatModels)
                        Builder(
                          builder: (context) {
                            final disabled = disabledModelIds.contains(
                              option.id,
                            );
                            return ListTile(
                              enabled: !disabled,
                              title: Text(
                                option.displayModelName,
                                style: typo.body.copyWith(
                                  color: disabled
                                      ? colors.textSubtle
                                      : colors.textPrimary,
                                ),
                              ),
                              subtitle: Text(
                                option.providerDisplayName,
                                style: typo.uiSmall.copyWith(
                                  color: colors.textMuted,
                                ),
                              ),
                              trailing: option.id == current
                                  ? RevericIcon(
                                      RevericIcons.check,
                                      size: 18,
                                      color: colors.accent,
                                    )
                                  : null,
                              onTap: disabled
                                  ? null
                                  : () {
                                      onSelect(option.id);
                                      Navigator.of(sheetContext).maybePop();
                                    },
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

InputBorder _inputBorder(Color color) => OutlineInputBorder(
  borderRadius: BorderRadius.circular(RevericRadius.xl),
  borderSide: BorderSide(color: color),
);

InputDecoration _sheetFieldDecoration(RevericColors colors) => InputDecoration(
  filled: true,
  fillColor: colors.surfaceDim,
  border: _inputBorder(colors.borderInput),
  enabledBorder: _inputBorder(colors.borderInput),
  focusedBorder: _inputBorder(colors.accent),
  contentPadding: const EdgeInsets.symmetric(
    horizontal: RevericSpacing.lg,
    vertical: RevericSpacing.md,
  ),
);

ButtonStyle _compactTextButton() => TextButton.styleFrom(
  visualDensity: VisualDensity.compact,
  padding: const EdgeInsets.symmetric(horizontal: RevericSpacing.sm),
  minimumSize: Size.zero,
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
);
