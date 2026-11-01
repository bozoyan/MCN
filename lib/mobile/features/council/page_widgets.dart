// 职责: 移动端圆桌会议页的页面级组件 — 会话模型选择条、开始栏、讨论中状态栏与空闲时的插话/追加轮次/转写作操作栏；发言卡片与时间线来自 shared。
// 关联文件:
//   lib/mobile/features/council/page.dart
//   lib/mobile/features/council/page_sections.dart
//   lib/mobile/widgets/model_selector.dart
//   lib/shared/hooks/use_council_run.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/council.json
//   assets/translations/zh-CN/council.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
//   assets/translations/en/ai.json
//   assets/translations/zh-CN/ai.json
part of 'page.dart';

Widget _sessionModelSelector(AiModeModelSelection models) {
  return Builder(
    builder: (context) {
      final selector = MobileModelSelector.bar(
        models: [
          for (final m in models.availableModels)
            if (m.kind == AiModelKind.chat) m,
        ],
        selectedId: models.displayed?.id,
        selectedEffort: models.selectedEffort,
        disabledModelIds: const <String>{},

        onSelectModel: models.select,
        onSelectEffort: models.selectWithEffort,
      );
      return selector;
    },
  );
}

/// 通用可点选择行：图标 + 标签 + chevron，用于模型选择展示。
class _PickerRow extends StatelessWidget {
  const _PickerRow({
    required this.colors,
    required this.typo,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final RevericColors colors;
  final RevericTypography typo;
  final String icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(RevericRadius.large),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(RevericRadius.large),
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: RevericSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(RevericRadius.large),
            border: Border.all(color: colors.borderInput),
          ),
          child: Row(
            children: [
              RevericIcon(icon, size: 17, color: colors.accent),
              const SizedBox(width: RevericSpacing.sm),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: typo.ui.copyWith(color: colors.textPrimary),
                ),
              ),
              RevericIcon(
                RevericIcons.expand_more,
                size: 18,
                color: colors.textSubtle,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Setup 底部固定栏：模型选择 + 开始讨论按钮。
class _CouncilStartBar extends StatelessWidget {
  const _CouncilStartBar({
    required this.isRunning,
    required this.isEnabled,
    required this.modelSelector,
    required this.onStart,
  });

  final bool isRunning;
  final bool isEnabled;
  final Widget modelSelector;
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
            modelSelector,
            const SizedBox(height: RevericSpacing.md),
            FilledButton.icon(
              onPressed: isEnabled ? onStart : null,
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
                      RevericIcons.groups_rounded,
                      size: 18,
                      color: colors.onAccent,
                    ),
              label: Text(
                isRunning
                    ? context.t(LocaleKeys.councilDiscussing)
                    : context.t(LocaleKeys.councilStart),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 讨论进行中的底部状态栏：进度文案 + 暂停 / 取消。
class _CouncilActiveBar extends StatelessWidget {
  const _CouncilActiveBar({
    required this.run,
    required this.session,
    required this.speaker,
    required this.modelSelector,
    required this.onPause,
    required this.onCancel,
  });

  final CouncilRun run;
  final AgentCouncilSession session;
  final String? speaker;
  final Widget modelSelector;
  final VoidCallback onPause;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final speaker = this.speaker;
    final label = session.phase == CouncilPhase.summarizing
        ? context.t(LocaleKeys.councilSummarizingState)
        : speaker != null
        ? context.t(LocaleKeys.councilSpeakingFmt, namedArgs: {'name': speaker})
        : context.t(LocaleKeys.councilDiscussionInProgress);
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
            // 讨论中也能插话，排到下一位成员发言前。
            _InterjectionInput(run: run),
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

/// 讨论空闲时的底部输入栏：插话输入 + 追加轮次 + 切换写作模式。
class _CouncilComposerBar extends StatelessWidget {
  const _CouncilComposerBar({
    required this.run,
    required this.canUpdateSummary,
    required this.modelSelector,
    this.onSwitchToWriteMode,
  });

  final CouncilRun run;
  final bool canUpdateSummary;
  final Widget modelSelector;
  final Future<void> Function()? onSwitchToWriteMode;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final switchToWrite = onSwitchToWriteMode;
    final isRunning = run.isRunning;
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
            _InterjectionInput(run: run),
            const SizedBox(height: RevericSpacing.sm),
            if (canUpdateSummary) ...[
              OutlinedButton.icon(
                onPressed: isRunning ? null : run.updateSummary,
                icon: RevericIcon(RevericIcons.summarize_rounded, size: 16),
                label: Text(context.t(LocaleKeys.councilUpdateSummary)),
              ),
              const SizedBox(height: RevericSpacing.sm),
            ],
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: isRunning ? null : run.addRound,
                    icon: RevericIcon(RevericIcons.add_rounded, size: 16),
                    label: Text(context.t(LocaleKeys.councilAddRound)),
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

/// 插话输入框 + 发送按钮；空闲与讨论中共用。
class _InterjectionInput extends StatelessWidget {
  const _InterjectionInput({required this.run});

  final CouncilRun run;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final controller = run.userInputController;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            maxLines: 3,
            minLines: 1,
            style: typo.ui.copyWith(color: colors.textPrimary),
            decoration: InputDecoration(
              hintText: context.t(LocaleKeys.councilUserInputHint),
              hintStyle: typo.ui.copyWith(color: colors.textSubtle),
              filled: true,
              fillColor: colors.surfaceContainerHigh,
              border: _inputBorder(colors.borderInput),
              enabledBorder: _inputBorder(colors.borderInput),
              focusedBorder: _inputBorder(colors.accent),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: RevericSpacing.md,
                vertical: RevericSpacing.sm,
              ),
              isDense: true,
            ),
            onSubmitted: (_) => run.sendUserMessage(),
          ),
        ),
        const SizedBox(width: RevericSpacing.sm),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) {
            final hasText = value.text.trim().isNotEmpty;
            final accent = hasText ? colors.accent : colors.textSubtle;
            return IconButton(
              onPressed: hasText ? run.sendUserMessage : null,
              tooltip: context.t(LocaleKeys.commonSend),
              icon: RevericIcon(
                RevericIcons.arrow_upward_rounded,
                color: accent,
                size: 18,
              ),
              style: IconButton.styleFrom(
                backgroundColor: accent.withValues(alpha: 0.12),
              ),
            );
          },
        ),
      ],
    );
  }
}
