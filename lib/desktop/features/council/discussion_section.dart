// 职责: 桌面端议会讨论区 — 议题头、讨论时间线、进行中的状态栏与空闲时的插话/追加一轮/总结/转写作操作栏，自持 debug 重放状态。
// 关联文件:
//   lib/shared/hooks/use_council_run.dart
//   lib/shared/widgets/ai/council/timeline.dart
//   lib/desktop/features/council/replay_controller.dart
//   lib/desktop/features/council/panel.dart
//   lib/shared/providers/settings_providers.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/council.json
//   assets/translations/zh-CN/council.json
//   assets/translations/en/ai.json
//   assets/translations/zh-CN/ai.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/widget-decomposition.md
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../shared/hooks/use_council_run.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/models/agent_council_models.dart';
import '../../../shared/providers/settings_providers.dart';
import '../../../shared/theme/theme.dart';
import '../../../shared/widgets/ai/agent_message_card.dart';
import '../../../shared/widgets/ai/chat/chat_message_parts.dart'
    show CopyIconButton;
import '../../../shared/widgets/ai/council/participant.dart';
import '../../../shared/widgets/ai/council/timeline.dart';
import 'replay_controller.dart';

/// 完整讨论记录纯文本（议题、成员、各轮发言与总结），供一键复制。
String _transcriptForCopy(BuildContext context, AgentCouncilSession session) {
  final t = context.t;
  final buffer = StringBuffer()
    ..writeln('${t(LocaleKeys.councilTopic)}: ${session.topic}');
  final names = session.participants
      .map((p) => p.resolveName(t))
      .where((name) => name.trim().isNotEmpty)
      .join(', ');
  if (names.isNotEmpty) {
    buffer.writeln('${t(LocaleKeys.councilSelectParticipants)}: $names');
  }
  for (final round in session.rounds) {
    buffer
      ..writeln()
      ..writeln(
        t(
          LocaleKeys.councilRoundLabelFmt,
          namedArgs: {'round': '${round.roundNumber}'},
        ),
      );
    for (final message in round.messages) {
      final speaker = message.isUser
          ? t(LocaleKeys.councilUserSpeakerLabel)
          : message.participantName;
      buffer.writeln('$speaker: ${message.content}');
    }
  }
  final summary = session.summary;
  if (summary != null) {
    buffer
      ..writeln()
      ..writeln('${t(LocaleKeys.councilSummaryTitle)}:')
      ..writeln(summary.content);
  }
  return buffer.toString().trim();
}

class CouncilDiscussionSection extends HookConsumerWidget {
  const CouncilDiscussionSection({
    super.key,
    required this.run,
    required this.session,
    required this.modelSelector,
    required this.databasePath,
    required this.novelId,
    required this.onOpenActiveRunDetail,
    this.onSwitchToWriteMode,
  });

  final CouncilRun run;
  final AgentCouncilSession session;
  final Widget modelSelector;
  final String? databasePath;
  final String novelId;
  final void Function(String title) onOpenActiveRunDetail;
  final Future<void> Function()? onSwitchToWriteMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final debugMode = ref.watch(appDebugModeProvider);

    final replay = useMemoized(CouncilReplayController.new, const []);
    useListenable(replay);
    useEffect(() => replay.dispose, [replay]);
    useEffect(() {
      replay.stop();
      return null;
    }, [session.id]);

