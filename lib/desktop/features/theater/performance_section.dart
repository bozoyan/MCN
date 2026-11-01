// 职责: 桌面端小剧场表演区 — 场景头、台词流与导演栏，以及表演中（暂停/取消）与表演后（加一轮/转写作）的底栏。
// 关联文件:
//   lib/desktop/features/theater/panel.dart
//   lib/desktop/features/theater/line_list.dart
//   lib/shared/hooks/use_theater_run.dart
import 'package:flutter/material.dart';

import '../../../shared/hooks/use_theater_run.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/models/theater_models.dart';
import '../../../shared/theme/theme.dart';
import '../../../shared/widgets/ai/theater_director_bar.dart';
import '../../../shared/widgets/ai/theater_write_button.dart';
import 'line_list.dart';

class TheaterPerformanceSection extends StatelessWidget {
  const TheaterPerformanceSection({
    super.key,
    required this.run,
    required this.session,
    required this.modelSelector,
    required this.onOpenActiveRunDetail,
    this.onSwitchToWriteMode,
  });

  final TheaterRun run;
  final TheaterSession session;
  final Widget modelSelector;
  final Future<void> Function(String title) onOpenActiveRunDetail;
  final Future<void> Function(String? instruction)? onSwitchToWriteMode;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final isPerforming = session.phase == TheaterPhase.performing;
    final canEdit = !isPerforming && !run.isRunning;

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: RevericSpacing.x2l,
            vertical: RevericSpacing.md,
          ),
          color: colors.surface,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.t(LocaleKeys.theaterSceneDescription),
                style: typo.uiSmall.copyWith(color: colors.textMuted),
              ),
              const SizedBox(height: RevericSpacing.xxs),
              Text(
                session.sceneDescription,
                style: typo.uiSemibold.copyWith(color: colors.textPrimary),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: colors.border),
        Expanded(
          child: TheaterLineList(
            session: session,
            activeRun: run.activeRun,
            runHistory: run.runHistory,
            onOpenActiveRunDetail: onOpenActiveRunDetail,
            onRegenerate: canEdit ? run.regenerate : null,
            onRewindAfter: canEdit ? run.rewindAfter : null,
            onRemoveDirection: canEdit ? run.removeLine : null,
          ),
        ),
        _BottomBar(
          padding: isPerforming
              ? const EdgeInsets.symmetric(
                  horizontal: RevericSpacing.x2l,
                  vertical: RevericSpacing.md,
                )
              : const EdgeInsets.all(RevericSpacing.lg),
          modelSelector: modelSelector,
          directorBar: TheaterDirectorBar(run: run, session: session),
          actions: isPerforming
              ? _activeActions(context, colors, typo)
              : _completedActions(context),
        ),
      ],
    );
  }

  Widget _activeActions(
    BuildContext context,
    RevericColors colors,
    RevericTypography typo,
  ) {
    final speakerName = run.activeRun?.agentName;
    final label = speakerName != null
        ? context.t(
            LocaleKeys.theaterSpeakingFmt,
            namedArgs: {'name': speakerName},
          )
        : context.t(LocaleKeys.theaterPerforming);
    final buttonStyle = typo.uiSmall.copyWith(color: colors.textMuted);
    return Row(
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
          onPressed: run.pause,
          child: Text(context.t(LocaleKeys.commonPause), style: buttonStyle),
        ),
        TextButton(
          onPressed: run.cancel,
          child: Text(context.t(LocaleKeys.commonCancel), style: buttonStyle),
        ),
      ],
    );
  }

  Widget _completedActions(BuildContext context) {
    final switchToWriteMode = onSwitchToWriteMode;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: run.isRunning ? null : run.continueRun,
            icon: RevericIcon(RevericIcons.add_rounded, size: 16),
            label: Text(context.t(LocaleKeys.theaterAddRound)),
          ),
        ),
        const SizedBox(width: RevericSpacing.sm),
        Expanded(
          child: TheaterWriteButton(
            session: session,
            onWrite: run.isRunning || switchToWriteMode == null
                ? null
                : switchToWriteMode,
          ),
        ),
      ],
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.padding,
    required this.modelSelector,
    required this.directorBar,
    required this.actions,
  });

  final EdgeInsets padding;
  final Widget modelSelector;
  final Widget directorBar;
  final Widget actions;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            directorBar,
            const SizedBox(height: RevericSpacing.sm),
            Align(alignment: Alignment.centerLeft, child: modelSelector),
            const SizedBox(height: RevericSpacing.sm),
            actions,
          ],
        ),
      ),
    );
  }
}