    final isReplaying = replay.isReplaying;
    final snapshot = isReplaying ? replay.snapshot : null;
    final displaySession = snapshot?.session ?? session;
    final displayActiveRun = isReplaying ? snapshot?.activeRun : run.activeRun;
    final canReplay =
        debugMode &&
        !session.isActive &&
        !run.isRunning &&
        !isReplaying &&
        CouncilReplayController.canReplay(session);
    // 重放中视为「活跃」；底部按钮外观与真实讨论相同，点击即停止重放。
    final showActiveBar = isReplaying || session.isActive;
    // 只有空闲时能点名或改写历史。
    final idle = !showActiveBar && !run.isRunning;

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
                border: Border(bottom: BorderSide(color: colors.border)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          context.t(LocaleKeys.councilTopic),
                          style: typo.uiTiny.copyWith(color: colors.textMuted),
                        ),
                      ),
                      CopyIconButton(
                        text: _transcriptForCopy(context, session),
                        tooltip: context.t(LocaleKeys.councilCopyDiscussion),
                      ),
                    ],
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
                session: displaySession,
                activeRun: displayActiveRun,
                runHistory: isReplaying ? const {} : run.runHistory,
                queuedMessageIds: isReplaying ? const {} : run.queuedMessageIds,
                density: AgentMessageDensity.panel,
                onOpenActiveRunDetail: onOpenActiveRunDetail,
                databasePath: databasePath,
                novelId: novelId,
                onRegenerate: idle ? run.regenerate : null,
                onRewindAfter: idle ? run.rewindAfter : null,
                onRemove: idle ? run.removeMessage : null,
              ),
            ),
            if (showActiveBar)
              _ActiveBar(
                run: run,
                isReplaying: isReplaying,
                session: displaySession,
                speaker:
                    displayActiveRun?.agentName ??
                    snapshot?.currentSpeaker?.resolveName(context.t),
                modelSelector: modelSelector,
                onPause: isReplaying ? replay.stop : run.pause,
                onCancel: isReplaying ? replay.stop : run.cancel,
              )
            else
              _ComposerBar(
                run: run,
                canUpdateSummary: session.canUpdateSummary,
                canReplay: canReplay,
                modelSelector: modelSelector,
                onReplay: () => replay.start(session),
                onSwitchToWriteMode: onSwitchToWriteMode,
              ),
          ],
        );
      },
    );
  }
}

BoxDecoration _barDecoration(RevericColors colors) => BoxDecoration(
  color: colors.surface,
  border: Border(top: BorderSide(color: colors.border)),
);

class _ActiveBar extends StatelessWidget {
  const _ActiveBar({
    required this.run,
    required this.isReplaying,
    required this.session,
    required this.speaker,
    required this.modelSelector,
    required this.onPause,
    required this.onCancel,
  });

  final CouncilRun run;
  final bool isReplaying;
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
    final buttonStyle = typo.uiSmall.copyWith(color: colors.textMuted);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: RevericSpacing.x2l,
        vertical: RevericSpacing.md,
      ),
      decoration: _barDecoration(colors),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(alignment: Alignment.centerLeft, child: modelSelector),
            const SizedBox(height: RevericSpacing.sm),
            // 讨论中也能插话，排到下一位成员发言前。
            if (!isReplaying) ...[
              _InterjectionInput(run: run),
              const SizedBox(height: RevericSpacing.sm),
            ],
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
                    style: buttonStyle,
                  ),
                ),
                TextButton(
                  onPressed: onCancel,
                  child: Text(
                    context.t(LocaleKeys.commonCancel),
                    style: buttonStyle,
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

class _ComposerBar extends StatelessWidget {
  const _ComposerBar({
    required this.run,
    required this.canUpdateSummary,
    required this.canReplay,
    required this.modelSelector,
    required this.onReplay,
    this.onSwitchToWriteMode,
  });

  final CouncilRun run;
  final bool canUpdateSummary;
  final bool canReplay;
  final Widget modelSelector;
  final VoidCallback onReplay;
  final Future<void> Function()? onSwitchToWriteMode;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final isRunning = run.isRunning;
    final switchToWrite = onSwitchToWriteMode;
    return Container(
      padding: const EdgeInsets.all(RevericSpacing.lg),
      decoration: _barDecoration(colors),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(alignment: Alignment.centerLeft, child: modelSelector),
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
            if (canReplay) ...[
              OutlinedButton.icon(
                onPressed: onReplay,
                icon: RevericIcon(RevericIcons.play_arrow_rounded, size: 16),
                label: Text(context.t(LocaleKeys.councilReplay)),
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
    OutlineInputBorder border(Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(RevericRadius.xl),
      borderSide: BorderSide(color: color),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: TextField(
            controller: run.userInputController,
            maxLines: 3,
            minLines: 1,
            style: typo.ui.copyWith(color: colors.textPrimary),
            decoration: InputDecoration(
              hintText: context.t(LocaleKeys.councilUserInputHint),
              hintStyle: typo.ui.copyWith(color: colors.textSubtle),
              filled: true,
              fillColor: colors.surfaceContainerHigh,
              border: border(colors.borderInput),
              enabledBorder: border(colors.borderInput),
              focusedBorder: border(colors.accent),
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
          valueListenable: run.userInputController,
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
